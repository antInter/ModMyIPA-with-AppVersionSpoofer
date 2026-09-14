import SwiftUI

struct ContentView: View {
    @StateObject private var model = IPAFile.shared
    var body: some View {
        TabView {
            NavigationView { MainView() }.navigationViewStyle(.stack)
                .tabItem { Label("Editor", systemImage: "slider.horizontal.3") }
            NavigationView { PackageListView() }.navigationViewStyle(.stack)
                .tabItem { Label("Exports", systemImage: "tray.full") }
            NavigationView { InfoView() }.navigationViewStyle(.stack)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .tint(.indigo)
        .sheet(item: $model.share) { item in ShareSheet(activityItems: [item.url]) }
        .alert(item: $model.notice) { notice in
            Alert(title: Text("IPA Editor"), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }
}
