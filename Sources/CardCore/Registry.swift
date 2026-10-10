import Foundation

public struct RegistryEntry: Equatable {
    public let row: Int
    public let printed: String
    public let card: String
}
public struct CardRegistry {
    public let entries: [RegistryEntry]
    public let nextRow: Int
    public func existingPrinted(_ printed: String) -> RegistryEntry? { entries.first { $0.printed == printed } }
    public static func validPrinted(_ text: String) -> Bool {
        text.utf8.count == 4 && text.utf8.allSatisfy { (48...57).contains($0) }
    }
    public init(tsv: String) throws {
        guard tsv.utf8.count < 2_000_000 else { throw CardError("Workbook data is too large.") }
        let lines = tsv.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var entries: [RegistryEntry] = []; var last = 0
        for (i, line) in lines.enumerated() {
            let fields = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            if fields.allSatisfy({ $0.isEmpty }) { continue }
            guard fields.count == 2 else { throw CardError("Expected exactly two workbook columns, A and B.") }
            last = i + 1
            let a = fields[0], b = fields[1]
            let numericA = a.utf8.allSatisfy { (48...57).contains($0) } && !a.isEmpty && a.count <= 4
            let numericB = !b.isEmpty && b.count <= 64 && b.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
            // One header row is supported; every subsequent nonempty row must be an identifier pair.
            if i == 0 && !numericA && !numericB { continue }
            guard (numericA || a.isEmpty) && (numericB || b.isEmpty) else { throw CardError("Unexpected workbook values on row \(i + 1). Saving stopped.") }
            entries.append(RegistryEntry(row: i + 1, printed: a.isEmpty ? "" : String(repeating: "0", count: 4 - a.count) + a, card: b))
        }
        guard !entries.isEmpty else { throw CardError("No card records were read. Check the workbook and active sheet.") }
        self.entries = entries; nextRow = last + 1
    }
    public func check(printed: String, card: String) throws {
        guard Self.validPrinted(printed) else { throw CardError("Enter exactly four printed digits.") }
        guard !card.isEmpty, card.count <= 64, card.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw CardError("The workbook needs a decimal or hex card number.")
        }
        func canonical(_ value: String) -> String {
            let n = value.uppercased().drop(while: { $0 == "0" }); return n.isEmpty ? "0" : String(n)
        }
        if let match = existingPrinted(printed) {
            throw CardError(match.card.isEmpty ? "Printed number \(printed) already exists on row \(match.row), with no scanned number." : "Printed number \(printed) already exists on row \(match.row) (\(match.card)).")
        }
        if let match = entries.first(where: { !$0.card.isEmpty && canonical($0.card) == canonical(card) }) {
            throw CardError("Scanned number already exists on row \(match.row), printed number \(match.printed).")
        }
    }
}
