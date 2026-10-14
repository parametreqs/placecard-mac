import SwiftUI
import AppKit
import ApplicationServices
import CardCore

enum Terminator: String, CaseIterable, Identifiable {
    case none = "None", enter = "Return", tab = "Tab"
    var id: String { rawValue }
    var code: CGKeyCode? { self == .enter ? 36 : self == .tab ? 48 : nil }
}
@MainActor final class Model: ObservableObject {
    @Published var devices = Device.available()
    @Published var selected = ""
    @Published var status = "Connect your Z-2 reader and choose Start reading."
    @Published var connected = false
    @Published var reading = false
    @Published var typing = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var latest: Card?
    @Published var log: [String] = []
    @Published var transform = (UserDefaults.standard.data(forKey: "transform").flatMap { try? JSONDecoder().decode(NumberTransform.self, from: $0) } ?? NumberTransform()) {
        didSet { typing = false; cloudEnabled = false; pending = nil; if connected { status = "Connected" }; UserDefaults.standard.set(try? JSONEncoder().encode(transform), forKey: "transform") }
    }
    @Published var cloudEnabled = false {
        didSet { if cloudEnabled { typing = false; pending = nil; cloudStatus = "Ready. Scan a card and enter its four printed digits." }; debounce?.cancel() }
    }
    @Published var printed = "" { didSet { scheduleSave() } }
    @Published var cloudStatus = "Open the workbook in Brave, then enable automatic saving."
    @Published var showWorkbookSettings = false
    @Published var cloudBusy = false
    @Published var pending: Card?
    @Published var workbookURL = UserDefaults.standard.string(forKey: "workbookURL") ?? "" {
        didSet { cloudEnabled = false; pending = nil; UserDefaults.standard.set(workbookURL, forKey: "workbookURL") }
    }
    @Published var workbookName = UserDefaults.standard.string(forKey: "workbookName") ?? "" {
        didSet { cloudEnabled = false; pending = nil; UserDefaults.standard.set(workbookName, forKey: "workbookName") }
    }
    var workbookTarget: WorkbookTarget? { try? WorkbookTarget(rawURL: workbookURL, filename: workbookName) }
    var workbookError: String? {
        do { _ = try WorkbookTarget(rawURL: workbookURL, filename: workbookName); return nil }
        catch { return error.localizedDescription }
    }
    private func writer() throws -> NextcloudWriter {
        NextcloudWriter(target: try WorkbookTarget(rawURL: workbookURL, filename: workbookName))
    }
    private var debounce: Task<Void, Never>?
    @Published var format = OutputFormat(rawValue: UserDefaults.standard.string(forKey: "format") ?? "") ?? .automaticMifare {
        didSet {
            typing = false; cloudEnabled = false; pending = nil
            // Selecting Auto starts with identity adjustments so a previously forced decimal
            // output or padding cannot change a four-byte card's original hex identifier.
            if format == .automaticMifare { transform = NumberTransform() }
            if connected { status = "Connected" }
            UserDefaults.standard.set(format.rawValue, forKey: "format")
        }
    }
    @Published var ending = Terminator(rawValue: UserDefaults.standard.string(forKey: "ending") ?? "") ?? .none {
        didSet { typing = false; UserDefaults.standard.set(ending.rawValue, forKey: "ending") }
    }
    private var worker: ReaderWorker?
    private var generation = UUID()
    private var timer: Timer?
    init() {
        selected = devices.first?.id ?? ""
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.trusted = AXIsProcessTrusted()
                if !self.trusted { self.typing = false; self.cloudEnabled = false; self.pending = nil }
                if !self.reading {
                    self.devices = Device.available()
                    if !self.devices.contains(where: { $0.id == self.selected }) { self.selected = self.devices.first?.id ?? "" }
                }
            }
        }
    }
    func permission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
    }
    func render(_ card: Card) -> String? { try? transform.render(card, source: format) }
    var preview: String { latest.map { card in (try? transform.render(card, source: format)) ?? "Format unavailable" } ?? "—" }
    var formatError: String? {
        guard let latest else { return nil }
        do { _ = try transform.render(latest, source: format); return nil } catch { return error.localizedDescription }
    }
    private func scheduleSave() {
        debounce?.cancel()
        guard cloudEnabled, !cloudBusy, pending != nil, CardRegistry.validPrinted(printed) else { return }
        debounce = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 700_000_000) } catch { return }
            guard !Task.isCancelled else { return }; self?.saveRecord()
        }
    }
    func checkWorkbook() {
        guard !cloudBusy else { return }
        cloudBusy = true; cloudStatus = "Reading existing records…"
        Task {
            do {
                let records = try await writer().read()
                if let existing = records.existingPrinted(printed), CardRegistry.validPrinted(printed) {
                    cloudStatus = "Printed number \(printed) already exists on row \(existing.row) (\(existing.card))."
                } else { cloudStatus = "Checked \(records.entries.count) records. Next empty row: \(records.nextRow)." }
            }
            catch { cloudStatus = error.localizedDescription }
            cloudBusy = false; NSApp.activate(ignoringOtherApps: true)
        }
    }
    func saveRecord() {
        debounce?.cancel()
        guard cloudEnabled, !cloudBusy, CardRegistry.validPrinted(printed), let pending else { return }
        let digits = printed
        let value: String
        do { value = try transform.render(pending, source: format) }
        catch { cloudStatus = error.localizedDescription; return }
        cloudBusy = true; cloudStatus = "Checking duplicates in Nextcloud…"
        Task {
            do {
                let row = try await writer().append(printed: digits, card: value)
                self.pending = nil; printed = ""
                cloudStatus = "Added \(digits) → \(value) on row \(row). Save requested; check Nextcloud’s saved status."
                appendLog("Nextcloud row \(row): \(digits) → \(value)")
            } catch {
                cloudStatus = error.localizedDescription
                // Re-presenting a card or editing the digits is required for another automatic attempt.
                // Uncertain/partial writes are left visible and never overwritten or rolled back blindly.
                if !cloudStatus.contains("already exists") { cloudEnabled = false }
            }
            cloudBusy = false; NSApp.activate(ignoringOtherApps: true)
        }
    }
    func start() {
        guard !reading, let device = devices.first(where: { $0.id == selected }) else { return }
        typing = false; reading = true; connected = false; latest = nil; pending = nil
        status = "Connecting…"
        let token = UUID(); generation = token
        let worker = ReaderWorker(); self.worker = worker
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            worker.run(device: device) { message, events in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    if let message {
                        self.status = message
                        self.connected = message == "Connected"
                        if !self.connected { self.typing = false; self.cloudEnabled = false; self.pending = nil; self.reading = false; self.worker = nil }
                    }
                    for event in events { self.receive(event) }
                }
            }
        }
    }
    func stop() {
        generation = UUID(); worker?.stop(); worker = nil
        typing = false; cloudEnabled = false; pending = nil; reading = false; connected = false; status = "Stopped"
    }
    func receive(_ event: ReaderEvent) {
        switch event {
        case .removed: break
        case .message(let message): appendLog(message)
        case .card(let card):
            latest = card
            let value: String
            do { value = try transform.render(card, source: format) }
            catch { status = error.localizedDescription; appendLog(status); return }
            appendLog("\(card.kind): \(value)")
            if cloudEnabled {
                guard !cloudBusy else { appendLog("Scan skipped while a workbook update is in progress."); return }
                pending = card; cloudStatus = "Card ready. Enter its four printed digits."; scheduleSave(); return
            }
            guard typing else { return }
            guard AXIsProcessTrusted() else { typing = false; status = "Enable Accessibility permission to type card numbers."; return }
            guard let target = NSWorkspace.shared.frontmostApplication,
                  target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                status = "Card read. Focus Notes or another app to type the next card."; return
            }
            // Avoid sending a terminator while the user is holding a shortcut modifier.
            let flags = CGEventSource.flagsState(.combinedSessionState)
            guard flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
                status = "Card read; typing skipped while a modifier key is held."; return
            }
            let source = CGEventSource(stateID: .privateState)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                typing = false; status = "Could not create keyboard events."; return
            }
            let text = Array(value.utf16)
            down.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
            up.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
            down.flags = []; up.flags = []
            down.postToPid(target.processIdentifier); up.postToPid(target.processIdentifier)
            if let key = ending.code {
                let endDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
                let endUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
                endDown?.flags = []; endUp?.flags = []
                endDown?.postToPid(target.processIdentifier); endUp?.postToPid(target.processIdentifier)
            }
            status = "Sent \(value) to \(target.localizedName ?? "active app")"
        }
    }
    private func appendLog(_ text: String) { log.append(text); if log.count > 100 { log.removeFirst(log.count - 100) } }
}

struct PrintedNumberView: View {
    @Binding var value: String
    var submit: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                ForEach(0..<4) { i in
                    Text(i < value.count ? String(Array(value)[i]) : "·")
                        .font(.system(size: 42, weight: .semibold, design: .monospaced))
                        .foregroundStyle(i < value.count ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: 67, height: 82)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(focused ? Color.blue.opacity(0.65) : Color.secondary.opacity(0.2), lineWidth: focused ? 2 : 1))
                }
            }.accessibilityHidden(true)
            TextField("Four printed digits", text: $value)
                .textFieldStyle(.plain).foregroundStyle(.clear).tint(.clear)
                .font(.system(size: 42, design: .monospaced))
                .frame(width: 298, height: 82).focused($focused)
                .accessibilityLabel("Four printed digits").onSubmit(submit)
        }.contentShape(Rectangle()).onTapGesture { focused = true }
    }
}
struct MainView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "wave.3.right.circle.fill").font(.system(size: 36)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("PlaceCard for Mac").font(.title2.bold())
                    Text("Z-2 RD_ALL · Card number entry").foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 10, height: 10)
            }
            HStack {
                Picker("Reader", selection: $model.selected) {
                    if model.devices.isEmpty { Text("No reader detected").tag("") }
                    ForEach(model.devices) { Text($0.label).tag($0.id) }
                }.disabled(model.reading)
                Button(model.reading ? "Stop" : "Start reading") { model.reading ? model.stop() : model.start() }
                    .disabled(model.cloudBusy || (!model.reading && model.selected.isEmpty))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Last card").font(.caption).foregroundStyle(.secondary)
                Text(model.preview).font(.system(size: 30, weight: .medium, design: .monospaced)).textSelection(.enabled)
                if let card = model.latest { Text("\(card.kind) · \(card.reportedHex.count / 2)-byte · Reader hex: \(card.reportedHex)").font(.caption).foregroundStyle(.secondary) }
                if let error = model.formatError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            TabView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(model.workbookName.isEmpty ? "Nextcloud workbook" : model.workbookName, systemImage: "tablecells").font(.headline)
                        Spacer()
                        Button("Workbook…") { model.showWorkbookSettings = true }.disabled(model.cloudBusy)
                        if let target = model.workbookTarget { Link("Open workbook", destination: target.url) }
                    }
                    Toggle("Automatically add cards to Nextcloud", isOn: $model.cloudEnabled)
                        .disabled(!model.connected || !model.trusted || model.cloudBusy || model.workbookTarget == nil)
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("NUMBER PRINTED ON CARD").font(.caption.bold()).foregroundStyle(.secondary)
                            PrintedNumberView(value: $model.printed) { model.saveRecord() }.disabled(model.cloudBusy)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Label(model.pending == nil ? "Scan a card" : "Card ready", systemImage: model.pending == nil ? "wave.3.right" : "checkmark.circle.fill")
                                .foregroundStyle(model.pending == nil ? Color.secondary : Color.green)
                            Text(model.pending.flatMap { model.render($0) } ?? "Waiting for reader").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            Text("Column A: printed number\nColumn B: scanned number").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !model.printed.isEmpty && !CardRegistry.validPrinted(model.printed) { Text("Enter exactly four digits, including any leading zero.").font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button("Check workbook") { model.checkWorkbook() }.disabled(!model.trusted || model.cloudBusy || model.workbookTarget == nil)
                        Button("Retry this card") { model.saveRecord() }.disabled(!model.cloudEnabled || model.cloudBusy || model.pending == nil || !CardRegistry.validPrinted(model.printed))
                        if model.cloudBusy { ProgressView().controlSize(.small) }
                    }
                    Text(model.workbookTarget == nil ? "Choose Workbook… to set your Nextcloud file link and filename, or use the Typing tab for Notes." : model.cloudStatus).font(.callout).textSelection(.enabled)
                    Text("Keep the workbook open in Brave. Saving briefly focuses its editor. Both numbers are checked against existing records; duplicate entries are blocked.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.padding(18).tabItem { Label("Nextcloud", systemImage: "cloud") }
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Source", selection: $model.format) { ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Output", selection: $model.transform.notation) { ForEach(NumberNotation.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Byte positions", text: $model.transform.byteOrder, prompt: Text("1,2,3 or 3,2,1"))
                    Text(model.format == .automaticMifare ? "Four-byte Mifare stays hex; seven-byte Mifare uses Windows decimal. No format switching needed." : "Choose a hex source to select or rearrange bytes. Positions start at 1; leave blank to use all bytes.").font(.caption).foregroundStyle(.secondary)
                    TextField("Calculation", text: $model.transform.expression, prompt: Text("x"))
                    Text("x is the source number. Use + − * / %, & | ^, << >>, ~ and parentheses. Example: (x & 0xFFFFFFFF) + 8. Integer arithmetic, up to 64 bits.").font(.caption).foregroundStyle(.secondary)
                    Stepper("Minimum digits: \(model.transform.width)", value: $model.transform.width, in: 0...64)
                    Text("Leading zeros fill the minimum width. Digits are never truncated. The live result appears above.").font(.caption).foregroundStyle(.secondary)
                    Button("Reset adjustments") { model.transform = NumberTransform() }
                    Spacer(minLength: 0)
                }.padding(18).disabled(model.cloudBusy).tabItem { Label("Number format", systemImage: "slider.horizontal.3") }
                VStack(alignment: .leading, spacing: 16) {
                    Picker("After number", selection: $model.ending) { ForEach(Terminator.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Type card numbers into the active app", isOn: $model.typing)
                        .disabled(!model.connected || !model.trusted || model.cloudEnabled || model.cloudBusy)
                    Text("Enable typing, then click in Notes or another text field. Remove and present the card again for each entry.").foregroundStyle(.secondary)
                    Text("Nextcloud mode pairs each scan with the printed number. Disable it to use ordinary typing.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.padding(18).tabItem { Label("Typing", systemImage: "keyboard") }
            }.frame(height: 365)
            if !model.trusted {
                HStack {
                    Text("Accessibility is required for typing and Nextcloud entry.").font(.callout)
                    Spacer()
                    Button("Enable Accessibility…") { model.permission() }
                }
            }
            Text(model.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            DisclosureGroup("Reader messages") {
                ScrollView { Text(model.log.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 80)
            }
        }.padding(26).frame(minWidth: 710, idealWidth: 760, minHeight: 670)
        .sheet(isPresented: $model.showWorkbookSettings) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nextcloud workbook").font(.title2.bold())
                TextField("File link", text: $model.workbookURL, prompt: Text("https://cloud.example.org/index.php/apps/files/files/42"))
                TextField("Workbook filename", text: $model.workbookName, prompt: Text("Cards.xlsx"))
                Text("Use a dedicated two-column card register with its intended sheet active: printed digits in A, scanned numbers in B. Keep it open in Brave and use one registration operator at a time.").font(.callout).foregroundStyle(.secondary)
                if let error = model.workbookError { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack { Spacer(); Button("Done") { model.showWorkbookSettings = false }.keyboardShortcut(.defaultAction) }
            }.padding(26).frame(width: 560)
        }
    }
}
struct PlaceCardApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup { MainView(model: model) }.windowResizability(.contentSize)
        MenuBarExtra("PlaceCard", systemImage: "wave.3.right") {
            Text(model.status)
            Toggle("Type card numbers", isOn: $model.typing).disabled(!model.connected || !model.trusted || model.cloudEnabled || model.cloudBusy)
            Button("Stop reading") { model.stop() }.disabled(!model.reading)
            Divider()
            Button("Show PlaceCard") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Button("Quit") { model.stop(); NSApp.terminate(nil) }
        }
    }
}
@main enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--list") {
            for device in Device.available() { print("\(device.id)\t\(device.label)") }
            return
        }
        if let index = args.firstIndex(of: "--capture"), args.count > index + 2 {
            let id = args[index + 1]
            guard let seconds = Double(args[index + 2]), seconds > 0, seconds <= 600 else {
                fputs("Capture duration must be between 0 and 600 seconds.\n", stderr); exit(2)
            }
            let device = Device.available().first { $0.id == id } ?? Device(id: id, label: id, location: nil)
            let worker = ReaderWorker()
            var failed = false
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { worker.stop() }
            worker.run(device: device) { message, events in
                if let message { print(message); if message != "Connected" { failed = true } }
                for event in events { print(String(describing: event)) }
                fflush(stdout)
            }
            if failed { exit(1) }
            return
        }
        PlaceCardApp.main()
    }
}
