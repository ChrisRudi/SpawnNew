# tests/SpawnNew.Catalog.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Catalog.psm1.
# Zweck  : Aktionserkennung, Aktions-IDs und Beschreibungspruefung nach
#          docs/Dateiliste.md Abschnitt 8 und 10.

Import-SpawnNewHostModule -Name 'Config', 'Catalog'

function Get-TestSource {
    param([Parameter(Mandatory)][string]$Path)

    return [pscustomobject]@{
        Name  = 'Test'
        Path  = $Path
        Key   = (Get-SpawnNewPathKey -Path $Path)
        Scope = 'personal'
    }
}

function Get-TestScan {
    param([Parameter(Mandatory)][string]$Path, [int]$MaxDepth = 3)

    $diagnostics = New-Object System.Collections.ArrayList
    $scan = Get-SpawnNewSourceScan -Source (Get-TestSource -Path $Path) -MaxDepth $MaxDepth -Diagnostics $diagnostics

    return [pscustomobject]@{
        Reachable   = $scan.Reachable
        Actions     = @($scan.Actions)
        Diagnostics = $diagnostics
    }
}

Add-SpawnNewTest 'Einzelskript in der Quellenwurzel wird Aktion mit automatischer ID' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestFile -Path (Join-Path $Work 'Mein Werkzeug.ps1') -Content 'param()')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Titel' -Actual $scan.Actions[0].Title -Expected 'Mein Werkzeug'
    Confirm-SpawnNewValue -Label 'Art der ID' -Actual $scan.Actions[0].IdKind -Expected 'auto'
    Confirm-SpawnNewMatch -Label 'ID' -Actual $scan.Actions[0].Id -Pattern '^auto:[0-9a-f]{16}$'
}

Add-SpawnNewTest 'Aktionsordner mit Beschreibung liefert die deklarierten Angaben' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'GitProjekt') -Json @'
{ "schemaVersion": 1, "id": "spawnnew.gitproject", "title": "Git-Projekt",
  "category": "Entwicklung", "requiresAdmin": true, "supportsCancel": true,
  "allowsOverwrite": true, "defaultTarget": "D:\\Projekte", "targetKind": "inPlace",
  "fields": [ { "name": "name" } ], "plannedSteps": [ "Ordner", "Repository" ] }
'@)
    $scan = Get-TestScan -Path $Work
    $action = $scan.Actions[0]

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'ID' -Actual $action.Id -Expected 'spawnnew.gitproject'
    Confirm-SpawnNewValue -Label 'Art der ID' -Actual $action.IdKind -Expected 'explicit'
    Confirm-SpawnNewValue -Label 'Titel' -Actual $action.Title -Expected 'Git-Projekt'
    Confirm-SpawnNewValue -Label 'Kategorie' -Actual $action.Category -Expected 'Entwicklung'
    Confirm-SpawnNewValue -Label 'Rechte' -Actual $action.RequiresAdmin -Expected $true
    Confirm-SpawnNewValue -Label 'Abbruch' -Actual $action.SupportsCancel -Expected $true
    Confirm-SpawnNewValue -Label 'Ueberschreiben' -Actual $action.AllowsOverwrite -Expected $true
    Confirm-SpawnNewValue -Label 'Standardziel' -Actual $action.DefaultTarget -Expected 'D:\Projekte'
    Confirm-SpawnNewValue -Label 'Zielart' -Actual $action.TargetKind -Expected 'inPlace'
    Confirm-SpawnNewValue -Label 'Felder' -Actual $action.Fields.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Schritte' -Actual $action.PlannedSteps.Count -Expected 2
}

Add-SpawnNewTest 'Zielart hat im Katalogeintrag die Vorgabe folder' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Ohne') -Json '{ "schemaVersion": 1, "id": "spawnnew.ohne" }')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Zielart' -Actual $scan.Actions[0].TargetKind -Expected 'folder'
}

Add-SpawnNewTest 'Aktionsordner ohne Beschreibung nutzt Ordnername und automatische ID' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Werkstattprotokoll'))
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Titel' -Actual $scan.Actions[0].Title -Expected 'Werkstattprotokoll'
    Confirm-SpawnNewValue -Label 'Art der ID' -Actual $scan.Actions[0].IdKind -Expected 'auto'
}

Add-SpawnNewTest 'Hilfsskript in einem Aktionsordner wird keine eigene Aktion' {
    $Work = Get-SpawnNewTestDirectory
    $directory = Add-SpawnNewTestAction -Directory (Join-Path $Work 'Sitzung') -Json '{ "schemaVersion": 1, "id": "spawnnew.meeting" }'
    [void](Add-SpawnNewTestFile -Path (Join-Path $directory 'Write-Agenda.ps1') -Content 'param()')
    [void](Add-SpawnNewTestFile -Path (Join-Path $directory 'Vorlagen/Protokoll.ps1') -Content 'param()')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'ID' -Actual $scan.Actions[0].Id -Expected 'spawnnew.meeting'
}

Add-SpawnNewTest 'Aktionsordner in einer Unterebene wird gefunden' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Buero/Sitzung') -Json '{ "schemaVersion": 1, "id": "spawnnew.meeting" }')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'ID' -Actual $scan.Actions[0].Id -Expected 'spawnnew.meeting'
}

Add-SpawnNewTest 'Abtasttiefe begrenzt die Suche' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'A/B/C/Tief') -Json '{ "schemaVersion": 1, "id": "spawnnew.tief" }')

    Confirm-SpawnNewValue -Label 'Tiefe 1' -Actual (Get-TestScan -Path $Work -MaxDepth 1).Actions.Count -Expected 0
    Confirm-SpawnNewValue -Label 'Tiefe 4' -Actual (Get-TestScan -Path $Work -MaxDepth 4).Actions.Count -Expected 1
}

Add-SpawnNewTest 'Ungueltige Beschreibung liefert Diagnose und keine Aktion' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Kaputt') -Json '{ "schemaVersion": 1,')
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Heil') -Json '{ "schemaVersion": 1, "id": "spawnnew.heil" }')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Gewinner' -Actual $scan.Actions[0].Id -Expected 'spawnnew.heil'
    Confirm-SpawnNewValue -Label 'Diagnosen' -Actual $scan.Diagnostics.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Stufe' -Actual $scan.Diagnostics[0].Severity -Expected 'error'
}

Add-SpawnNewTest 'Aktions-ID ausserhalb des Musters wird abgewiesen' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Falsch') -Json '{ "schemaVersion": 1, "id": "a!b" }')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 0
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $scan.Diagnostics[0].Message -Pattern 'Muster'
}

Add-SpawnNewTest 'Nicht unterstuetzte schemaVersion wird abgewiesen' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Alt') -Json '{ "schemaVersion": 2, "id": "spawnnew.alt" }')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 0
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $scan.Diagnostics[0].Message -Pattern 'schemaVersion 2'
}

Add-SpawnNewTest 'Fehlendes Einstiegsskript wird abgewiesen' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Leer') -Json '{ "schemaVersion": 1, "id": "spawnnew.leer" }' -NoEntryPoint)
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 0
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $scan.Diagnostics[0].Message -Pattern 'fehlt'
}

Add-SpawnNewTest 'Einstiegsskript ausserhalb des Aktionsordners wird abgewiesen' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestFile -Path (Join-Path $Work 'Fremd.ps1') -Content 'param()')
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Ausbruch') -Json '{ "schemaVersion": 1, "id": "spawnnew.ausbruch", "entryPoint": "../Fremd.ps1" }')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'nur das Einzelskript' -Actual $scan.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Titel' -Actual $scan.Actions[0].Title -Expected 'Fremd'
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $scan.Diagnostics[0].Message -Pattern 'außerhalb'
}

Add-SpawnNewTest 'Fehlendes Aufraeumskript warnt, die Aktion bleibt nutzbar' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'Mit') -Json '{ "schemaVersion": 1, "id": "spawnnew.mit", "cleanup": "Clear-Action.ps1" }')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Aufraeumen leer' -Actual $scan.Actions[0].Cleanup -Expected ''
    Confirm-SpawnNewValue -Label 'Stufe' -Actual $scan.Diagnostics[0].Severity -Expected 'warning'
}

Add-SpawnNewTest 'Vorhandenes Aufraeumskript wird zum vollen Pfad aufgeloest' {
    $Work = Get-SpawnNewTestDirectory
    $directory = Add-SpawnNewTestAction -Directory (Join-Path $Work 'Mit') -Json '{ "schemaVersion": 1, "id": "spawnnew.mit", "cleanup": "Clear-Action.ps1" }'
    [void](Add-SpawnNewTestFile -Path (Join-Path $directory 'Clear-Action.ps1') -Content 'param()')
    $scan = Get-TestScan -Path $Work

    Confirm-SpawnNewValue -Label 'Aufraeumen' -Actual $scan.Actions[0].Cleanup -Expected (Join-Path $directory 'Clear-Action.ps1')
    Confirm-SpawnNewValue -Label 'keine Warnung' -Actual $scan.Diagnostics.Count -Expected 0
}

Add-SpawnNewTest 'Nicht erreichbare Quelle meldet sich als solche' {
    $Work = Get-SpawnNewTestDirectory
    $scan = Get-TestScan -Path (Join-Path $Work 'gibtesnicht')

    Confirm-SpawnNewValue -Label 'Erreichbarkeit' -Actual $scan.Reachable -Expected $false
    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $scan.Actions.Count -Expected 0
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $scan.Diagnostics[0].Message -Pattern 'nicht erreichbar'
}

Add-SpawnNewTest 'Automatische ID ist deterministisch und unabhaengig von Schreibweise' {
    $a = Get-SpawnNewAutoActionId -SourcePath 'C:\Quelle'   -RelativePath 'Unter/Skript.ps1'
    $b = Get-SpawnNewAutoActionId -SourcePath 'c:\quelle\'  -RelativePath 'Unter/Skript.ps1'
    $c = Get-SpawnNewAutoActionId -SourcePath 'C:\Andere'   -RelativePath 'Unter/Skript.ps1'

    Confirm-SpawnNewValue -Label 'gleich' -Actual $b -Expected $a
    Confirm-SpawnNewCondition -Label 'andere Quelle anders' -Condition ($c -ne $a)
}

Add-SpawnNewTest 'Automatische ID kann keine explizite ID ersetzen' {
    $auto = Get-SpawnNewAutoActionId -SourcePath 'C:\Quelle' -RelativePath 'Skript.ps1'

    Confirm-SpawnNewValue -Label 'faellt unter Muster' -Actual (Test-SpawnNewExplicitActionId -Id $auto) -Expected $false
}

Add-SpawnNewTest 'Muster der expliziten Aktions-ID' {
    $cases = @(
        @{ Id = 'spawnnew.gitproject'; Ok = $true }
        @{ Id = 'a-b_c.1';             Ok = $true }
        @{ Id = 'ab';                  Ok = $false }
        @{ Id = 'a!b';                 Ok = $false }
        @{ Id = '.leading';            Ok = $false }
        @{ Id = 'auto:1234';           Ok = $false }
        @{ Id = '';                    Ok = $false }
    )

    foreach ($entry in $cases) {
        Confirm-SpawnNewValue -Label ("ID '" + $entry.Id + "'") -Actual (Test-SpawnNewExplicitActionId -Id $entry.Id) -Expected $entry.Ok
    }
}
