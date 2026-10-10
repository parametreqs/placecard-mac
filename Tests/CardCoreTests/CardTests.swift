import Testing
import CardCore
import Z2Transport

struct CardTests {
    @Test func testWindowsDecimalIncludesMifareCascadeTag() throws {
        let card = try #require(Card.parse("Mifare[01020304010203] 001,00515 DF (0744,20)"))
        #expect(OutputFormat.windowsMifare.render(card) == "50463112")
        // A different UID verifies the conversion rather than a card-specific correction.
        let other = try #require(Card.parse("Mifare[803285A204A9DB] 004,43483 DF (0744,20)"))
        #expect(OutputFormat.windowsMifare.render(other) == "3685287048")
        let four = try #require(Card.parse("Mifare[00112233] 001,00023"))
        #expect(OutputFormat.windowsMifare.render(four) == nil)
        let nonMifare = try #require(Card.parse("HID[01020304010203] 001,00515"))
        #expect(OutputFormat.windowsMifare.render(nonMifare) == nil)
    }
    @Test func testRDAllFirmware230DesfireFrame() throws {
        let card = try #require(Card.parse("Mifare[01020304010203] 001,00515 DF (0744,20)"))
        #expect(card.reportedHex == "01020304010203")
        #expect(card.wiegand == "001,00515")
        #expect(card.decimal24 == "66051")
        #expect(Card.parse("Mifare[01020304010203] 001,00515 DF (0744,20) EXTRA") == nil)
    }
    @Test func testFormatsPreserveLeadingZerosAndByteOrder() throws {
        let card = try #require(Card.parse("EM-Marine[0011223344] 007,00123"))
        #expect(OutputFormat.wiegand.render(card) == "007,00123")
        #expect(OutputFormat.decimal24.render(card) == "458875")
        #expect(OutputFormat.reportedHex.render(card) == "0011223344")
        #expect(OutputFormat.reversedHex.render(card) == "4433221100")
    }
    @Test func testRejectsBannersOverflowAndMalformedIDs() {
        for line in ["S/N: 123456", "version: 1.0", "HID[0011] 000,00001", "HID[001122] 256,00001", "Mifare[00112233] 001,65536", "Mifare[0011223] 001,00001", "garbage HID[001122] 001,00001", "HID[001122] 001,00001 EXTRA"] {
            #expect(Card.parse(line) == nil)
        }
    }
    @Test func testSplitFramesRemovalAndHeldCardDeduplication() {
        var stream = ReaderStream()
        #expect(stream.feed(Array("Mifare[0011".utf8)) == [])
        let cardEvents = stream.feed(Array("2233] 001,00023\r\n".utf8))
        #expect(cardEvents.count == 1)
        #expect(stream.feed(Array("Mifare[00112233] 001,00023\r\n".utf8)) == [])
        #expect(stream.feed(Array("No card\r\n".utf8)) == [.removed])
        #expect(stream.feed(Array("Mifare[00112233] 001,00023\r\n".utf8)) == cardEvents)
    }
    @Test func testBadAndOversizedFramesCannotLeakIntoTyping() {
        var stream = ReaderStream()
        let valid = Array("HID[001122] 001,00001\r".utf8)
        #expect(stream.feed([0xff] + valid) == [])
        #expect(stream.feed(Array(repeating: 65, count: 1100) + valid) == [])
        #expect(stream.feed(valid).count == 1)
    }
    @Test func testFTDIPacketDecodingAndUARTErrorRejection() {
        var packets: [UInt8] = [0x01, 0x60] + Array(repeating: 65, count: 62) + [0x01, 0x60, 66, 67]
        #expect(z2_decode_ftdi(&packets, Int32(packets.count), 64) == 64)
        #expect(Array(packets.prefix(64)) == Array(repeating: 65, count: 62) + [66, 67])
        var empty: [UInt8] = [1, 0x60]
        #expect(z2_decode_ftdi(&empty, 2, 64) == 0)
        var bad: [UInt8] = [1, 0x62, 65]
        #expect(z2_decode_ftdi(&bad, 3, 64) == -1)
        #expect(z2_decode_ftdi(&bad, 1, 64) == -1)
    }
}
