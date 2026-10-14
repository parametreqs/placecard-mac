import Testing
import CardCore

struct AutomaticMifareTests {
    @Test func preservesFourByteHexIncludingZeros() throws {
        for hex in ["DEADBEEF", "00112233", "00000000", "12345678"] {
            let card = try #require(Card.parse("Mifare[\(hex)] 001,00023"))
            #expect(OutputFormat.automaticMifare.render(card) == hex)
            #expect(try NumberTransform().render(card, source: .automaticMifare) == hex)
        }
    }
    @Test func selectsWindowsDecimalForSevenBytes() throws {
        let card = try #require(Card.parse("Mifare[01020304010203] 001,00515 DF (0744,20)"))
        #expect(OutputFormat.automaticMifare.render(card) == "50463112")
        #expect(try NumberTransform().render(card, source: .automaticMifare) == "50463112")
    }
    @Test func alternatesFormatsOnEveryScanWithoutChangingSettings() throws {
        let lines = ["Mifare[DEADBEEF] 001,00023", "Mifare[01020304010203] 001,00515 DF (0744,20)", "Mifare[00112233] 001,00023", "Mifare[01020304010203] 001,00515 DF (0744,20)"]
        var stream = ReaderStream()
        let transform = NumberTransform()
        let outputs = try lines.flatMap { line in
            try stream.feed(Array((line + "\r\n").utf8)).compactMap { event -> String? in
                guard case .card(let card) = event else { return nil }
                return try transform.render(card, source: .automaticMifare)
            }
        }
        #expect(outputs == ["DEADBEEF", "50463112", "00112233", "50463112"])
    }
    @Test func numericAdjustmentsUseTheDetectedRadix() throws {
        let four = try #require(Card.parse("Mifare[00000010] 001,00023"))
        let seven = try #require(Card.parse("Mifare[01020304010203] 001,00515"))
        var transform = NumberTransform(); transform.expression = "x + 1"
        #expect(try transform.render(four, source: .automaticMifare) == "11")
        #expect(try transform.render(seven, source: .automaticMifare) == "50463113")
        transform.notation = .decimal
        #expect(try transform.render(four, source: .automaticMifare) == "17")
        transform.notation = .hex
        #expect(try transform.render(seven, source: .automaticMifare) == "3020189")
        transform = NumberTransform(); transform.byteOrder = "4,3,2,1"
        #expect(try transform.render(four, source: .automaticMifare) == "10000000")
        #expect(throws: CardError.self) { try transform.render(seven, source: .automaticMifare) }
    }
    @Test func rejectsUnsupportedTypesAndLengthsWithoutFallback() throws {
        for line in ["HID[DEADBEEF] 001,00023", "EM-Marine[0011223344] 007,00123", "Mifare[001122] 001,00023", "Mifare[00112233445566778899] 001,00023"] {
            let card = try #require(Card.parse(line))
            #expect(OutputFormat.automaticMifare.render(card) == nil)
            #expect(throws: CardError.self) { try NumberTransform().render(card, source: .automaticMifare) }
        }
    }
}
