using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Rewrite.Services;

/// Stores the API key encrypted with Windows DPAPI (per-user), not in plain JSON.
public static class SecretStore
{
    private static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Rewrite");
    private static string KeyFile => Path.Combine(Dir, "apikey.bin");

    public static void Save(string apiKey)
    {
        Directory.CreateDirectory(Dir);
        if (string.IsNullOrEmpty(apiKey)) { Delete(); return; }
        var enc = ProtectedData.Protect(Encoding.UTF8.GetBytes(apiKey), null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(KeyFile, enc);
    }

    public static string Load()
    {
        try
        {
            if (!File.Exists(KeyFile)) return "";
            var dec = ProtectedData.Unprotect(File.ReadAllBytes(KeyFile), null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(dec);
        }
        catch { return ""; }
    }

    public static void Delete()
    {
        try { if (File.Exists(KeyFile)) File.Delete(KeyFile); } catch { }
    }
}
