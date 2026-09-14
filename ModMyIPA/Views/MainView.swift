// ModMyIPA version editor; based on powenn's import/edit/export interface.
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject private var model = IPAFile.shared
    @State private var isImporting = false
    @State private var confirmExport = false

    var body: some View {
        Form {
            Section {
                Label("IPA Version Editor", systemImage: "shippingbox")
                    .font(.title2.bold()).padding(.vertical, 8)
                Text("Import a copy. Edit its version. Export for re-signing.")
                    .foregroundColor(.secondary)
                Button { isImporting = true } label: {
                    Label(model.prepared == nil ? "Import IPA" : "Import another IPA", systemImage: "square.and.arrow.down")
                }
                .disabled(model.processing)
            } footer: {
                Text("All processing stays on this device. The original file is never modified.")
            }
            if let prepared = model.prepared {
                Section("Imported application") {
                    Text(prepared.displayName).font(.headline)
                    Text(model.fileName).font(.caption).textSelection(.enabled)
                    Text(prepared.bundleIdentifier).font(.caption.monospaced()).textSelection(.enabled)
                    row("Current app version", prepared.main.version)
                    row("Current build", prepared.main.build)
                    row("Minimum iOS (unchanged)", prepared.main.info["MinimumOSVersion"] as? String ?? "Not specified")
                    row("Nested apps/extensions", String(prepared.bundles.count - 1))
                }
                EditAppInfoView()
                    .disabled(model.processing)
                Section {
                    Button { hideKeyboard(); confirmExport = true } label: {
                        Label("Repackage and export IPA", systemImage: "square.and.arrow.up")
                            .font(.headline)
                    }
                    .disabled(model.processing || (!model.editVersion && !model.editBuild))
                } footer: {
                    Text("Exporting invalidates the original signature. Sign and install the result using your sideloading tool. This is metadata editing, not a runtime hook or iOS upgrade.")
                }
            }
            Section("Status") {
                if model.processing {
                    ProgressView(model.status)
                    Button("Cancel operation", role: .cancel) { model.cancel() }
                } else {
                    Text(model.status).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Version Editor")
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                guard url.pathExtension.lowercased() == "ipa" else { throw IPAError("Please choose a file ending in .ipa.") }
                model.importIPA(url)
            } catch {
                if (error as NSError).code != NSUserCancelledError { model.show(error) }
            }
        }
        .confirmationDialog("Export an edited copy?", isPresented: $confirmExport, titleVisibility: .visible) {
            Button("Export IPA for re-signing") { model.exportIPA() }
        } message: {
            Text("The app may still reject this version. Keep the original IPA and back up app data before installing. No signing or installation is performed here.")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value.isEmpty ? "Not specified" : value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }
}
