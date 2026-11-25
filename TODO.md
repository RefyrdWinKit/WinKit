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
- [x] **Licensing & Repo Migration**: Switched to Apache License 2.0 with [NOTICE](NOTICE) and updated repository links to `RefyrdWinKit/WinKit`.

### Planned / Backlog
- [ ] **Unhandled UI Error Guard**: Add `DispatcherUnhandledException` handler in [winkit.ps1](winkit.ps1) to show a dialog instead of crashing silently.
- [ ] **Safe Window Close During Install**: Cancel active `winget` runs cleanly in `Add_Closing` when closing the window mid-install.
- [ ] **Search `Esc` Shortcut**: Clear search input, reset online results, and return to categories on `Esc` in `TxtSearch`.
- [ ] **Selective App Updates**: Add a quick action to select/upgrade only outdated catalog apps without running system-wide `Upgrade All`.
- [ ] **Per-App `Upgrade All` Summary**: Parse `Upgrade All` log output into individual app result cards instead of a single summary card.
- [ ] **Release Pinning in `install.ps1`**: Pin [install.ps1](install.ps1) to tagged releases with SHA-256 checksum verification once release artifacts are published.
- [ ] **Catalog & Linter Check**: Verify all 42 WinGet IDs in [Apps.ps1](src/config/Apps.ps1) against live WinGet and run `PSScriptAnalyzer` in CI.
