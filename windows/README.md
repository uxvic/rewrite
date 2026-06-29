# Rewrite for Windows

A Windows‑native build of Rewrite (the macOS app lives in `../RewriteApp`). This is a **new app**,
not a port of the Swift code — SwiftUI/AppKit don't exist on Windows — but it reuses the prompts, the
Smart decide‑and‑act logic, the provider contract, and the floating‑glass design.

**Stack:** WPF on .NET 8 (`net8.0-windows`).

## What's here (Milestone 1 — MVP)
- System‑tray app; **Ctrl+Space** (or click the tray icon) toggles a borderless **acrylic‑glass**
  popover near the tray.
- **Chat UI**: message list + floating glass composer (**Enter** sends, **Shift+Enter** newline) +
  Writing/Prompt segment + **Smart** chip + action chips (Paraphrase, Fix Grammar, …).
- **Smart** send: a single decide‑and‑act pass that polishes text or fulfils a request, self‑tags its
  reply (`[REWRITE]`/`[REQUEST]` → "Improve"/"Request"), and keeps **conversation context** so a
  follow‑up refines the previous answer instead of starting over.
- **Providers:** Anthropic (API key, DPAPI‑encrypted) and Ollama (local) with streaming.
- Copy / Retry on each result.

## Project layout
```
windows/
  Rewrite.sln
  src/Rewrite/
    App.xaml(.cs)              tray + global hotkey + window lifetime
    Providers/                 IRewriteProvider, Anthropic, Ollama
    Prompts/RewriteActions.cs  action prompts + smartSystemPrompt + ParseSmart (port of RewriteAction.swift)
    Models/Models.cs           ChatTurn, RewriteMode
    ViewModels/ChatViewModel.cs  send / Smart pipeline / per-mode threads / shared draft
    Services/                  AppSettings, SecretStore (DPAPI), HotkeyService, GlassHelper (DWM acrylic)
    Views/                     PopoverWindow.xaml(.cs), Converters.cs
    Theme.xaml                 brushes + converter resources
```

## Build & run (on Windows)
Requires the **.NET 8 SDK** and Windows 10/11.

```powershell
cd windows
dotnet restore Rewrite.sln
dotnet build Rewrite.sln -c Release
dotnet run --project src/Rewrite/Rewrite.csproj
```
Or open `Rewrite.sln` in **Visual Studio 2022** and press **F5**.

First run: the tray icon (a lavender "R") appears. Press **Ctrl+Space** to open the popover. To use
the Anthropic provider, settings/key UI lands in M2 — for now set the key by editing
`%APPDATA%\Rewrite\settings.json` won't work (the key is DPAPI‑encrypted in `apikey.bin`); a Settings
screen is the next milestone. The **Ollama** provider works out of the box if Ollama is running
locally (`ollama serve` + a pulled model).

## CI build (no Windows machine needed)
`.github/workflows/windows-build.yml` builds on a `windows-latest` runner and uploads a
self‑contained `win-x64` build as an artifact on every push to `windows/**` (and via "Run workflow").
Download it from the **Actions** tab.

## Roadmap
- **M2** Settings screen (provider + API key), History panel, per‑mode threads polish.
- **M3** Global selection‑rewrite hotkey, dictation (`System.Speech.Recognition`).
- **M4** **Velopack** auto‑update + signed installer (the downloadable build for users).
