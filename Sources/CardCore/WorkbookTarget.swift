import Foundation

/// Immutable destination for one browser transaction. No account information is bundled.
public struct WorkbookTarget {
    public let url: URL
    public let filename: String
    private let paths: Set<String>

    public init(rawURL: String, filename: String) throws {
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 255, name.lowercased().hasSuffix(".xlsx"),
              !name.contains(where: { $0.isNewline || $0 == "\t" || $0 == "/" || $0 == "\\" }) else {
            throw CardError("Enter the exact workbook filename, ending in .xlsx.")
        }
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw CardError("Enter an HTTPS Nextcloud file link without embedded login details.")
        }
        let pattern = #"^(.*?)(?:/index\.php)?/apps/(?:files/files|onlyoffice)/([0-9]+)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: url.path, range: NSRange(url.path.startIndex..., in: url.path)),
              let prefixRange = Range(match.range(at: 1), in: url.path),
              let idRange = Range(match.range(at: 2), in: url.path) else {
            throw CardError("Use the Nextcloud link that opens a specific workbook, including its numeric file ID.")
        }
        let prefix = String(url.path[prefixRange]), id = String(url.path[idRange])
        self.url = url; self.filename = name
        paths = Set(["/index.php/apps/files/files/", "/apps/files/files/", "/index.php/apps/onlyoffice/", "/apps/onlyoffice/"].map { prefix + $0 + id })
    }

    public func matches(_ candidate: URL) -> Bool {
        candidate.scheme?.lowercased() == "https" && candidate.host?.lowercased() == url.host?.lowercased()
            && (candidate.port ?? 443) == (url.port ?? 443) && candidate.user == nil && candidate.password == nil
            && paths.contains(candidate.path)
    }
}
