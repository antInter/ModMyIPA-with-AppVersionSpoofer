import Foundation

let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
// Working copies are private, ephemeral, and not exposed through Files sharing.
let tmpDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("IPAEditorWork", isDirectory: true)
let outputDirectory = docPath.appendingPathComponent("Exports", isDirectory: true)
