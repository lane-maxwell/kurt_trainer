import Foundation
@testable import KineticRevival

extension Data {
    init(hex: String) {
        self.init(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
    }
}

struct FakeWriteError: Error, LocalizedError {
    var errorDescription: String? { "radio unavailable" }
}

/// Stands in for the peripheral: records control point writes and optionally answers them
/// asynchronously, the way a real trainer's indication would arrive.
@MainActor
final class FakeTrainerLink: ControlPointWriter {
    var writes: [Data] = []
    var failWrites = false
    /// Returns the indication to deliver for a write, or nil to stay silent.
    var responder: (Data) -> Data? = { request in Data([0x80, request[0], 0x01]) }
    var deliver: (Data) -> Void = { _ in }

    func writeControlPoint(_ data: Data) throws {
        if failWrites { throw FakeWriteError() }
        writes.append(data)
        guard let response = responder(data) else { return }
        Task { @MainActor in self.deliver(response) }
    }
}

@MainActor
final class TestClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 0)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

/// Parses XML (failing on malformed input) and returns every element with its trimmed text.
final class XMLElementCollector: NSObject, XMLParserDelegate {
    struct Element: Equatable {
        let name: String
        let text: String
    }

    private var elements: [Element] = []
    private var text = ""

    static func collect(_ xml: String) throws -> [Element] {
        let collector = XMLElementCollector()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = collector
        guard parser.parse() else {
            throw parser.parserError ?? CocoaError(.coderReadCorrupt)
        }
        return collector.elements
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        elements.append(Element(name: elementName, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        text = ""
    }
}
