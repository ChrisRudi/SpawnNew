# tests/SpawnNew.PowerShellWerkzeug.Tests.ps1
# Version 1.0 | Prueft Aktion 3 gegen den Ausfuehrungsvertrag.
# Zweck  : Skript mit Kopf, Konfiguration und README; das erzeugte Skript
#          muss fehlerfrei parsen und lauffaehig sein.

Import-SpawnNewHostModule -Name 'Config', 'Runner'

function Invoke-Werkzeug {
    param([hashtable]$Value, [string]$Target)
    if (-not $Target) { $Target = Join-Path (Get-SpawnNewTestDirectory) $Value['name'] }
    return (Invoke-SpawnNewTestAction -Folder 'PowerShellWerkzeug' -Id 'spawnnew.pstool' -Value $Value -TargetPath $Target)
}

function Get-ParseError {
    param([string]$Path)
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    return @($errors).Count
}

Add-SpawnNewTest 'Legt Skript, Konfiguration und README an' {
    $run = Invoke-Werkzeug -Value @{ name = 'Get-Inventar'; beschreibung = 'Liest den Bestand ein.'; konfiguration = $true }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 0
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'

    $script = Join-Path $run.Target 'Get-Inventar.ps1'
    $text = [System.IO.File]::ReadAllText($script)
    Confirm-SpawnNewMatch -Label 'Dateiname im Kopf' -Actual $text -Pattern '^﻿?# Get-Inventar\.ps1'
    Confirm-SpawnNewMatch -Label 'Version im Kopf' -Actual $text -Pattern '# Version 1\.0 \| Liest den Bestand ein\.'
    Confirm-SpawnNewValue -Label 'BOM' -Actual ([System.IO.File]::ReadAllBytes($script)[0]) -Expected 239
    Confirm-SpawnNewValue -Label 'parst fehlerfrei' -Actual (Get-ParseError -Path $script) -Expected 0

    $config = ConvertFrom-Json ([System.IO.File]::ReadAllText((Join-Path $run.Target 'Get-Inventar.config.json')))
    Confirm-SpawnNewValue -Label 'Konfigurationsversion' -Actual $config.version -Expected '1.0'
    Confirm-SpawnNewMatch -Label 'README' -Actual ([System.IO.File]::ReadAllText((Join-Path $run.Target 'README.md'))) -Pattern 'Get-Inventar\.ps1'
}

Add-SpawnNewTest 'Erzeugtes Skript laeuft mit seiner Konfiguration' {
    $run = Invoke-Werkzeug -Value @{ name = 'Test-Lauf'; beschreibung = 'Probe'; konfiguration = $true }
    $shell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    # Fehlerausgaben des Skripts sollen in der Meldung landen, nicht den
    # Test vorzeitig abbrechen.
    $ErrorActionPreference = 'Continue'
    $output = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $run.Target 'Test-Lauf.ps1') -Verbose 2>&1

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $LASTEXITCODE -Expected 0
    Confirm-SpawnNewMatch -Label 'Konfiguration geladen' -Actual (($output | ForEach-Object { [string]$_ }) -join ' ') -Pattern 'Version 1\.0'
}

Add-SpawnNewTest 'Ohne Konfiguration entsteht keine JSON-Datei' {
    $run = Invoke-Werkzeug -Value @{ name = 'Ohne'; beschreibung = 'x'; konfiguration = $false }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewCondition -Label 'keine JSON' -Condition (-not (Test-Path -LiteralPath (Join-Path $run.Target 'Ohne.config.json')))
    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $run.Result.Created.Count -Expected 3
}

Add-SpawnNewTest 'Mehrzeilige Beschreibung bleibt im Kommentar' {
    $run = Invoke-Werkzeug -Value @{ name = 'Mehr'; beschreibung = "Erste Zeile.`r`nZweite Zeile mit Ümlaut."; konfiguration = $false }
    $script = Join-Path $run.Target 'Mehr.ps1'

    Confirm-SpawnNewValue -Label 'parst fehlerfrei' -Actual (Get-ParseError -Path $script) -Expected 0
    Confirm-SpawnNewMatch -Label 'Fortsetzung' -Actual ([System.IO.File]::ReadAllText($script)) -Pattern '#          Zweite Zeile mit Ümlaut\.'
}

Add-SpawnNewTest 'Vorhandene README bleibt, Status partial' {
    $target = Join-Path (Get-SpawnNewTestDirectory) 'Alt'
    [void](Add-SpawnNewTestFile -Path (Join-Path $target 'README.md') -Content 'EIGEN')
    $run = Invoke-Werkzeug -Value @{ name = 'Alt'; beschreibung = 'x'; konfiguration = $false } -Target $target

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 2
    Confirm-SpawnNewValue -Label 'README' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'README.md'))) -Expected 'EIGEN'
}
