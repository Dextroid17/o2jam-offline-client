# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller recipe for the O2Jam installer -- one file, no Python needed.

Used by packaging/build-linux.sh and packaging/build-windows.ps1:

    pyinstaller --noconfirm --clean packaging/o2jam-installer.spec

The CLI drivers (install.sh, install.ps1) are embedded as data under `payload/`
so the built binary is a complete installer on its own -- no checkout beside it.
"""

import re
import subprocess
import sys
from pathlib import Path

PKG = Path(SPECPATH).resolve()
REPO = PKG.parent


# ---------------------------------------------------------------------------
#  Tcl/Tk shared libraries.
#
#  PyInstaller brings along the tcl/tk *data* trees by itself, but it can miss
#  the libraries _tkinter.so actually links to -- which is exactly what happens
#  with the relocatable CPython builds (uv / python-build-standalone), where
#  libtcl9.0.so and libtcl9tk9.0.so live inside the interpreter's own lib/.
#  Miss them and the frozen app dies the moment a window opens.
#  So: ask ldd what _tkinter needs, and bundle whatever we can find.
# ---------------------------------------------------------------------------
def _tcl_tk_binaries() -> list:
    try:
        from PyInstaller.utils.hooks import get_module_file_attribute
        so = get_module_file_attribute("_tkinter")
    except Exception:
        return []
    try:
        out = subprocess.run(["ldd", so], capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return []
    wanted = [m.group(1) for m in
              (re.match(r"\s*(lib(?:tcl|tk)\S*)\s*=>", ln) for ln in out.splitlines()) if m]

    search: list[Path] = []
    for base in (sys.base_prefix, sys.prefix, sys.exec_prefix, "/usr", "/usr/local"):
        for sub in ("lib", "lib64", "lib/x86_64-linux-gnu"):
            search.append(Path(base) / sub)

    found: list = []
    for name in wanted:
        for folder in search:
            cand = folder / name
            if cand.exists():
                found.append((str(cand), "."))
                break
    return found


tcl_tk = _tcl_tk_binaries()
print("[o2jam spec] Tcl/Tk libraries bundled: "
      f"{[Path(p).name for p, _ in tcl_tk] or 'none found (relying on PyInstaller hooks)'}")

datas = [
    (str(REPO / "install.sh"), "payload"),
    (str(REPO / "install.ps1"), "payload"),
]
for extra in ("o2jam.png", "o2jam.ico"):
    if (PKG / extra).exists():
        datas.append((str(PKG / extra), "payload"))

icon = str(PKG / "o2jam.ico") if sys.platform == "win32" else None

a = Analysis(
    [str(REPO / "installer" / "o2jam-installer.py")],
    pathex=[str(REPO / "installer")],
    binaries=tcl_tk,
    datas=datas,
    hiddenimports=["tkinter", "tkinter.ttk", "tkinter.filedialog", "tkinter.messagebox"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["numpy", "pytest", "setuptools", "pip"],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="O2Jam-Installer",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    runtime_tmpdir=None,
    console=False,          # a windowed app; --self-test still prints to a terminal
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=icon,
)
