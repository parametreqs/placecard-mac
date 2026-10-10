import AppKit
import ApplicationServices
import CardCore

/// Uses the user's signed-in editor. No passwords, cookies or cloud file replacements.
@MainActor final class NextcloudWriter {
    private let target: WorkbookTarget
    init(target: WorkbookTarget) { self.target = target }
    private var browser: NSRunningApplication?
    private var window: AXUIElement?
    private var clipboardVersion = -1

    private func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?; AXUIElementCopyAttributeValue(e, name as CFString, &result); return result
    }
    private func string(_ e: AXUIElement, _ name: String) -> String {
        if let value = attr(e, name) as? String { return value }
        if let value = attr(e, name) as? URL { return value.absoluteString }
        return ""
    }
    private func label(_ e: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].map { string(e, $0) }.joined(separator: " ")
    }
    private func descendants(_ root: AXUIElement) -> [AXUIElement] {
        var queue = [root], result: [AXUIElement] = [], index = 0
        while index < queue.count && index < 12000 {
            let e = queue[index]; index += 1; result.append(e)
            queue.append(contentsOf: attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        return result
    }
    private func pause(_ ms: UInt64 = 150) async throws {
        try await Task.sleep(nanoseconds: ms * 1_000_000)
        try Task.checkCancellation()
    }
    private func ensureTarget() throws -> AXUIElement {
        guard let browser, let window, NSWorkspace.shared.frontmostApplication?.processIdentifier == browser.processIdentifier else {
            throw CardError("Browser focus changed. Saving stopped.")
        }
        let root = AXUIElementCreateApplication(browser.processIdentifier)
        guard let focusedWindow = attr(root, kAXFocusedWindowAttribute), CFEqual(focusedWindow, window) else {
            throw CardError("Browser window changed. Saving stopped.")
        }
        let nodes = descendants(window)
        guard nodes.contains(where: { e in
            guard string(e, kAXRoleAttribute) == "AXWebArea", let url = URL(string: string(e, kAXURLAttribute)), target.matches(url) else { return false }
            return true
        }), nodes.contains(where: { string($0, kAXRoleAttribute) == "AXWebArea" && label($0).contains(target.filename) }) else {
            throw CardError("Open the specified Nextcloud workbook in Brave. Saving stopped.")
        }
        guard let editor = nodes.first(where: { string($0, kAXRoleAttribute) == "AXWebArea" && label($0).contains("ONLYOFFICE") && label($0).contains(target.filename) }) else {
            throw CardError("The workbook editor is not ready.")
        }
        return editor
    }
    private func address() throws -> AXUIElement {
        let fields = descendants(try ensureTarget()).filter { e in
            string(e, kAXRoleAttribute) == kAXTextFieldRole && string(e, kAXValueAttribute).range(of: #"^[A-Z]+[1-9][0-9]*(?::[A-Z]+[1-9][0-9]*)?$"#, options: .regularExpression) != nil
        }
        guard fields.count == 1 else { throw CardError("Close editor dialogs and finish editing the current cell, then retry.") }
        return fields[0]
    }
    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws {
        _ = try ensureTarget()
        guard let pid = browser?.processIdentifier,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { throw CardError("Could not send keyboard input.") }
        down.flags = flags; up.flags = flags
        down.postToPid(pid); up.postToPid(pid)
    }
    private func text(_ value: String) throws {
        _ = try ensureTarget()
        guard let pid = browser?.processIdentifier else { throw CardError("Browser unavailable.") }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown) else { throw CardError("Could not send text.") }
            let chars = Array(value.utf16); event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            event.flags = []; event.postToPid(pid)
        }
    }
    private func select(_ range: String) async throws {
        let field = try address()
        guard AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else { throw CardError("Cannot focus the cell address field.") }
        try key(0, flags: .maskCommand); try await pause(50)
        try text(range); try await pause(50); try key(36); try await pause()
        // ONLYOFFICE reports the active top-left cell, even when an entire range is selected.
        let active = string(try address(), kAXValueAttribute)
        guard active == range || (range.contains(":") && active == range.components(separatedBy: ":")[0]) else {
            throw CardError("Could not select \(range). Saving stopped.")
        }
    }
    private func copy(_ range: String) async throws -> String {
        try await select(range)
        let pb = NSPasteboard.general
        let before = pb.changeCount
        try key(8, flags: .maskCommand)
        for _ in 0..<30 {
            try await pause(100)
            if pb.changeCount != before, let text = pb.string(forType: .string) {
                clipboardVersion = pb.changeCount
                _ = try ensureTarget()
                if range.contains(":") {
                    let ends = range.components(separatedBy: ":")
                    let rows = ends.compactMap { Int($0.drop(while: { !$0.isNumber })) }
                    var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
                    if lines.last == "" { lines.removeLast() }
                    guard rows.count == 2, lines.count == rows[1] - rows[0] + 1,
                          lines.allSatisfy({ $0.components(separatedBy: "\t").count == 2 }) else {
                        throw CardError("Copied cells do not match the complete requested range. Saving stopped; inspect the workbook before retrying.")
                    }
                }
                return text
            }
        }
        throw CardError("The editor did not copy its cells. Check browser clipboard permission.")
    }
    private func attach() async throws {
        guard AXIsProcessTrusted() else { throw CardError("Enable Accessibility for PlaceCard to update Nextcloud.") }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else { throw CardError("Release shortcut keys before saving.") }
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: "com.brave.Browser")
        for app in candidates {
            // Chromium can withhold the editor's accessibility subtree while in the background.
            // Activate before discovering it; keyboard input still requires the exact file and window.
            app.activate(options: [])
            try await pause(400)
            let root = AXUIElementCreateApplication(app.processIdentifier)
            _ = AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            _ = AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            try await pause(200)
            let windows = attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            for win in windows {
                let nodes = descendants(win)
                let tab = nodes.first(where: { e in
                    let role = string(e, kAXRoleAttribute), title = label(e)
                    return (role == "AXRadioButton" || role == "AXTab") && title.contains(target.filename)
                })
                let workbookVisible = nodes.contains { string($0, kAXRoleAttribute) == "AXWebArea" && label($0).contains(target.filename) }
                guard tab != nil || workbookVisible else { continue }
                browser = app; window = win
                app.activate(options: [])
                _ = AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                if let tab {
                    let pressed = AXUIElementPerformAction(tab, kAXPressAction as CFString)
                    if pressed != .success { _ = AXUIElementSetAttributeValue(tab, kAXValueAttribute as CFString, kCFBooleanTrue) }
                }
                try await pause(400)
                _ = try ensureTarget(); return
            }
        }
        throw CardError("Open \(target.filename) in Brave and sign in to your configured Nextcloud first.")
    }
    private func snapshot() async throws -> (String, CardRegistry) {
        try await select("A1")
        // ONLYOFFICE Ctrl+End selects the final used cell, including gaps in the table.
        try key(119, flags: .maskControl); try await pause(250)
        let value = string(try address(), kAXValueAttribute)
        guard let rowStart = value.firstIndex(where: { $0.isNumber }), let row = Int(value[rowStart...]), row > 1, row <= 10000 else {
            throw CardError("Could not determine the complete workbook range (maximum 10,000 rows).")
        }
        let tsv = try await copy("A1:B\(row)")
        return (tsv, try CardRegistry(tsv: tsv))
    }
    func read() async throws -> CardRegistry { try await transaction(printed: nil, card: nil) }
    func append(printed: String, card: String) async throws -> Int {
        let registry = try await transaction(printed: printed, card: card)
        return registry.nextRow
    }
    private func transaction(printed: String?, card: String?) async throws -> CardRegistry {
        let pb = NSPasteboard.general
        let original: [NSPasteboardItem] = pb.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        clipboardVersion = pb.changeCount
        defer {
            // Never replace clipboard contents the user copied during this operation.
            if pb.changeCount == clipboardVersion { pb.clearContents(); if !original.isEmpty { pb.writeObjects(original) } }
        }
        try await attach()
        let (before, registry) = try await snapshot()
        guard let printed, let card else { return registry }
        try registry.check(printed: printed, card: card)
        let (fresh, current) = try await snapshot()
        guard fresh == before else { throw CardError("Workbook changed during the duplicate check. Retry.") }
        try current.check(printed: printed, card: card)
        let row = current.nextRow
        let empty = try await copy("A\(row):B\(row)")
        guard empty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CardError("The destination row is no longer empty. Retry.") }
        try await select("A\(row)")
        // A leading apostrophe enters an identifier as text, preserving all zeros.
        try text("'" + printed); try key(36); try await pause(200)
        try await select("B\(row)")
        try text("'" + card); try key(36); try await pause(200)
        let verified = try await copy("A\(row):B\(row)")
        guard verified.trimmingCharacters(in: .newlines) == printed + "\t" + card else {
            throw CardError("Row \(row) could not be verified. Inspect it before retrying; automatic saving has stopped.")
        }
        try key(1, flags: .maskCommand); try await pause(300)
        return current
    }
}
