// Original ModMyIPA by powenn. Reworked state and background processing.
import Foundation
import SwiftUI
import UIKit

struct EditorNotice: Identifiable {
    let id = UUID()
    let message: String
}
struct SharedIPA: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class IPAFile: ObservableObject {
    static let shared = IPAFile()
    @Published private(set) var prepared: PreparedIPA?
    @Published private(set) var processing = true
    @Published private(set) var status = "Preparing storage…"
    @Published private(set) var fileName = ""
    @Published private(set) var outputs: [URL] = []
    @Published var version = ""
    @Published var build = ""
    @Published var editVersion = true
    @Published var editBuild = false
    @Published var synchronizeNested = true
    @Published var notice: EditorNotice?
    @Published var share: SharedIPA?

    private let queue = DispatchQueue(label: "ipa.editor.processing", qos: .userInitiated)
    private var progress = Progress(totalUnitCount: 1)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private init() {
        Task {
            do {
                let files = try await perform {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: tmpDirectory.path) { try fm.removeItem(at: tmpDirectory) }
                    try fm.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
                    try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                    for url in try fm.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)
                        where url.pathExtension == "partial" {
                        try fm.removeItem(at: url)
                    }
                    return try Self.outputFiles()
                }
                outputs = files
                status = "Ready to import"
            } catch { show(error) }
            processing = false
        }
    }

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    nonisolated private static func outputFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "ipa" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func show(_ error: Error) {
        notice = EditorNotice(message: error.localizedDescription)
        status = "Operation did not complete"
    }

    private func begin(_ text: String) -> Progress {
        processing = true
        status = text
        progress = Progress(totalUnitCount: 1)
        let current = progress
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "IPA processing") { current.cancel() }
        return current
    }

    private func finish() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        processing = false
    }

    func cancel() { progress.cancel(); status = "Cancelling…" }

    func importIPA(_ url: URL) {
        guard !processing else { return }
        let current = begin("Copying, validating, and extracting…")
        let old = prepared
        prepared = nil
        fileName = ""
        Task {
            defer { finish() }
            do {
                let result = try await perform {
                    if let old { try FileManager.default.removeItem(at: old.workspace) }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    // A false access result may mean the URL is already inside our sandbox.
                    // Let the actual coordinated read determine whether it is accessible.
                    let coordinator = NSFileCoordinator()
                    var coordinationError: NSError?
                    var result: Result<PreparedIPA, Error>?
                    coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readableURL in
                        result = Result { try MyFileManager().prepare(ipa: readableURL, workspaceParent: tmpDirectory, progress: current) }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let result else { throw IPAError("The file provider did not supply the IPA. Download it in Files and try again.") }
                    return try result.get()
                }
                prepared = result
                fileName = url.lastPathComponent
                version = result.main.version
                build = result.main.build
                editVersion = true
                editBuild = false
                synchronizeNested = true
                status = "Ready to edit"
            } catch { show(error) }
        }
    }

    func exportIPA() {
        guard !processing, let prepared else { return }
        let changes = VersionChanges(
            version: editVersion ? version.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            build: editBuild ? build.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            synchronizeNestedBundles: synchronizeNested)
        do { try changes.validate() } catch { show(error); return }
        let current = begin("Repackaging and verifying edited metadata…")
        Task {
            defer { finish() }
            do {
                let url = try await perform {
                    try MyFileManager().export(prepared, changes: changes, outputDirectory: outputDirectory, progress: current)
                }
                // Publish success even if refreshing the directory list later fails.
                outputs.append(url)
                status = "Exported. Re-sign before installing."
                share = SharedIPA(url: url)
            } catch { show(error) }
        }
    }

    func deleteOutputs(_ urls: [URL]) {
        guard !processing else { return }
        _ = begin("Deleting selected exports…")
        Task {
            defer { finish() }
            do {
                let files = try await perform {
                    for url in urls { try FileManager.default.removeItem(at: url) }
                    return try Self.outputFiles()
                }
                outputs = files
                status = "Exports updated"
            } catch { show(error) }
        }
    }

    func clearImport() {
        guard !processing, let prepared else { return }
        _ = begin("Clearing imported working copy…")
        Task {
            defer { finish() }
            do {
                try await perform { try FileManager.default.removeItem(at: prepared.workspace) }
                self.prepared = nil
                fileName = ""
                status = "Ready to import"
            } catch { show(error) }
        }
    }
}
