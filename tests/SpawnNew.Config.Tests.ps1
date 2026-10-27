# tests/SpawnNew.Config.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Config.psm1.
# Zweck  : Konfigurationsschichten, Quellenpriorietaet, Entdoppelung,
#          Pfadauflösung und Diagnosen nach docs/Dateiliste.md Abschnitt 7 bis 9.

Import-SpawnNewHostModule -Name 'Config'

function Get-ConfigFixture {
    param($Work, [string]$User, [string]$Machine, [string]$Default)

    $entries = @(
        @{ Name = 'user.json';    Json = $User }
        @{ Name = 'machine.json'; Json = $Machine }
        @{ Name = 'default.json'; Json = $Default }
    )

    $layers = @()
    foreach ($entry in $entries) {
        if ($null -eq $entry.Json) { continue }
        $layers += (Add-SpawnNewTestFile -Path (Join-Path $Work $entry.Name) -Content $entry.Json)
    }

    return (Get-SpawnNewConfig -AppDirectory $Work -LayerPath $layers)
}

Add-SpawnNewTest 'Einzelwert stammt aus der ersten Schicht, die ihn definiert' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -User    '{ "sourceTimeoutMs": 700 }' -Machine '{ "sourceTimeoutMs": 2000, "cacheMaxAgeMinutes": 60 }' -Default '{ "sourceTimeoutMs": 1500, "cacheMaxAgeMinutes": 1440, "scanDepth": 3 }'

    Confirm-SpawnNewValue -Label 'Zeitlimit aus Benutzerschicht' -Actual $config.SourceTimeoutMs -Expected 700
    Confirm-SpawnNewValue -Label 'Cachealter aus Maschinenschicht' -Actual $config.CacheMaxAgeMinutes -Expected 60
    Confirm-SpawnNewValue -Label 'Tiefe aus Standardschicht' -Actual $config.ScanDepth -Expected 3
}

Add-SpawnNewTest 'Fehlende Einzelwerte fallen auf die eingebauten Vorgaben zurueck' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default '{ "schemaVersion": 1 }'

    Confirm-SpawnNewValue -Label 'Zeitlimit' -Actual $config.SourceTimeoutMs -Expected 1500
    Confirm-SpawnNewValue -Label 'Cachealter' -Actual $config.CacheMaxAgeMinutes -Expected 1440
    Confirm-SpawnNewValue -Label 'Tiefe' -Actual $config.ScanDepth -Expected 3
}

Add-SpawnNewTest 'Quellen aller Schichten werden verbunden' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -User    '{ "sources": [ { "name": "A", "path": "C:\\A", "order": 10 } ] }' -Default '{ "sources": [ { "name": "B", "path": "C:\\B", "order": 20 } ] }'

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $config.Sources.Count -Expected 2
    Confirm-SpawnNewValue -Label 'erste'  -Actual $config.Sources[0].Name -Expected 'A'
    Confirm-SpawnNewValue -Label 'zweite' -Actual $config.Sources[1].Name -Expected 'B'
}

Add-SpawnNewTest 'Bei gleicher Ordnung kommt persoenlich vor gemeinsam' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default @'
{ "sources": [
  { "name": "Gemeinsam",   "path": "C:\\G", "scope": "shared",   "order": 100 },
  { "name": "Persoenlich", "path": "C:\\P", "scope": "personal", "order": 100 }
] }
'@

    Confirm-SpawnNewValue -Label 'erste Quelle' -Actual $config.Sources[0].Name -Expected 'Persoenlich'
    Confirm-SpawnNewValue -Label 'zweite Quelle' -Actual $config.Sources[1].Name -Expected 'Gemeinsam'
}

Add-SpawnNewTest 'Explizite Ordnung schlaegt die Ebene' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default @'
{ "sources": [
  { "name": "Persoenlich", "path": "C:\\P", "scope": "personal", "order": 900 },
  { "name": "Gemeinsam",   "path": "C:\\G", "scope": "shared",   "order": 100 }
] }
'@

    Confirm-SpawnNewValue -Label 'erste Quelle' -Actual $config.Sources[0].Name -Expected 'Gemeinsam'
}

Add-SpawnNewTest 'Derselbe Pfad wird unabhaengig von Schreibweise entdoppelt' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default @'
{ "sources": [
  { "name": "Erste",  "path": "C:\\Quelle",   "order": 10 },
  { "name": "Zweite", "path": "c:\\quelle\\", "order": 20 }
] }
'@

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $config.Sources.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Gewinner' -Actual $config.Sources[0].Name -Expected 'Erste'
    Confirm-SpawnNewValue -Label 'Diagnosen' -Actual $config.Diagnostics.Count -Expected 1
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $config.Diagnostics[0].Message -Pattern 'mehrfach konfiguriert'
}

Add-SpawnNewTest 'Quelle ohne Pfad wird mit Diagnose uebersprungen' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default '{ "sources": [ { "name": "Ohne" }, { "name": "Mit", "path": "C:\\M" } ] }'

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $config.Sources.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Gewinner' -Actual $config.Sources[0].Name -Expected 'Mit'
    Confirm-SpawnNewValue -Label 'Stufe' -Actual $config.Diagnostics[0].Severity -Expected 'error'
}

Add-SpawnNewTest 'Unbekannte Ebene wird zu shared mit Warnung' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default '{ "sources": [ { "name": "A", "path": "C:\\A", "scope": "wolke" } ] }'

    Confirm-SpawnNewValue -Label 'Ebene' -Actual $config.Sources[0].Scope -Expected 'shared'
    Confirm-SpawnNewValue -Label 'Stufe' -Actual $config.Diagnostics[0].Severity -Expected 'warning'
}

Add-SpawnNewTest 'Nicht ganzzahlige Ordnung wird zur Vorgabe mit Warnung' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default '{ "sources": [ { "name": "A", "path": "C:\\A", "order": "abc" } ] }'

    Confirm-SpawnNewValue -Label 'Ordnung' -Actual $config.Sources[0].Order -Expected 1000
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $config.Diagnostics[0].Message -Pattern 'keine Ganzzahl'
}

Add-SpawnNewTest 'Ungueltige JSON blockiert die uebrigen Schichten nicht' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -User    '{ "sources": [ { "name": "Kaputt",' -Default '{ "sources": [ { "name": "Heil", "path": "C:\\H" } ] }'

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $config.Sources.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Gewinner' -Actual $config.Sources[0].Name -Expected 'Heil'
    Confirm-SpawnNewValue -Label 'Stufe' -Actual $config.Diagnostics[0].Severity -Expected 'error'
}

Add-SpawnNewTest 'Fehlende Konfigurationsdatei erzeugt keine Diagnose' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-SpawnNewConfig -AppDirectory $Work -LayerPath @((Join-Path $Work 'gibtesnicht.json'))

    Confirm-SpawnNewValue -Label 'Diagnosen' -Actual $config.Diagnostics.Count -Expected 0
    Confirm-SpawnNewValue -Label 'Quellen' -Actual $config.Sources.Count -Expected 0
}

Add-SpawnNewTest 'SPAWNNEW_APP wird im Quellenpfad aufgeloest' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default '{ "sources": [ { "name": "A", "path": "%SPAWNNEW_APP%\\Actions" } ] }'

    Confirm-SpawnNewValue -Label 'Pfad' -Actual $config.Sources[0].Path -Expected ($Work + '\Actions')
}

Add-SpawnNewTest 'Einzeiler werden aufgeloest und mit Rechteangabe geliefert' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default @'
{ "install": { "command": "x \"%SPAWNNEW_APP%\\Install.ps1\"", "requiresAdmin": true },
  "update":  { "command": "y" } }
'@

    Confirm-SpawnNewValue -Label 'Installationsbefehl' -Actual $config.Install.Command -Expected ('x "' + $Work + '\Install.ps1"')
    Confirm-SpawnNewValue -Label 'Rechte' -Actual $config.Install.RequiresAdmin -Expected $true
    Confirm-SpawnNewValue -Label 'Aktualisierung' -Actual $config.Update.Command -Expected 'y'
    Confirm-SpawnNewValue -Label 'Rechte Vorgabe' -Actual $config.Update.RequiresAdmin -Expected $false
}

Add-SpawnNewTest 'Einzeiler ohne Befehl bleibt leer' {
    $Work = Get-SpawnNewTestDirectory
    $config = Get-ConfigFixture -Work $Work -Default '{ "install": { "requiresAdmin": true } }'

    Confirm-SpawnNewValue -Label 'Installationsbefehl' -Actual $config.Install -Expected $null
}

Add-SpawnNewTest 'Ohne Markierung liegt das Datenverzeichnis lokal' {
    $app = Join-Path (Get-SpawnNewTestDirectory) 'App'
    [void](New-Item -ItemType Directory -Path $app -Force)

    Confirm-SpawnNewValue -Label 'Daten' -Actual (Get-SpawnNewDataDirectory -AppDirectory $app) -Expected (Join-Path $env:LOCALAPPDATA 'SpawnNew')
    Confirm-SpawnNewValue -Label 'portabel' -Actual (Test-SpawnNewPortable -AppDirectory $app) -Expected $false
}

Add-SpawnNewTest 'Markierung im Cloudordner zeigt relativ auf das Datenverzeichnis' {
    $cloud = Join-Path (Get-SpawnNewTestDirectory) 'OneDrive - Schule\SpawnNew'
    $app = Join-Path $cloud 'App'
    [void](Add-SpawnNewTestFile -Path (Join-Path $app 'spawnnew.portable.json') -Content '{ "schemaVersion": 1, "dataDirectory": ".." }')

    Confirm-SpawnNewValue -Label 'Daten' -Actual (Get-SpawnNewDataDirectory -AppDirectory $app) -Expected $cloud
    Confirm-SpawnNewValue -Label 'portabel' -Actual (Test-SpawnNewPortable -AppDirectory $app) -Expected $true
    Confirm-SpawnNewValue -Label 'Platzhalter' -Actual (Expand-SpawnNewPath -Path '%SPAWNNEW_DATA%\Actions' -AppDirectory $app) -Expected (Join-Path $cloud 'Actions')
    Confirm-SpawnNewValue -Label 'Benutzerschicht' -Actual (Get-SpawnNewConfigLayerPath -AppDirectory $app)[0] -Expected (Join-Path $cloud 'spawnnew.settings.json')
    Confirm-SpawnNewValue -Label 'lokal bleibt lokal' -Actual (Get-SpawnNewLocalDirectory) -Expected (Join-Path $env:LOCALAPPDATA 'SpawnNew')
}

Add-SpawnNewTest 'Mitgelieferte Konfiguration legt persoenliche Aktionen ins Datenverzeichnis' {
    $cloud = Join-Path (Get-SpawnNewTestDirectory) 'Cloud'
    $app = Join-Path $cloud 'App'
    [void](Add-SpawnNewTestFile -Path (Join-Path $app 'spawnnew.portable.json') -Content '{ "dataDirectory": ".." }')
    Copy-Item -LiteralPath (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'config') 'spawnnew.settings.default.json') -Destination $app

    $config = Get-SpawnNewConfig -AppDirectory $app
    $personal = @($config.Sources | Where-Object { $_.Scope -eq 'personal' })[0]
    Confirm-SpawnNewValue -Label 'persoenlich' -Actual $personal.Path -Expected (Join-Path $cloud 'Actions')
}

Add-SpawnNewTest 'Unlesbare Markierung faellt auf das lokale Verzeichnis zurueck' {
    $app = Join-Path (Get-SpawnNewTestDirectory) 'App'
    [void](Add-SpawnNewTestFile -Path (Join-Path $app 'spawnnew.portable.json') -Content 'kaputt')
    Confirm-SpawnNewValue -Label 'Daten' -Actual (Get-SpawnNewDataDirectory -AppDirectory $app) -Expected (Join-Path $env:LOCALAPPDATA 'SpawnNew')
}
