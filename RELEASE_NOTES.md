# PlaceCard for Mac 0.3.0 — first public release

Read IronLogic Z-2 RD_ALL card numbers on Apple Silicon Macs and enter them into Notes or another active application. Includes Windows-compatible seven-byte Mifare decimal output, byte reordering, exact integer calculations, decimal/hex conversion, leading zeros, and optional four-digit card registration in a configurable Nextcloud / ONLYOFFICE workbook with duplicate checks.

## Download and installation

Download **PlaceCard-Mac-arm64.zip**, unzip it, and move **PlaceCard Mac.app** to Applications. Supports Apple Silicon, macOS 14+. The app is locally ad-hoc signed, **not Apple-notarized**. Follow the app-specific Open Anyway process documented in the README if macOS blocks a trusted download. Accessibility permission is required for typing and browser automation.

No private server or card register is bundled. Nextcloud is optional and starts unconfigured. Ordinary card entry works without a browser.

Hardware validation: Z-2 RD_ALL firmware 230 on Apple M4/macOS 27, with real Notes typing and an automatically registered Nextcloud row verified after reloading the workbook. The public configurable destination has unit coverage; other sites/editor layouts still need live verification. Intel, other hardware combinations, and direct USB were not tested on hardware. This release is an independent community implementation under MIT.

Build verification: native arm64 release; unit tests and both pseudo-terminal serial checks; local signature and release ZIP integrity checks. See README for detailed limitations and build instructions. SHA256SUMS.txt accompanies the download.
