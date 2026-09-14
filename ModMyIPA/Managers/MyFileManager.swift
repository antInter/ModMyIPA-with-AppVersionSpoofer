// Original ModMyIPA project by powenn. New sandbox-only IPA version editing core.
// ZIPFoundation is pinned to 0.9.20 in both the app and the core test package.
import Foundation
import ZIPFoundation

struct IPAError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct IPALimits {
    var maxEntries = 100_000
    var maxBytes: UInt64 = 4 * 1024 * 1024 * 1024
    var diskReserve: UInt64 = 128 * 1024 * 1024
}

struct IPABundle {
    let path: String
    let original: Data
    let format: PropertyListSerialization.PropertyListFormat
    let info: [String: Any]
    var version: String { info["CFBundleShortVersionString"] as? String ?? "" }
    var build: String { info["CFBundleVersion"] as? String ?? "" }
}

struct PreparedIPA {
    let workspace: URL
    let contents: URL
    let bundles: [IPABundle] // main bundle first; then nested apps/extensions
    let expandedBytes: UInt64
    var main: IPABundle { bundles[0] }
    var displayName: String {
        main.info["CFBundleDisplayName"] as? String ?? main.info["CFBundleName"] as? String ?? "App"
    }
    var bundleIdentifier: String { main.info["CFBundleIdentifier"] as? String ?? "" }
}

struct VersionChanges {
    // nil preserves the original value, even if it uses an unusual format.
    var version: String?
    var build: String?
    var synchronizeNestedBundles = true
    func validate() throws {
        guard version != nil || build != nil else { throw IPAError("Choose at least one field to edit.") }
        if let v = version {
            guard v.utf8.count <= 64,
                  v.range(of: #"\A[0-9]+\.[0-9]+\.[0-9]+\z"#, options: .regularExpression) != nil else {
                throw IPAError("Use three numbers for the app version, for example 3.2.1.")
            }
        }
        if let v = build {
            guard v.range(of: #"\A[0-9]{1,4}(\.[0-9]{1,2}){0,2}\z"#, options: .regularExpression) != nil else {
                throw IPAError("Use a release build number such as 123 or 123.4.5 (up to 4, 2, and 2 digits). Development suffixes are not supported for new values.")
            }
        }
    }
}

final class MyFileManager {
    let limits: IPALimits
    private let fm = FileManager.default
    init(limits: IPALimits = IPALimits()) { self.limits = limits }

    static func checkCancellation(_ progress: Progress) throws {
        if progress.isCancelled { throw IPAError("Operation cancelled. No output was published.") }
    }

    static func safePath(_ path: String, directory: Bool = false) throws -> String {
        var value = path
        if directory && value.hasSuffix("/") { value.removeLast() }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty, value.utf8.count <= 4096, !value.contains("\\"), !value.contains(":"),
              !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
            throw IPAError("Unsafe archive path: \(path.prefix(100))")
        }
        return value
    }

    private func requireSpace(at url: URL, bytes: UInt64) throws {
        let attributes = try fm.attributesOfFileSystem(forPath: url.path)
        if let free = attributes[.systemFreeSize] as? NSNumber, free.uint64Value < bytes + limits.diskReserve {
            throw IPAError("Not enough storage for the IPA, its extracted contents, and a new output file.")
        }
    }

    func prepare(ipa: URL, workspaceParent: URL, progress: Progress = Progress(totalUnitCount: 1)) throws -> PreparedIPA {
        try fm.createDirectory(at: workspaceParent, withIntermediateDirectories: true)
        let root = workspaceParent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: root) } }
        let inputSize = (try fm.attributesOfItem(atPath: ipa.path)[.size] as? NSNumber)?.uint64Value ?? 0
        guard inputSize > 0, inputSize <= limits.maxBytes else { throw IPAError("IPA is empty or exceeds the input size limit (normally 4 GiB).") }
        try requireSpace(at: root, bytes: inputSize)
        try Self.checkCancellation(progress)
        let input = root.appendingPathComponent("input.ipa")
        try fm.copyItem(at: ipa, to: input)
        let archive = try Archive(url: input, accessMode: .read)
        var entries: [(Entry, String)] = []
        var seen = Set<String>()
        var spellings: [String: String] = [:]
        var kinds: [String: Bool] = [:]
        var expanded: UInt64 = 0
        for entry in archive {
            try Self.checkCancellation(progress)
            guard entries.count < limits.maxEntries else { throw IPAError("Archive contains too many entries.") }
            guard entry.type != .symlink else { throw IPAError("Symbolic links are not supported by this editor. This includes legitimate symlinks in unusual IPAs.") }
            let path = try Self.safePath(entry.path, directory: entry.type == .directory)
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(key).inserted else { throw IPAError("Duplicate archive path: \(path)") }
            let parts = path.split(separator: "/")
            for count in 1...parts.count {
                let prefix = parts.prefix(count).joined(separator: "/")
                let folded = prefix.precomposedStringWithCanonicalMapping.lowercased()
                if let prior = spellings[folded], prior != prefix { throw IPAError("Case-colliding archive paths are not supported.") }
                spellings[folded] = prefix
            }
            kinds[key] = entry.type == .directory
            guard entry.uncompressedSize <= limits.maxBytes - expanded else { throw IPAError("Expanded archive exceeds the size limit (normally 4 GiB).") }
            expanded += entry.uncompressedSize
            entries.append((entry, path))
        }
        guard !entries.isEmpty else { throw IPAError("Archive is empty or unsupported.") }
        for (_, path) in entries {
            var parts = path.split(separator: "/")
            while parts.count > 1 {
                parts.removeLast()
                let parent = parts.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
                if kinds[parent] == false { throw IPAError("An archive file is also used as a directory.") }
            }
        }
        try requireSpace(at: root, bytes: expanded)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        var actualTotal: UInt64 = 0
        for (entry, path) in entries {
            try Self.checkCancellation(progress)
            let destination = contents.appendingPathComponent(path)
            if entry.type == .directory {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: destination.path, contents: nil) else { throw IPAError("Unable to create extracted file.") }
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            var written: UInt64 = 0
            let checksum = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
                try Self.checkCancellation(progress)
                let count = UInt64(chunk.count)
                guard count <= entry.uncompressedSize - written, count <= self.limits.maxBytes - actualTotal else {
                    throw IPAError("Archive expands beyond its declared size.")
                }
                try handle.write(contentsOf: chunk)
                written += count
                actualTotal += count
            }
            guard written == entry.uncompressedSize, checksum == entry.checksum else { throw IPAError("Archive checksum or size mismatch: \(path)") }
        }
        let payload = contents.appendingPathComponent("Payload", isDirectory: true)
        let children = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey])
        let apps = try children.filter {
            guard $0.pathExtension == "app" else { return false }
            return try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }
        guard apps.count == 1, let app = apps.first else { throw IPAError("Expected exactly one Payload/*.app bundle.") }
        let mainPath = "Payload/\(app.lastPathComponent)/Info.plist"
        let nested = entries.map { $0.1 }.filter {
            guard $0.hasPrefix("Payload/\(app.lastPathComponent)/"), $0 != mainPath, $0.hasSuffix("/Info.plist") else { return false }
            let ext = URL(fileURLWithPath: $0).deletingLastPathComponent().pathExtension
            return ext == "app" || ext == "appex"
        }.sorted()
        let bundles = try ([mainPath] + nested).map { path -> IPABundle in
            let url = contents.appendingPathComponent(path)
            let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
            guard size <= 8 * 1024 * 1024 else { throw IPAError("Info.plist is unexpectedly large.") }
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let info = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any],
                  let executable = info["CFBundleExecutable"] as? String, !executable.contains("/"),
                  let identifier = info["CFBundleIdentifier"] as? String, !identifier.isEmpty else {
                throw IPAError("Invalid bundle metadata: \(path)")
            }
            _ = try Self.safePath(executable)
            if try MachOInspector.isEncrypted(url.deletingLastPathComponent().appendingPathComponent(executable)) {
                throw IPAError("Encrypted executable in \(path). This editor cannot decrypt App Store IPAs. Use an unencrypted build you are authorized to modify.")
            }
            return IPABundle(path: path, original: data, format: format, info: info)
        }
        try Self.checkCancellation(progress)
        succeeded = true
        return PreparedIPA(workspace: root, contents: contents, bundles: bundles, expandedBytes: expanded)
    }

    func export(_ prepared: PreparedIPA, changes: VersionChanges, outputDirectory: URL,
                progress: Progress = Progress(totalUnitCount: 1)) throws -> URL {
        try changes.validate()
        try Self.checkCancellation(progress)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try requireSpace(at: outputDirectory, bytes: prepared.expandedBytes + prepared.expandedBytes / 10)
        let output = outputDirectory.appendingPathComponent("VersionEdited-\(UUID().uuidString).ipa")
        let partial = outputDirectory.appendingPathComponent(".\(UUID().uuidString).partial")
        defer { try? fm.removeItem(at: partial) }
        // Serialize changes in memory. The extracted original is never modified, so repeated
        // exports, failed exports, and changing the nested-bundle option cannot leak old edits.
        var replacements: [String: Data] = [:]
        for (index, bundle) in prepared.bundles.enumerated() where index == 0 || changes.synchronizeNestedBundles {
            var info = bundle.info
            if let version = changes.version { info["CFBundleShortVersionString"] = version }
            if let build = changes.build { info["CFBundleVersion"] = build }
            replacements[bundle.path] = try PropertyListSerialization.data(fromPropertyList: info, format: bundle.format, options: 0)
        }
        do {
            let original = try Archive(url: prepared.workspace.appendingPathComponent("input.ipa"), accessMode: .read)
            let result = try Archive(url: partial, accessMode: .create)
            for entry in original {
                try Self.checkCancellation(progress)
                let path = try Self.safePath(entry.path, directory: entry.type == .directory)
                // Preserve ordinary permissions but discard setuid/setgid/sticky bits.
                let permissions = ((entry.fileAttributes[.posixPermissions] as? NSNumber)?.uint16Value
                                   ?? (entry.type == .directory ? 0o755 : 0o644)) & 0o777
                let date = entry.fileAttributes[.modificationDate] as? Date ?? Date()
                if let data = replacements[path] {
                    try result.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                        modificationDate: date, permissions: permissions, compressionMethod: .deflate) { offset, count in
                        try Self.checkCancellation(progress)
                        return data.subdata(in: Int(offset)..<min(Int(offset) + count, data.count))
                    }
                } else if entry.type == .directory {
                    try result.addEntry(with: entry.path, type: .directory, uncompressedSize: Int64(0),
                                        modificationDate: date, permissions: permissions, provider: { _, _ in Data() })
                } else {
                    let source = prepared.contents.appendingPathComponent(path)
                    let size = (try fm.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
                    guard UInt64(size) == entry.uncompressedSize else { throw IPAError("Imported contents changed. Please import the IPA again.") }
                    let handle = try FileHandle(forReadingFrom: source)
                    defer { try? handle.close() }
                    try result.addEntry(with: entry.path, type: .file, uncompressedSize: size,
                                        modificationDate: date, permissions: permissions,
                                        compressionMethod: .deflate, bufferSize: 64 * 1024) { offset, count in
                        try Self.checkCancellation(progress)
                        try handle.seek(toOffset: UInt64(offset))
                        return try handle.read(upToCount: count) ?? Data()
                    }
                }
            }
        } // closes output before verification
        let verified = try Archive(url: partial, accessMode: .read)
        for (path, expected) in replacements {
            guard let entry = verified[path], entry.uncompressedSize == UInt64(expected.count) else { throw IPAError("Export verification failed: Info.plist missing or wrong size.") }
            var data = Data()
            let crc = try verified.extract(entry) { chunk in
                try Self.checkCancellation(progress)
                guard chunk.count <= expected.count - data.count else { throw IPAError("Export verification failed.") }
                data.append(chunk)
            }
            guard crc == entry.checksum, data == expected else { throw IPAError("Export verification failed: modified values do not match.") }
        }
        try Self.checkCancellation(progress)
        // Original signatures/profiles remain for the external signer to inspect and replace.
        // They are no longer valid for this edited IPA. This function does NOT sign anything.
        try fm.moveItem(at: partial, to: output)
        return output
    }
}
