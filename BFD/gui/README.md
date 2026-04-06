# BFD GUI (v1.0.0)

PySide6 desktop wizard for BFD (Bulk Font Downloader).

## Run From Source

```powershell
cd .\BFD\gui
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\requirements.txt
.\.venv\Scripts\python.exe .\app.py
```

## Build EXE

```powershell
cd .\BFD\gui
.\build_exe.ps1 -PythonExe "python"
```

Output: `dist\BFD.exe`

## Build MSI

```powershell
cd .\BFD\gui
.\build_msi.ps1 -ProductVersion "1.0.0"
```

Output: `dist\BFD-1.0.0.msi`

## GitHub Release Automation

- Windows release publishing is automated by `.github/workflows/release-windows.yml`.
- Every push to `main` creates a new GitHub Release with EXE + MSI assets.
- Manual workflow runs can override the version (for example `1.0.42`).

## Runtime Worker

The GUI executes:

- `runtime/BFD.worker.ps1`
- which imports `../core/BFD.Engine.psm1`

GUI and worker communicate via `__FX_GUI_EVENT__` JSON lines.
