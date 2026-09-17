# ============================================================================
#  Build the Windows installers -- a standalone .exe and (optionally) a
#  classic setup.exe made with Inno Setup.
#
#      powershell -ExecutionPolicy Bypass -File packaging\build-windows.ps1
#
#  Produces (in .\dist):
#      O2Jam-Installer.exe            single file, no Python needed
#      O2Jam-Installer-Setup.exe      only if Inno Setup (iscc) is installed
#
#  Needs: Python 3.11+ for Windows (python.org installer, tkinter included),
#         and Inno Setup 6 for the setup.exe step (https://jrsoftware.org/isdl.php).
#  Everything is user-space. No admin rights, no downloads except pip packages.
# ============================================================================
[CmdletBinding()]
param(
    [switch] $SkipInno,
    [string] $OutDir = ""
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
if (-not $OutDir) { $OutDir = Join-Path $repo 'dist' }
$work = Join-Path $env:LOCALAPPDATA 'o2jam-packaging'
$venv = Join-Path $work 'venv'

function Say([string] $m) { Write-Host "`n==> $m" -ForegroundColor Green }
function Dim([string] $m) { Write-Host "    $m" -ForegroundColor DarkGray }

New-Item -ItemType Directory -Force -Path $OutDir, $work | Out-Null

# ---- 1. python -----------------------------------------------------------
Say '1/5  finding python'
$pyExe = $null
$pyArgs = @()
foreach ($cand in @('py -3', 'python', 'python3')) {
    $parts = $cand.Split(' ')
    if (Get-Command $parts[0] -ErrorAction SilentlyContinue) {
        $pyExe = $parts[0]
        $pyArgs = @($parts | Select-Object -Skip 1)     # e.g. '-3' for the py launcher
        break
    }
}
if (-not $pyExe) { throw 'Python not found. Install it from https://python.org (tick "tcl/tk" and "Add to PATH").' }
Dim "$cand  --  $(& $pyExe @pyArgs --version 2>&1 | Select-Object -First 1)"

# ---- 2. venv -------------------------------------------------------------
Say '2/5  packaging virtualenv'
if (-not (Test-Path (Join-Path $venv 'Scripts\pyinstaller.exe'))) {
    & $pyExe @pyArgs -m venv $venv
    & (Join-Path $venv 'Scripts\python.exe') -m pip install -q --upgrade pip
    & (Join-Path $venv 'Scripts\pip.exe') install -q pyinstaller pillow
}
Dim "pyinstaller $(& (Join-Path $venv 'Scripts\pyinstaller.exe') --version)"

# ---- 3. icon -------------------------------------------------------------
Say '3/5  icon'
& (Join-Path $venv 'Scripts\python.exe') (Join-Path $here 'make-icon.py')

# ---- 4. exe --------------------------------------------------------------
Say '4/5  standalone .exe (PyInstaller, one file)'
& (Join-Path $venv 'Scripts\pyinstaller.exe') --noconfirm --clean `
    --distpath $OutDir --workpath (Join-Path $work 'build') (Join-Path $here 'o2jam-installer.spec')
$exe = Join-Path $OutDir 'O2Jam-Installer.exe'
if (-not (Test-Path $exe)) { throw "pyinstaller did not produce $exe" }
Dim ("{0}  ({1:N1} MB)" -f $exe, ((Get-Item $exe).Length / 1MB))

Say '     self-test of the built exe'
& $exe --self-test
if ($LASTEXITCODE -ne 0) { throw 'the built exe failed its own self-test' }

# ---- 5. Inno Setup -------------------------------------------------------
if ($SkipInno) { Say '5/5  Inno Setup skipped (--SkipInno)'; return }

Say '5/5  classic setup.exe (Inno Setup)'
$iscc = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    Dim 'Inno Setup (iscc) not found -- skipping the setup.exe.'
    Dim 'The standalone O2Jam-Installer.exe above is already a complete installer.'
    Dim 'For the classic wizard: install Inno Setup 6, then re-run this script.'
    return
}
Push-Location $repo
try {
    & $iscc "/DAppVersion=1.2" "/DSourceExe=$exe" (Join-Path $here 'o2jam-installer.iss')
} finally { Pop-Location }

$setup = Join-Path $OutDir 'O2Jam-Installer-Setup.exe'
if (Test-Path $setup) { Dim ("{0}  ({1:N1} MB)" -f $setup, ((Get-Item $setup).Length / 1MB)) }

Say 'done'
Dim "standalone : $exe"
if (Test-Path $setup) { Dim "setup.exe  : $setup" }
Dim 'both are user-space installers: no admin rights, no Python needed.'
