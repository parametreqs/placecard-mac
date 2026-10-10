import Foundation

public struct CardError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum NumberNotation: String, CaseIterable, Identifiable, Codable {
    case source = "Keep source", decimal = "Decimal", hex = "Hexadecimal"
    public var id: String { rawValue }
}

public struct NumberTransform: Codable, Equatable {
    public var notation: NumberNotation = .source
    public var byteOrder = ""
    public var expression = "x"
    public var width = 0
    public init() {}
    public func render(_ card: Card, source: OutputFormat) throws -> String {
        guard var text = source.render(card) else { throw CardError("This source requires a seven-byte Mifare card.") }
        guard (0...64).contains(width) else { throw CardError("Minimum digits must be between 0 and 64.") }
        let isHex = source == .reportedHex || source == .reversedHex
        let order = byteOrder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !order.isEmpty {
            guard isHex else { throw CardError("Choose a hex source to rearrange its bytes.") }
            let chars = Array(text)
            let bytes = stride(from: 0, to: chars.count, by: 2).map { String(chars[$0...$0+1]) }
            let parts = order.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count <= 10 else { throw CardError("Select at most ten bytes.") }
            let indices = try parts.map { part -> Int in
                guard let i = Int(part.trimmingCharacters(in: .whitespaces)), (1...bytes.count).contains(i) else {
                    throw CardError("Byte positions start at 1 and must exist in the selected source.")
                }
                return i - 1
            }
            text = indices.map { bytes[$0] }.joined()
        }
        let formula = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if formula != "x" || notation != .source {
            guard let value = UInt64(text, radix: isHex ? 16 : 10) else {
                throw CardError("Calculations need a numeric source of at most 64 bits. Choose decimal or hex instead of Wiegand fields.")
            }
            let result = try IntegerFormula.evaluate(formula, x: value)
            text = String(result, radix: notation == .hex || (notation == .source && isHex) ? 16 : 10).uppercased()
        }
        if width > text.count { text = String(repeating: "0", count: width - text.count) + text }
        return text
    }
}

// A bounded integer parser, never evaluated as Swift/JavaScript or shell code.
public enum IntegerFormula {
    public static func evaluate(_ text: String, x: UInt64) throws -> UInt64 {
        guard !text.isEmpty, text.utf8.count <= 256 else { throw CardError("Enter a formula of 1–256 characters.") }
        var parser = Parser(chars: Array(text), x: x)
        let result = try parser.expr(0, depth: 0)
        parser.space()
        guard parser.index == parser.chars.count else { throw CardError("Unexpected text in formula.") }
        return result
    }
    private struct Parser {
        let chars: [Character]
        let x: UInt64
        var index = 0
        mutating func space() { while index < chars.count && chars[index].isWhitespace { index += 1 } }
        mutating func take(_ text: String) -> Bool {
            space(); let token = Array(text)
            guard index + token.count <= chars.count, Array(chars[index..<index+token.count]) == token else { return false }
            index += token.count; return true
        }
        mutating func atom(depth: Int) throws -> UInt64 {
            guard depth < 32 else { throw CardError("Formula nesting is too deep.") }
            if take("~") { return ~(try atom(depth: depth + 1)) }
            if take("+") { return try atom(depth: depth + 1) }
            if take("(") {
                let result = try expr(0, depth: depth + 1)
                guard take(")") else { throw CardError("Missing closing parenthesis.") }; return result
            }
            if take("x") { return x }
            space(); let start = index
            let hex = take("0x") || take("0X")
            let digitsStart = index
            while index < chars.count && (hex ? chars[index].isHexDigit : chars[index].isASCII && chars[index].isNumber) { index += 1 }
            guard index > digitsStart, let n = UInt64(String(chars[digitsStart..<index]), radix: hex ? 16 : 10) else {
                index = start; throw CardError("Expected x, a decimal number, or 0x hex number.")
            }; return n
        }
        mutating func expr(_ min: Int, depth: Int) throws -> UInt64 {
            var left = try atom(depth: depth)
            let operators: [(String, Int)] = [("|", 1), ("^", 2), ("&", 3), ("<<", 4), (">>", 4), ("+", 5), ("-", 5), ("*", 6), ("/", 6), ("%", 6)]
            while true {
                space(); let before = index
                guard let (op, precedence) = operators.first(where: { item in
                    let t = Array(item.0); return index + t.count <= chars.count && Array(chars[index..<index+t.count]) == t
                }), precedence >= min else { return left }
                index = before + op.count
                let right = try expr(precedence + 1, depth: depth + 1)
                switch op {
                case "+", "-", "*":
                    let pair = op == "+" ? left.addingReportingOverflow(right) : op == "-" ? left.subtractingReportingOverflow(right) : left.multipliedReportingOverflow(by: right)
                    guard !pair.overflow else { throw CardError("Calculation is outside the unsigned 64-bit range.") }; left = pair.partialValue
                case "/", "%":
                    guard right != 0 else { throw CardError("Cannot divide by zero.") }; left = op == "/" ? left / right : left % right
                case "<<", ">>":
                    guard right < 64 else { throw CardError("Bit shifts must be 0–63.") }
                    if op == "<<" {
                        guard left <= UInt64.max >> right else { throw CardError("Left shift overflows 64 bits.") }; left <<= right
                    } else { left >>= right }
                case "&": left &= right
                case "|": left |= right
                default: left ^= right
                }
            }
        }
    }
}
