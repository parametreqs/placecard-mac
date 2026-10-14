import Testing
import CardCore

struct RegistrationTests {
    @Test func registrationUsesWindowsDecimalWhileDisplayCanBeHex() throws {
        let card = try #require(Card.parse("Mifare[01020304010203] 001,00515 DF (0744,20)"))
        var transform = NumberTransform()
        transform.notation = .hex
        transform.expression = "x + 1"
        #expect(try transform.render(card, source: .windowsMifare) == "3020189")
        #expect(try card.registrationNumber() == "50463112")
    }

    @Test func unsupportedRegistrationCardsCannotFallBackToDisplayHex() throws {
        for frame in ["Mifare[010203] 001,00001", "Mifare[0102030405] 001,00001", "HID[01020304010203] 001,00001", "HID[01020304] 001,00001"] {
            let card = try #require(Card.parse(frame))
            #expect(throws: CardError.self) { try card.registrationNumber() }
        }
    }

    @Test func fourByteRegisterFormatUsesFirstThreeBytesAndKeepsAutoHex() throws {
        let card = try #require(Card.parse("Mifare[01020399] 001,00001"))
        #expect(try card.registrationNumber() == "50463112")
        #expect(OutputFormat.registerMifare.render(card) == "50463112")
        #expect(OutputFormat.automaticMifare.render(card) == "01020399")
        #expect(OutputFormat.windowsMifare.render(card) == nil)
        #expect(try NumberTransform().render(card, source: .registerMifare) == "50463112")
    }

    @Test func mixedUidLengthsAndTruncatedUidCollisionsAreBlockedAsDuplicates() throws {
        let registry = try CardRegistry(tsv: "0101\t50463112\n")
        for frame in ["Mifare[01020399] 001,00001", "Mifare[010203AA] 001,00001", "Mifare[09080706010203] 001,00001"] {
            let card = try #require(Card.parse(frame))
            let value = try card.registrationNumber()
            #expect(value == "50463112")
            #expect(throws: CardError.self) { try registry.check(printed: "0102", card: value) }
        }
        let padded = try #require(Card.parse("Mifare[00112233] 001,00001"))
        #expect(try padded.registrationNumber() == "571539592")
    }
}
