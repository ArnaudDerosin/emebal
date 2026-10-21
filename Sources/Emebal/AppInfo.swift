import Foundation

/// Emebal's own version, from Info.plist, which scripts/release.sh sets.
enum AppInfo {
    /// "0.1.0", or "dev" when running outside the app bundle (swift run, tests).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
