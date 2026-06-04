import Foundation

enum OutputFileHelper {
    static func saveDirectoryURL() -> URL {
        if let dir = UserDefaults.standard.string(forKey: UDKey.saveDirectory) {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        }
        if let desktop = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first {
            return URL(fileURLWithPath: desktop)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    static func screenshotURL(format: String) -> URL {
        let ext = format == "jpeg" ? "jpg" : "png"
        return saveDirectoryURL().appendingPathComponent("Snap2_\(timestamp()).\(ext)")
    }

    static func recordingURL() -> URL {
        let directory = saveDirectoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Snap2_\(timestamp()).mp4")
    }
}

enum UpdateAvailabilityStore {
    static var cachedLatestVersionIfNewer: String? {
        guard let latest = UserDefaults.standard.string(forKey: UDKey.lastKnownLatestVersion),
              !latest.isEmpty,
              UpdateChecker.isVersionNewer(latest, than: UpdateChecker.shared.currentVersion)
        else {
            return nil
        }
        return latest
    }
}
