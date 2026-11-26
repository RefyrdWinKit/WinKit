# WinKit

Minimal Windows 10/11 GUI installer and updater powered by WinGet and Chocolatey.

[English](README.md) | [Русский](README-RU.md)

![WinKit Demo](winkit-preview.gif)

## Quick Start

Run via PowerShell:

```powershell
irm https://raw.githubusercontent.com/RefyrdWinKit/WinKit/main/install.ps1 | iex
```

Or clone and run locally:

```powershell
git clone git@github.com:RefyrdWinKit/WinKit.git
cd WinKit
powershell -ExecutionPolicy Bypass -File winkit.ps1
```

## Features

- Switchable package manager backend: **WinGet** or **Chocolatey** (auto-installs Chocolatey on demand)
- Curated catalog of 42 applications across 7 categories (`src/config/Apps.ps1`)
- Online WinGet / Chocolatey search directly from the search bar (`Enter`)
- Background scan for installed apps and available updates
- One-click `Upgrade All` via `winget upgrade --all` or `choco upgrade all`
- Save and load presets in WinGet JSON (`.json`) or plain text (`.txt`)
- Sequential batch installation with live logs, exportable output, and cancel support
- Automatic UAC elevation with user-context fallback for user-scoped apps (Discord, Telegram, Spotify, Roblox, Obsidian, Notion)
- Windows 11 Mica backdrop and automatic light/dark theme sync with manual toggle

## Requirements

- Windows 10 (1709+) or Windows 11
- WinGet (pre-installed on Windows 11; automatically bootstrapped via `Microsoft.WinGet.Client` if missing)

## Adding Apps

Edit [`src/config/Apps.ps1`](src/config/Apps.ps1) and add entries with `Name`, `Id`, and `Cat` to `$global:apps`.

## License

[Apache 2.0](LICENSE) (see [NOTICE](NOTICE))
