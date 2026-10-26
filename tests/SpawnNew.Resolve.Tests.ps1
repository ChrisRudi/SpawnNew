# tests/SpawnNew.Resolve.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Resolve.psm1.
# Zweck  : Quellenprioritaet, Zeitlimit, Metadaten-Cache und die
#          Nachpruefung vor der Ausfuehrung. Deckt Abnahme 4, 10, 14 und 16.

Import-SpawnNewHostModule -Name 'Config', 'Catalog', 'Resolve'

function Get-ResolveFixture {
    param([Parameter(Mandatory)]$Work, [Parameter(Mandatory)][string]$Sources)

    $app  = Join-Path $Work 'app'
    $json = '{ "schemaVersion": 1, "sourceTimeoutMs": 20000, "scanDepth": 3, "sources": [ ' + $Sources + ' ] }'
    $file = Add-SpawnNewTestFile -Path (Join-Path $app 'default.json') -Content $json

    return (Get-SpawnNewConfig -AppDirectory $app -LayerPath @($file))
}

function Get-TestAction {
    param([Parameter(Mandatory)]$Catalog, [Parameter(Mandatory)][string]$Id)

    return ($Catalog.Actions | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

Add-SpawnNewTest 'Persoenliche Quelle verdeckt die gemeinsame bei gleicher expliziter ID' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject", "title": "Persoenlich" }')
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 's/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject", "title": "Gemeinsam" }')

    $config = Get-ResolveFixture -Work $Work -Sources (
        '{ "name": "P", "path": "' + ($Work -replace '\\', '\\') + '/p", "scope": "personal", "order": 100 },' +
        '{ "name": "S", "path": "' + ($Work -replace '\\', '\\') + '/s", "scope": "shared",   "order": 900 }')
    $catalog = Get-SpawnNewCatalog -Config $config

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $catalog.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Gewinner' -Actual $catalog.Actions[0].Title -Expected 'Persoenlich'

    $verdeckt = @($catalog.Diagnostics | Where-Object { $_.Message -match 'verdeckt' })
    Confirm-SpawnNewValue -Label 'Diagnose' -Actual $verdeckt.Count -Expected 1
}

Add-SpawnNewTest 'Verschiedene IDs mit gleichem Titel bleiben getrennte Aktionen' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Eins') -Json '{ "schemaVersion": 1, "id": "spawnnew.eins", "title": "Sitzung" }')
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Zwei') -Json '{ "schemaVersion": 1, "id": "spawnnew.zwei", "title": "Sitzung" }')

    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $catalog.Actions.Count -Expected 2
}

Add-SpawnNewTest 'Erreichbare Quelle schreibt den Metadaten-Cache' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject" }')
    $config = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    [void](Get-SpawnNewCatalog -Config $config)

    $cache = Get-SpawnNewCacheFilePath -Source $config.Sources[0]
    Confirm-SpawnNewCondition -Label 'Cachedatei da' -Condition (Test-Path -LiteralPath $cache -PathType Leaf)
}

Add-SpawnNewTest 'Nicht erreichbare Quelle liefert die Aktionen aus dem Cache als veraltet' {
    $Work = Get-SpawnNewTestDirectory
    $source = Join-Path $Work 'p'
    [void](Add-SpawnNewTestAction -Directory (Join-Path $source 'Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject", "title": "Aus dem Cache" }')
    $config = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $source + '", "order": 100 }')

    [void](Get-SpawnNewCatalog -Config $config)
    Remove-Item -LiteralPath $source -Recurse -Force

    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $source + '", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $catalog.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Titel' -Actual $catalog.Actions[0].Title -Expected 'Aus dem Cache'
    Confirm-SpawnNewValue -Label 'veraltet' -Actual $catalog.Actions[0].Stale -Expected $true
}

Add-SpawnNewTest 'Zeitlimit greift und faellt auf den Cache zurueck' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject", "title": "Vom Datentraeger" }')
    $config = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    [void](Get-SpawnNewCatalog -Config $config)

    $config.SourceTimeoutMs = 1
    $catalog = Get-SpawnNewCatalog -Config $config

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $catalog.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'veraltet' -Actual $catalog.Actions[0].Stale -Expected $true

    $limit = @($catalog.Diagnostics | Where-Object { $_.Message -match 'Zeitlimit' })
    Confirm-SpawnNewValue -Label 'Diagnose' -Actual $limit.Count -Expected 1
}

Add-SpawnNewTest 'Zu alter Cache wird verworfen' {
    $Work = Get-SpawnNewTestDirectory
    $source = Join-Path $Work 'p'
    [void](Add-SpawnNewTestAction -Directory (Join-Path $source 'Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject" }')
    $config = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $source + '", "order": 100 }')
    [void](Get-SpawnNewCatalog -Config $config)

    $cache   = Get-SpawnNewCacheFilePath -Source $config.Sources[0]
    $payload = ConvertFrom-Json ([System.IO.File]::ReadAllText($cache))
    $payload.savedUtc = [System.DateTime]::UtcNow.AddDays(-10).ToString('o')
    [void](Add-SpawnNewTestFile -Path $cache -Content (ConvertTo-Json -InputObject $payload -Depth 8))

    Remove-Item -LiteralPath $source -Recurse -Force
    $config.CacheMaxAgeMinutes = 60
    $catalog = Get-SpawnNewCatalog -Config $config

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $catalog.Actions.Count -Expected 0

    $alt = @($catalog.Diagnostics | Where-Object { $_.Message -match 'Minuten alt' })
    Confirm-SpawnNewValue -Label 'Diagnose' -Actual $alt.Count -Expected 1
}

Add-SpawnNewTest 'Cache mit fremder Version wird verworfen' {
    $Work = Get-SpawnNewTestDirectory
    $source = Join-Path $Work 'p'
    $config = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $source + '", "order": 100 }')
    $cache  = Get-SpawnNewCacheFilePath -Source $config.Sources[0]
    [void](Add-SpawnNewTestFile -Path $cache -Content '{ "schemaVersion": 99, "savedUtc": "2099-01-01T00:00:00.0000000Z", "actions": [] }')

    $catalog = Get-SpawnNewCatalog -Config $config

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $catalog.Actions.Count -Expected 0

    $version = @($catalog.Diagnostics | Where-Object { $_.Message -match 'Version 99' })
    Confirm-SpawnNewValue -Label 'Diagnose' -Actual $version.Count -Expected 1
}

Add-SpawnNewTest 'Nicht erreichbare Quelle ohne Cache liefert einfach nichts' {
    $Work = Get-SpawnNewTestDirectory
    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/gibtesnicht", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $catalog.Actions.Count -Expected 0
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $catalog.Diagnostics[0].Message -Pattern 'nicht erreichbar'
}

Add-SpawnNewTest 'Eine fehlerhafte Quelle blockiert die anderen nicht' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 's/Heil') -Json '{ "schemaVersion": 1, "id": "spawnnew.heil" }')
    $config = Get-ResolveFixture -Work $Work -Sources (
        '{ "name": "Weg", "path": "' + $Work + '/weg", "order": 100 },' +
        '{ "name": "S",   "path": "' + $Work + '/s",   "order": 900 }')
    $catalog = Get-SpawnNewCatalog -Config $config

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $catalog.Actions.Count -Expected 1
    Confirm-SpawnNewValue -Label 'ID' -Actual $catalog.Actions[0].Id -Expected 'spawnnew.heil'
}

Add-SpawnNewTest 'Unveraenderte Aktion besteht die Nachpruefung' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject" }')
    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config

    $result = Test-SpawnNewAction -Action (Get-TestAction -Catalog $catalog -Id 'spawnnew.gitproject')

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $result.Valid -Expected $true
    Confirm-SpawnNewValue -Label 'frische ID' -Actual $result.Action.Id -Expected 'spawnnew.gitproject'
}

Add-SpawnNewTest 'Aktion aus dem Cache wird nicht gestartet' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject" }')
    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config
    $action  = Get-TestAction -Catalog $catalog -Id 'spawnnew.gitproject'
    $action.Stale = $true

    $result = Test-SpawnNewAction -Action $action

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $result.Valid -Expected $false
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $result.Message -Pattern 'Zwischenspeicher'
}

Add-SpawnNewTest 'Geaenderte Aktions-ID verhindert den Start' {
    $Work = Get-SpawnNewTestDirectory
    $directory = Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject" }'
    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config
    $action  = Get-TestAction -Catalog $catalog -Id 'spawnnew.gitproject'

    [void](Add-SpawnNewTestFile -Path (Join-Path $directory 'action.json') -Content '{ "schemaVersion": 1, "id": "spawnnew.anders" }')
    $result = Test-SpawnNewAction -Action $action

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $result.Valid -Expected $false
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $result.Message -Pattern 'Aktions-ID'
}

Add-SpawnNewTest 'Entferntes Einstiegsskript verhindert den Start' {
    $Work = Get-SpawnNewTestDirectory
    $directory = Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject" }'
    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config
    $action  = Get-TestAction -Catalog $catalog -Id 'spawnnew.gitproject'

    Remove-Item -LiteralPath (Join-Path $directory 'Invoke-SpawnAction.ps1') -Force
    $result = Test-SpawnNewAction -Action $action

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $result.Valid -Expected $false
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $result.Message -Pattern 'fehlt'
}

Add-SpawnNewTest 'Verschwundene Quelle verhindert den Start' {
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestAction -Directory (Join-Path $Work 'p/Git') -Json '{ "schemaVersion": 1, "id": "spawnnew.gitproject" }')
    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config
    $action  = Get-TestAction -Catalog $catalog -Id 'spawnnew.gitproject'

    Remove-Item -LiteralPath (Join-Path $Work 'p') -Recurse -Force
    $result = Test-SpawnNewAction -Action $action

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $result.Valid -Expected $false
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $result.Message -Pattern 'nicht erreichbar'
}

Add-SpawnNewTest 'Einzelskript wird vor dem Start auf Vorhandensein geprueft' {
    $Work = Get-SpawnNewTestDirectory
    $script = Add-SpawnNewTestFile -Path (Join-Path $Work 'p/Werkzeug.ps1') -Content 'param()'
    $config  = Get-ResolveFixture -Work $Work -Sources ('{ "name": "P", "path": "' + $Work + '/p", "order": 100 }')
    $catalog = Get-SpawnNewCatalog -Config $config
    $action  = $catalog.Actions[0]

    Confirm-SpawnNewValue -Label 'vorher gueltig' -Actual (Test-SpawnNewAction -Action $action).Valid -Expected $true

    Remove-Item -LiteralPath $script -Force
    $result = Test-SpawnNewAction -Action $action

    Confirm-SpawnNewValue -Label 'nachher gueltig' -Actual $result.Valid -Expected $false
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $result.Message -Pattern 'nicht mehr vorhanden'
}
