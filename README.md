# BFD (Bulk Font Downloader)

BFD is an open-source desktop + CLI tool for downloading font files from multiple public font providers.

This project is a personal, non-profit effort.
It is not affiliated with any font platform.
Users are responsible for complying with each provider's license and terms.

## v1.0.0 Scope

- Rebranded product identity to `BFD`
- Multi-provider pipeline:
  - Google Fonts
  - Font Hub
  - DaFont
  - Font Share
  - Open Foundry
  - Befonts
- Per-provider fallback order:
  - `direct -> api -> html`
  - if all fail, provider is skipped and run continues
- Output structure:
  - `<output>/<provider>/...`
  - only `.ttf` and `.otf` are retained
- New 4-step desktop wizard (Figma-aligned)
- CLI + one-line online execution path
- Windows release artifacts: `EXE + MSI`

## Repository Layout

- `BFD/core/BFD.Engine.psm1` - provider engine + installer routines
- `BFD/cli/BFD.ps1` - CLI entrypoint
- `BFD/gui/app.py` - 4-step PySide6 wizard
- `BFD/gui/runtime/BFD.worker.ps1` - GUI worker process
- `BFD.ps1` - top-level convenience launcher

## CLI Usage

Local run:

```powershell
powershell -ExecutionPolicy Bypass -File .\BFD.ps1 `
  -DownloadsRoot "D:\Fonts" `
  -BaseFolderName "BFD Fonts" `
  -Providers google_fonts,font_hub,dafont `
  -MethodOrder direct,api,html `
  -AutoInstallFonts $true `
  -InstallScope currentuser
```

Google-only compatibility run:

```powershell
powershell -ExecutionPolicy Bypass -File .\BFD.ps1 -Providers google_fonts
```

One-line online execution (update URL to your repo path):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='https://raw.githubusercontent.com/<owner>/<repo>/main/BFD.ps1'; $p=Join-Path $env:TEMP 'BFD.ps1'; Invoke-WebRequest -Uri $u -OutFile $p -UseBasicParsing; & $p"
```

## GUI Usage

```powershell
cd .\BFD\gui
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\requirements.txt
.\.venv\Scripts\python.exe .\app.py
```

## Build and Release

- Workflow: `.github/workflows/release-windows.yml`
- Trigger behavior:
  - Every push to `main` automatically builds and publishes a new GitHub Release
  - Manual `workflow_dispatch` also supported with optional `version` override
- Auto version format:
  - `1.0.<run_number>` with release tag `v1.0.<run_number>`
- Release documentation:
  - Every release includes generated notes with `Added`, `Changed`, and `Removed` sections
  - Notes are used as the release description and attached as a markdown asset
- Assets:
  - `BFD-<version>.exe`
  - `BFD-<version>.msi`
  - `BFD-<version>-release-notes.md`

## Roadmap

- Expand provider reliability and coverage
- Improve provider-specific API integrations
- Linux/macOS packaging in future releases

## License

MIT - see `LICENSE`.
