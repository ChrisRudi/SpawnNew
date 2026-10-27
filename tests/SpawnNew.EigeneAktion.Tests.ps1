# tests/SpawnNew.EigeneAktion.Tests.ps1
# Version 1.0 | Prueft Aktion 14 gegen den Ausfuehrungsvertrag.
# Zweck  : Das erzeugte Grundgeruest muss vom Katalog als Aktion mit
#          expliziter ID erkannt werden und selbst nach dem Vertrag laufen.

Import-SpawnNewHostModule -Name 'Config', 'Catalog', 'Runner'

function Invoke-Eigene {
    param([hashtable]$Value)
    $target = Join-Path (Join-Path (Get-SpawnNewTestDirectory) 'Actions') $Value['name']
    return (Invoke-SpawnNewTestAction -Folder 'EigeneAktion' -Id 'spawnnew.customaction' -Value $Value -TargetPath $target)
}

Add-SpawnNewTest 'Grundgeruest wird als Aktion mit expliziter ID erkannt' {
    $run = Invoke-Eigene -Value @{ name = 'Meine Notiz'; id = 'eigen.notiz'; beschreibung = 'Legt eine Notiz an.' }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'

    $source = [pscustomobject]@{ Name = 'P'; Path = (Split-Path -Parent $run.Target); Scope = 'personal' }
    $diagnostics = New-Object System.Collections.ArrayList
    $action = Read-SpawnNewActionFolder -Directory $run.Target -RelativePath 'Meine Notiz' -Source $source -Diagnostics $diagnostics

    Confirm-SpawnNewValue -Label 'Diagnosen' -Actual $diagnostics.Count -Expected 0
    Confirm-SpawnNewValue -Label 'ID' -Actual $action.Id -Expected 'eigen.notiz'
    Confirm-SpawnNewValue -Label 'ID-Art' -Actual $action.IdKind -Expected 'explicit'
    Confirm-SpawnNewValue -Label 'Titel' -Actual $action.Title -Expected 'Meine Notiz'
}

Add-SpawnNewTest 'Das erzeugte Skript laeuft nach dem Vertrag' {
    $first = Invoke-Eigene -Value @{ name = 'Probe'; id = 'eigen.probe'; beschreibung = '' }
    $target = Join-Path (Get-SpawnNewTestDirectory) 'Ergebnis'
    $run = Invoke-SpawnNewTestAction -Folder 'Probe' -ActionDirectory $first.Target -Id 'eigen.probe' -Value @{ name = 'Ergebnis' } -TargetPath $target

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 0
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewMatch -Label 'Notiz' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'Notiz.md'))) -Pattern '# Ergebnis'
}

Add-SpawnNewTest 'Anfuehrungszeichen im Namen ergeben gueltige JSON' {
    $run = Invoke-Eigene -Value @{ name = 'Sag ''Hallo'' & mehr'; id = 'eigen.hallo'; beschreibung = 'Mit "Zitat" und \ Strich' }
    $description = ConvertFrom-Json ([System.IO.File]::ReadAllText((Join-Path $run.Target 'action.json')))

    Confirm-SpawnNewValue -Label 'Titel' -Actual $description.title -Expected 'Sag ''Hallo'' & mehr'
    Confirm-SpawnNewMatch -Label 'README' -Actual ([System.IO.File]::ReadAllText((Join-Path $run.Target 'README.md'))) -Pattern 'Mit "Zitat"'
}

Add-SpawnNewTest 'Standardziel ist das persoenliche Aktionsverzeichnis' {
    $description = ConvertFrom-Json ([System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Actions') 'EigeneAktion') 'action.json')))
    Confirm-SpawnNewValue -Label 'Ziel' -Actual $description.defaultTarget -Expected '%LOCALAPPDATA%\SpawnNew\Actions'
}
