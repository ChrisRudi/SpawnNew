# tools/Invoke-Lint.ps1
# Version 1.1 | Prueft allen PowerShell-Code von SpawnNew.
# Zweck  : PSScriptAnalyzer ueber src/ und tools/ laufen lassen.
# Input  : -Path (optional) einzelne Dateien oder Ordner; -Severity Mindeststufe.
# Output : Befundliste auf stdout. Rueckgabewert 1, wenn Befunde ab -Severity.
# Deps   : PowerShell 7, PSScriptAnalyzer 1.23 (tools/Install-DevTools.ps1).

[CmdletBinding()]
param(
    [string[]]$Path,
    [ValidateSet('Information', 'Warning', 'Error')]
    [string]$Severity = 'Warning'
)

$ErrorActionPreference = 'Stop'

Import-Module PSScriptAnalyzer -ErrorAction Stop

$repoRoot   = Split-Path -Parent $PSScriptRoot
$settings   = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
$extensions = @('.ps1', '.psm1', '.psd1')

if (-not $Path) {
    $Path = @((Join-Path $repoRoot 'src'), (Join-Path $repoRoot 'tools'), (Join-Path $repoRoot 'tests'))
}

$existing = @($Path | Where-Object { Test-Path -LiteralPath $_ })

$fileCount = @(
    $existing |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File } |
        Where-Object { $extensions -contains $_.Extension }
).Count

if ($fileCount -eq 0) {
    Write-Output 'Keine PowerShell-Dateien gefunden.'
    exit 0
}

# Ein Aufruf je Pfad: PSScriptAnalyzer laedt das Kompatibilitaetsprofil pro
# Aufruf neu, was je Aufruf rund 20 Sekunden kostet.
$findings = @(
    $existing | ForEach-Object {
        if (Test-Path -LiteralPath $_ -PathType Container) {
            Invoke-ScriptAnalyzer -Path $_ -Settings $settings -Recurse
        }
        else {
            Invoke-ScriptAnalyzer -Path $_ -Settings $settings
        }
    }
)

$separator = [string][System.IO.Path]::DirectorySeparatorChar
$prefix    = $repoRoot.TrimEnd($separator) + $separator
$order     = @(
    @{ Expression = 'Severity'; Descending = $true }
    @{ Expression = 'ScriptPath' }
    @{ Expression = 'Line' }
)

foreach ($f in ($findings | Sort-Object -Property $order)) {
    $rel = ([string]$f.ScriptPath).Replace($prefix, '')
    Write-Output ('{0,-11} {1}:{2} {3} - {4}' -f $f.Severity, $rel, $f.Line, $f.RuleName, $f.Message)
}

# Nur Stufen ab -Severity brechen den Lauf ab; der Rest wird nur gemeldet.
$ranks    = @{ Information = 0; Warning = 1; Error = 2 }
$minRank  = $ranks[$Severity]
$blocking = @($findings | Where-Object { $ranks[[string]$_.Severity] -ge $minRank })

Write-Output ''
Write-Output ('{0} Datei(en) geprueft, {1} Befund(e), davon {2} ab Stufe {3}.' -f $fileCount, $findings.Count, $blocking.Count, $Severity)

if ($blocking.Count -gt 0) { exit 1 }
exit 0
