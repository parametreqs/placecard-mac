import Foundation
import Z2Transport
import CardCore

struct Device: Identifiable, Equatable {
    let id: String
    let label: String
    let location: UInt32?
    static func available() -> [Device] {
        var storage = [Z2Device](repeating: Z2Device(), count: 32)
        let count = z2_devices(&storage, Int32(storage.count))
        var devices = storage.prefix(Int(count)).map { d -> Device in
            var name = d.name
            let label = withUnsafePointer(to: &name) { p in p.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            return Device(id: "usb:\(d.location)", label: label, location: d.location)
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        devices += files.filter { $0.hasPrefix("cu.") && ($0.localizedCaseInsensitiveContains("usb") || $0.localizedCaseInsensitiveContains("wch")) }
            .sorted().map { Device(id: "/dev/\($0)", label: $0, location: nil) }
        return devices
    }
    func open(error: inout [CChar]) -> OpaquePointer? {
        if let location { return z2_open_usb(location, &error, error.count) }
        return z2_open_serial(id, &error, error.count)
    }
}
final class ReaderWorker: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func run(device: Device, callback: @escaping (String?, [ReaderEvent]) -> Void) {
        var error = [CChar](repeating: 0, count: 512)
        guard let connection = device.open(error: &error) else { callback(String(cString: error), []); return }
        defer { z2_close(connection) }
        callback("Connected", [])
        if z2_identify(connection, &error, error.count) != 0 { callback(String(cString: error), []); return }
        var stream = ReaderStream()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while !isStopped {
            let count = z2_read(connection, &bytes, Int32(bytes.count), &error, error.count)
            if count < 0 { callback(String(cString: error), []); return }
            if count > 0 { callback(nil, stream.feed(Array(bytes.prefix(Int(count))))) }
        }
    }
}
