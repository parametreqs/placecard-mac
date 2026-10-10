import Foundation
import Testing
import CardCore

struct WorkbookTargetTests {
    @Test func acceptsOnlyTheConfiguredOriginAndFile() throws {
        let target = try WorkbookTarget(rawURL: "https://cloud.example.org/index.php/apps/files/files/42?openfile=true", filename: "Cards.xlsx")
        #expect(target.matches(URL(string: "https://cloud.example.org/index.php/apps/onlyoffice/42?inframe=true")!))
        #expect(target.matches(URL(string: "https://cloud.example.org/apps/files/files/42")!))
        for url in ["https://other.example.org/index.php/apps/files/files/42", "https://cloud.example.org/index.php/apps/files/files/43", "http://cloud.example.org/index.php/apps/files/files/42", "https://cloud.example.org:8443/index.php/apps/files/files/42", "https://cloud.example.org/index.php/apps/files/files/42/extra", "https://user:password@cloud.example.org/index.php/apps/files/files/42"] {
            #expect(!target.matches(URL(string: url)!))
        }
    }
    @Test func supportsSubdirectoryInstallationsAndExplicitPorts() throws {
        let target = try WorkbookTarget(rawURL: "https://cloud.example.org:8443/nextcloud/index.php/apps/files/files/7", filename: "Cards.xlsx")
        #expect(target.matches(URL(string: "https://cloud.example.org:8443/nextcloud/index.php/apps/onlyoffice/7")!))
        #expect(!target.matches(URL(string: "https://cloud.example.org:8443/index.php/apps/onlyoffice/7")!))
    }
    @Test func rejectsMissingTargetsAndUnsafeFilenames() {
        for url in ["", "file:///tmp/cards.xlsx", "http://cloud.example.org/apps/files/files/1", "https://user:password@cloud.example.org/apps/files/files/1", "https://cloud.example.org/apps/files", "https://cloud.example.org/apps/files/files/1/extra"] {
            #expect(throws: CardError.self) { try WorkbookTarget(rawURL: url, filename: "Cards.xlsx") }
        }
        for name in ["", "Cards.csv", "folder/Cards.xlsx", "Cards\t.xlsx", "Cards\n.xlsx"] {
            #expect(throws: CardError.self) { try WorkbookTarget(rawURL: "https://cloud.example.org/apps/files/files/1", filename: name) }
        }
    }
}
