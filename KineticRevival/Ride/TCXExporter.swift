import Foundation

/// Garmin Training Center XML, which Strava, TrainingPeaks and intervals.icu import with power.
enum TCXExporter {
    static func export(_ record: RideRecord) -> String {
        let trackpoints = record.samples.map(trackpoint).joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
          <Activities>
            <Activity Sport="Biking">
              <Id>\(timestamp(record.startedAt))</Id>
              <Lap StartTime="\(timestamp(record.startedAt))">
                <TotalTimeSeconds>\(decimal(record.duration, digits: 1))</TotalTimeSeconds>
                <DistanceMeters>\(decimal(record.distance, digits: 1))</DistanceMeters>
                <Calories>\(Int(record.workKilojoules.rounded()))</Calories>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>
        \(trackpoints)
                </Track>
              </Lap>
              <Notes>\(escape("Kinetic Revival: \(record.routeName)"))</Notes>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>

        """
    }

    private static func trackpoint(_ sample: RideSample) -> String {
        let cadence = sample.cadenceRpm.map { "\n            <Cadence>\(min(max(Int($0.rounded()), 0), 254))</Cadence>" } ?? ""
        return """
                  <Trackpoint>
                    <Time>\(timestamp(sample.timestamp))</Time>
                    <Position>
                      <LatitudeDegrees>\(decimal(sample.latitude, digits: 7))</LatitudeDegrees>
                      <LongitudeDegrees>\(decimal(sample.longitude, digits: 7))</LongitudeDegrees>
                    </Position>
                    <AltitudeMeters>\(decimal(sample.elevation, digits: 1))</AltitudeMeters>
                    <DistanceMeters>\(decimal(sample.distance, digits: 1))</DistanceMeters>\(cadence)
                    <Extensions>
                      <ns3:TPX>
                        <ns3:Speed>\(decimal(sample.speedMetersPerSecond, digits: 2))</ns3:Speed>
                        <ns3:Watts>\(max(sample.powerWatts, 0))</ns3:Watts>
                      </ns3:TPX>
                    </Extensions>
                  </Trackpoint>
        """
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// Locale-independent, so a German phone doesn't write "12,5".
    private static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
