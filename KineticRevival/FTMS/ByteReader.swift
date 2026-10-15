import Foundation

/// Sequential little-endian reader for GATT payloads, which FTMS defines as little-endian throughout.
struct ByteReader {
    private let bytes: [UInt8]
    private let characteristic: String
    private(set) var offset = 0

    init(_ data: Data, characteristic: String) {
        self.bytes = Array(data)
        self.characteristic = characteristic
    }

    var remaining: Int { bytes.count - offset }

    mutating func uint8() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func uint16() throws -> UInt16 {
        try require(2)
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    mutating func int16() throws -> Int16 {
        Int16(bitPattern: try uint16())
    }

    mutating func uint24() throws -> UInt32 {
        try require(3)
        defer { offset += 3 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
    }

    mutating func uint32() throws -> UInt32 {
        try require(4)
        defer { offset += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }

    mutating func skip(_ count: Int) throws {
        try require(count)
        offset += count
    }

    private func require(_ count: Int) throws {
        guard remaining >= count else {
            throw FTMSParseError.truncated(
                characteristic: characteristic,
                expectedAtLeast: offset + count,
                actual: bytes.count
            )
        }
    }
}

extension Data {
    var hexDescription: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
