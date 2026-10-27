# tests/SpawnNew.ProjektAbschliessen.Tests.ps1
# Version 1.0 | Prueft Aktion 15 gegen den Ausfuehrungsvertrag.
# Zweck  : Abschlussvermerk, Manifest mit SHA-256, ZIP, Verschieben und die
#          Vorpruefungen, die jede Aenderung verhindern.

Import-SpawnNewHostModule -Name 'Config', 'Runner'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Initialize-TestProjekt {
    $root = Join-Path (Get-SpawnNewTestDirectory) 'Projekt Ä'
    [void](Add-SpawnNewTestFile -Path (Join-Path $root 'Bericht.txt') -Content 'Inhalt')
    [void](Add-SpawnNewTestFile -Path (Join-Path $root 'Unter\Daten.csv') -Content 'a;b')
    return $root
}

function Invoke-Abschluss {
    param([string]$Target, [hashtable]$Value)
    $all = @{ vermerk = ''; zip = $false; verschieben = $false; archiv = '' }
    foreach ($key in $Value.Keys) { $all[$key] = $Value[$key] }
    return (Invoke-SpawnNewTestAction -Folder 'ProjektAbschliessen' -Id 'spawnnew.closeout' -Value $all -TargetPath $Target -TargetExisted $true)
}

Add-SpawnNewTest 'Vermerk und Manifest mit Pruefsummen werden angelegt' {
    $target = Initialize-TestProjekt
    $run = Invoke-Abschluss -Target $target -Value @{ vermerk = 'Abgegeben.' }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewMatch -Label 'Vermerk' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'ABSCHLUSS.md'))) -Pattern 'Abgegeben\.'

    $manifest = [System.IO.File]::ReadAllText((Join-Path $target 'MANIFEST-SHA256.txt'))
    $hash = (Get-FileHash -LiteralPath (Join-Path $target 'Unter\Daten.csv') -Algorithm SHA256).Hash
    Confirm-SpawnNewMatch -Label 'Pruefsumme' -Actual $manifest -Pattern ($hash + '  3  Unter\\Daten\.csv')
    Confirm-SpawnNewMatch -Label 'Vermerk im Manifest' -Actual $manifest -Pattern 'ABSCHLUSS\.md'
    Confirm-SpawnNewCondition -Label 'Manifest nicht in sich selbst' -Condition ($manifest -notmatch '  MANIFEST-SHA256\.txt')
}

Add-SpawnNewTest 'Zweiter Abschluss aendert nichts' {
    $target = Initialize-TestProjekt
    [void](Invoke-Abschluss -Target $target -Value @{ vermerk = 'erst' })
    $before = [System.IO.File]::ReadAllText((Join-Path $target 'ABSCHLUSS.md'))

    $run = Invoke-Abschluss -Target $target -Value @{ vermerk = 'zweit' }
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'failed'
    Confirm-SpawnNewValue -Label 'unveraendert' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'ABSCHLUSS.md'))) -Expected $before
}

Add-SpawnNewTest 'ZIP entsteht neben dem Ordner und enthaelt alle Dateien' {
    $target = Initialize-TestProjekt
    $run = Invoke-Abschluss -Target $target -Value @{ zip = $true }
    $zip = Join-Path (Split-Path -Parent $target) 'Projekt Ä.zip'

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try { $names = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') }) } finally { $archive.Dispose() }
    Confirm-SpawnNewCondition -Label 'Datei im ZIP' -Condition ($names -contains 'Projekt Ä/Unter/Daten.csv')
    Confirm-SpawnNewCondition -Label 'Manifest im ZIP' -Condition ($names -contains 'Projekt Ä/MANIFEST-SHA256.txt')
}

Add-SpawnNewTest 'Verschieben in das Archivverzeichnis' {
    $target = Initialize-TestProjekt
    $archiv = Join-Path (Get-SpawnNewTestDirectory) 'Archiv 2026'
    $run = Invoke-Abschluss -Target $target -Value @{ verschieben = $true; archiv = $archiv; zip = $true }
    $moved = Join-Path $archiv 'Projekt Ä'

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewCondition -Label 'Quelle weg' -Condition (-not (Test-Path -LiteralPath $target))
    Confirm-SpawnNewValue -Label 'Inhalt' -Actual ([System.IO.File]::ReadAllText((Join-Path $moved 'Unter\Daten.csv'))) -Expected 'a;b'
    Confirm-SpawnNewCondition -Label 'ZIP im Archiv' -Condition (Test-Path -LiteralPath (Join-Path $archiv 'Projekt Ä.zip'))
    Confirm-SpawnNewCondition -Label 'gemeldet' -Condition (@($run.Result.Created | Where-Object { $_.Path -eq $moved }).Count -eq 1)
}

Add-SpawnNewTest 'Verschieben ohne Archivverzeichnis aendert nichts' {
    $target = Initialize-TestProjekt
    $run = Invoke-Abschluss -Target $target -Value @{ verschieben = $true }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'failed'
    Confirm-SpawnNewCondition -Label 'kein Vermerk' -Condition (-not (Test-Path -LiteralPath (Join-Path $target 'ABSCHLUSS.md')))
}

Add-SpawnNewTest 'Archiv im Projektordner und vorhandenes Ziel werden abgewiesen' {
    $target = Initialize-TestProjekt
    $run = Invoke-Abschluss -Target $target -Value @{ verschieben = $true; archiv = (Join-Path $target 'Archiv') }
    Confirm-SpawnNewMatch -Label 'innen' -Actual $run.Result.Error.Reason -Pattern 'nicht im abzuschließenden Ordner'

    $archiv = Join-Path (Get-SpawnNewTestDirectory) 'Archiv'
    [void](New-Item -ItemType Directory -Path (Join-Path $archiv 'Projekt Ä') -Force)
    $run = Invoke-Abschluss -Target $target -Value @{ verschieben = $true; archiv = $archiv }
    Confirm-SpawnNewMatch -Label 'vorhanden' -Actual $run.Result.Error.Reason -Pattern 'bereits'
    Confirm-SpawnNewCondition -Label 'nichts geaendert' -Condition (-not (Test-Path -LiteralPath (Join-Path $target 'ABSCHLUSS.md')))
}
