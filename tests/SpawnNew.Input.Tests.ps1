# tests/SpawnNew.Input.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Input.psm1.
# Zweck  : Normalisierung der Formularfelder, Vorbelegungen und Pruefung der
#          Eingaben. Deckt Abnahme 5 auf der Eingabeseite.

Import-SpawnNewHostModule -Name 'Config', 'Input'

function Get-TestActionObject {
    param($Fields)

    return [pscustomobject]@{
        Fields          = @($Fields)
        DescriptionPath = 'C:\Quelle\Aktion\action.json'
    }
}

function Get-TestFieldList {
    param($Fields)

    $diagnostics = New-Object System.Collections.ArrayList
    $list = @(Get-SpawnNewFieldList -Action (Get-TestActionObject -Fields $Fields) -Diagnostics $diagnostics)

    return [pscustomobject]@{ Field = $list; Diagnostics = $diagnostics }
}

function Get-TestField {
    param([string]$Json)

    return (Get-TestFieldList -Fields (ConvertFrom-Json $Json)).Field[0]
}

Add-SpawnNewTest 'Feld erhaelt Vorgaben fuer Label, Typ und Pflicht' {
    $field = Get-TestField -Json '[ { "name": "projekt" } ]'

    Confirm-SpawnNewValue -Label 'Name' -Actual $field.Name -Expected 'projekt'
    Confirm-SpawnNewValue -Label 'Label' -Actual $field.Label -Expected 'projekt'
    Confirm-SpawnNewValue -Label 'Typ' -Actual $field.Type -Expected 'text'
    Confirm-SpawnNewValue -Label 'Pflicht' -Actual $field.Required -Expected $false
}

Add-SpawnNewTest 'Unbekannter Feldtyp wird zu text mit Warnung' {
    $result = Get-TestFieldList -Fields (ConvertFrom-Json '[ { "name": "a", "type": "farbe" } ]')

    Confirm-SpawnNewValue -Label 'Typ' -Actual $result.Field[0].Type -Expected 'text'
    Confirm-SpawnNewValue -Label 'Stufe' -Actual $result.Diagnostics[0].Severity -Expected 'warning'
}

Add-SpawnNewTest 'Feld ohne Namen wird uebersprungen' {
    $result = Get-TestFieldList -Fields (ConvertFrom-Json '[ { "label": "Ohne" }, { "name": "mit" } ]')

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $result.Field.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Name' -Actual $result.Field[0].Name -Expected 'mit'
    Confirm-SpawnNewValue -Label 'Stufe' -Actual $result.Diagnostics[0].Severity -Expected 'error'
}

Add-SpawnNewTest 'Auswahlfeld ohne Auswahlwerte wird uebersprungen' {
    $result = Get-TestFieldList -Fields (ConvertFrom-Json '[ { "name": "a", "type": "choice" } ]')

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $result.Field.Count -Expected 0
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $result.Diagnostics[0].Message -Pattern 'keine Auswahlwerte'
}

Add-SpawnNewTest 'Doppelter Feldname wird verworfen, der erste gilt' {
    $result = Get-TestFieldList -Fields (ConvertFrom-Json '[ { "name": "a", "label": "Erst" }, { "name": "A", "label": "Zweit" } ]')

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $result.Field.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Label' -Actual $result.Field[0].Label -Expected 'Erst'
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $result.Diagnostics[0].Message -Pattern 'mehrfach deklariert'
}

Add-SpawnNewTest 'Datumsfeld mit today wird auf heute vorbelegt' {
    $field = Get-TestField -Json '[ { "name": "datum", "type": "date", "default": "today" } ]'

    Confirm-SpawnNewValue -Label 'Vorbelegung' -Actual (Get-SpawnNewFieldDefault -Field $field) -Expected ([System.DateTime]::Today.ToString('yyyy-MM-dd'))
}

Add-SpawnNewTest 'Auswahlfeld ohne Vorgabe nimmt den ersten Auswahlwert' {
    $field = Get-TestField -Json '[ { "name": "format", "type": "choice", "choices": [ "md", "docx" ] } ]'

    Confirm-SpawnNewValue -Label 'Vorbelegung' -Actual (Get-SpawnNewFieldDefault -Field $field) -Expected 'md'
}

Add-SpawnNewTest 'Leeres Pflichtfeld wird abgewiesen' {
    $field = Get-TestField -Json '[ { "name": "a", "label": "Projektname", "required": true } ]'
    $check = Test-SpawnNewFieldValue -Field $field -Value '   '

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $check.Valid -Expected $false
    Confirm-SpawnNewMatch -Label 'Meldung' -Actual $check.Message -Pattern 'Projektname'
}

Add-SpawnNewTest 'Leeres optionales Feld ist gueltig und bleibt leer' {
    $field = Get-TestField -Json '[ { "name": "a" } ]'
    $check = Test-SpawnNewFieldValue -Field $field -Value $null

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $check.Valid -Expected $true
    Confirm-SpawnNewValue -Label 'Wert' -Actual $check.Value -Expected ''
}

Add-SpawnNewTest 'Eingaben werden von Leerraum befreit' {
    $field = Get-TestField -Json '[ { "name": "a" } ]'

    Confirm-SpawnNewValue -Label 'Wert' -Actual (Test-SpawnNewFieldValue -Field $field -Value '  Hallo  ').Value -Expected 'Hallo'
}

Add-SpawnNewTest 'Wahrheitsfeld nimmt True und False' {
    $field = Get-TestField -Json '[ { "name": "commit", "label": "Commit", "type": "bool" } ]'

    Confirm-SpawnNewValue -Label 'wahr' -Actual (Test-SpawnNewFieldValue -Field $field -Value 'True').Value -Expected $true
    Confirm-SpawnNewValue -Label 'falsch' -Actual (Test-SpawnNewFieldValue -Field $field -Value 'false').Value -Expected $false
    Confirm-SpawnNewValue -Label 'unsinn' -Actual (Test-SpawnNewFieldValue -Field $field -Value 'vielleicht').Valid -Expected $false
}

Add-SpawnNewTest 'Datumsfeld nimmt deutsche Schreibweise und liefert ISO 8601' {
    $field = Get-TestField -Json '[ { "name": "datum", "label": "Datum", "type": "date" } ]'

    Confirm-SpawnNewValue -Label 'deutsch' -Actual (Test-SpawnNewFieldValue -Field $field -Value '26.10.2026').Value -Expected '2026-10-26'
    Confirm-SpawnNewValue -Label 'ISO' -Actual (Test-SpawnNewFieldValue -Field $field -Value '2026-10-26').Value -Expected '2026-10-26'
    Confirm-SpawnNewValue -Label 'unsinn' -Actual (Test-SpawnNewFieldValue -Field $field -Value 'uebermorgen').Valid -Expected $false
}

Add-SpawnNewTest 'Auswahlfeld laesst nur deklarierte Werte zu' {
    $field = Get-TestField -Json '[ { "name": "format", "label": "Format", "type": "choice", "choices": [ "md", "docx" ] } ]'

    Confirm-SpawnNewValue -Label 'gueltig' -Actual (Test-SpawnNewFieldValue -Field $field -Value 'docx').Valid -Expected $true
    $check = Test-SpawnNewFieldValue -Field $field -Value 'pdf'
    Confirm-SpawnNewValue -Label 'ungueltig' -Actual $check.Valid -Expected $false
    Confirm-SpawnNewMatch -Label 'Meldung nennt Auswahl' -Actual $check.Message -Pattern 'md, docx'
}

Add-SpawnNewTest 'Muster und eigene Meldung werden angewandt' {
    $field = Get-TestField -Json '[ { "name": "a", "label": "Klasse", "pattern": "^[0-9]{1,2}[a-z]$", "message": "Bitte wie 10b angeben." } ]'

    Confirm-SpawnNewValue -Label 'passend' -Actual (Test-SpawnNewFieldValue -Field $field -Value '10b').Valid -Expected $true
    $check = Test-SpawnNewFieldValue -Field $field -Value 'Zehn B'
    Confirm-SpawnNewValue -Label 'unpassend' -Actual $check.Valid -Expected $false
    Confirm-SpawnNewValue -Label 'eigene Meldung' -Actual $check.Message -Expected 'Bitte wie 10b angeben.'
}

Add-SpawnNewTest 'Muster ohne eigene Meldung nennt das Label' {
    $field = Get-TestField -Json '[ { "name": "a", "label": "Klasse", "pattern": "^[0-9]+$" } ]'

    Confirm-SpawnNewMatch -Label 'Meldung' -Actual (Test-SpawnNewFieldValue -Field $field -Value 'x').Message -Pattern 'Klasse'
}

Add-SpawnNewTest 'Vollstaendiger Wertesatz wird uebernommen' {
    $fields = (Get-TestFieldList -Fields (ConvertFrom-Json '[ { "name": "name", "required": true }, { "name": "datum", "type": "date" } ]')).Field
    $result = Test-SpawnNewFieldValueSet -Field $fields -Value @{ name = ' Projekt '; datum = '26.10.2026' }

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $result.Valid -Expected $true
    Confirm-SpawnNewValue -Label 'Name' -Actual $result.Value['name'] -Expected 'Projekt'
    Confirm-SpawnNewValue -Label 'Datum' -Actual $result.Value['datum'] -Expected '2026-10-26'
}

Add-SpawnNewTest 'Fehlerhafter Wertesatz sammelt alle Meldungen' {
    $fields = (Get-TestFieldList -Fields (ConvertFrom-Json '[ { "name": "a", "label": "A", "required": true }, { "name": "b", "label": "B", "type": "date" } ]')).Field
    $result = Test-SpawnNewFieldValueSet -Field $fields -Value @{ b = 'unsinn' }

    Confirm-SpawnNewValue -Label 'gueltig' -Actual $result.Valid -Expected $false
    Confirm-SpawnNewValue -Label 'Anzahl Meldungen' -Actual $result.Errors.Count -Expected 2
}

Add-SpawnNewTest 'Aktion ohne Felder liefert eine leere Feldliste' {
    $result = Get-TestFieldList -Fields @()

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $result.Field.Count -Expected 0
    Confirm-SpawnNewValue -Label 'Diagnosen' -Actual $result.Diagnostics.Count -Expected 0
}

Add-SpawnNewTest 'Dateifeld verlangt eine vorhandene Datei mit vollem Pfad' {
    $Work = Get-SpawnNewTestDirectory
    $file = Add-SpawnNewTestFile -Path (Join-Path $Work 'Bericht Ü.txt') -Content 'x'
    $field = [pscustomobject]@{ Name = 'datei'; Label = 'Datei'; Type = 'file'; Required = $true; Default = ''; Choices = @(); Pattern = ''; Message = '' }

    Confirm-SpawnNewValue -Label 'vorhanden' -Actual (Test-SpawnNewFieldValue -Field $field -Value $file).Valid -Expected $true
    Confirm-SpawnNewValue -Label 'fehlt' -Actual (Test-SpawnNewFieldValue -Field $field -Value (Join-Path $Work 'nein.txt')).Valid -Expected $false
    Confirm-SpawnNewValue -Label 'relativ' -Actual (Test-SpawnNewFieldValue -Field $field -Value 'Bericht Ü.txt').Valid -Expected $false
}

Add-SpawnNewTest 'Endpunktfeld wird aus der Konfiguration gefuellt' {
    $diagnostics = New-Object System.Collections.ArrayList
    $holder = [pscustomobject]@{ Fields = (ConvertFrom-Json '[ { "name": "modell", "label": "Modell", "type": "endpoint" } ]'); DescriptionPath = '' }
    $fields = @(Get-SpawnNewFieldList -Action $holder -Diagnostics $diagnostics)

    Confirm-SpawnNewValue -Label 'nicht uebersprungen' -Actual $fields.Count -Expected 1
    Confirm-SpawnNewValue -Label 'ohne Endpunkte ungueltig' -Actual (Test-SpawnNewFieldValue -Field $fields[0] -Value 'Lokal').Valid -Expected $false

    Set-SpawnNewEndpointChoice -Field $fields -Name @('Lokal', 'Web') -Default 'Web'

    Confirm-SpawnNewValue -Label 'Vorbelegung' -Actual (Get-SpawnNewFieldDefault -Field $fields[0]) -Expected 'Web'
    Confirm-SpawnNewValue -Label 'gueltig' -Actual (Test-SpawnNewFieldValue -Field $fields[0] -Value 'Lokal').Valid -Expected $true
    Confirm-SpawnNewValue -Label 'unbekannt' -Actual (Test-SpawnNewFieldValue -Field $fields[0] -Value 'Andere').Valid -Expected $false
}

Add-SpawnNewTest 'Dateifeld mit mehreren Dateien liefert eine Liste' {
    $Work = Get-SpawnNewTestDirectory
    $a = Add-SpawnNewTestFile -Path (Join-Path $Work 'a.txt') -Content 'x'
    $b = Add-SpawnNewTestFile -Path (Join-Path $Work 'b c.txt') -Content 'y'
    $diagnostics = New-Object System.Collections.ArrayList
    $holder = [pscustomobject]@{ Fields = (ConvertFrom-Json '[ { "name": "datei", "label": "Dateien", "type": "file", "multiple": true } ]'); DescriptionPath = '' }
    $field = @(Get-SpawnNewFieldList -Action $holder -Diagnostics $diagnostics)[0]

    $check = Test-SpawnNewFieldValue -Field $field -Value ($a + "`r`n`r`n" + $b + "`r`n")
    Confirm-SpawnNewValue -Label 'gueltig' -Actual $check.Valid -Expected $true
    Confirm-SpawnNewValue -Label 'Liste' -Actual (@($check.Value) -join '|') -Expected ($a + '|' + $b)

    $bad = Test-SpawnNewFieldValue -Field $field -Value ($a + "`r`n" + (Join-Path $Work 'fehlt.txt'))
    Confirm-SpawnNewMatch -Label 'fehlende Datei genannt' -Actual $bad.Message -Pattern 'fehlt\.txt'
}
