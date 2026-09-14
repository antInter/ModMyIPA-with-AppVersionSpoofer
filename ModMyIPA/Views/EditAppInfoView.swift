import SwiftUI

struct EditAppInfoView: View {
    @ObservedObject private var model = IPAFile.shared
    var body: some View {
        Section {
            Toggle("Edit app version", isOn: $model.editVersion)
            if model.editVersion {
                TextField("For example 3.2.1", text: $model.version)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never).disableAutocorrection(true)
                    .accessibilityLabel("New app version")
            }
            Toggle("Edit build number", isOn: $model.editBuild)
            if model.editBuild {
                TextField("For example 123", text: $model.build)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never).disableAutocorrection(true)
                    .accessibilityLabel("New build number")
            }
            if (model.prepared?.bundles.count ?? 0) > 1 {
                Toggle("Sync nested apps and extensions", isOn: $model.synchronizeNested)
            }
        } header: {
            Text("New version metadata")
        } footer: {
            Text("App version changes CFBundleShortVersionString. Build changes CFBundleVersion. Disabled fields keep their original values. Sync changes only enabled fields in nested .app/.appex bundles, not frameworks. Bundle IDs, executables, and MinimumOSVersion are left alone.")
        }
    }
}
