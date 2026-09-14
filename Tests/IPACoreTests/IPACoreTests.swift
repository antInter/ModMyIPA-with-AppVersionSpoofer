import XCTest
import Foundation
import ZIPFoundation
@testable import IPACore

final class IPACoreTests: XCTestCase {
    var root: URL!
    let mainPath = "Payload/Demo.app/Info.plist"
    let nestedPath = "Payload/Demo.app/PlugIns/Widget.appex/Info.plist"
    let frameworkPath = "Payload/Demo.app/Frameworks/Library.framework/Info.plist"
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func words(_ values: [UInt32], little: Bool = true) -> Data {
        Data(values.flatMap { value in
            (0..<4).map { UInt8(truncatingIfNeeded: value >> ((little ? $0 : 3 - $0) * 8)) }
        })
    }
    func binary(encrypted: Bool = false) -> Data {
        // Synthetic Mach-O header with one encryption command. Not executable code.
        words([0xfeedfacf, 0x0100000c, 0, 2, 1, 24, 0, 0,
               0x2c, 24, 0, 0, encrypted ? 1 : 0, 0])
    }
    func plist(format: PropertyListSerialization.PropertyListFormat = .binary,
               identifier: String = "org.example.demo", executable: String = "Demo") throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleExecutable": executable, "CFBundleIdentifier": identifier,
            "CFBundleName": "Demo", "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42", "MinimumOSVersion": "15.0",
            "CustomMetadata": ["array": [1, 2], "flag": true]
        ], format: format, options: 0)
    }
    func append(_ archive: Archive, path: String, data: Data, type: Entry.EntryType = .file, permissions: UInt16 = 0o644) throws {
        try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count),
                             permissions: permissions, compressionMethod: .none) { offset, count in
            data.subdata(in: Int(offset)..<min(Int(offset) + count, data.count))
        }
    }
    func fixture(xml: Bool = false, encrypted: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + ".ipa")
        let archive = try Archive(url: url, accessMode: .create)
        try append(archive, path: mainPath, data: plist(format: xml ? .xml : .binary))
        try append(archive, path: "Payload/Demo.app/Demo", data: binary(encrypted: encrypted), permissions: 0o755)
        try append(archive, path: nestedPath, data: plist(identifier: "org.example.demo.widget", executable: "Widget"))
        try append(archive, path: "Payload/Demo.app/PlugIns/Widget.appex/Widget", data: binary(), permissions: 0o755)
        try append(archive, path: frameworkPath, data: plist(identifier: "org.example.library"))
        try append(archive, path: "Payload/Demo.app/_CodeSignature/CodeResources", data: Data("original-signature-metadata".utf8))
        try append(archive, path: "Payload/Demo.app/embedded.mobileprovision", data: Data("original-profile".utf8))
        try append(archive, path: "Payload/Demo.app/resource.dat", data: Data(repeating: 137, count: 150_000))
        try append(archive, path: "iTunesMetadata.plist", data: Data("outside-payload-preserved".utf8))
        return url
    }
    func prepare(_ url: URL, limits: IPALimits = IPALimits()) throws -> PreparedIPA {
        try MyFileManager(limits: limits).prepare(ipa: url, workspaceParent: root.appendingPathComponent("work"))
    }
    func export(_ ipa: PreparedIPA, version: String? = "9.8.7", build: String? = "123", sync: Bool = true) throws -> URL {
        try MyFileManager().export(ipa, changes: VersionChanges(version: version, build: build, synchronizeNestedBundles: sync), outputDirectory: root.appendingPathComponent("out"))
    }
    func data(_ path: String, in url: URL) throws -> Data {
        let archive = try Archive(url: url, accessMode: .read)
        let entry = try XCTUnwrap(archive[path])
        var result = Data()
        let checksum = try archive.extract(entry) { result.append($0) }
        XCTAssertEqual(checksum, entry.checksum)
        return result
    }
    func info(_ path: String, in url: URL) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: data(path, in: url), options: [], format: nil) as? [String: Any])
    }

    func testRoundTripPreservesOriginalBinaryResourcesAndPermissions() throws {
        let input = try fixture()
        let original = try Data(contentsOf: input)
        let prepared = try prepare(input)
        XCTAssertEqual(prepared.bundles.count, 2)
        let output = try export(prepared)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try info(mainPath, in: output)["CFBundleShortVersionString"] as? String, "9.8.7")
        XCTAssertEqual(try info(mainPath, in: output)["CFBundleVersion"] as? String, "123")
        XCTAssertEqual(try info(nestedPath, in: output)["CFBundleVersion"] as? String, "123")
        XCTAssertEqual(try info(mainPath, in: output)["MinimumOSVersion"] as? String, "15.0")
        XCTAssertEqual(try info(mainPath, in: output)["CFBundleIdentifier"] as? String, "org.example.demo")
        let source = try Archive(url: input, accessMode: .read)
        let destination = try Archive(url: output, accessMode: .read)
        XCTAssertEqual(Set(source.map(\.path)), Set(destination.map(\.path)))
        for entry in source where entry.path != mainPath && entry.path != nestedPath {
            XCTAssertEqual(try data(entry.path, in: input), try data(entry.path, in: output), entry.path)
        }
        let executable = try XCTUnwrap(destination["Payload/Demo.app/Demo"])
        XCTAssertEqual((executable.fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
        XCTAssertTrue(try data(mainPath, in: output).starts(with: Data("bplist00".utf8)))
    }
    func testXMLFormatAndUnknownMetadataPreserved() throws {
        let output = try export(prepare(fixture(xml: true)))
        XCTAssertTrue(try data(mainPath, in: output).starts(with: Data("<?xml".utf8)))
        let custom = try XCTUnwrap(info(mainPath, in: output)["CustomMetadata"] as? [String: Any])
        XCTAssertEqual(custom["flag"] as? Bool, true)
    }
    func testVersionOnlyPreservesBuild() throws {
        let output = try export(prepare(fixture()), build: nil)
        XCTAssertEqual(try info(mainPath, in: output)["CFBundleVersion"] as? String, "42")
        XCTAssertEqual(try info(nestedPath, in: output)["CFBundleVersion"] as? String, "42")
    }
    func testBuildOnlyPreservesVersion() throws {
        let output = try export(prepare(fixture()), version: nil)
        XCTAssertEqual(try info(mainPath, in: output)["CFBundleShortVersionString"] as? String, "1.2.3")
    }
    func testRepeatedExportsDoNotLeakPreviousEdits() throws {
        let input = try fixture()
        let prepared = try prepare(input)
        let first = try export(prepared)
        let second = try export(prepared, version: "2.0.0", build: nil, sync: false)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try info(mainPath, in: second)["CFBundleVersion"] as? String, "42")
        XCTAssertEqual(try data(nestedPath, in: input), try data(nestedPath, in: second))
        XCTAssertEqual(try Data(contentsOf: prepared.contents.appendingPathComponent(mainPath)), try data(mainPath, in: input))
    }
    func testRejectsInvalidVersions() {
        for value in ["", "1", "1.2", "1.2.3.4", "-1.0.0", "1.2.x", "1.2.3\n"] {
            XCTAssertThrowsError(try VersionChanges(version: value, build: nil).validate(), value)
        }
        XCTAssertThrowsError(try VersionChanges(version: nil, build: nil).validate())
        XCTAssertThrowsError(try VersionChanges(version: nil, build: "1.234.5").validate())
        XCTAssertNoThrow(try VersionChanges(version: "0.1.0", build: "123.4.5").validate())
    }
    func testRejectsUnsafePaths() {
        for path in ["../escape", "/absolute", "a/../b", "a//b", "a\\b", "a/./b", "C:/file", "a\u{0}b"] {
            XCTAssertThrowsError(try MyFileManager.safePath(path), path)
        }
    }
    func testRejectsZipSlipAndCleansWorkspace() throws {
        let input = try fixture()
        do { let a = try Archive(url: input, accessMode: .update); try append(a, path: "../escape", data: Data([1])) }
        XCTAssertThrowsError(try prepare(input))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("work").path), [])
    }
    func testRejectsSymlinks() throws {
        let input = try fixture()
        do { let a = try Archive(url: input, accessMode: .update); try append(a, path: "Payload/link", data: Data("../../escape".utf8), type: .symlink) }
        XCTAssertThrowsError(try prepare(input))
    }
    func testRejectsCaseCollidingParentDirectories() throws {
        let input = try fixture()
        do { let a = try Archive(url: input, accessMode: .update); try append(a, path: "payload/other", data: Data([1])) }
        XCTAssertThrowsError(try prepare(input))
    }
    func testRejectsDuplicatePaths() throws {
        let input = try fixture()
        do { let a = try Archive(url: input, accessMode: .update); try append(a, path: mainPath, data: plist()) }
        XCTAssertThrowsError(try prepare(input))
    }
    func testRejectsMissingExecutable() throws {
        let input = try fixture()
        let prepared = try prepare(input)
        try FileManager.default.removeItem(at: prepared.contents.appendingPathComponent("Payload/Demo.app/Demo"))
        XCTAssertThrowsError(try export(prepared))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("out").path), [])
    }
    func testRejectsEncryptedMainExecutable() throws { XCTAssertThrowsError(try prepare(fixture(encrypted: true))) }
    func testLimitsAndCancellation() throws {
        let input = try fixture()
        XCTAssertThrowsError(try prepare(input, limits: IPALimits(maxEntries: 2)))
        XCTAssertThrowsError(try prepare(input, limits: IPALimits(maxBytes: 10)))
        let cancelled = Progress(totalUnitCount: 1); cancelled.cancel()
        XCTAssertThrowsError(try MyFileManager().prepare(ipa: input, workspaceParent: root.appendingPathComponent("work"), progress: cancelled))
        let prepared = try prepare(input)
        XCTAssertThrowsError(try MyFileManager().export(prepared, changes: VersionChanges(version: "2.0.0"), outputDirectory: root.appendingPathComponent("out"), progress: cancelled))
    }
    func testMachOThinFatAndMalformedHeaders() throws {
        let file = root.appendingPathComponent("binary")
        try binary().write(to: file)
        XCTAssertFalse(try MachOInspector.isEncrypted(file))
        try binary(encrypted: true).write(to: file)
        XCTAssertTrue(try MachOInspector.isEncrypted(file))
        var fat = words([0xcafebabe, 1, 0x0100000c, 0, 28, 56, 0], little: false)
        fat.append(binary(encrypted: true))
        try fat.write(to: file)
        XCTAssertTrue(try MachOInspector.isEncrypted(file))
        try Data([1, 2, 3]).write(to: file)
        XCTAssertThrowsError(try MachOInspector.isEncrypted(file))
        var malformed = binary(); malformed[36] = 255
        try malformed.write(to: file)
        XCTAssertThrowsError(try MachOInspector.isEncrypted(file))
    }
    func testRejectsCorruptCRC() throws {
        let input = try fixture()
        var raw = try Data(contentsOf: input)
        let marker = Data("outside-payload-preserved".utf8)
        let range = try XCTUnwrap(raw.range(of: marker)); raw[range.lowerBound] ^= 1
        try raw.write(to: input)
        XCTAssertThrowsError(try prepare(input))
    }
}
