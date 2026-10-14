# PlaceCard for Mac 0.3.3 — ready for the next card

After a successful registration or duplicate result, PlaceCard clears the four printed digits and queued card, then returns keyboard focus to the digit field. A duplicate found through **Check workbook** also resets the current entry. Automatic registration remains enabled after duplicates, so the next card can be scanned immediately. The duplicate message remains visible.

Errors that require inspection or retry retain the current entry and stop automatic saving. The field regains focus when the browser operation ends.

Validation: the native app builds; all 25 unit tests and both pseudo-terminal serial checks pass. The live duplicate workflow was verified: the four-digit field became empty and focused, the queued card reset, automatic saving remained enabled, and the duplicate status stayed visible. No workbook rows were written during that check. A new append was not re-tested for this UI update.

Download **PlaceCard-Mac-arm64.zip** for Apple Silicon/macOS 14+. Ad-hoc signed, not Apple-notarized. Updating can require refreshing the current app's Accessibility entry. Source and app are MIT licensed; public fixtures contain synthetic identifiers only.
