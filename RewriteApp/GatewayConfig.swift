import Foundation

/// Where the hosted "free models" gateway lives. After you deploy the Worker
/// (see ~/RewriteApp-gateway/README.md), set this to your Workers URL — or
/// override it at runtime in Settings → Free models → Advanced.
enum GatewayConfig {
    /// Baked-in default for shipped builds. Replace REPLACE-ME after deploying.
    static let defaultBaseURL = "https://rewrite-gateway.REPLACE-ME.workers.dev"
}
