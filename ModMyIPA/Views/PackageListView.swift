import SwiftUI

struct PackageListView: View {
    @ObservedObject private var model = IPAFile.shared
    @State private var pendingDeletion: [URL] = []
    @State private var confirmDelete = false
    var body: some View {
        List {
            Section {
                if model.outputs.isEmpty {
                    Label("No exported IPAs yet", systemImage: "tray")
                    Text("Export an IPA from the editor, then share or save it here.").foregroundColor(.secondary)
                }
                ForEach(model.outputs, id: \.self) { url in
                    Button { model.share = SharedIPA(url: url) } label: {
                        HStack {
                            Image(systemName: "doc.zipper").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.lastPathComponent).font(.subheadline).lineLimit(2)
                                Text("Tap to share or save to Files").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }.padding(.vertical, 4)
                    }.disabled(model.processing)
                }
                .onDelete { indices in
                    pendingDeletion = indices.compactMap { model.outputs.indices.contains($0) ? model.outputs[$0] : nil }
                    confirmDelete = !pendingDeletion.isEmpty
                }
                .deleteDisabled(model.processing)
            } footer: {
                Text("These files require re-signing. Exports are also available under On My iPhone → IPA Version Editor → Exports. Swipe to delete an export.")
            }
        }
        .navigationTitle("Exports")
        .confirmationDialog("Delete selected exports?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteOutputs(pendingDeletion) }
        } message: { Text("This cannot be undone. Your original imported IPA is not affected.") }
    }
}
