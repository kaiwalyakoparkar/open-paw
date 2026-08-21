import Foundation
import Darwin

/// `swift run` ships a naked binary. macOS will not prompt for Microphone
/// without an .app + Info.plist, and AVAudioEngine then records silence.
enum AppRelaunch {
    static func execFromBundleIfNeeded() {
        let running = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        guard !running.path.contains(".app/Contents/MacOS/") else { return }

        let fm = FileManager.default
        let app = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenPaw/OpenPaw.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        let dest = macos.appendingPathComponent("OpenPaw")
        do {
            try fm.createDirectory(at: macos, withIntermediateDirectories: true)
            let plistDest = app.appendingPathComponent("Contents/Info.plist")
            let plistSrc = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Info.plist")
            try? fm.removeItem(at: plistDest)
            if fm.fileExists(atPath: plistSrc.path) {
                try fm.copyItem(at: plistSrc, to: plistDest)
            } else {
                try writeInfoPlist(to: plistDest)
            }
            try Data("APPL????".utf8).write(to: app.appendingPathComponent("Contents/PkgInfo"))

            try? fm.removeItem(at: dest)
            try fm.copyItem(at: running, to: dest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)

            // Do not put .bundle in MacOS — codesign rejects it (no nested Info.plist).
            let stale = macos.appendingPathComponent("OpenPaw_OpenPaw.bundle")
            try? fm.removeItem(at: stale)

            let resName = "OpenPaw_OpenPaw.bundle"
            let resSrc = running.deletingLastPathComponent().appendingPathComponent(resName)
            if fm.fileExists(atPath: resSrc.path) {
                let resources = app.appendingPathComponent("Contents/Resources")
                try fm.createDirectory(at: resources, withIntermediateDirectories: true)
                let resDst = resources.appendingPathComponent(resName)
                try? fm.removeItem(at: resDst)
                try fm.copyItem(at: resSrc, to: resDst)
                try writeBundleInfoPlist(to: resDst.appendingPathComponent("Info.plist"))
            }
        } catch {
            NSLog("open-paw: app bundle wrap failed (%@) — mic may stay silent", error.localizedDescription)
            return
        }

        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", "--identifier", "local.openpaw", app.path]
        let err = Pipe()
        sign.standardError = err
        try? sign.run()
        sign.waitUntilExit()
        if sign.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            NSLog("open-paw: codesign failed (%d) %@", sign.terminationStatus, msg)
            return
        }

        let argv = [dest.path] + Array(CommandLine.arguments.dropFirst())
        let cargs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        execv(dest.path, cargs)
        cargs.forEach { free($0) }
        NSLog("open-paw: exec into OpenPaw.app failed")
    }

    private static func writeInfoPlist(to url: URL) throws {
        let info: [String: Any] = [
            "CFBundleExecutable": "OpenPaw",
            "CFBundleIdentifier": "local.openpaw",
            "CFBundleName": "OpenPaw",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.2",
            "LSUIElement": true,
            "NSMicrophoneUsageDescription":
                "Open Paw listens when you wake the cat so Gradium can transcribe your voice.",
            "NSScreenCaptureUsageDescription":
                "Open Paw captures the main display when you annotate a region to explain.",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url)
    }

    private static func writeBundleInfoPlist(to url: URL) throws {
        let info: [String: Any] = [
            "CFBundleIdentifier": "local.openpaw.resources",
            "CFBundleName": "OpenPaw_OpenPaw",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url)
    }
}
