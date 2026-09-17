# Parse-check the Windows driver with real PowerShell 7 (running natively on Linux).
# Reports: syntax errors, the declared parameters, and whether every flag the GUI
# sends actually exists -- i.e. the GUI <-> install.ps1 contract.
#
#   pwsh -NoProfile -Command "& packaging/check-powershell.ps1 -Files install.ps1,packaging/build-windows.ps1"
#
# (Use -Command, not -File: with -File the comma list arrives as one literal string.)
#
# Why bother: PowerShell parses "$var: text" as a *drive/scope* reference, so a
# stray colon silently breaks the whole script -- and a Windows one-liner that
# fails to parse on line 201 is a one-liner that never runs at all.
param([string[]]$Files)

$fail = $false
foreach ($f in $Files) {
    Write-Host "`n=== $f ==="
    $errors = $null; $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $fail = $true
        Write-Host "  PARSE ERRORS: $($errors.Count)"
        $errors | ForEach-Object { Write-Host ("   line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) }
    } else {
        Write-Host "  [ok  ] parse: no syntax errors"
    }

    $params = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true) |
              ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object -Unique
    if ($params) { Write-Host ("  params: " + ($params -join ', ')) }

    $fn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    if ($fn) { Write-Host ("  functions: " + (($fn | ForEach-Object { $_.Name }) -join ', ')) }

    # The flag contract only applies to the driver itself (install.ps1).
    if ($params -contains 'Prefix') {
        foreach ($flag in 'Prefix', 'Assets', 'Jobs', 'NoBuild', 'NoShortcut', 'SkipPatches', 'Yes') {
            $state = if ($params -contains $flag) { 'ok  ' } else { 'MISS' }
            Write-Host "  [$state] accepts -$flag"
        }
    }
}
if ($fail) { exit 1 }
Write-Host "`nPARSE-CHECK OK"
