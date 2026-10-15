import CoreLocation
import Foundation

enum GPXError: Error, LocalizedError {
    case malformed(String)
    case noTrackPoints

    var errorDescription: String? {
        switch self {
        case let .malformed(detail): "This GPX file couldn't be read: \(detail)"
        case .noTrackPoints: "This GPX file has no track or route points."
        }
    }
}

/// Reads track points (`trkpt`) or, failing that, route points (`rtept`) from a GPX 1.0/1.1 file.
enum GPXParser {
    static func parse(_ data: Data, id: String, fallbackName: String) throws -> Route {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw GPXError.malformed(parser.parserError?.localizedDescription ?? "unknown XML error")
        }

        let points = delegate.trackPoints.isEmpty ? delegate.routePoints : delegate.trackPoints
        guard !points.isEmpty else { throw GPXError.noTrackPoints }

        let name = delegate.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try Route(
            id: id,
            name: name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName,
            coordinates: points.map(\.coordinate),
            elevations: points.map(\.elevation)
        )
    }

    private struct Point {
        let coordinate: CLLocationCoordinate2D
        var elevation: Double?
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var trackPoints: [Point] = []
        var routePoints: [Point] = []
        var name: String?

        private var current: Point?
        private var currentIsTrackPoint = false
        private var text = ""
        private var depthInsidePoint = 0

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            let element = Self.localName(elementName)
            text = ""
            if current != nil { depthInsidePoint += 1 }

            guard element == "trkpt" || element == "rtept" else { return }
            guard let lat = attributes["lat"].flatMap(Double.init),
                  let lon = attributes["lon"].flatMap(Double.init)
            else {
                parser.abortParsing()
                return
            }
            current = Point(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            currentIsTrackPoint = element == "trkpt"
            depthInsidePoint = 0
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        // AllTrails and others wrap names in CDATA, which XMLParser reports separately.
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let element = Self.localName(elementName)

            if var point = current {
                if element == "ele", depthInsidePoint == 1 {
                    point.elevation = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = point
                } else if element == "trkpt" || element == "rtept" {
                    if currentIsTrackPoint { trackPoints.append(point) } else { routePoints.append(point) }
                    current = nil
                    return
                }
                depthInsidePoint -= 1
            } else if element == "name", name == nil {
                // The first <name> outside a point is the file/track name.
                name = text
            }
        }

        private static func localName(_ qualified: String) -> String {
            qualified.split(separator: ":").last.map(String.init) ?? qualified
        }
    }
}
