using System;
using Velopack;

namespace Rewrite;

/// Explicit entry point so Velopack can run its install/update hooks BEFORE any
/// WPF UI spins up (VelopackApp.Run may handle a hook invocation and exit). After
/// that we start the WPF application normally.
public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        VelopackApp.Build().Run();

        var app = new App();
        app.InitializeComponent();
        app.Run();
    }
}
