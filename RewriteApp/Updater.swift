import Foundation
import SwiftUI

enum UpdateConfig {
    /// Raw JSON describing the latest release. Host on GitHub (a raw file in your
    /// releases repo, or a release asset). Replace REPLACE-ME after you create it.
    /// Example: https://raw.githubusercontent.com/<you>/rewrite-releases/main/version.json
    static let defaultFeedURL = "https://raw.githubusercontent.com/uxvic/rewrite/main/version.json"
}

/// Shape of the hosted version.json.
struct UpdateInfo: Codable, Equatable {
    let version: String          // e.g. "1.1.0"
    let url: String              // download link to the .dmg
    var notes: String?           // optional "what's new"
    var minimumSystemVersion: String?
}

/// Checks the hosted feed and, if a newer version exists, publishes it so the UI
/// can show a "Download" prompt. Does not self-install — the user installs the
/// downloaded .dmg manually (no signing/notarization needed for this to work).
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var available: UpdateInfo?
    @Published var checking = false
    @Published var lastChecked: Date?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var feedURL: String { AppSettings.shared.updateFeedURL }

    func check() {
        guard !feedURL.contains("REPLACE-ME"), let url = URL(string: feedURL) else { return }
        checking = true
        Task {
            defer { checking = false; lastChecked = Date() }
            do {
                var req = URLRequest(url: url)
                req.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, _) = try await URLSession.shared.data(for: req)
                let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
                available = Self.isNewer(info.version, than: currentVersion) ? info : nil
            } catch {
                // Silent — a failed check should never interrupt the user.
            }
        }
    }

    func openDownload() {
        guard let info = available, let url = URL(string: info.url) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Semantic-ish comparison: "1.2.0" > "1.1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
