# PlaceCard for Mac

An open-source macOS companion for **IronLogic Z-2 RD_ALL** card readers. Read a card number and enter it into **Notes, a text field, or another active app**. Adjust number formats and optionally register cards in your own Nextcloud workbook.

[**Download the Mac app**](https://github.com/parametreqs/placecard-mac/releases/latest) · [Русская инструкция](README.ru.md) · [Report a problem](https://github.com/parametreqs/placecard-mac/issues)

Independent implementation; not an official IronLogic product or a recompiled Windows application. The reader's macOS serial connection or a direct user-space FTDI connection is used. No kernel extension or firmware/EEPROM update is required.

## Compatibility

- **Apple Silicon Macs (M1–M5), macOS 14 or newer.** The downloadable app is arm64, with no third-party runtime dependency.
- **Tested on an Apple M4 with macOS 27**, a Z-2 RD_ALL running firmware 230, and a seven-byte Mifare/DESFire card. Real card display, entry into Notes, and a Nextcloud registration were verified before the public release. Other chips, older macOS releases, other firmware/card families, and the direct USB route still need hardware verification.
- Readers exposed as `/dev/cu.usbserial…` use 9600 baud, 8N1, no flow control. Direct USB supports FTDI vendor `0403`, IronLogic product `1234`; the tested reader used standard FTDI product `6001` through the system serial driver.
- Intel Macs, binary SDK mode, keyboard-only readers, card-memory access, and writing cards are not supported by the downloadable build.

## Install and read a card

1. Download **PlaceCard-Mac-arm64.zip** from [Releases](https://github.com/parametreqs/placecard-mac/releases/latest), unzip it, and move **PlaceCard Mac.app** into Applications.
2. Open the app. This community release is **ad-hoc signed and not notarized**. If macOS blocks it and you trust this project, use the app-specific **Open Anyway** option in System Settings → Privacy & Security, as described in [Apple's instructions](https://support.apple.com/en-us/102445). Managed Macs may prevent this.
3. Connect the RD_ALL, select the reader or its `cu.usbserial…` port, and choose **Start reading**. Close other apps using the same reader first.
4. Present a card and compare **Last card** with the desired Windows PlaceCard format. Open **Number format** to choose a source. For the legacy decimal output of a seven-byte Mifare card, choose **Mifare 7-byte: Windows decimal**.
5. For typing, open **Typing**, choose **Enable Accessibility…** if required, and grant access to **PlaceCard Mac** in Privacy & Security → Accessibility. On the tested macOS 27 build this page is called **Device Control and Data Access**. Grant it only if you trust the app; it can send input to other apps.
6. Enable **Type card numbers into the active app**, focus an editable note or another text field, then remove and present the card again.

The default format is Wiegand `000,00000`. Typing and automatic saving start disabled. **After number** optionally sends Return or Tab. A held card produces one entry until removal or a different card is reported. Disconnects and format changes disable automatic entry. Reconnect and choose Start reading again when necessary.

## Number adjustments

- Source: Wiegand facility/card, 24-bit Wiegand decimal, legacy seven-byte Mifare Windows decimal, reported hex, or reversed hex.
- Output: keep the source notation, decimal, or uppercase hex.
- Byte positions: choose a hex source and enter one-based positions, for example `7,6,5`. Positions refer to that source's displayed bytes. Blank uses all bytes.
- Calculation: `x` is the selected source value. Supports parentheses, decimal and `0x` constants, `+ - * / %`, `& | ^`, `<< >>`, and unary `~`.
- Minimum digits: add leading zeros; never truncate the result.

Arithmetic is exact unsigned 64-bit integer arithmetic. Invalid expressions, division by zero, overflow/underflow, and shifts above 63 stop output. Raw hex without arithmetic can retain longer identifiers. Settings are remembered locally; the last card previews the result.

The legacy seven-byte Mifare format uses the RD_ALL terminal representation's last three hex bytes as UID0–UID2 and interprets `[0x88, UID0, UID1, UID2]` as a little-endian 32-bit number. For the synthetic bytes `01 02 03`, the output is `50463112`. The `0x88` cascade marker is documented by [NXP AN10927](https://www.nxp.com/docs/en/application-note/AN10927.pdf). This compatibility interpretation was checked against a Windows reading; it represents the first cascade, not the full seven-byte UID. Unsupported card types are rejected for this format.

## Optional Nextcloud registration

This feature uses your signed-in **Brave** browser and a **Nextcloud / ONLYOFFICE** workbook. There is **no default server, account, or workbook** in the public app. Ordinary typing does not require Nextcloud or Brave.

1. Open a dedicated `.xlsx` card register in Brave. Keep the intended sheet active, with printed numbers in **column A** and scanned numbers in **column B**. The current integration requires at least one existing record; creating an empty register is not supported yet.
2. In PlaceCard's **Nextcloud** tab, choose **Workbook…**. Enter the HTTPS link that opens your specific file, such as `https://cloud.example.org/index.php/apps/files/files/42`, and its exact filename, such as `Cards.xlsx`. Folder links and share links are not supported. Subdirectory installs and explicit HTTPS ports are accepted.
3. Choose **Check workbook**. If four digits are already entered, it also checks whether that printed number exists.
4. Start the reader and enable **Automatically add cards to Nextcloud**. Scan a card and enter its **four printed digits**, in either order. A short pause triggers registration once both are ready.
5. Keep Brave open and avoid typing or changing its focus during the operation. On success the app verifies the new A/B cells, requests Save, and clears the printed number. Check the editor's saved status; the app does not independently confirm server persistence.

The app reads the complete two-column range, checks both identifiers for duplicates, rechecks for intervening edits, verifies the destination row is empty, and appends after the last record. Leading zeros are stored as text. Existing rows are not replaced and gaps are not filled. Scanned-number comparison ignores zero padding and hex letter case; it does not equate differently formatted decimal and hex values. Use a consistent format.

**Limits:** maximum 10,000 used rows; current active sheet only; desktop ONLYOFFICE editor and Brave accessibility layout required. Browser automation does not provide atomic uniqueness across simultaneous writers: **use one registration operator at a time**. Unexpected data or uncertain/partial writes stop automatic saving; inspect the reported row before retrying. Changes in Nextcloud, ONLYOFFICE, or Brave can require integration updates. The public configurable destination checks have automated coverage; only the original site's complete browser flow has been tested live.

## Privacy

No analytics, telemetry, login collection, bundled credentials, or cloud requests by the app. Card display and typing stay local. Optional Nextcloud mode enters the selected printed/scanned pair into the workbook you configure through the browser; it briefly uses and restores the clipboard. Settings are stored in local UserDefaults and the last 100 reader messages stay in memory until quit. The repository contains synthetic card fixtures and no operational card register.

## Build and test

Requires Apple's Swift 6 tools and Python 3 for the serial tests; no third-party package dependency. Install Xcode or Command Line Tools if needed.

```sh
git clone https://github.com/parametreqs/placecard-mac.git
cd placecard-mac
zsh build.sh
zsh test.sh
```

Outputs: `dist/PlaceCard Mac.app` and `dist/PlaceCard-Mac-arm64.zip`. Unit tests cover parsing, held-card deduplication, FTDI status/error decoding, exact calculations, byte ordering, padding, malformed registers, duplicate detection, and destination origin/file checks. Two integration tests exercise the release executable through real POSIX pseudo-terminals, including serial configuration, fragmented input, removal, settings restoration, and disconnects. These do not emulate USB hardware.

The public app has a separate bundle identifier from the original private development app. Builds are locally signed; replacing a build can invalidate its Accessibility entry. If permission remains enabled but unrecognized, remove that app's entry and add the exact current app again. `test.sh` includes a Swift Testing macro-discovery workaround for the macOS 27 command-line tools.

Diagnostic commands read without typing into other apps:

```sh
'dist/PlaceCard Mac.app/Contents/MacOS/PlaceCardMac' --list
'dist/PlaceCard Mac.app/Contents/MacOS/PlaceCardMac' --capture /dev/cu.usbserial-EXAMPLE 15
```

Never post real card identifiers, reader serial numbers, credentials, or private server links in a public issue. Replace identifying values while preserving frame syntax.

## References and license

- [IronLogic PlaceCard](https://www.ironlogic.ru/il_new.nsf/htm/ru_placecard): original number conversion and keyboard-entry workflow.
- [RD_ALL manual](https://ironlogic.me/files/documentation/product-guides/en/Icontrol/IC_Z-2_USB.pdf): terminal protocol and serial settings.
- [IronLogic FTDI PID guidance](https://ironlogic.ru/web/ilBY.nsf/file/ru_restoring_ironlogic_pid_v3.pdf/%24FILE/restoring_ironlogic_pid_v3.pdf): IronLogic and standard FTDI product IDs.
- [libftdi implementation](https://github.com/legege/libftdi): reference for the FTDI protocol, not a bundled dependency.

Licensed under [MIT](LICENSE). No vendor installer, proprietary SDK source/binary, Apple framework binary, or third-party driver is redistributed. All app and test code in this repository is the independent implementation.
