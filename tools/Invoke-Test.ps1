# tools/Invoke-Test.ps1
# Version 1.0 | Fuehrt die Tests von SpawnNew aus.
# Zweck  : Alle Dateien tests/*.Tests.ps1 laufen lassen.
# Input  : -Path (optional) einzelne Testdateien oder Ordner;
#          -Filter (optional) Namensmuster einzelner Testfaelle.
# Output : Bericht auf stdout. Rueckgabewert 1 bei mindestens einem Fehler.
# Deps   : Windows PowerShell 5.1, tools/SpawnNew.Test.psm1.

[CmdletBinding()]
param(
    [string[]]$Path,
    [string]$Filter = '*'
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Test.psm1') -ErrorAction Stop

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = @((Join-Path $repoRoot 'tests')) }

$failed = Invoke-SpawnNewTest -Path $Path -Filter $Filter

if ($failed -gt 0) { exit 1 }
exit 0
