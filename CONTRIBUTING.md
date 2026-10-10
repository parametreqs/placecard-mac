# Contributing

Open an issue with the macOS version, Mac chip, exact reader model, firmware version, selected output format, and steps to reproduce. State whether the reader appears as a serial port or direct USB device. Do not post card identifiers, device serials, credentials, or private workbook URLs; use synthetic replacements that preserve frame syntax.

Keep changes focused. Build with `zsh build.sh` and run `zsh test.sh` before submitting a pull request. Add regression coverage for protocol, formatting, or duplicate-check changes. Keep the project independent of proprietary SDKs and avoid external runtime dependencies.

Hardware compatibility reports are welcome. A passing build or pseudo-terminal test is not proof that a new reader, firmware, card family, Mac chip, or macOS version works on hardware; identify what was actually tested.

For Nextcloud changes, preserve exact origin/file matching, both duplicate checks, leading zeros, clipboard restoration, and stopping after uncertain writes. Do not replace the whole cloud workbook or silently overwrite existing rows.
