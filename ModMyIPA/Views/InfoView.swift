import SwiftUI

struct InfoView: View {
    @ObservedObject private var model = IPAFile.shared
    var body: some View {
        Form {
            Section("About") {
                Text("IPA Version Editor \(appVersion ?? "?") (\(buildVersion ?? "?"))")
                Text("Native SwiftUI patch of ModMyIPA by powenn. Inspired by analysis of 0xkuj's 3DAppVersionSpoofer.")
            }
            Section("What this does") {
                Text("Edits version keys in an imported IPA's Info.plist and repackages it. Apps reading those keys can see the new values after re-signing and installation.")
            }
            Section("What this does not do") {
                Text("No jailbreak hooks, iOS version spoofing, dylib injection, signing, installation, App Store decryption, or server-check bypass. Hardcoded versions, receipts, and integrity checks may still prevent an app from working.")
                Text("An edited minimum iOS requirement would not add missing operating-system APIs. This editor leaves it unchanged.")
                Text("Encrypted main/nested app executables are rejected. Symlinks, ambiguous paths, and archives exceeding 4 GiB or 100,000 entries are also rejected. The encryption check is not a full compatibility or security audit of every library.")
            }
            Section("Testing on iOS 15.6.1") {
                Text("TrollStore is useful for an initial test, but does not prove normal sideloading works. Also test a sandboxed install through AltStore, SideStore, or another signer. Disable the original version-spoofing tweak for the target app while comparing results.")
                Text("Keep the app in the foreground while working on large IPAs. iOS grants only limited background execution time; cancellation may wait for file-provider copying to finish.")
            }
            Section("Storage") {
                Button("Clear imported working copy", role: .destructive) { model.clearImport() }
                    .disabled(model.processing || model.prepared == nil)
                Text("Working copies are cleared on next launch. Exports remain until you delete them. The editor makes no network requests and uploads no IPA contents.")
            }
            Section("Upstream projects") {
                Link("ModMyIPA — powenn", destination: URL(string: "https://github.com/powenn/ModMyIPA")!)
                Link("3DAppVersionSpoofer — 0xkuj", destination: URL(string: "https://github.com/0xkuj/3DAppVersionSpoofer")!)
                Link("ZIPFoundation — archive library", destination: URL(string: "https://github.com/weichsel/ZIPFoundation")!)
            }
        }.navigationTitle("About & limitations")
    }
}
