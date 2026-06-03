import SwiftUI

@main
struct RewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The app is a menu bar agent (LSUIElement). The status item + popover
        // are managed in AppDelegate, so this Settings scene is just a valid,
        // empty placeholder scene required by SwiftUI's App protocol.
        Settings {
            EmptyView()
        }
    }
}
