# WinKit — Task & Roadmap Tracker

## Status: Active

### Architecture & Code Quality
- [x] Separate modules into `src/ui`, `src/core`, and `src/config`
- [x] Streamline `.gitignore` for Windows, PowerShell, VS Code, local presets, and `.agents/`
- [x] Unify `winget` table parsing (`ConvertFrom-WingetTable`) and non-blocking async runner
- [x] Fix command quoting/ID validation, cancel process targeting, and hang guards in `src/core/Installer.ps1`
- [x] Rename `DoEvents` to `Invoke-DoEvents` for PowerShell approved verb compliance

### Implemented Features
- [x] **Installed Detection & Version Badges**: Background `winget list` scan showing installed versions and available updates.
- [x] **One-Click WinGet Upgrade All**: `Upgrade All` button with live log streaming and badge refresh.
- [x] **Native WinGet JSON Preset Support**: Save/load presets in official WinGet `.json` schema and `.txt`.
- [x] **UI & Search UX**: Non-blocking online WinGet search (`Enter`), search loading indicator, and outside-click focus handling.
- [x] **Install Script & Docs**: UTF-8 compatibility in [install.ps1](install.ps1), simplified [README.md](README.md) and [README-RU.md](README-RU.md).
