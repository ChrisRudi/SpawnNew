# tests/SpawnNew.CatalogCli.Tests.ps1
# Version 1.0 | Prueft src/Host/SpawnNew.Catalog.ps1.
# Zweck  : Die JSON-Ausgabe fuer die Explorer-Erweiterung. Deckt Abnahme 2,
#          13 und den Grundsatz, dass das Menue keine Aktion ausfuehrt.

function Get-CatalogScriptPath {
    return (Join-Path (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Host') 'SpawnNew.Catalog.ps1')
}

function Get-TestCatalog {
    param([Parameter(Mandatory)]$Work, [Parameter(Mandatory)][string]$Json)

    $app   = Join-Path $Work 'app'
    $layer = Add-SpawnNewTestFile -Path (Join-Path $app 'default.json') -Content $Json
    $out   = Join-Path $Work 'katalog.json'

    & (Get-CatalogScriptPath) -OutputFile $out -AppDirectory $app -LayerPath @($layer)

    return (ConvertFrom-Json ([System.IO.File]::ReadAllText($out)))
}

Add-SpawnNewTest 'Katalog nennt Aktionen mit Menuedaten' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'q/Git') -Json @'
{ "schemaVersion": 1, "id": "spawnnew.gitproject", "title": "Git-Projekt",
  "category": "Entwicklung", "icon": "git.ico", "requiresAdmin": true }
'@)
    $catalog = Get-TestCatalog -Work $Work -Json ('{ "schemaVersion": 1, "sources": [ { "name": "Q", "path": "' + (ConvertTo-SpawnNewJsonText $Work) + '/q", "order": 100 } ] }')
    $action  = $catalog.actions[0]

    Confirm-SpawnNewValue -Label 'schemaVersion' -Actual $catalog.schemaVersion -Expected 1
    Confirm-SpawnNewValue -Label 'Anzahl' -Actual @($catalog.actions).Count -Expected 1
    Confirm-SpawnNewValue -Label 'ID' -Actual $action.id -Expected 'spawnnew.gitproject'
    Confirm-SpawnNewValue -Label 'Titel' -Actual $action.title -Expected 'Git-Projekt'
    Confirm-SpawnNewValue -Label 'Kategorie' -Actual $action.category -Expected 'Entwicklung'
    Confirm-SpawnNewValue -Label 'Symbol' -Actual $action.icon -Expected 'git.ico'
    Confirm-SpawnNewValue -Label 'Rechte' -Actual $action.requiresAdmin -Expected $true
    Confirm-SpawnNewValue -Label 'Quelle' -Actual $action.sourceName -Expected 'Q'
    Confirm-SpawnNewValue -Label 'veraltet' -Actual $action.stale -Expected $false
}

Add-SpawnNewTest 'Neue Aktion erscheint ohne Neubau im naechsten Katalog' {
    $Work = Get-SpawnNewTestDirectory
    $layerJson = '{ "schemaVersion": 1, "sources": [ { "name": "Q", "path": "' + (ConvertTo-SpawnNewJsonText $Work) + '/q", "order": 100 } ] }'
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'q/Eins') -Json '{ "schemaVersion": 1, "id": "spawnnew.eins" }')

    Confirm-SpawnNewValue -Label 'vorher' -Actual @((Get-TestCatalog -Work $Work -Json $layerJson).actions).Count -Expected 1

    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'q/Zwei') -Json '{ "schemaVersion": 1, "id": "spawnnew.zwei" }')

    Confirm-SpawnNewValue -Label 'nachher' -Actual @((Get-TestCatalog -Work $Work -Json $layerJson).actions).Count -Expected 2
}

Add-SpawnNewTest 'Einzeiler fuer Installation und Aktualisierung stehen im Katalog' {
    $Work = Get-SpawnNewTestDirectory
    $catalog = Get-TestCatalog -Work $Work -Json @'
{ "schemaVersion": 1, "sources": [],
  "install": { "command": "x %SPAWNNEW_APP%\\Install.ps1", "requiresAdmin": true },
  "update":  { "command": "y" } }
'@
    $commands = @($catalog.commands)

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $commands.Count -Expected 2
    Confirm-SpawnNewValue -Label 'Installations-ID' -Actual $commands[0].id -Expected 'spawnnew.install'
    Confirm-SpawnNewValue -Label 'Titel' -Actual $commands[0].title -Expected 'SpawnNew installieren'
    Confirm-SpawnNewMatch -Label 'Befehl aufgeloest' -Actual $commands[0].command -Pattern 'Install\.ps1'
    Confirm-SpawnNewValue -Label 'Rechte' -Actual $commands[0].requiresAdmin -Expected $true
    Confirm-SpawnNewValue -Label 'Aktualisierung' -Actual $commands[1].id -Expected 'spawnnew.update'
}

Add-SpawnNewTest 'Fehlerhafte Quelle erscheint als Diagnose, der Katalog bleibt nutzbar' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'q/Heil') -Json '{ "schemaVersion": 1, "id": "spawnnew.heil" }')
    $catalog = Get-TestCatalog -Work $Work -Json (
        '{ "schemaVersion": 1, "sources": [ ' +
        '{ "name": "Weg", "path": "' + (ConvertTo-SpawnNewJsonText $Work) + '/weg", "order": 100 },' +
        '{ "name": "Q",   "path": "' + (ConvertTo-SpawnNewJsonText $Work) + '/q",   "order": 900 } ] }')

    Confirm-SpawnNewValue -Label 'Aktionen' -Actual @($catalog.actions).Count -Expected 1
    Confirm-SpawnNewMatch -Label 'Diagnose' -Actual @($catalog.diagnostics)[0].message -Pattern 'nicht erreichbar'
}

Add-SpawnNewTest 'Das Erzeugen des Katalogs fuehrt kein Aktionsskript aus' {
    $Work = Get-SpawnNewTestDirectory
    $spur = Join-Path $Work 'spur.txt'
    $directory = Join-Path $Work 'q/Boese'
    [void](Add-SpawnNewTestFile -Path (Join-Path $directory 'action.json') -Content '{ "schemaVersion": 1, "id": "spawnnew.boese" }')
    [void](Add-SpawnNewTestFile -Path (Join-Path $directory 'Invoke-SpawnAction.ps1') -Content ("param([string]`$ContextFile)`r`nSet-Content -LiteralPath '" + $spur + "' -Value 'gelaufen'`r`n"))

    $catalog = Get-TestCatalog -Work $Work -Json ('{ "schemaVersion": 1, "sources": [ { "name": "Q", "path": "' + (ConvertTo-SpawnNewJsonText $Work) + '/q", "order": 100 } ] }')

    Confirm-SpawnNewValue -Label 'Aktion gefunden' -Actual @($catalog.actions).Count -Expected 1
    Confirm-SpawnNewValue -Label 'Skript nicht gelaufen' -Actual (Test-Path -LiteralPath $spur) -Expected $false
}

Add-SpawnNewTest 'Katalogdatei ist UTF-8 ohne BOM' {
    $Work = Get-SpawnNewTestDirectory
    [void](Get-TestCatalog -Work $Work -Json '{ "schemaVersion": 1, "sources": [] }')
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $Work 'katalog.json'))

    Confirm-SpawnNewCondition -Label 'kein BOM' -Condition (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))
}
