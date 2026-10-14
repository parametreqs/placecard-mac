# PlaceCard for Mac 0.3.1 — automatic Mifare formats

New **Mifare: Auto (4-byte hex / 7-byte decimal)** source:

- Four-byte Mifare cards retain their original uppercase hexadecimal identifier, including leading zeros.
- Seven-byte Mifare cards use the existing Windows-compatible legacy decimal conversion.
- Selection happens for every scan, so alternating card types requires no manual format switch.
- New installations default to Auto. Existing installations keep their chosen source; select Auto once after updating. Selecting Auto resets custom adjustments to preserve original four-byte hex values.
- Manual formats remain available. Unsupported card types/lengths stop output with a specific message.

Also shows the card's byte count and clears a stale reader format-error status when settings change.

Download **PlaceCard-Mac-arm64.zip** for Apple Silicon/macOS 14+. The build remains ad-hoc signed, not Apple-notarized. A replaced build may need its Accessibility permission refreshed. Source and app are MIT licensed; private card data is not included in public fixtures.

Validation: 21 unit tests and both pseudo-terminal serial checks pass, including alternating four- and seven-byte frames without changing settings, leading-zero preservation, adjustment radix, and rejection of unsupported card types. The release ZIP and local signature are verified.
