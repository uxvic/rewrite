using Velopack;
using Velopack.Sources;

namespace Rewrite.Services;

/// Silent auto-update against the GitHub releases feed (the Windows analog of
/// Sparkle on macOS). Only does anything when the app was actually installed via
/// Velopack; otherwise (dev run, portable) it's a no-op. Best-effort — any failure
/// is swallowed so a network hiccup never blocks startup.
public static class UpdateService
{
    private const string RepoUrl = "https://github.com/uxvic/rewrite";

    public static async Task CheckAsync()
    {
        try
        {
            var mgr = new UpdateManager(new GithubSource(RepoUrl, null, prerelease: false));
            if (!mgr.IsInstalled) return;

            var info = await mgr.CheckForUpdatesAsync();
            if (info is null) return;                 // already up to date

            await mgr.DownloadUpdatesAsync(info);
            mgr.ApplyUpdatesAndRestart(info);         // relaunches into the new version
        }
        catch
        {
            // No update feed yet / offline / not a Velopack install — ignore.
        }
    }
}
