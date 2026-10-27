# tests/SpawnNew.KiAktionen.Tests.ps1
# Version 1.0 | Prueft die Aktionen 17, 18 und 19 gegen den Ausfuehrungsvertrag.
# Zweck  : Vorschlag vor der Zusammenfassung ohne Aenderung (Abnahme 20),
#          Entwurfsdateien ohne Ueberschreiben (Abnahme 21), fehlender
#          Endpunkt (Abnahme 22) und die Pruefung der Modellantworten.

Import-SpawnNewHostModule -Name 'Config', 'Runner'

$strukturModul = Join-Path (Join-Path (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Actions') 'StrukturAusBeschreibung') 'StrukturPruefung.psm1'
Import-Module $strukturModul -Force

function Invoke-Vorschlag {
    param([string]$Reply, [string]$Target)
    $server = Start-SpawnNewFakeLlm -Reply $Reply
    try {
        $run = Get-SpawnNewRun -Root (Get-SpawnNewTestDirectory)
        $result = Invoke-SpawnNewTestAction -Folder 'StrukturAusBeschreibung' -Id 'spawnnew.structurefromtext' -Script 'Get-SpawnProposal.ps1' -Value @{ name = 'Projekt'; beschreibung = 'Ein Schulprojekt mit Planung und Abgabe' } -TargetPath $Target -Llm (Get-SpawnNewTestEndpoint -Url $server.Url) -ProposalFile $run.ProposalFile
    }
    finally { Stop-SpawnNewFakeLlm -Server $server }
    return [pscustomobject]@{ Run = $result; ProposalFile = $run.ProposalFile; Requests = $server.Requests }
}

Add-SpawnNewTest 'Vorschlag legt nichts an und verwirft ungueltige Pfade' {
    $target = Join-Path (Get-SpawnNewTestDirectory) 'Projekt'
    $reply = "Gern:`n" + '```json' + "`n" + '["01 Planung", "02 Umsetzung/Entwürfe", "../Ausbruch", "C:/Windows", "a:b", "CON", "03 Abgabe/"]' + "`n" + '```'
    $proposal = Invoke-Vorschlag -Reply $reply -Target $target

    Confirm-SpawnNewValue -Label 'Status' -Actual $proposal.Run.Result.Status -Expected 'success'
    Confirm-SpawnNewCondition -Label 'nichts angelegt' -Condition (-not (Test-Path -LiteralPath $target))

    $data = ConvertFrom-Json ([System.IO.File]::ReadAllText($proposal.ProposalFile, [System.Text.Encoding]::UTF8))
    Confirm-SpawnNewValue -Label 'Ordner' -Actual (@($data.data.folders) -join '|') -Expected '01 Planung|02 Umsetzung|02 Umsetzung/Entwürfe|03 Abgabe'
    Confirm-SpawnNewMatch -Label 'Baum' -Actual $data.text -Pattern '  - Entwürfe'
    Confirm-SpawnNewMatch -Label 'Verworfene genannt' -Actual $data.text -Pattern '4 ungültige'
    Confirm-SpawnNewMatch -Label 'Beschreibung gesendet' -Actual $proposal.Requests[0].Body -Pattern 'Schulprojekt'
}

Add-SpawnNewTest 'Nach Erstellen entsteht genau der bestaetigte Vorschlag' {
    $target = Join-Path (Get-SpawnNewTestDirectory) 'Projekt'
    $proposal = Invoke-Vorschlag -Reply '["A", "A/B", "C"]' -Target $target

    $run = Invoke-SpawnNewTestAction -Folder 'StrukturAusBeschreibung' -Id 'spawnnew.structurefromtext' -Value @{ name = 'Projekt'; beschreibung = 'Text' } -TargetPath $target -Llm (Get-SpawnNewTestEndpoint -Url 'http://127.0.0.1:9/v1') -ProposalFile $proposal.ProposalFile

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    foreach ($folder in @('A', 'A\B', 'C')) { Confirm-SpawnNewCondition -Label $folder -Condition (Test-Path -LiteralPath (Join-Path $target $folder) -PathType Container) }
    Confirm-SpawnNewMatch -Label 'README' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'README.md'))) -Pattern 'vor dem Anlegen bestätigt'
}

Add-SpawnNewTest 'Unbrauchbare Modellantwort ergibt keinen Vorschlag' {
    $proposal = Invoke-Vorschlag -Reply 'Das kann ich leider nicht.' -Target (Join-Path (Get-SpawnNewTestDirectory) 'X')

    Confirm-SpawnNewValue -Label 'Status' -Actual $proposal.Run.Result.Status -Expected 'failed'
    Confirm-SpawnNewCondition -Label 'keine Vorschlagsdatei' -Condition (-not (Test-Path -LiteralPath $proposal.ProposalFile))
}

Add-SpawnNewTest 'Veraenderter Vorschlag wird nicht angelegt' {
    $target = Join-Path (Get-SpawnNewTestDirectory) 'Projekt'
    $file = Add-SpawnNewTestFile -Path (Join-Path (Get-SpawnNewTestDirectory) 'proposal.json') -Content '{ "text": "x", "data": { "folders": [ "A", "../B" ], "model": "m" } }'
    $run = Invoke-SpawnNewTestAction -Folder 'StrukturAusBeschreibung' -Id 'spawnnew.structurefromtext' -Value @{ name = 'Projekt'; beschreibung = 'Text' } -TargetPath $target -ProposalFile $file

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'failed'
    Confirm-SpawnNewCondition -Label 'nichts angelegt' -Condition (-not (Test-Path -LiteralPath $target))
}

Add-SpawnNewTest 'Strukturpruefung sortiert nach Ebenen und kennt reservierte Namen' {
    $check = ConvertTo-StrukturListe -Data @('A-B', 'A/x', 'nul', 'Lpt1.txt', 'ok.')
    Confirm-SpawnNewValue -Label 'Reihenfolge' -Actual ($check.Folders -join '|') -Expected 'A|A/x|A-B'
    Confirm-SpawnNewValue -Label 'verworfen' -Actual $check.Dropped -Expected 3

    $object = ConvertTo-StrukturListe -Data ([pscustomobject]@{ ordner = @('Eins') })
    Confirm-SpawnNewValue -Label 'Objekt mit ordner' -Actual ($object.Folders -join '|') -Expected 'Eins'
}

function Invoke-Zusammenfassung {
    param([string]$Source, $Llm)
    return (Invoke-SpawnNewTestAction -Folder 'DateiZusammenfassen' -Id 'spawnnew.summarizefile' -Value @{ datei = $Source; umfang = 'Kurz'; modell = 'Test' } -TargetPath (Split-Path -Parent $Source) -TargetExisted $true -Llm $Llm)
}

Add-SpawnNewTest 'Zusammenfassung landet als Entwurf neben der Quelle' {
    $source = Add-SpawnNewTestFile -Path (Join-Path (Get-SpawnNewTestDirectory) 'Daten\Bericht.txt') -Content 'Die Größe beträgt 12 Meter.'
    $server = Start-SpawnNewFakeLlm -Reply '- Größe: 12 m'
    try { $run = Invoke-Zusammenfassung -Source $source -Llm (Get-SpawnNewTestEndpoint -Url $server.Url) }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    $draft = Join-Path (Split-Path -Parent $source) 'Bericht.Zusammenfassung.Entwurf.md'
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewMatch -Label 'Entwurf' -Actual ([System.IO.File]::ReadAllText($draft)) -Pattern 'ENTWURF[\s\S]*Größe: 12 m'
    Confirm-SpawnNewMatch -Label 'Inhalt gesendet' -Actual $server.Requests[0].Body -Pattern 'Die Größe beträgt 12 Meter'
    Confirm-SpawnNewMatch -Label 'kurz' -Actual $server.Requests[0].Body -Pattern 'zehn Stichpunkte'
}

Add-SpawnNewTest 'Vorhandener Entwurf bleibt, der neue bekommt einen freien Namen' {
    $source = Add-SpawnNewTestFile -Path (Join-Path (Get-SpawnNewTestDirectory) 'Bericht.txt') -Content 'Text'
    $old = Add-SpawnNewTestFile -Path (Join-Path (Get-SpawnNewTestDirectory) 'Bericht.Zusammenfassung.Entwurf.md') -Content 'ALT'
    $server = Start-SpawnNewFakeLlm -Reply 'neu'
    try { $run = Invoke-Zusammenfassung -Source $source -Llm (Get-SpawnNewTestEndpoint -Url $server.Url) }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewValue -Label 'alt unveraendert' -Actual ([System.IO.File]::ReadAllText($old)) -Expected 'ALT'
    Confirm-SpawnNewCondition -Label 'neuer Name' -Condition (Test-Path -LiteralPath (Join-Path (Get-SpawnNewTestDirectory) 'Bericht.Zusammenfassung.Entwurf (2).md'))
}

Add-SpawnNewTest 'ANSI-Datei wird korrekt gelesen, Binaerdatei abgewiesen' {
    $ansi = Join-Path (Get-SpawnNewTestDirectory) 'ansi.txt'
    [System.IO.File]::WriteAllBytes($ansi, [System.Text.Encoding]::GetEncoding(1252).GetBytes('Maße und Gewichte'))
    $server = Start-SpawnNewFakeLlm -Reply 'ok'
    try { [void](Invoke-Zusammenfassung -Source $ansi -Llm (Get-SpawnNewTestEndpoint -Url $server.Url)) }
    finally { Stop-SpawnNewFakeLlm -Server $server }
    Confirm-SpawnNewMatch -Label 'Umlaut' -Actual $server.Requests[0].Body -Pattern 'Maße und Gewichte'

    $binary = Join-Path (Get-SpawnNewTestDirectory) 'bild.bin'
    [System.IO.File]::WriteAllBytes($binary, [byte[]](0, 1, 2, 3, 0, 255))
    $run = Invoke-Zusammenfassung -Source $binary -Llm (Get-SpawnNewTestEndpoint -Url 'http://127.0.0.1:9/v1')
    Confirm-SpawnNewMatch -Label 'abgewiesen' -Actual $run.Result.Error.Reason -Pattern 'keine Textdatei'
}

Add-SpawnNewTest 'Ohne Endpunkt startet die Zusammenfassung nicht' {
    $source = Add-SpawnNewTestFile -Path (Join-Path (Get-SpawnNewTestDirectory) 'a.txt') -Content 'Text'
    $run = Invoke-Zusammenfassung -Source $source -Llm $null

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'failed'
    Confirm-SpawnNewValue -Label 'nichts erstellt' -Actual $run.Result.Created.Count -Expected 0
}

Add-SpawnNewTest 'Ordner dokumentieren nutzt Dateiliste und Auszuege, ueberschreibt nichts' {
    $root = Join-Path (Get-SpawnNewTestDirectory) 'Werkzeug'
    [void](Add-SpawnNewTestFile -Path (Join-Path $root 'README.md') -Content 'Altes README mit Hinweis XYZ')
    [void](Add-SpawnNewTestFile -Path (Join-Path $root 'src\Haupt.ps1') -Content 'param()')
    [void](Add-SpawnNewTestFile -Path (Join-Path $root 'node_modules\paket\index.js') -Content 'x')

    $server = Start-SpawnNewFakeLlm -Reply "# Werkzeug`n`n## Zweck"
    try {
        $run = Invoke-SpawnNewTestAction -Folder 'OrdnerDokumentieren' -Id 'spawnnew.documentfolder' -Value @{ zweck = 'Skripte'; modell = 'Test' } -TargetPath $root -TargetExisted $true -Llm (Get-SpawnNewTestEndpoint -Url $server.Url)
        $again = Invoke-SpawnNewTestAction -Folder 'OrdnerDokumentieren' -Id 'spawnnew.documentfolder' -Value @{ zweck = ''; modell = 'Test' } -TargetPath $root -TargetExisted $true -Llm (Get-SpawnNewTestEndpoint -Url $server.Url)
    }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewValue -Label 'README unveraendert' -Actual ([System.IO.File]::ReadAllText((Join-Path $root 'README.md'))) -Expected 'Altes README mit Hinweis XYZ'
    Confirm-SpawnNewMatch -Label 'Entwurf' -Actual ([System.IO.File]::ReadAllText((Join-Path $root 'README.Entwurf.md'))) -Pattern 'ENTWURF[\s\S]*## Zweck'

    $body = $server.Requests[0].Body
    Confirm-SpawnNewMatch -Label 'Unterordner' -Actual $body -Pattern 'src/Haupt\.ps1'
    Confirm-SpawnNewMatch -Label 'Auszug' -Actual $body -Pattern 'Hinweis XYZ'
    Confirm-SpawnNewCondition -Label 'node_modules ausgelassen' -Condition ($body -notmatch 'index\.js')
    Confirm-SpawnNewCondition -Label 'Entwurf nicht als Quelle' -Condition ($server.Requests[1].Body -notmatch 'README\.Entwurf')
    Confirm-SpawnNewValue -Label 'zweiter Lauf' -Actual $again.Result.Status -Expected 'success'
    Confirm-SpawnNewCondition -Label 'freier Name' -Condition (Test-Path -LiteralPath (Join-Path $root 'README.Entwurf (2).md'))
}

Add-SpawnNewTest 'Leerer Ordner wird nicht dokumentiert' {
    $root = Join-Path (Get-SpawnNewTestDirectory) 'Leer'
    [void](New-Item -ItemType Directory -Path $root -Force)
    $run = Invoke-SpawnNewTestAction -Folder 'OrdnerDokumentieren' -Id 'spawnnew.documentfolder' -Value @{ zweck = ''; modell = 'Test' } -TargetPath $root -TargetExisted $true -Llm (Get-SpawnNewTestEndpoint -Url 'http://127.0.0.1:9/v1')

    Confirm-SpawnNewMatch -Label 'Grund' -Actual $run.Result.Error.Reason -Pattern 'leer'
}

Add-SpawnNewTest 'Mehrere Dateien ergeben je einen Entwurf, unpassende werden uebersprungen' {
    $Work = Get-SpawnNewTestDirectory
    $a = Add-SpawnNewTestFile -Path (Join-Path $Work 'Daten\Bericht.txt') -Content 'Erster Bericht'
    $b = Add-SpawnNewTestFile -Path (Join-Path $Work 'Daten\Notiz.md') -Content 'Zweite Notiz'
    $c = Join-Path $Work 'Daten\bild.bin'
    [System.IO.File]::WriteAllBytes($c, [byte[]](0, 1, 2))

    $server = Start-SpawnNewFakeLlm -Reply '- Kernaussage'
    try { $run = Invoke-SpawnNewTestAction -Folder 'DateiZusammenfassen' -Id 'spawnnew.summarizefile' -Value @{ datei = [string[]]@($a, $c, $b); umfang = 'Kurz'; modell = 'Test' } -TargetPath (Join-Path $Work 'Daten') -TargetExisted $true -Llm (Get-SpawnNewTestEndpoint -Url $server.Url) }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'partial'
    Confirm-SpawnNewValue -Label 'zwei Anfragen' -Actual @($server.Requests | Where-Object { $_.Path -like '*chat*' }).Count -Expected 2
    Confirm-SpawnNewCondition -Label 'Entwurf 1' -Condition (Test-Path -LiteralPath (Join-Path $Work 'Daten\Bericht.Zusammenfassung.Entwurf.md'))
    Confirm-SpawnNewCondition -Label 'Entwurf 2' -Condition (Test-Path -LiteralPath (Join-Path $Work 'Daten\Notiz.Zusammenfassung.Entwurf.md'))
    Confirm-SpawnNewMatch -Label 'Warnung' -Actual (@($run.Progress | Where-Object { $_.Type -eq 'warn' })[0].Text) -Pattern 'bild\.bin ist keine Textdatei'
}
