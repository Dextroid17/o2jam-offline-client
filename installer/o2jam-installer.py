#!/usr/bin/env python3
"""
================================================================================
             O2Jam Offline Client -- graphical installer   v1.2
================================================================================

A small Tkinter front-end for install.sh (Linux) and install.ps1 (Windows).
Same window, same options on both platforms: pick where it goes, point at the
game data you already own, press Install, watch the log.

Three ways to run it
--------------------
    O2Jam-Installer                             the packaged build: no Python needed
    python3 installer/o2jam-installer.py        straight from the checkout
    py -3 installer\\o2jam-installer.py          same, on Windows

    O2Jam-Installer --self-test                 headless check of this build
    O2Jam-Installer --print-command             show the command it would run
    O2Jam-Installer --dry-run --prefix DIR      run the driver, build skipped

When this file is packaged (PyInstaller), install.sh and install.ps1 travel
*inside* the executable as data files and get unpacked to a temp directory on
demand -- so the binary / AppImage / .exe is a complete, self-contained
installer that needs no checkout next to it.

Nothing here uses sudo / admin rights. Everything lands in user space.
================================================================================
"""

import argparse
import io
import os
import platform
import queue
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

TK_ERROR = ""
try:
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox
except Exception as exc:                              # pragma: no cover
    tk = None                                         # --self-test still works
    TK_ERROR = f"{type(exc).__name__}: {exc}"

WIN = platform.system() == "Windows"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
VERSION = "1.2"
FROZEN = bool(getattr(sys, "frozen", False))
DRIVERS = ("install.ps1", "install.sh") if WIN else ("install.sh", "install.ps1")

# ---------------------------------------------------------------------------
#  A *windowed* .exe has no stdout/stderr at all. Borrow the console we were
#  launched from when there is one (so `O2Jam-Installer.exe --self-test` prints
#  like a normal command-line tool); if there is none, carry on with a sink --
#  self-test still returns its exit code and hands the report over another way.
# ---------------------------------------------------------------------------
CONSOLE = True


def _fix_streams() -> None:
    global CONSOLE
    if sys.stdout is not None and sys.stderr is not None:
        return
    if WIN:
        try:
            import ctypes
            if ctypes.windll.kernel32.AttachConsole(-1):
                sys.stdout = open("CONOUT$", "w", encoding="utf-8", errors="replace",
                                  buffering=1)
                sys.stderr = sys.stdout
                return
        except Exception:
            pass
    CONSOLE = False

    class _Sink:
        def write(self, *_a):
            return 0

        def flush(self):
            pass

        def isatty(self):
            return False

    sys.stdout = _Sink()
    sys.stderr = _Sink()


_fix_streams()

NO_TK_HELP = (
    "\n  This installer needs Python's tkinter module.\n"
    "    Debian/Ubuntu : sudo apt install python3-tk\n"
    "    Fedora        : sudo dnf install python3-tkinter\n"
    "    Arch/CachyOS  : sudo pacman -S tk\n"
    "    Windows/macOS : comes with the python.org installer\n\n")


# ---------------------------------------------------------------- drivers ---
def payload_dir() -> Path | None:
    """Where the bundled install.sh / install.ps1 live inside a packaged build."""
    if not FROZEN:
        return None
    base = Path(getattr(sys, "_MEIPASS", ROOT))
    for cand in (base / "payload", base):
        if any((cand / d).is_file() for d in DRIVERS):
            return cand
    return None


_staged: Path | None = None


def staged_dir() -> Path:
    """Copy the bundled drivers somewhere executable and hand back that folder.

    PyInstaller's _MEIPASS is read-only-ish and its mode bits don't survive, so
    bash cannot run install.sh straight out of the bundle.
    """
    global _staged
    if _staged and _staged.is_dir():
        return _staged
    d = Path(tempfile.mkdtemp(prefix="o2jam-installer-"))
    payload = payload_dir()
    if payload:
        for name in DRIVERS:
            src = payload / name
            if src.is_file():
                dst = d / name
                shutil.copy2(src, dst)
                try:
                    dst.chmod(0o755)
                except OSError:
                    pass
    _staged = d
    return d


def find_script(explicit: str | None = None, win: bool | None = None) -> Path | None:
    """Locate the CLI installer this GUI drives."""
    win = WIN if win is None else win
    order = ("install.ps1", "install.sh") if win else ("install.sh", "install.ps1")
    payload = payload_dir()

    cands: list[Path] = []
    if explicit:
        cands.append(Path(explicit).expanduser())
    env = os.environ.get("O2JAM_INSTALLER_SCRIPT")
    if env:
        cands.append(Path(env).expanduser())
    for folder in (ROOT, HERE):
        cands += [folder / n for n in order]
    if payload:
        cands += [payload / n for n in order]

    for c in cands:
        if c.is_file():
            if payload and c.parent == payload:      # unpack it first
                return Path(staged_dir()) / c.name
            return c
    return None


def default_prefix() -> str:
    return str(Path.home() / "o2jam")


# --------------------------------------------------------------- command ----
def driver_for(win: bool, script: Path | str | None = None) -> Path | str:
    """The driver that belongs to `win`, swapping a mismatched sibling if we can.

    Guards the trap the first packaging build fell into: a Linux checkout handed
    to the Windows branch would run install.sh *through PowerShell*.
    """
    want = "install.ps1" if win else "install.sh"
    if script:
        p = Path(script)
        if p.name.lower() == want:
            return p
        sibling = p.with_name(want)
        return sibling if sibling.is_file() else want
    return find_script(win=win) or want


def build_command(script: Path | str | None, prefix: str, assets: str = "", jobs: str = "",
                  build: bool = True, shortcut: bool = True, patches: bool = True,
                  verify: bool = False, win: bool | None = None) -> list[str]:
    """The exact command line for the driver, on either platform."""
    win = WIN if win is None else win
    target = str(driver_for(win, script))

    if win:
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", target,
               "-Prefix", prefix, "-Yes"]
        if jobs:
            cmd += ["-Jobs", str(jobs)]
        if assets:
            cmd += ["-Assets", assets]
        if verify or not build:
            cmd.append("-NoBuild")
        if verify or not shortcut:
            cmd.append("-NoShortcut")
        if not patches:
            cmd.append("-SkipPatches")
        return cmd

    cmd = ["bash", target, "--prefix", prefix, "--yes"]
    if jobs:
        cmd += ["--jobs", str(jobs)]
    if assets:
        cmd += ["--assets", assets]
    if verify or not build:
        cmd.append("--no-build")
    if verify or not shortcut:
        cmd.append("--no-shortcut")
    if not patches:
        cmd.append("--skip-patches")
    return cmd


def pretty(cmd: list[str]) -> str:
    return " ".join(shlex.quote(c) if (" " in c or not c) else c for c in cmd)


# ------------------------------------------------------------- self-test ----
def self_test(win: bool | None = None) -> int:
    """Run the headless checks, keeping the report for console-less builds."""
    buf = io.StringIO()
    real = sys.stdout

    class _Tee:
        def write(self, s: str):
            buf.write(s)
            try:
                real.write(s)
            except Exception:
                pass

        def flush(self):
            try:
                real.flush()
            except Exception:
                pass

    sys.stdout = _Tee()
    try:
        rc = _self_test_report(win)
    finally:
        sys.stdout = real
    if not CONSOLE:
        _deliver_report(buf.getvalue(), rc)
    return rc


def _deliver_report(text: str, rc: int) -> None:
    """No console to print to: leave the report where a person can read it."""
    path = None
    try:
        path = Path(tempfile.gettempdir()) / "o2jam-installer-self-test.txt"
        path.write_text(text, encoding="utf-8")
    except Exception:
        path = None
    try:
        import ctypes
        body = text if len(text) < 1800 else text[:1800] + "\n..."
        tail = f"\n\nfull report: {path}" if path else ""
        ctypes.windll.user32.MessageBoxW(
            None, body + tail,
            f"O2Jam installer self-test -- {'OK' if rc == 0 else 'FAILED'}",
            0x40 if rc == 0 else 0x30)
    except Exception:
        pass


def _self_test_report(win: bool | None = None) -> int:
    """Headless verification, used by the build scripts and by curious people."""
    win = WIN if win is None else win
    failures: list[str] = []

    def check(label: str, cond: bool, extra: str = "") -> None:
        print(f"  [{'ok  ' if cond else 'FAIL'}] {label}" + (f"  -- {extra}" if extra else ""))
        if not cond:
            failures.append(label)

    print(f"O2Jam Offline Client installer -- self-test")
    print(f"  version {VERSION}  frozen={FROZEN}")
    print(f"  python  {sys.version.split()[0]}  on {platform.system()} {platform.release()} ({platform.machine()})")
    print(f"  kit     {'tkinter ' + str(getattr(tk, 'TkVersion', '?')) if tk else 'NO TKINTER'}")
    check("tkinter importable (needed for the window)", tk is not None,
          (f"Tk {getattr(tk, 'TkVersion', '?')}" if tk else f"NO TKINTER -- {TK_ERROR}"))

    script = find_script()
    check("driver script found", script is not None,
          str(script) if script else "install.sh / install.ps1 not found")
    if script:
        check("driver readable", os.access(script, os.R_OK), str(script))
        check("driver non-empty", script.stat().st_size > 1000, f"{script.stat().st_size} bytes")
        text = script.read_text(errors="replace")
        check("driver never calls sudo", not any(
            ln.lstrip().startswith("sudo") for ln in text.splitlines()))
        check("driver never calls a package manager",
              not any(k in text for k in ("apt-get install -y", "pacman -S --noconfirm")))
    if script and not WIN and script.suffix == ".sh":
        try:
            pr = subprocess.run(["bash", str(script), "--help"],
                                capture_output=True, text=True, timeout=60)
            check("driver actually runs (--help)", pr.returncode == 0,
                  f"exit {pr.returncode}, {len(pr.stdout.splitlines())} lines of help")
        except Exception as exc:
            check("driver actually runs (--help)", False, f"{type(exc).__name__}: {exc}")

    if FROZEN:
        payload = payload_dir()
        check("drivers bundled inside this build", payload is not None,
              str(payload) if payload else "no payload directory in the bundle")
        if payload:
            for n in DRIVERS:
                check(f"bundled {n}", (payload / n).is_file())

    print("  commands it would run:")
    for label, w in (("linux  ", False), ("windows", True)):
        drv = find_script(win=w) or script
        cmd = build_command(drv, "PREFIX", assets="/path/to/game/data", jobs="8",
                            build=True, shortcut=True, patches=True, verify=False, win=w)
        want = ("-Prefix" if w else "--prefix"), ("-Jobs" if w else "--jobs"), \
               ("-Assets" if w else "--assets")
        got = all(any(x == flag for x in cmd) for flag in want)
        check(f"{label}: command built with prefix/jobs/assets", got)
        expect = "install.ps1" if w else "install.sh"
        chosen = Path(cmd[cmd.index("-File") + 1]).name if "-File" in cmd else \
            (Path(cmd[1]).name if len(cmd) > 1 else "")
        check(f"{label}: runs {expect}", chosen == expect, chosen or "no driver picked")
        print(f"      {pretty(cmd)}")
        dry = build_command(drv, "PREFIX", jobs="8", verify=True, win=w)
        flag = "-NoBuild" if w else "--no-build"
        check(f"{label}: dry run skips the build", flag in dry)
        print(f"      {pretty(dry)}")

    print()
    if failures:
        print(f"SELF-TEST FAILED -- {len(failures)} problem(s): " + "; ".join(failures))
        return 1
    print("SELF-TEST OK -- this build is ready to install O2Jam.")
    return 0


# ------------------------------------------------------------------- CLI ----
def dry_run(prefix: str, assets: str, jobs: str, script: Path | str | None) -> int:
    script = script or find_script()
    if not script:
        sys.stderr.write("no install.sh / install.ps1 found -- cannot dry run\n")
        return 2
    cmd = build_command(script, prefix, assets=assets, jobs=jobs, verify=True)
    print("$ " + pretty(cmd), flush=True)
    print("  (dry run: patches + downloads + layout, no build, no shortcuts)\n", flush=True)
    try:
        proc = subprocess.run(cmd)
    except OSError as e:
        sys.stderr.write(f"could not start the driver: {e}\n")
        return 2
    print(f"\n== driver exit code {proc.returncode} ==", flush=True)
    return proc.returncode


# ------------------------------------------------------------------- GUI ----
# Subclass defensively: without tkinter there is no window, but the module must
# still import so --self-test / --print-command can explain *why*.
class Installer(tk.Tk if tk else object):
    def __init__(self, prefix: str | None = None, assets: str = "", jobs: str = "") -> None:
        super().__init__()
        self.title(f"O2Jam Offline Client -- installer v{VERSION}")
        self.geometry("840x620")
        self.minsize(720, 520)

        self.script = find_script()
        self.proc: subprocess.Popen | None = None
        self.log_q: queue.Queue[str] = queue.Queue()
        self.busy = False

        self.prefix_var = tk.StringVar(value=prefix or default_prefix())
        self.assets_var = tk.StringVar(value=assets)
        self.build_var = tk.BooleanVar(value=True)
        self.shortcut_var = tk.BooleanVar(value=True)
        self.patches_var = tk.BooleanVar(value=True)
        self.jobs_var = tk.StringVar(value=jobs or str(max(2, (os.cpu_count() or 4) - 1)))

        self._build_ui()
        self._poll_log()
        self.log(f"O2Jam Offline Client installer v{VERSION}")
        self.log(f"platform : {platform.system()} {platform.release()}  ({platform.machine()})")
        self.log(f"python   : {sys.version.split()[0]}" + ("   (bundled)" if FROZEN else ""))
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
        if not self.script:
            raise RuntimeError("cannot find install.sh / install.ps1 for this platform")
        return build_command(self.script, self.prefix_var.get(), assets=self.assets_var.get(),
                             jobs=self.jobs_var.get(), build=self.build_var.get(),
                             shortcut=self.shortcut_var.get(), patches=self.patches_var.get(),
                             verify=verify)

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
        self.log("$ " + pretty(cmd))

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


# ------------------------------------------------------------------ main ----
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="O2Jam-Installer",
        description="Graphical installer for the O2Jam Offline Client (native, no Wine).",
        epilog="No sudo, no admin rights, no game data downloaded. Ever.")
    ap.add_argument("--version", action="version", version=f"O2Jam Offline Client installer {VERSION}")
    ap.add_argument("--prefix", default=None, help="install folder (default: ~/o2jam)")
    ap.add_argument("--assets", default="", help="folder holding your own Image/ and Music/")
    ap.add_argument("--jobs", default="", help="parallel build jobs")
    ap.add_argument("--script", default=None, help="path to install.sh / install.ps1")
    ap.add_argument("--self-test", action="store_true", help="check this build and exit")
    ap.add_argument("--print-command", action="store_true",
                    help="print the driver command line and exit")
    ap.add_argument("--dry-run", action="store_true",
                    help="run the driver with the build and shortcuts skipped")
    ap.add_argument("--simulate-windows", action="store_true",
                    help="with --self-test/--print-command: show the Windows command line")
    args = ap.parse_args(argv)

    win = WIN or args.simulate_windows

    if args.self_test:
        return self_test(win)

    if args.print_command:
        script = find_script(args.script, win)
        cmd = build_command(script, args.prefix or default_prefix(), assets=args.assets,
                            jobs=args.jobs or str(os.cpu_count() or 1), win=win)
        print(pretty(cmd))
        return 0 if script else 1

    if args.dry_run:
        return dry_run(args.prefix or default_prefix(), args.assets,
                       args.jobs or str(os.cpu_count() or 1), find_script(args.script, win))

    if tk is None:
        sys.stderr.write(f"tkinter is unavailable ({TK_ERROR or 'not installed'})." + NO_TK_HELP)
        return 1

    app = Installer(prefix=args.prefix, assets=args.assets, jobs=args.jobs)
    app.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
