# tests/SpawnNew.Document.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Document.psm1.
# Zweck  : Platzhalter, Vorlagensuche, Markdown- und .docx-Erzeugung sowie
#          Platzhalter im Inhalt einer eigenen .docx-Vorlage. Deckt
#          Abnahme 11 ohne Word-Automatisierung.

Import-SpawnNewHostModule -Name 'Config', 'Document'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-TestDocxPart {
    param([Parameter(Mandatory)][string]$Path, [string]$Part = 'word/document.xml')

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry($Part)
        if ($null -eq $entry) { return $null }
        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally { $zip.Dispose() }
}

function Initialize-TestDocxTemplate {
    # Baut eine Vorlage wie Word sie speichert: der Platzhalter {{thema}} ist
    # auf drei Laeufe verteilt, {{klasse}} steht am Stueck im Kopf.
    param([Parameter(Mandatory)][string]$Path)

    $ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $body = @(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>Thema: {{</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>the</w:t></w:r><w:r><w:t>ma}}</w:t></w:r></w:p>',
        '<w:p><w:r><w:t xml:space="preserve">Datum {{datum}} und {{unbekannt}}</w:t></w:r></w:p><w:p><w:r><w:t>Ohne Platzhalter</w:t></w:r></w:p>'
    ) -join ''
    $files = @{
        '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/></Types>'
        '_rels/.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
        'word/document.xml' = '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="' + $ns + '"><w:body>' + $body + '</w:body></w:document>'
        'word/header1.xml' = '<?xml version="1.0" encoding="UTF-8"?><w:hdr xmlns:w="' + $ns + '"><w:p><w:r><w:t>Klasse {{klasse}}</w:t></w:r></w:p></w:hdr>'
    }

    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::CreateNew)
    $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $files.Keys) {
            $writer = New-Object System.IO.StreamWriter($zip.CreateEntry($name).Open(), (New-Object System.Text.UTF8Encoding $false))
            try { $writer.Write($files[$name]) } finally { $writer.Dispose() }
        }
    }
    finally { $zip.Dispose(); $stream.Dispose() }
    return $Path
}

Add-SpawnNewTest 'Platzhalter werden ohne Ruecksicht auf Schreibweise ersetzt' {
    $text = Expand-SpawnNewPlaceholder -Text 'Hallo {{Name}}, {{ name }} und {{fehlt}}' -Value @{ name = 'Welt' }
    Confirm-SpawnNewValue -Label 'Text' -Actual $text -Expected 'Hallo Welt, Welt und {{fehlt}}'
}

Add-SpawnNewTest 'Eigene Vorlage geht der mitgelieferten vor' {
    $Work = Get-SpawnNewTestDirectory
    $action = Join-Path $Work 'aktion'
    [void](Add-SpawnNewTestFile -Path (Join-Path $action 'Vorlagen\Protokoll.md') -Content 'mitgeliefert')

    $found = Find-SpawnNewTemplate -ActionId 'spawnnew.test' -ActionDirectory $action -Name 'Protokoll' -Format 'markdown'
    Confirm-SpawnNewValue -Label 'mitgeliefert' -Actual $found.Personal -Expected $false

    [void](Add-SpawnNewTestFile -Path (Join-Path (Get-SpawnNewTemplateDirectory -ActionId 'spawnnew.test') 'Protokoll.md') -Content 'eigen')
    $found = Find-SpawnNewTemplate -ActionId 'spawnnew.test' -ActionDirectory $action -Name 'Protokoll' -Format 'markdown'
    Confirm-SpawnNewValue -Label 'eigen' -Actual $found.Personal -Expected $true
}

Add-SpawnNewTest 'Fuer Word gilt eine docx-Vorlage vor Markdown' {
    $Work = Get-SpawnNewTestDirectory
    $action = Join-Path $Work 'aktion'
    [void](Add-SpawnNewTestFile -Path (Join-Path $action 'Vorlagen\Protokoll.md') -Content '# x')

    Confirm-SpawnNewValue -Label 'Markdown umwandeln' -Actual (Find-SpawnNewTemplate -ActionId 'a.b.c' -ActionDirectory $action -Name 'Protokoll' -Format 'docx').Kind -Expected 'md'

    [void](Initialize-TestDocxTemplate -Path (Join-Path $action 'Vorlagen\Protokoll.docx'))
    Confirm-SpawnNewValue -Label 'docx' -Actual (Find-SpawnNewTemplate -ActionId 'a.b.c' -ActionDirectory $action -Name 'Protokoll' -Format 'docx').Kind -Expected 'docx'
}

Add-SpawnNewTest 'Markdown-Dokument wird mit Werten und BOM geschrieben' {
    $Work = Get-SpawnNewTestDirectory
    $action = Join-Path $Work 'aktion'
    [void](Add-SpawnNewTestFile -Path (Join-Path $action 'Vorlagen\Notiz.md') -Content "# {{thema}}`r`n`r`nKlasse {{klasse}}")

    $path = New-SpawnNewDocument -ActionId 'a.b.c' -ActionDirectory $action -Name 'Notiz' -Format 'markdown' -Directory $Work -Value @{ thema = 'Löten'; klasse = 'E1' }

    Confirm-SpawnNewValue -Label 'Pfad' -Actual $path -Expected (Join-Path $Work 'Notiz.md')
    $bytes = [System.IO.File]::ReadAllBytes($path)
    Confirm-SpawnNewValue -Label 'BOM' -Actual $bytes[0] -Expected 239
    Confirm-SpawnNewMatch -Label 'Inhalt' -Actual ([System.IO.File]::ReadAllText($path)) -Pattern '# Löten'
}

Add-SpawnNewTest 'Word-Dokument aus Markdown ist ein gueltiges Paket' {
    $Work = Get-SpawnNewTestDirectory
    $path = Join-Path $Work 'test.docx'
    New-SpawnNewDocxFromMarkdown -Markdown "# Titel & Co`n`nAbsatz mit **fett**`n`n- Punkt`n- [ ] offen`n`n| A | B |`n|---|---|`n| 1 | 2 |" -Path $path

    $xml = Read-TestDocxPart -Path $path
    [void]([xml]$xml)
    Confirm-SpawnNewMatch -Label 'Ueberschrift' -Actual $xml -Pattern 'Heading1'
    Confirm-SpawnNewMatch -Label 'maskiert' -Actual $xml -Pattern 'Titel &amp; Co'
    Confirm-SpawnNewMatch -Label 'fett' -Actual $xml -Pattern '<w:b/></w:rPr><w:t xml:space="preserve">fett'
    Confirm-SpawnNewMatch -Label 'Aufzaehlung' -Actual $xml -Pattern 'w:numId w:val="1"'
    Confirm-SpawnNewMatch -Label 'Tabelle' -Actual $xml -Pattern '<w:tbl>'
    Confirm-SpawnNewCondition -Label 'Trennzeile entfaellt' -Condition ($xml -notmatch '---')

    foreach ($part in @('[Content_Types].xml', 'word/styles.xml', 'word/numbering.xml', 'word/_rels/document.xml.rels')) {
        [void]([xml](Read-TestDocxPart -Path $path -Part $part))
    }
}

Add-SpawnNewTest 'Platzhalter in einer docx-Vorlage werden auch ueber Laeufe hinweg ersetzt' {
    $Work = Get-SpawnNewTestDirectory
    $template = Initialize-TestDocxTemplate -Path (Join-Path $Work 'vorlage.docx')
    $path = Join-Path $Work 'ergebnis.docx'

    New-SpawnNewDocxFromTemplate -TemplatePath $template -Path $path -Value @{ thema = 'Messen & Prüfen'; datum = '2026-10-26'; klasse = 'E1a' }

    $xml = Read-TestDocxPart -Path $path
    [void]([xml]$xml)
    Confirm-SpawnNewMatch -Label 'geteilter Platzhalter' -Actual $xml -Pattern 'Thema: Messen &amp; Prüfen'
    Confirm-SpawnNewMatch -Label 'Formatierung bleibt' -Actual $xml -Pattern '<w:pStyle w:val="Heading1"/></w:pPr><w:r><w:rPr><w:b/></w:rPr>'
    Confirm-SpawnNewMatch -Label 'einfacher Platzhalter' -Actual $xml -Pattern 'Datum 2026-10-26'
    Confirm-SpawnNewMatch -Label 'unbekannt bleibt' -Actual $xml -Pattern '\{\{unbekannt\}\}'
    Confirm-SpawnNewMatch -Label 'unberuehrter Absatz' -Actual $xml -Pattern '<w:p><w:r><w:t>Ohne Platzhalter</w:t></w:r></w:p>'
    Confirm-SpawnNewMatch -Label 'Kopfzeile' -Actual (Read-TestDocxPart -Path $path -Part 'word/header1.xml') -Pattern 'Klasse E1a'
    Confirm-SpawnNewMatch -Label 'Vorlage unveraendert' -Actual (Read-TestDocxPart -Path $template) -Pattern '\{\{datum\}\}'
}

Add-SpawnNewTest 'Zeilenumbrueche im Wert werden Umbrueche im Dokument' {
    $xml = Expand-SpawnNewWordXml -Xml '<w:p><w:r><w:t>{{text}}</w:t></w:r></w:p>' -Value @{ text = "eins`r`nzwei" }
    Confirm-SpawnNewMatch -Label 'Umbruch' -Actual $xml -Pattern 'eins</w:t><w:br/><w:t xml:space="preserve">zwei'
}

Add-SpawnNewTest 'Vorhandene Datei wird nie ueberschrieben' {
    $Work = Get-SpawnNewTestDirectory
    $action = Join-Path $Work 'aktion'
    [void](Add-SpawnNewTestFile -Path (Join-Path $action 'Vorlagen\Notiz.md') -Content 'neu')
    [void](Add-SpawnNewTestFile -Path (Join-Path $Work 'Notiz.md') -Content 'ALT')

    $message = ''
    try { [void](New-SpawnNewDocument -ActionId 'a.b.c' -ActionDirectory $action -Name 'Notiz' -Format 'markdown' -Directory $Work -Value @{}) }
    catch { $message = $_.Exception.Message }

    Confirm-SpawnNewMatch -Label 'Meldung' -Actual $message -Pattern 'nicht überschrieben'
    Confirm-SpawnNewValue -Label 'unveraendert' -Actual ([System.IO.File]::ReadAllText((Join-Path $Work 'Notiz.md'))) -Expected 'ALT'
}
