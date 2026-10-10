import Foundation

public struct Card: Equatable {
    public let kind: String
    public let reportedHex: String
    public let facility: UInt32
    public let number: UInt32
    public var wiegand: String { String(format: "%03u,%05u", facility, number) }
    public var decimal24: String { String((facility << 16) | number) }
    public var legacyMifareDecimal: String? {
        guard kind.lowercased().hasPrefix("mifare"), reportedHex.count == 14,
              let firstThree = UInt32(reportedHex.suffix(6), radix: 16) else { return nil }
        // RD_ALL's seven-byte terminal representation ends with UID0, UID1, UID2.
        // Legacy CL1 readers report [CT=0x88, UID0, UID1, UID2] as a little-endian UInt32.
        // NXP AN10927 describes the cascade marker; this is the compatibility format validated against Windows PlaceCard.
        let value = ((firstThree & 0xff) << 24) | ((firstThree & 0xff00) << 8)
            | ((firstThree >> 16) << 8) | 0x88
        return String(value)
    }

    public static func parse(_ line: String) -> Card? {
        // Factory terminal output. Anchoring prevents device banners and arbitrary text becoming keystrokes.
        let pattern = #"^\s*(EM[- ]?Marine|HID|Mifare(?:[A-Za-z0-9 _-]*)?|iCode(?:2)?|Temic|Cotag)\[([0-9A-Fa-f]{6,20})\]\s+([0-9]{1,3}),([0-9]{1,5})(?:\s+[A-Za-z0-9][A-Za-z0-9 _/-]{0,31}\s+\([0-9A-Fa-f]{4},[0-9A-Fa-f]{2}\))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        func field(_ i: Int) -> String { String(line[Range(m.range(at: i), in: line)!]) }
        let hex = field(2).uppercased()
        guard hex.count % 2 == 0, let facility = UInt32(field(3)), facility <= 255,
              let number = UInt32(field(4)), number <= 65535 else { return nil }
        return Card(kind: field(1), reportedHex: hex, facility: facility, number: number)
    }
}
public enum OutputFormat: String, CaseIterable, Identifiable {
    case wiegand = "Wiegand: 000,00000"
    case decimal24 = "Wiegand: decimal (24 bits)"
    case windowsMifare = "Mifare 7-byte: Windows decimal"
    case reportedHex = "Hex: as reported by reader"
    case reversedHex = "Hex: reversed byte order"
    public var id: String { rawValue }
    public func render(_ card: Card) -> String? {
        switch self {
        case .wiegand: return card.wiegand
        case .decimal24: return card.decimal24
        case .windowsMifare: return card.legacyMifareDecimal
        case .reportedHex: return card.reportedHex
        case .reversedHex:
            let chars = Array(card.reportedHex)
            return stride(from: 0, to: chars.count, by: 2).map { String(chars[$0...$0+1]) }.reversed().joined()
        }
    }
}
public enum ReaderEvent: Equatable { case card(Card), removed, message(String) }
public struct ReaderStream {
    private var buffer: [UInt8] = []
    private var dropping = false
    private var last: Card?
    public init() {}
    public mutating func feed(_ bytes: [UInt8]) -> [ReaderEvent] {
        var events: [ReaderEvent] = []
        for byte in bytes {
            if byte == 13 || byte == 10 {
                if !dropping && !buffer.isEmpty, let line = String(bytes: buffer, encoding: .ascii) {
                    if line.trimmingCharacters(in: .whitespaces).lowercased() == "no card" {
                        last = nil; events.append(.removed)
                    } else if let card = Card.parse(line) {
                        if last != card { events.append(.card(card)); last = card }
                    } else { events.append(.message(line)) }
                }
                buffer.removeAll(keepingCapacity: true); dropping = false
            } else if !dropping {
                if byte < 32 || byte > 126 || buffer.count >= 1024 {
                    buffer.removeAll(keepingCapacity: true); dropping = true
                } else { buffer.append(byte) }
            }
        }
        return events
    }
}
