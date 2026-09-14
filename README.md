# IPA Version Editor — ModMyIPA patch

Native SwiftUI app for iOS 15.0+, based on the supplied powenn/ModMyIPA source. Import an IPA, edit version metadata, and export for external re-signing. No jailbreak hooks or privileged entitlements are used by this editor.

## Build from Windows/Linux using GitHub

1. Fork https://github.com/powenn/ModMyIPA or use your own private working repository. This patch uses ModMyIPA, not the Theos tweak, as its base.
2. Extract the supplied source package and copy its contents to your repository root. Include the hidden `.github` directory. `ModMyIPA.xcodeproj`, `Package.swift`, and `.github/workflows/build-ipa.yml` must be at the root. Do not upload just the archive file.
3. Commit and push to main/master. Enable Actions in the fork if GitHub prompts you.
4. Open Actions → Build IPA → Run workflow. No Apple ID, certificates, provisioning profiles, or signing secrets are needed to build. GitHub Actions availability/billing depends on your account.
5. Download the successful run's `IPA-Version-Editor-<number>` artifact ZIP and extract it.
6. Sign/install `VersionEditor-unsigned.ipa` using SideStore, AltStore, Sideloadly, or a compatible certificate-based signer. Normal signing limits, expiration, capabilities, and Developer Mode requirements still apply.
7. `VersionEditor-adhoc.ipa` is an additional TrollStore test artifact. It is NOT Apple-signed or automatically permasigned. It cannot be installed directly on ordinary iOS without an appropriate signing/installation step.

The workflow targets macos-15 and Xcode 16.4. If GitHub retires that Xcode installation, update DEVELOPER_DIR to an installed compatible version. Failed runs upload diagnostic logs when available. Share the first compiler error with surrounding lines if a build fails.

On a Mac: `swift test --jobs 2`, then `bash compile.command`. Outputs are in `dist/`, with SHA-256 checksums.

## Use

- Keep the original IPA and back up app data. Import only unencrypted builds you are authorized to modify.
- Import IPA → edit app version (`CFBundleShortVersionString`, e.g. 3.2.1) → optionally edit build (`CFBundleVersion`, e.g. 123 or 123.4.5) → Repackage and export.
- New versions use three numeric components. New build numbers use a conservative release format with up to 4/2/2 digits. Existing unusual values remain unchanged when the field is disabled.
- Sync nested apps/extensions applies enabled fields to embedded .app/.appex bundles. Framework versions are not changed. Disabling sync can cause installation-time version mismatches.
- Save/share through the share sheet; previous exports remain in Exports and Documents/Exports. Re-sign and install the modified IPA using your external tool.
- Signing the editor does NOT sign the files it edits. Original signature/profile bytes are retained for signers to inspect/replace, but are invalid for the edited contents.

Bundle identifiers, executable bytes, MinimumOSVersion, unrelated metadata, and ordinary file permission bits are preserved. No executable/app directory renaming is performed. Binary/XML plist format is preserved; key ordering may change. Repeated exports start from immutable imported values and use unique output filenames.

## Important difference from 3DAppVersionSpoofer

Inspection of the supplied 0xkuj/3DAppVersionSpoofer Tweak.x found that lines 178–217 hook NSBundle.infoDictionary and replace CFBundleShortVersionString at runtime using a separate preferences plist. Lines 219–227 optionally hook UIDevice.systemVersion. Its SpringBoard shortcut and tweak injection depend on jailbreak infrastructure; it does not simply overwrite installed Info.plist files.

This patch implements the requested import/extract/edit/repackage/share workflow instead. Apps reading the edited bundle keys can observe the new values after installation. It is NOT a full runtime-hook equivalent. No iOS-version spoofing, dylib injection, decryption, signing, direct installation, or server-check bypass is implemented. Hardcoded versions, receipts, integrity checks, backend minimum versions, missing APIs, and entitlements can still stop an app from working. Lowering MinimumOSVersion would not add missing OS APIs, so it is deliberately left unchanged.

## Test on your iOS 15.6.1 device

TrollStore is useful for initial install/import/export/share tests. Use a controlled app you built with an About screen displaying Bundle.main.infoDictionary version keys. A copy of this editor IPA can also serve as a test: its About page reads those keys. Back up exports before replacing the installed editor.

Disable the original version-spoofing tweak for the target while comparing results, otherwise runtime hooks can mask disk values. First change only app version and confirm build/identifier/minimum OS remain unchanged. Then test build changes, nested extensions, provider imports, cancellation, repeat export, and iPad sharing.

A TrollStore success does NOT prove stock-iOS compatibility: also test an ordinary sandboxed install via AltStore/SideStore or another signer, preferably on a non-jailbroken device. Do not uninstall a valuable app without a data backup to resolve a signing conflict. Different teams/identifiers may change keychain and app-group access independently of version editing.

## Robustness and limits

- ZIPFoundation 0.9.20 is pinned, replacing the original unpinned ZipArchive branch.
- Serial background processing, security-scoped coordinated reads, visible errors, cancellation, and partial-output cleanup.
- Input copied to a private unique workspace, never edited in place. Working copies are cleared on next launch; exports persist until deleted.
- Rejects traversal/duplicate/case-colliding paths, file-directory conflicts, symlinks, bad metadata, CRC/size mismatches, and encrypted main/nested app executables.
- All symlinks are rejected, including legitimate ones. Password-protected and unusual archives may be unsupported. Limits: 4 GiB input/expanded size and 100,000 entries. Large archives still require substantial storage and may exceed device memory/time limits.
- Encryption detection is not a complete compatibility/security audit of every embedded library. Import trusted apps only.
- Keep the app foregrounded for large files; background execution is limited by iOS. Cancellation may wait for file-provider copying.
- The editor makes no network requests and uploads no IPA contents. CI downloads dependencies, not the IPAs you import on your phone.

## Validation status

The actual production MyFileManager.swift and MachOInspector.swift compiled and passed **16 XCTest tests, zero failures**, on Linux with Swift 6.0.3 in Swift 5 language mode during this session. Tests cover metadata edits, binary/XML preservation, resources/executable permissions, repeat-export isolation, selected nested changes, corrupted CRCs, traversal, duplicates, symlinks, cancellation/limits, encrypted executables, and malformed thin/fat Mach-O headers. The final patch includes the exact compile/validation fixes from that passing run.

All Swift source files also passed a syntax parse; shell syntax, workflow YAML, XML/plist and dependency-lock checks passed. The transient raw test log was lost in a sandbox reset; rerun `swift test --jobs 2` for fresh results. ZIPFoundation emits an unhandled privacy-manifest resource warning in SwiftPM; it did not prevent core tests.

**Not verified here:** full SwiftUI/Xcode typechecking/build, Apple package/signature verification, physical-device install, file-provider behavior, or stock-iOS compatibility. The supplied macOS workflow runs the tests and performs the Apple build/package checks. This deliverable is source + workflow, not a prebuilt or device-tested IPA.

## Attribution and licensing

Original app/UI/assets: https://github.com/powenn/ModMyIPA
Runtime behavior reference: https://github.com/0xkuj/3DAppVersionSpoofer
Archive library: https://github.com/weichsel/ZIPFoundation (MIT).

No Theos/Logos hook code is included. The supplied ModMyIPA archive has no LICENSE file. Preserve attribution and check upstream terms/permission before publicly redistributing a derivative binary; this patch does not grant a blanket license for upstream material. Historical screenshots in Screenshots/ are upstream screenshots, not the patched UI.

## References

- https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring
- https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion
- https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()
- https://github.com/weichsel/ZIPFoundation/tree/0.9.20
- https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md
- https://github.com/opa334/TrollStore
