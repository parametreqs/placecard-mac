# PlaceCard for Mac 0.3.2 — legacy register decimal and Nextcloud connection

Nextcloud registration now uses the legacy register decimal rule for both four- and seven-byte Mifare cards, independently of display/typing settings and custom adjustments. It never falls back to display hex. Existing records are never overwritten.

A new **Mifare 4/7-byte: Register decimal** source also applies this rule to card display and ordinary typing. Auto remains available for four-byte hex / seven-byte Windows decimal.

The four-byte rule uses the first three reported bytes; the seven-byte rule uses the last three. Both interpret `[0x88, byte1, byte2, byte3]` as little-endian UInt32. This preserves an existing register's convention, not the full UID or a universal Windows default. Different UIDs can share a legacy value; duplicate scanned numbers are blocked. Validate the format against your own register before using it.

Also fixes the PlaceCard-to-Brave handoff through macOS cooperative activation, verifies browser focus before input, and reports Accessibility window-access failures with recovery guidance. Exact configured origin/file ID, filename, editor and window checks still apply.

Validation: 25 unit tests and both pseudo-terminal serial checks pass, covering both UID lengths, legacy collisions, unsupported cards and independence from display adjustments. A live four-byte hardware scan displayed the decimal value matching the existing register. The known seven-byte mapping was checked against the current core conversion. A live workbook read reported an existing mapping without changing any rows. A new append with this build has not been verified live.

Download **PlaceCard-Mac-arm64.zip** for Apple Silicon/macOS 14+. Ad-hoc signed, not Apple-notarized. Updating can require refreshing the current app's Accessibility entry. Source and app are MIT licensed; public fixtures contain synthetic identifiers only.
