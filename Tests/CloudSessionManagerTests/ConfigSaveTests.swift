import Foundation
import Testing
@testable import CloudSessionManager

/// Covers writing the config file, including onto a fresh machine where the
/// `.aws` directory doesn't exist yet.
@Suite("Config save")
struct ConfigSaveTests {

    @Test func createsAWSDirectoryWhenMissing() throws {
        // A parent that exists, but no `.aws` inside it — the fresh-install case.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("awssso-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let awsDir = root.appendingPathComponent(".aws")
        #expect(!FileManager.default.fileExists(atPath: awsDir.path))

        let config = AWSConfig(awsDirectory: awsDir)
        let document = ConfigDocument.parse("[profile dev]\nregion = us-east-1")
        try config.save(document)

        let written = try String(contentsOf: config.configURL, encoding: .utf8)
        #expect(written.contains("[profile dev]"))
        #expect(written.contains("region = us-east-1"))
    }
}
