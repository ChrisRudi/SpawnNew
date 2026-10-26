# tests/SpawnNew.Target.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Target.psm1.
# Zweck  : Namens- und Pfadpruefung, Zielart, Zielzustand, freier Name,
#          Voraussetzungen und Zusammenfassung. Deckt Abschnitt 7, Abnahme 5 und 6.

Import-SpawnNewHostModule -Name 'Config', 'Input', 'Target'

function Get-TestActionObject {
    param(
        [string]$Title = 'Git-Projekt',
        [string]$DefaultTarget = '',
        [string]$TargetKind = 'folder',
        [bool]$RequiresAdmin = $false,
        $PlannedSteps = @(),
        $Prerequisites = @(),
        [string]$ActionDirectory = 'C:\Quelle\Aktion'
    )

    return [pscustomobject]@{
        Title           = $Title
        SourceName      = 'Testquelle'
        DefaultTarget   = $DefaultTarget
        TargetKind      = $TargetKind
        RequiresAdmin   = $RequiresAdmin
        PlannedSteps    = @($PlannedSteps)
        Prerequisites   = @($Prerequisites)
        ActionDirectory = $ActionDirectory
        DescriptionPath = 'C:\Quelle\Aktion\action.json'
    }
}

Add-SpawnNewTest 'Zulaessiger Name mit Umlauten und Leerzeichen' {
    $check = Test-SpawnNewName -Name '  Werkstättenprotokoll 10b  '

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $check.Valid -Expected $true
    Confirm-SpawnNewValue -Label 'getrimmt' -Actual $check.Value -Expected 'Werkstättenprotokoll 10b'
}

Add-SpawnNewTest 'Verbotene Zeichen im Namen werden abgewiesen' {
    foreach ($name in @('a/b', 'a\b', 'a:b', 'a*b', 'a?b', 'a"b', 'a<b', 'a>b', 'a|b')) {
        Confirm-SpawnNewValue -Label "Name '$name'" -Actual (Test-SpawnNewName -Name $name).Valid -Expected $false
    }
}

Add-SpawnNewTest 'Name darf nicht mit Punkt oder Leerzeichen enden' {
    Confirm-SpawnNewValue -Label 'Punkt' -Actual (Test-SpawnNewName -Name 'Projekt.').Valid -Expected $false
}

Add-SpawnNewTest 'Von Windows belegte Namen werden abgewiesen' {
    foreach ($name in @('CON', 'con', 'NUL', 'com1', 'LPT9', 'con.txt')) {
        Confirm-SpawnNewValue -Label "Name '$name'" -Actual (Test-SpawnNewName -Name $name).Valid -Expected $false
    }
    Confirm-SpawnNewValue -Label "Name 'Console'" -Actual (Test-SpawnNewName -Name 'Console').Valid -Expected $true
}

Add-SpawnNewTest 'Leerer Name wird abgewiesen' {
    Confirm-SpawnNewValue -Label 'gueltig' -Actual (Test-SpawnNewName -Name '   ').Valid -Expected $false
}

Add-SpawnNewTest 'Laufwerkspfad wird angenommen und normalisiert' {
    Confirm-SpawnNewValue -Label 'Pfad' -Actual (Test-SpawnNewBasePath -Path '  D:\Projekte\  ').Value -Expected 'D:\Projekte'
    Confirm-SpawnNewValue -Label 'Wurzel' -Actual (Test-SpawnNewBasePath -Path 'C:').Value -Expected 'C:\'
    Confirm-SpawnNewValue -Label 'Wurzel getrimmt' -Actual (Test-SpawnNewBasePath -Path 'C:\\').Value -Expected 'C:\'
    Confirm-SpawnNewValue -Label 'Umlaut' -Actual (Test-SpawnNewBasePath -Path 'D:\Büro\Sitzungen').Valid -Expected $true
}

Add-SpawnNewTest 'UNC-Freigabe wird angenommen' {
    $check = Test-SpawnNewBasePath -Path '\\server\freigabe\Aktionen'

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $check.Valid -Expected $true
    Confirm-SpawnNewValue -Label 'Pfad' -Actual $check.Value -Expected '\\server\freigabe\Aktionen'
}

Add-SpawnNewTest 'Nicht verankerter Pfad wird abgewiesen' {
    foreach ($path in @('Projekte', '\Projekte', '\\server', '')) {
        Confirm-SpawnNewValue -Label "Pfad '$path'" -Actual (Test-SpawnNewBasePath -Path $path).Valid -Expected $false
    }
}

Add-SpawnNewTest 'Verbotene Zeichen im Pfad werden abgewiesen' {
    $check = Test-SpawnNewBasePath -Path 'D:\Pro?jekte'

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $check.Valid -Expected $false
    Confirm-SpawnNewMatch -Label 'Meldung' -Actual $check.Message -Pattern 'Zeichen'
}

Add-SpawnNewTest 'Ohne Aktionsstandard gilt der Explorer-Ordner' {
    $path = Get-SpawnNewBasePath -Action (Get-TestActionObject) -ExplorerPath 'D:\Hier' -AppDirectory 'C:\App'

    Confirm-SpawnNewValue -Label 'Pfad' -Actual $path -Expected 'D:\Hier'
}

Add-SpawnNewTest 'Aktionsstandard ersetzt den Explorer-Ordner und wird aufgeloest' {
    $action = Get-TestActionObject -DefaultTarget '%SPAWNNEW_APP%\Vorlagen'
    $path   = Get-SpawnNewBasePath -Action $action -ExplorerPath 'D:\Hier' -AppDirectory 'C:\App'

    Confirm-SpawnNewValue -Label 'Pfad' -Actual $path -Expected 'C:\App\Vorlagen'
}

Add-SpawnNewTest 'Zielart hat die Vorgabe folder' {
    $diagnostics = New-Object System.Collections.ArrayList

    Confirm-SpawnNewValue -Label 'Vorgabe' -Actual (Get-SpawnNewTargetKind -Action (Get-TestActionObject) -Diagnostics $diagnostics) -Expected 'folder'
    Confirm-SpawnNewValue -Label 'inPlace' -Actual (Get-SpawnNewTargetKind -Action (Get-TestActionObject -TargetKind 'inPlace') -Diagnostics $diagnostics) -Expected 'inPlace'
    Confirm-SpawnNewValue -Label 'keine Diagnose' -Actual $diagnostics.Count -Expected 0
}

Add-SpawnNewTest 'Unbekannte Zielart wird zu folder mit Warnung' {
    $diagnostics = New-Object System.Collections.ArrayList
    $kind = Get-SpawnNewTargetKind -Action (Get-TestActionObject -TargetKind 'wolke') -Diagnostics $diagnostics

    Confirm-SpawnNewValue -Label 'Zielart' -Actual $kind -Expected 'folder'
    Confirm-SpawnNewValue -Label 'Stufe' -Actual $diagnostics[0].Severity -Expected 'warning'
}

Add-SpawnNewTest 'Zielpfad wird aus Basis und Name gebildet' {
    $Work = Get-SpawnNewTestDirectory
    $folder  = Join-SpawnNewTargetPath -BasePath $Work -TargetKind 'folder'  -Name 'Neues Projekt'
    $inPlace = Join-SpawnNewTargetPath -BasePath $Work -TargetKind 'inPlace' -Name 'Neues Projekt'

    Confirm-SpawnNewValue -Label 'folder' -Actual $folder -Expected (Join-Path $Work 'Neues Projekt')
    Confirm-SpawnNewValue -Label 'inPlace' -Actual $inPlace -Expected $Work
}

Add-SpawnNewTest 'Zielzustand unterscheidet fehlend, leer, gefuellt und Datei' {
    $Work = Get-SpawnNewTestDirectory
    $leer     = Join-Path $Work 'leer'
    $gefuellt = Join-Path $Work 'gefuellt'
    [void](New-Item -ItemType Directory -Path $leer -Force)
    [void](Add-SpawnNewTestFile -Path (Join-Path $gefuellt 'a.txt') -Content 'x')
    $datei = Add-SpawnNewTestFile -Path (Join-Path $Work 'datei.txt') -Content 'x'

    $fehlt = Get-SpawnNewTargetState -Path (Join-Path $Work 'gibtesnicht')
    Confirm-SpawnNewValue -Label 'fehlt' -Actual $fehlt.Exists -Expected $false

    $state = Get-SpawnNewTargetState -Path $leer
    Confirm-SpawnNewValue -Label 'leer vorhanden' -Actual $state.Exists -Expected $true
    Confirm-SpawnNewValue -Label 'leer' -Actual $state.IsEmpty -Expected $true

    $state = Get-SpawnNewTargetState -Path $gefuellt
    Confirm-SpawnNewValue -Label 'gefuellt' -Actual $state.IsEmpty -Expected $false
    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $state.EntryCount -Expected 1

    $state = Get-SpawnNewTargetState -Path $datei
    Confirm-SpawnNewValue -Label 'Datei' -Actual $state.IsFile -Expected $true
    Confirm-SpawnNewValue -Label 'kein Ordner' -Actual $state.IsFolder -Expected $false
}

Add-SpawnNewTest 'Freier Name ueberspringt vorhandene Ordner' {
    $Work = Get-SpawnNewTestDirectory
    [void](New-Item -ItemType Directory -Path (Join-Path $Work 'Projekt') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $Work 'Projekt (2)') -Force)

    Confirm-SpawnNewValue -Label 'Vorschlag' -Actual (Get-SpawnNewFreeName -BasePath $Work -Name 'Projekt') -Expected 'Projekt (3)'
}

Add-SpawnNewTest 'Fehlendes Programm wird als Voraussetzung gemeldet' {
    $action = Get-TestActionObject -Prerequisites (ConvertFrom-Json '[ { "kind": "command", "name": "gibtesnicht.exe", "hint": "Bitte installieren." } ]')
    $missing = @(Get-SpawnNewMissingPrerequisite -Action $action)

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $missing.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Name' -Actual $missing[0].Name -Expected 'gibtesnicht.exe'
    Confirm-SpawnNewValue -Label 'Hinweis' -Actual $missing[0].Hint -Expected 'Bitte installieren.'
}

Add-SpawnNewTest 'Vorhandenes Programm wird nicht gemeldet' {
    $action = Get-TestActionObject -Prerequisites (ConvertFrom-Json '[ { "kind": "command", "name": "Get-ChildItem" } ]')

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual @(Get-SpawnNewMissingPrerequisite -Action $action).Count -Expected 0
}

Add-SpawnNewTest 'Fehlende Vorlagendatei wird gemeldet' {
    $Work = Get-SpawnNewTestDirectory
    $action = Get-TestActionObject -ActionDirectory $Work -Prerequisites (ConvertFrom-Json '[ { "kind": "file", "name": "Vorlage.docx" } ]')
    Confirm-SpawnNewValue -Label 'fehlt' -Actual @(Get-SpawnNewMissingPrerequisite -Action $action).Count -Expected 1

    [void](Add-SpawnNewTestFile -Path (Join-Path $Work 'Vorlage.docx') -Content 'x')
    Confirm-SpawnNewValue -Label 'vorhanden' -Actual @(Get-SpawnNewMissingPrerequisite -Action $action).Count -Expected 0
}

Add-SpawnNewTest 'Zusammenfassung nennt Ziel, Eingaben, Schritte und Konfliktregel' {
    $action = Get-TestActionObject -PlannedSteps @('Ordner anlegen', 'Repository initialisieren')
    $diagnostics = New-Object System.Collections.ArrayList
    $holder = [pscustomobject]@{
        Fields          = (ConvertFrom-Json '[ { "name": "name", "label": "Projektname" }, { "name": "notiz", "label": "Notiz" } ]')
        DescriptionPath = ''
    }
    $fields = @(Get-SpawnNewFieldList -Action $holder -Diagnostics $diagnostics)

    $text = Get-SpawnNewSummaryText -Action $action -TargetPath 'D:\Projekte\Neu' -Field $fields -Value @{ name = 'Neu' } -ConflictPolicy 'fail' -TargetExisted $false

    Confirm-SpawnNewMatch -Label 'Titel' -Actual $text -Pattern 'Git-Projekt'
    Confirm-SpawnNewMatch -Label 'Quelle' -Actual $text -Pattern 'Testquelle'
    Confirm-SpawnNewMatch -Label 'Ziel' -Actual $text -Pattern 'D:\\Projekte\\Neu'
    Confirm-SpawnNewMatch -Label 'Eingabe' -Actual $text -Pattern 'Projektname: Neu'
    Confirm-SpawnNewMatch -Label 'leere Eingabe' -Actual $text -Pattern 'Notiz: \(leer\)'
    Confirm-SpawnNewMatch -Label 'Schritt' -Actual $text -Pattern '- Repository initialisieren'
    Confirm-SpawnNewMatch -Label 'Konflikt' -Actual $text -Pattern 'nichts wird überschrieben'
    Confirm-SpawnNewCondition -Label 'kein Rechtehinweis' -Condition ($text -notmatch 'Administratorrechte')
}

Add-SpawnNewTest 'Zusammenfassung weist auf Rechte und vorhandenen Ordner hin' {
    $text = Get-SpawnNewSummaryText -Action (Get-TestActionObject -RequiresAdmin $true) -TargetPath 'D:\Neu' -Field @() -Value @{} -ConflictPolicy 'overwrite' -TargetExisted $true

    Confirm-SpawnNewMatch -Label 'Rechte' -Actual $text -Pattern 'Administratorrechte'
    Confirm-SpawnNewMatch -Label 'vorhanden' -Actual $text -Pattern 'weiterverwendet'
    Confirm-SpawnNewMatch -Label 'ueberschreiben' -Actual $text -Pattern 'überschreiben'
    Confirm-SpawnNewMatch -Label 'keine Eingaben' -Actual $text -Pattern 'keine'
    Confirm-SpawnNewMatch -Label 'keine Schritte' -Actual $text -Pattern 'nennt keine Schritte'
}

Add-SpawnNewTest 'Zusammenfassung zeigt Wahrheitswerte als Ja und Nein' {
    $diagnostics = New-Object System.Collections.ArrayList
    $holder = [pscustomobject]@{
        Fields          = (ConvertFrom-Json '[ { "name": "commit", "label": "Commit", "type": "bool" }, { "name": "push", "label": "Push", "type": "bool" } ]')
        DescriptionPath = ''
    }
    $fields = @(Get-SpawnNewFieldList -Action $holder -Diagnostics $diagnostics)

    $text = Get-SpawnNewSummaryText -Action (Get-TestActionObject) -TargetPath 'D:\Neu' -Field $fields -Value @{ commit = $true; push = $false } -ConflictPolicy 'fail' -TargetExisted $false

    Confirm-SpawnNewMatch -Label 'wahr' -Actual $text -Pattern 'Commit: Ja'
    Confirm-SpawnNewMatch -Label 'falsch' -Actual $text -Pattern 'Push: Nein'
}
