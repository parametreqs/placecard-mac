import Testing
import CardCore

struct TransformTests {
    @Test func preservesDefaultsAndSupportsBothConversions() throws {
        let card = try #require(Card.parse("Mifare[01020304010203] 001,00515 DF (0744,20)"))
        var t = NumberTransform()
        #expect(try t.render(card, source: .windowsMifare) == "50463112")
        t.notation = .hex; t.width = 10
        #expect(try t.render(card, source: .windowsMifare) == "0003020188")
        t.notation = .decimal; t.width = 0; t.byteOrder = "7,6,5"
        #expect(try t.render(card, source: .reportedHex) == "197121")
        t.expression = "(x << 8) | 0x88"
        #expect(try t.render(card, source: .reportedHex) == "50463112")
    }
    @Test func paddingDoesNotTruncateOrRound() throws {
        let card = try #require(Card.parse("HID[00112233445566778899] 001,00001"))
        var t = NumberTransform(); t.width = 22
        #expect(try t.render(card, source: .reportedHex) == "0000112233445566778899")
        t.width = 2
        #expect(try t.render(card, source: .reportedHex) == card.reportedHex)
        t.notation = .decimal
        #expect(throws: CardError.self) { try t.render(card, source: .reportedHex) }
    }
    @Test func integerMathUsesPrecedenceAndExactArithmetic() throws {
        #expect(try IntegerFormula.evaluate("x + 2 * 3", x: 5) == 11)
        #expect(try IntegerFormula.evaluate("(x + 2) * 3", x: 5) == 21)
        #expect(try IntegerFormula.evaluate("x >> 8 & 0xff", x: 0x123456) == 0x34)
        #expect(try IntegerFormula.evaluate("x / 3 % 4", x: 29) == 1)
        #expect(try IntegerFormula.evaluate("~x & 0xFF ^ 0x10", x: 0) == 239)
        #expect(try IntegerFormula.evaluate("x", x: UInt64.max) == UInt64.max)
        #expect(try IntegerFormula.evaluate("9007199254740993 + 2", x: 0) == 9007199254740995)
    }
    @Test func badMathAndByteSelectionsNeverProduceOutput() throws {
        for formula in ["", "x/0", "x - 3", "x << 64", "x + 18446744073709551615", "18446744073709551615 * 2", "(x", "x); evil()", "x << 63"] {
            #expect(throws: CardError.self) { try IntegerFormula.evaluate(formula, x: 2) }
        }
        let card = try #require(Card.parse("HID[001122] 001,00001"))
        for order in ["0", "4", "1,,2", "-1", "1, hello"] {
            var t = NumberTransform(); t.byteOrder = order
            #expect(throws: CardError.self) { try t.render(card, source: .reportedHex) }
        }
        var t = NumberTransform(); t.byteOrder = "1,2"
        #expect(throws: CardError.self) { try t.render(card, source: .decimal24) }
    }
    @Test func duplicateChecksIncludeBothIdentifiersAndLeadingZeros() throws {
        let registry = try CardRegistry(tsv: "Printed\tCard\n0101\t1000000001\n102\t01000000002\n\t\n0103\t1000000003\n")
        #expect(registry.entries.count == 3)
        #expect(registry.nextRow == 6)
        #expect(throws: CardError.self) { try registry.check(printed: "0101", card: "1") }
        #expect(throws: CardError.self) { try registry.check(printed: "9999", card: "1000000002") }
        #expect(throws: CardError.self) { try registry.check(printed: "0102", card: "9") }
        try registry.check(printed: "0001", card: "50463112")
        #expect(!CardRegistry.validPrinted("001"))
        #expect(!CardRegistry.validPrinted("１２３４"))
        #expect(!CardRegistry.validPrinted("12345"))
        #expect(throws: CardError.self) { try registry.check(printed: "0001", card: "=2+2") }
    }
    @Test func incompleteAndMalformedTablesFailSafely() throws {
        let registry = try CardRegistry(tsv: "0001\t\n0002\t123\n\t456\n")
        #expect(throws: CardError.self) { try registry.check(printed: "0001", card: "456") }
        #expect(throws: CardError.self) { try registry.check(printed: "0003", card: "456") }
        for table in ["", "some webpage", "0001\t1\textra", "0001\t123\nwrong\tvalue", "0001\t=SUM(A1)"] {
            #expect(throws: CardError.self) { try CardRegistry(tsv: table) }
        }
    }
}
