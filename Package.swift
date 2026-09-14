// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "IPAVersionEditorCore",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [.library(name: "IPACore", targets: ["IPACore"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "IPACore", dependencies: ["ZIPFoundation"], path: "ModMyIPA/Managers",
                exclude: ["IPAFile.swift"], sources: ["MyFileManager.swift", "MachOInspector.swift"]),
        .testTarget(name: "IPACoreTests", dependencies: ["IPACore", "ZIPFoundation"], path: "Tests/IPACoreTests")
    ]
)
