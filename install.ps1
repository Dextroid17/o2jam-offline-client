<#
================================================================================
                  O2Jam Offline Client -- installer (Windows)

  One line (PowerShell, no admin needed for the game itself):

    irm https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.ps1 | iex

  With your game data:
    & ([scriptblock]::Create((irm .../install.ps1))) -Assets "$HOME\O2Jam"

  What it does
    1. checks the toolchain (git, cmake, ninja, MSVC C++ tools) -- it will TELL
       you the winget command for anything missing, and only runs it if you say yes
    2. clones this project + upstream CXO2 into $Prefix
    3. applies our patches to CXO2, Genode and the fetched SFML source
    4. builds with MSVC + Ninja, exactly like upstream's own CI does
    5. junctions YOUR OWN O2Jam data next to the executable
    6. drops a Start-Menu + Desktop shortcut

  Honesty note: this script follows upstream's Windows CI recipe (msvc + ninja,
  build dir build/, output bin/windows/<Config>/). I developed the whole project
  on Linux and have NO Windows machine to test it on -- treat the Windows path
  as "should work, report what breaks". The Linux installer is battle-tested.

  Nothing here needs game data to be downloaded. No game files are bundled.
================================================================================
#>

[CmdletBinding()]
param(
    [string] $Prefix      = (Join-Path $HOME 'o2jam'),
    [string] $Assets      = '',
    [string] $Repo        = 'https://github.com/Dextroid17/o2jam-offline-client.git',
    [string] $Branch      = 'main',
    [string] $Cxo2Url     = 'https://github.com/SirusDoma/CXO2.git',
    [string] $Cxo2Ref     = '720f966',
    [string] $BuildType   = 'Release',
    [string] $Arch        = 'x64',
    [int]    $Jobs        = 0,
    [switch] $NoBuild,
    [switch] $NoShortcut,
    [switch] $SkipPatches,
    [switch] $Yes,
    [switch] $Gui
)

$ErrorActionPreference = 'Stop'
$Version = '1.1'

# ------------------------------------------------------------------- output --
function Info($m) { Write-Host "    $m" }
function Dim($m)  { Write-Host "    $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "    ! $m" -ForegroundColor Yellow }
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Green -NoNewline; Write-Host '' }
function Die($m)  { Write-Host "`nxx  $m`n" -ForegroundColor Red; exit 1 }
function Ask($q) {
    if ($Yes) { return $true }
    $a = Read-Host "    $q [Y/n]"
    return ($a -eq '' -or $a -match '^[Yy]')
}

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor White
Write-Host '    O2Jam Offline Client -- installer' -NoNewline
Write-Host " v$Version  (Windows)"
Write-Host '    native client, no Wine, no emulator, no VM'
Write-Host '  ============================================================' -ForegroundColor White
Write-Host ''
Info "install dir : $Prefix"
Info "source      : $Repo  (branch $Branch)"
Info "client      : $Cxo2Url  @ $Cxo2Ref"
Info "toolchain   : MSVC ($Arch) + Ninja, $BuildType"
Info "game data   : $(if ($Assets) { $Assets } else { '<you will be asked / pass -Assets later>' })"

# ------------------------------------------------------------------ 1. tools --
Step '1/7  checking the toolchain'

$wingetPkgs = [ordered]@{
    git   = 'Git.Git'
    cmake = 'Kitware.CMake'
    ninja = 'Ninja-build.Ninja'
    py    = 'Python.Python.3.12'
}
$missing = @()
foreach ($c in 'git','cmake','ninja') {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { $missing += $c }
}
function Get-VsPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $null }
    $p = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($p) { return $p.Trim() }
    return $null
}
$vsPath = Get-VsPath

if ($missing.Count -gt 0 -or -not $vsPath) {
    if ($missing.Count -gt 0) { Warn "missing tools: $($missing -join ', ')" }
    if (-not $vsPath) { Warn 'Visual Studio C++ build tools not found' }

    $cmds = @()
    foreach ($m in $missing) { $cmds += "winget install --id $($wingetPkgs[$m]) -e" }
    if (-not $vsPath) {
        $cmds += 'winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"'
    }
    Write-Host ''
    Dim 'Run these (the VS one is a multi-GB download and may show a UAC prompt):'
    foreach ($c in $cmds) { Write-Host "      $c" -ForegroundColor Cyan }
    Write-Host ''
    if (Ask 'Run them now?') {
        foreach ($c in $cmds) {
            Info "running: $c"
            cmd /c $c
        }
        # refresh PATH for this session
        $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path','User')
        $vsPath = Get-VsPath
    } else {
        Dim 'fine -- install them yourself and re-run me.'
        exit 1
    }
}

if (-not $vsPath) { Die 'still no MSVC C++ tools. Re-run after installing the VS Build Tools.' }
Info ("git   " + (& git --version))
Info ("cmake " + ((& cmake --version)[0]))
if (Get-Command ninja -ErrorAction SilentlyContinue) { Info ("ninja " + (& ninja --version)) } else { Warn 'ninja not on PATH (CMake will complain)' }
Info "MSVC  $vsPath"

# put the MSVC environment into this PowerShell session (same trick upstream CI uses)
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat'
if (Test-Path $vcvars) {
    Info "MSVC env: vcvarsall $Arch"
    $lines = & cmd.exe /c "`"$vcvars`" $Arch >nul 2>&1 && set"
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $n = $Matches[1]; $v = $Matches[2]
            if ($n -and $v -and $n -notmatch '[\s]') {
                try { Set-Item -Path "env:$n" -Value $v -ErrorAction Stop } catch { }
            }
        }
    }
} else {
    Warn "no vcvarsall.bat at $vcvars -- MSVC may not be on PATH for this shell"
}
if ($Jobs -le 0) { $Jobs = [Math]::Max(2, [Environment]::ProcessorCount - 1) }
Info "build jobs: $Jobs"

# ----------------------------------------------------------------- 2. layout --
Step "2/7  creating $Prefix"
foreach ($d in 'src','native') { New-Item -ItemType Directory -Force -Path (Join-Path $Prefix $d) | Out-Null }
Info "$Prefix\src      this project"
Info "$Prefix\native   scripts + the built client"

# ---------------------------------------------------------------- 3. sources --
Step '3/7  getting the sources'

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
if (Test-Path (Join-Path $scriptDir 'scripts\apply-patches.sh')) {
    $src = $scriptDir
    Info "using the checkout at $src"
} else {
    $src = Join-Path $Prefix 'src\o2jam-offline-client'
    if (Test-Path (Join-Path $src '.git')) {
        Info "updating $src"
        & git -C $src fetch --depth 1 origin $Branch ; & git -C $src checkout -q $Branch ; & git -C $src pull -q --ff-only
    } else {
        Info "cloning $Repo"
        & git clone -q --branch $Branch --depth 1 $Repo $src
        if ($LASTEXITCODE -ne 0) { Die "clone failed -- is the repo public? ($Repo)" }
    }
}
if (-not (Test-Path (Join-Path $src 'patches'))) { Die "$src does not look like this project" }

$cxo2 = Join-Path $Prefix 'native\CXO2'
if (Test-Path (Join-Path $cxo2 '.git')) {
    Info "CXO2 already present at $cxo2"
} else {
    Info 'cloning CXO2 (with the Genode submodule) -- the big download'
    & git clone -q $Cxo2Url $cxo2
    if ($LASTEXITCODE -ne 0) { Die 'CXO2 clone failed' }
}
& git -C $cxo2 cat-file -e "$Cxo2Ref^{commit}" 2>$null
if ($LASTEXITCODE -eq 0) {
    & git -C $cxo2 checkout -q $Cxo2Ref
    Info "CXO2 pinned to $Cxo2Ref (the commit our patches are tested against)"
} else {
    Warn "commit $Cxo2Ref not found -- staying on the default branch"
}
Info 'fetching submodules ...'
& git -C $cxo2 submodule update --init --recursive
Info 'submodules ready'

# ---------------------------------------------------------------- 4. patches --
Step '4/7  applying patches'

function Apply-Patch([string]$repo, [string]$patch, [string]$label) {
    if (-not (Test-Path $repo)) { Warn "  ?  ${label}: no source at $repo"; return $false }
    if (-not (Test-Path $patch)) { Warn "  ?  ${label}: no patch $patch"; return $false }
    $name = Split-Path $patch -Leaf
    & git -C $repo apply --reverse --check $patch 2>$null
    if ($LASTEXITCODE -eq 0) { Info "  ok already applied  $name  ($label)"; return $true }
    & git -C $repo apply --3way $patch 2>$null
    if ($LASTEXITCODE -ne 0) { & git -C $repo apply $patch }
    if ($LASTEXITCODE -ne 0) {
        Warn "  !! FAILED           $name  ($label)"
        & git -C $repo apply --check $patch
        return $false
    }
    Info "  ok applied         $name  ($label)"
    return $true
}

if ($SkipPatches) {
    Dim 'skipped (-SkipPatches) -- building upstream as-is'
} else {
    $ok = $true
    foreach ($p in (Get-ChildItem (Join-Path $src 'patches') -Filter '01-*.patch')) {
        if (-not (Apply-Patch $cxo2 $p.FullName 'CXO2')) { $ok = $false }
    }
    $genode = Join-Path $cxo2 'modules\Genode'
    foreach ($p in (Get-ChildItem (Join-Path $src 'patches') -Filter '03-*.patch')) {
        if (-not (Apply-Patch $genode $p.FullName 'Genode')) { $ok = $false }
    }
    if (-not $ok) { Warn 'some patches did not apply -- the build may fail; the log will say where' }
}

# ------------------------------------------------------------------ 5. venv ---
Step '5/7  python (only for the graphical installer / tooling)'
$py = $null
foreach ($c in 'py','python','python3') {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $py = $c; break }
}
if ($py) { Info "python: $py" } else { Dim 'no python found -- text mode only, the game does not need it' }

# ------------------------------------------------------------------ 6. build --
Step '6/7  building the client'
$buildDir  = Join-Path $cxo2 'build'
$outDir    = Join-Path $cxo2 "bin\windows\$BuildType"
$exePath   = Join-Path $outDir 'OTwo.exe'
$logFile   = Join-Path $Prefix 'native\build.log'

if ($NoBuild) {
    Dim 'skipped (-NoBuild)'
} elseif (Ask "Build now? It takes 15-40 minutes on a decent CPU (log: $logFile)") {
    try {
        $cmakeFlags = @('-B', $buildDir, '-G', 'Ninja', "-DCMAKE_BUILD_TYPE=$BuildType")
        Info 'step 1/4  cmake configure (downloads SFML etc.)'
        & cmake @cmakeFlags *>> $logFile
        if ($LASTEXITCODE -ne 0) { throw 'configure failed' }

        $sfml = Get-ChildItem (Join-Path $buildDir '_deps') -Filter 'sfml-src' -Directory -ErrorAction SilentlyContinue |
                Select-Object -First 1
        if ($sfml -and -not $SkipPatches) {
            foreach ($p in (Get-ChildItem (Join-Path $src 'patches') -Filter '02-*.patch')) {
                $applied = Apply-Patch $sfml.FullName $p.FullName 'sfml-src'
                if ($applied) {
                    Info 'step 2/4  SFML patch applied -- re-configuring'
                    & cmake @cmakeFlags *>> $logFile
                }
            }
        } else {
            Info 'step 2/4  no SFML patch needed here'
        }

        Info 'step 3/4  ResourceCompiler (upstream requires it first)'
        & cmake --build $buildDir --config $BuildType --target ResourceCompiler -j $Jobs *>> $logFile
        $rc = Join-Path $cxo2 "bin\compiler\$BuildType\ResourceCompiler.exe"
        if (Test-Path $rc) { Push-Location $cxo2; & $rc *>> $logFile; Pop-Location }
        else { Warn "ResourceCompiler.exe not where expected ($rc)" }

        Info 'step 4/4  the game itself (the slow one)'
        & cmake --build $buildDir --config $BuildType --target CXO2 -j $Jobs *>> $logFile
        if (Test-Path $exePath) { Info "client built: $exePath" }
        else { Warn "no OTwo.exe at $exePath -- full log: $logFile"; Get-Content $logFile -Tail 25 | ForEach-Object { Dim $_ } }
    } catch {
        Warn "build problem: $_  (log: $logFile)"
    }
} else {
    Dim "fine -- later:  cd `"$cxo2`" ; cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=$BuildType"
}

# ----------------------------------------------------------------- 7. assets ---
Step '7/7  game data + shortcuts'

if (-not $Assets) {
    Dim 'I did not touch your game data. Point me at it whenever you like:'
    Dim "  .\install.ps1 -Prefix `"$Prefix`" -Assets `"D:\path\to\your\o2jam`""
    Dim '  (the folder that contains Image\ and Music\)'
} else {
    if (-not (Test-Path $Assets)) { Die "the assets path does not exist: $Assets" }
    $targets = @()
    foreach ($d in 'Image','Music','Avatar') {
        $s = Join-Path $Assets $d
        if (Test-Path $s) { $targets += @{ Src = $s; Name = $d } }
    }
    if ($targets.Count -eq 0) { Warn "no Image\, Music\ or Avatar\ inside $Assets" }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    foreach ($t in $targets) {
        $dest = Join-Path $outDir $t.Name
        if (Test-Path $dest) { Info "  keeping existing $($t.Name)\ (not touching it)"; continue }
        try {
            New-Item -ItemType Junction -Path $dest -Target $t.Src | Out-Null
            Info "  junction  $($t.Name)  ->  $($t.Src)"
        } catch {
            Warn "  junction failed for $($t.Name) -- copying instead (uses disk space)"
            Copy-Item -Recurse -Force $t.Src $dest
        }
    }
    Info "data linked next to the executable: $outDir"
}

if ($NoShortcut) {
    Dim 'shortcuts skipped (-NoShortcut)'
} else {
    $native = Join-Path $Prefix 'native'
    $cmd = Join-Path $native 'o2jam-offline.cmd'
    @"
@echo off
rem O2Jam Offline Client -- generated by install.ps1
rem Window geometry is read by the patched client from these variables.
set O2JAM_WINDOW=1280x720
rem set O2JAM_POS=100,100
rem set O2JAM_FIT=letterbox
rem set O2JAM_BORDERLESS=1
start "" "$exePath"
"@ | Set-Content -Encoding ASCII $cmd
    Info "launcher: $cmd"

    $ws = New-Object -ComObject WScript.Shell
    $targets = @()
    $targets += (Join-Path ([Environment]::GetFolderPath('Programs')) 'O2Jam Offline Client.lnk')
    $targets += (Join-Path ([Environment]::GetFolderPath('Desktop')) 'O2Jam Offline Client.lnk')
    foreach ($lnkPath in $targets) {
        try {
            $lnk = $ws.CreateShortcut($lnkPath)
            $lnk.TargetPath       = $cmd
            $lnk.WorkingDirectory = $outDir
            $lnk.Description      = 'O2Jam, running natively'
            if (Test-Path (Join-Path $src 'desktop\o2jam.ico')) { $lnk.IconLocation = (Join-Path $src 'desktop\o2jam.ico') }
            elseif (Test-Path $exePath) { $lnk.IconLocation = $exePath }
            $lnk.Save()
            Info "shortcut: $lnkPath"
        } catch { Warn "could not write $lnkPath" }
    }
}

if ($Gui) {
    if ($py) { & $py (Join-Path $src 'installer\o2jam-installer.py') --prefix $Prefix }
    else { Warn 'no python -- cannot open the graphical installer' }
}

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Green
Write-Host '    done -- O2Jam should be yours now'
Write-Host '  ============================================================' -ForegroundColor Green
Write-Host ''
if (Test-Path $exePath) {
    Info "play it:  `"$cmd`"    (or the Start-Menu entry)"
    Info "bare exe: $exePath"
} else {
    Warn "the client was not built -- check $logFile"
}
Info "assets expected at: $outDir\{Image,Music}"
Write-Host ''
