#!/usr/bin/env python3
"""
================================================================================
             O2Jam Offline Client -- graphical installer
================================================================================

A small Tkinter front-end for install.sh (Linux) and install.ps1 (Windows).
Same window, same options, on both platforms: pick where it goes, point at the
game data you already own, press Install, watch the log.

    python3 o2jam-installer.py                 # Linux / any POSIX
    py -3 o2jam-installer.py                   # Windows

Why Tkinter: it ships with Python on both platforms and needs no downloads, so
the installer that installs things doesn't itself need installing.

Nothing here uses sudo / admin rights. Everything lands in user space.
================================================================================
"""

import os
import platform
import shlex
import subprocess
import sys
import threading
import queue
from pathlib import Path

try:
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox
except ImportError:                                  # pragma: no cover
    sys.stderr.write(
        "\n  This installer needs Python's tkinter module.\n"
        "    Debian/Ubuntu : sudo apt install python3-tk\n"
        "    Fedora        : sudo dnf install python3-tkinter\n"
        "    Arch/CachyOS  : sudo pacman -S tk\n"
        "    Windows/macOS : comes with the python.org installer\n\n")
    sys.exit(1)

WIN = platform.system() == "Windows"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
VERSION = "1.1"


def find_script() -> Path | None:
    """Locate the CLI installer this GUI drives."""
    names = ["install.ps1", "install.sh"] if WIN else ["install.sh", "install.ps1"]
    for name in names:
        for cand in (ROOT / name, HERE / name):
            if cand.is_file():
                return cand
    return None


def default_prefix() -> str:
    home = Path.home()
    if WIN:
        return str(home / "o2jam")
    return str(home / "o2jam")


class Installer(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"O2Jam Offline Client -- installer v{VERSION}")
        self.geometry("840x620")
        self.minsize(720, 520)

        self.script = find_script()
        self.proc: subprocess.Popen | None = None
        self.log_q: queue.Queue[str] = queue.Queue()
        self.busy = False

        self.prefix_var = tk.StringVar(value=default_prefix())
        self.assets_var = tk.StringVar(value="")
        self.build_var = tk.BooleanVar(value=True)
        self.shortcut_var = tk.BooleanVar(value=True)
        self.patches_var = tk.BooleanVar(value=True)
        self.jobs_var = tk.StringVar(value=str(max(2, (os.cpu_count() or 4) - 1)))

        self._build_ui()
        self._poll_log()
        self.log(f"O2Jam Offline Client installer v{VERSION}")
        self.log(f"platform : {platform.system()} {platform.release()}  ({platform.machine()})")
        self.log(f"python   : {sys.version.split()[0]}")
        if self.script:
            self.log(f"driver   : {self.script}")
        else:
            self.log("driver   : NOT FOUND -- install.sh / install.ps1 must sit next to this file")
        self.log("")

    # ------------------------------------------------------------------ UI --
    def _build_ui(self) -> None:
        outer = ttk.Frame(self, padding=12)
        outer.pack(fill="both", expand=True)

        ttk.Label(outer, text="O2Jam Offline Client",
                  font=("TkDefaultFont", 15, "bold")).pack(anchor="w")
        ttk.Label(outer, text="The Korean rhythm classic, running natively. No Wine, no emulator, "
                              "no VM, no admin rights.",
                  foreground="#666666").pack(anchor="w", pady=(0, 10))

        grid = ttk.Frame(outer)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1)

        # install dir
        ttk.Label(grid, text="Install into").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(grid, textvariable=self.prefix_var).grid(row=0, column=1, sticky="ew", padx=6)
        ttk.Button(grid, text="Browse", command=self._pick_prefix).grid(row=0, column=2)

        # assets
        ttk.Label(grid, text="Your game data").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(grid, textvariable=self.assets_var).grid(row=1, column=1, sticky="ew", padx=6)
        ttk.Button(grid, text="Browse", command=self._pick_assets).grid(row=1, column=2)
        ttk.Label(grid, text="the folder that contains Image/ and Music/ -- nothing is copied, "
                             "it is only linked",
                  foreground="#666666").grid(row=2, column=1, sticky="w", padx=6)

        # options
        opts = ttk.LabelFrame(outer, text="Options", padding=8)
        opts.pack(fill="x", pady=10)
        ttk.Checkbutton(opts, text="Build the client (15-40 min, all cores)",
                        variable=self.build_var).grid(row=0, column=0, sticky="w")
        ttk.Checkbutton(opts, text="Install menu + desktop shortcut",
                        variable=self.shortcut_var).grid(row=1, column=0, sticky="w")
        ttk.Checkbutton(opts, text="Apply the project's patches",
                        variable=self.patches_var).grid(row=2, column=0, sticky="w")
        ttk.Label(opts, text="jobs").grid(row=0, column=1, padx=(24, 4))
        ttk.Spinbox(opts, from_=1, to=64, width=4, textvariable=self.jobs_var).grid(row=0, column=2)

        # buttons
        btns = ttk.Frame(outer)
        btns.pack(fill="x")
        self.install_btn = ttk.Button(btns, text="Install", command=self.start_install)
        self.install_btn.pack(side="left")
        self.verify_btn = ttk.Button(btns, text="Dry run", command=self.start_verify)
        self.verify_btn.pack(side="left", padx=6)
        self.stop_btn = ttk.Button(btns, text="Stop", command=self.stop, state="disabled")
        self.stop_btn.pack(side="left")
        ttk.Button(btns, text="Quit", command=self.destroy).pack(side="right")

        self.bar = ttk.Progressbar(outer, mode="indeterminate")
        self.bar.pack(fill="x", pady=(10, 6))

        # log
        logf = ttk.LabelFrame(outer, text="Log", padding=4)
        logf.pack(fill="both", expand=True)
        self.log_widget = tk.Text(logf, height=14, wrap="word", borderwidth=0,
                                  background="#1e1f22", foreground="#dcdcdc",
                                  insertbackground="#dcdcdc", font=("TkFixedFont", 9))
        scroll = ttk.Scrollbar(logf, command=self.log_widget.yview)
        self.log_widget.configure(yscrollcommand=scroll.set)
        self.log_widget.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")

    def _pick_prefix(self) -> None:
        d = filedialog.askdirectory(title="Where should O2Jam be installed?",
                                    initialdir=str(Path.home()))
        if d:
            self.prefix_var.set(d)

    def _pick_assets(self) -> None:
        d = filedialog.askdirectory(title="Pick the folder that contains Image/ and Music/")
        if d:
            self.assets_var.set(d)

    # ----------------------------------------------------------------- log --
    def log(self, line: str) -> None:
        self.log_widget.configure(state="normal")
        self.log_widget.insert("end", line + "\n")
        self.log_widget.see("end")
        self.log_widget.configure(state="disabled")

    def _poll_log(self) -> None:
        try:
            while True:
                self.log(self.log_q.get_nowait())
        except queue.Empty:
            pass
        self.after(120, self._poll_log)

    # -------------------------------------------------------------- command --
    def build_command(self, verify: bool) -> list[str]:
        prefix, assets = self.prefix_var.get(), self.assets_var.get()
        if not self.script:
            raise RuntimeError("cannot find install.sh / install.ps1 next to this installer")
        if self.script.suffix == ".ps1":
            cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                   "-File", str(self.script), "-Prefix", prefix, "-Yes",
                   "-Jobs", self.jobs_var.get()]
            if assets:
                cmd += ["-Assets", assets]
            if verify or not self.build_var.get():
                cmd.append("-NoBuild")
            if verify or not self.shortcut_var.get():
                cmd.append("-NoShortcut")
            if not self.patches_var.get():
                cmd.append("-SkipPatches")
            return cmd
        cmd = ["bash", str(self.script), "--prefix", prefix, "--yes",
               "--jobs", self.jobs_var.get()]
        if assets:
            cmd += ["--assets", assets]
        if verify or not self.build_var.get():
            cmd.append("--no-build")
        if verify or not self.shortcut_var.get():
            cmd.append("--no-shortcut")
        return cmd

    def _start(self, verify: bool) -> None:
        if self.busy:
            return
        if not self.prefix_var.get().strip():
            messagebox.showerror("Missing install folder", "Pick a folder to install into.")
            return
        if verify:
            self.log("")
            self.log("== DRY RUN: no build, no shortcuts -- this checks downloads, patches and layout ==")
        try:
            cmd = self.build_command(verify)
        except RuntimeError as e:
            messagebox.showerror("Cannot start", str(e))
            return

        self.busy = True
        self.install_btn.configure(state="disabled")
        self.verify_btn.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        self.bar.start(12)
        self.log("")
        self.log("$ " + " ".join(shlex.quote(c) if " " in c else c for c in cmd))

        env = dict(os.environ, PYTHONUNBUFFERED="1")
        creation = subprocess.CREATE_NO_WINDOW if WIN else 0
        try:
            self.proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL, text=True, bufsize=1, env=env,
                creationflags=creation)
        except OSError as e:
            self._finish(f"could not start the installer: {e}")
            return
        threading.Thread(target=self._reader, daemon=True).start()

    def start_install(self) -> None:
        if messagebox.askokcancel(
                "Install O2Jam?",
                "This will download source code and (optionally) build the client.\n\n"
                f"Install folder : {self.prefix_var.get()}\n"
                f"Game data      : {self.assets_var.get() or '(none yet)'}\n\n"
                "No sudo/admin rights are used, and no game data is downloaded."):
            self._start(verify=False)

    def start_verify(self) -> None:
        self._start(verify=True)

    def _reader(self) -> None:
        assert self.proc and self.proc.stdout
        for line in self.proc.stdout:
            self.log_q.put(line.rstrip("\n"))
        self.proc.wait()
        self._finish(None)

    def _finish(self, error: str | None) -> None:
        rc = self.proc.returncode if self.proc else None
        self.proc = None
        self.busy = False
        self.install_btn.configure(state="normal")
        self.verify_btn.configure(state="normal")
        self.stop_btn.configure(state="disabled")
        self.bar.stop()
        self.log("")
        if error:
            self.log(f"!! {error}")
            messagebox.showerror("Installer", error)
        elif rc == 0:
            self.log("== installer finished, exit 0 ==")
            messagebox.showinfo("Done", "Finished.\n\nIf you skipped the build, run it from the "
                                        "install folder when you're ready.")
        else:
            self.log(f"== installer exited with code {rc} -- scroll up for the first error ==")
            messagebox.showwarning("Finished with problems",
                                   f"The installer exited with code {rc}.\n"
                                   "The log in this window shows what happened.")

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            if messagebox.askyesno("Stop?", "Kill the installer process?"):
                self.proc.terminate()
                self.log("!! stopped by user")


def main() -> int:
    app = Installer()
    app.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
