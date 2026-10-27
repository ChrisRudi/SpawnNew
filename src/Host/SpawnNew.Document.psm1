# SpawnNew.Document.psm1
# Version 1.0 | Dokumente aus Vorlagen ohne Word-Automatisierung.
# Zweck  : Platzhalter der Form {{name}} ersetzen, Markdown schreiben und
#          Word-kompatible .docx-Dateien erzeugen: entweder aus einer
#          Markdown-Vorlage oder durch Ersetzen im Inhalt einer eigenen
#          .docx-Vorlage. Eigene Vorlagen des Benutzers gehen den
#          mitgelieferten vor.
# Input  : Vorlagenpfad, Zielpfad, Platzhalterwerte als Hashtable.
# Output : Geschriebene Datei. Vorhandene Dateien werden nie ueberschrieben.
# Deps   : Windows PowerShell 5.1, System.IO.Compression, SpawnNew.Config.psm1.

Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')

$script:PlaceholderPattern = '\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}'
$script:WordNamespace = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

function Expand-SpawnNewPlaceholder {
    <#
    .SYNOPSIS
    Ersetzt {{name}} durch Werte. Gross- und Kleinschreibung der Namen ist
    egal; unbekannte Platzhalter bleiben sichtbar stehen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][hashtable]$Value
    )

    $lookup = @{}
    foreach ($key in $Value.Keys) { $lookup[([string]$key).ToLowerInvariant()] = [string]$Value[$key] }

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($match)
        $name = $match.Groups[1].Value.ToLowerInvariant()
        if ($lookup.ContainsKey($name)) { return $lookup[$name] }
        return $match.Value
    }
    return [regex]::Replace($Text, $script:PlaceholderPattern, $evaluator)
}

function Get-SpawnNewTemplateDirectory {
    <#
    .SYNOPSIS
    Ablage eigener Vorlagen je Aktion im Benutzerdatenbereich.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$ActionId)

    return (Join-Path (Join-Path (Get-SpawnNewDataDirectory) 'Vorlagen') $ActionId)
}

function Find-SpawnNewTemplate {
    <#
    .SYNOPSIS
    Sucht die Vorlage fuer ein Dokument und ein Format.
    .DESCRIPTION
    Reihenfolge: eigene Vorlage des Benutzers vor mitgelieferter, und fuer
    Word eine .docx-Vorlage vor einer umzuwandelnden Markdown-Vorlage.
    Liefert $null, wenn nichts passt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$ActionDirectory,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('markdown', 'docx')][string]$Format
    )

    $directories = @((Get-SpawnNewTemplateDirectory -ActionId $ActionId), (Join-Path $ActionDirectory 'Vorlagen'))
    $extensions  = if ($Format -eq 'docx') { @('.docx', '.md') } else { @('.md') }

    foreach ($directory in $directories) {
        foreach ($extension in $extensions) {
            $path = Join-Path $directory ($Name + $extension)
            if ([System.IO.File]::Exists($path)) {
                return [pscustomobject]@{ Path = $path; Kind = $extension.TrimStart('.'); Personal = ($directory -eq $directories[0]) }
            }
        }
    }
    return $null
}

function ConvertTo-SpawnNewXmlText {
    <#
    .SYNOPSIS
    Maskiert Text fuer XML-Inhalt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function ConvertTo-SpawnNewRunXml {
    <#
    .SYNOPSIS
    Textlauf mit optionalem Fettdruck; Zeilenumbrueche werden w:br.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Properties = '',
        [switch]$Bold
    )

    $props = $Properties
    if ($Bold) { $props = '<w:rPr><w:b/></w:rPr>' }

    $parts = @($Text.Replace("`r`n", "`n").Split("`n") | ForEach-Object { '<w:t xml:space="preserve">' + (ConvertTo-SpawnNewXmlText -Text $_) + '</w:t>' })
    return ('<w:r>' + $props + ($parts -join '<w:br/>') + '</w:r>')
}

function ConvertTo-SpawnNewInlineXml {
    <#
    .SYNOPSIS
    Absatzinhalt mit **fett** als Wechsel zwischen normalen und fetten Laeufen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $pieces = $Text -split '\*\*'
    $xml = ''
    for ($i = 0; $i -lt $pieces.Count; $i++) {
        if ($pieces[$i].Length -eq 0) { continue }
        $xml += ConvertTo-SpawnNewRunXml -Text $pieces[$i] -Bold:([bool]($i % 2))
    }
    return $xml
}

function ConvertTo-SpawnNewParagraphXml {
    <#
    .SYNOPSIS
    Absatz mit Formatvorlage und optionaler Aufzaehlung.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Style = '',
        [switch]$Bullet
    )

    $props = ''
    if ($Style) { $props += '<w:pStyle w:val="' + $Style + '"/>' }
    if ($Bullet) { $props += '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>' }
    if ($props) { $props = '<w:pPr>' + $props + '</w:pPr>' }

    return ('<w:p>' + $props + (ConvertTo-SpawnNewInlineXml -Text $Text) + '</w:p>')
}

function ConvertTo-SpawnNewTableXml {
    <#
    .SYNOPSIS
    Tabelle aus Markdown-Tabellenzeilen; die erste Zeile ist Kopfzeile.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string[]]$Row)

    $border = '<w:tblBorders>' + (@('top', 'left', 'bottom', 'right', 'insideH', 'insideV' | ForEach-Object { '<w:' + $_ + ' w:val="single" w:sz="4" w:space="0" w:color="808080"/>' }) -join '') + '</w:tblBorders>'
    $xml = '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/>' + $border + '</w:tblPr>'

    $first = $true
    foreach ($line in $Row) {
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if (($cells -join '') -match '^[-:\s]*$') { continue }

        $xml += '<w:tr>'
        foreach ($cell in $cells) {
            $run = if ($first) { ConvertTo-SpawnNewRunXml -Text $cell -Bold } else { ConvertTo-SpawnNewInlineXml -Text $cell }
            $xml += '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr><w:p>' + $run + '</w:p></w:tc>'
        }
        $xml += '</w:tr>'
        $first = $false
    }
    return ($xml + '</w:tbl>')
}

function ConvertTo-SpawnNewBodyXml {
    <#
    .SYNOPSIS
    Wandelt die Markdown-Teilmenge der Vorlagen in WordprocessingML.
    .DESCRIPTION
    Unterstuetzt Ueberschriften (#, ##, ###), Aufzaehlungen (- oder *),
    Kontrollkaestchen (- [ ]), Tabellen mit | und **fett**. Leerzeilen
    trennen Absaetze.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Markdown)

    $lines = $Markdown.Replace("`r`n", "`n").Split("`n")
    $body  = New-Object System.Text.StringBuilder
    $table = New-Object System.Collections.ArrayList

    foreach ($line in $lines) {
        if ($line.TrimStart().StartsWith('|')) {
            [void]$table.Add($line)
            continue
        }
        if ($table.Count -gt 0) {
            [void]$body.Append((ConvertTo-SpawnNewTableXml -Row ([string[]]$table.ToArray())))
            [void]$body.Append('<w:p/>')
            $table.Clear()
        }

        if ($line.Trim().Length -eq 0) { continue }

        if ($line -match '^(#{1,3})\s+(.*)$') {
            [void]$body.Append((ConvertTo-SpawnNewParagraphXml -Text $Matches[2] -Style ('Heading' + $Matches[1].Length)))
        }
        elseif ($line -match '^\s*[-*]\s+\[\s?\]\s+(.*)$') {
            [void]$body.Append((ConvertTo-SpawnNewParagraphXml -Text ([string][char]0x2610 + ' ' + $Matches[1])))
        }
        elseif ($line -match '^\s*[-*]\s+(.*)$') {
            [void]$body.Append((ConvertTo-SpawnNewParagraphXml -Text $Matches[1] -Bullet))
        }
        else {
            [void]$body.Append((ConvertTo-SpawnNewParagraphXml -Text $line))
        }
    }
    if ($table.Count -gt 0) { [void]$body.Append((ConvertTo-SpawnNewTableXml -Row ([string[]]$table.ToArray()))) }

    return $body.ToString()
}

function Get-SpawnNewDocxPart {
    <#
    .SYNOPSIS
    Die festen Teile eines minimalen Word-Dokuments.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Body)

    $ns = $script:WordNamespace
    $heading = {
        param($Level, $Size)
        '<w:style w:type="paragraph" w:styleId="Heading' + $Level + '"><w:name w:val="heading ' + $Level + '"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>' +
        '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="' + ($Level - 1) + '"/></w:pPr><w:rPr><w:b/><w:sz w:val="' + $Size + '"/></w:rPr></w:style>'
    }

    return @{
        '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>'
        '_rels/.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
        'word/_rels/document.xml.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/></Relationships>'
        'word/styles.xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="' + $ns + '"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:lang w:val="de-DE"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>' + (& $heading 1 32) + (& $heading 2 28) + (& $heading 3 24) + '</w:styles>'
        'word/numbering.xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:numbering xmlns:w="' + $ns + '"><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="' + [char]0x2022 + '"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>'
        'word/document.xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="' + $ns + '"><w:body>' + $Body + '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1417" w:right="1417" w:bottom="1134" w:left="1417" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>'
    }
}

function Write-SpawnNewZipEntry {
    <#
    .SYNOPSIS
    Schreibt einen Text als UTF-8 ohne BOM in ein Archiv.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Archive,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $entry  = $Archive.CreateEntry($Name)
    $writer = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding $false))
    try { $writer.Write($Text) }
    finally { $writer.Dispose() }
}

function Assert-SpawnNewNewFile {
    <#
    .SYNOPSIS
    Bricht ab, wenn die Zieldatei schon existiert. Es wird nie still
    ueberschrieben.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.File]::Exists($Path)) { throw "Die Datei ist bereits vorhanden und wird nicht überschrieben: $Path" }
}

function New-SpawnNewDocxFromMarkdown {
    <#
    .SYNOPSIS
    Erzeugt eine .docx-Datei aus Markdown-Text.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Markdown,
        [Parameter(Mandatory)][string]$Path
    )

    Assert-SpawnNewNewFile -Path $Path
    if (-not $PSCmdlet.ShouldProcess($Path, 'Word-Dokument erzeugen')) { return }

    $parts  = Get-SpawnNewDocxPart -Body (ConvertTo-SpawnNewBodyXml -Markdown $Markdown)
    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::CreateNew)
    $zip    = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in @('[Content_Types].xml', '_rels/.rels', 'word/_rels/document.xml.rels', 'word/styles.xml', 'word/numbering.xml', 'word/document.xml')) {
            Write-SpawnNewZipEntry -Archive $zip -Name $name -Text $parts[$name]
        }
    }
    finally {
        $zip.Dispose()
        $stream.Dispose()
    }
}

function Get-SpawnNewParagraphText {
    <#
    .SYNOPSIS
    Sichtbarer Text eines w:p-Elements als Zeichenkette.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Xml)

    $texts = [regex]::Matches($Xml, '<w:t(?:\s[^>]*)?>(.*?)</w:t>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $value = (@($texts | ForEach-Object { $_.Groups[1].Value }) -join '')
    return [System.Net.WebUtility]::HtmlDecode($value)
}

function Expand-SpawnNewWordXml {
    <#
    .SYNOPSIS
    Ersetzt Platzhalter im XML eines Word-Teils.
    .DESCRIPTION
    Word teilt Text oft in mehrere Laeufe, etwa nach einer Korrektur. Steht
    ein Platzhalter nicht am Stueck im XML, wird der betroffene Absatz zu
    einem einzigen Lauf mit der Formatierung des ersten Laufs
    zusammengefasst. Absaetze ohne Platzhalter bleiben unberuehrt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Xml,
        [Parameter(Mandatory)][hashtable]$Value
    )

    # Werte fuer den Einsatz direkt im XML: maskiert, Zeilenumbrueche als w:br.
    $escaped = @{}
    foreach ($key in $Value.Keys) {
        $text = (ConvertTo-SpawnNewXmlText -Text ([string]$Value[$key])).Replace("`r`n", "`n")
        $escaped[$key] = $text.Replace("`n", '</w:t><w:br/><w:t xml:space="preserve">')
    }

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($match)
        $paragraph = $match.Value
        $text = Get-SpawnNewParagraphText -Xml $paragraph
        if ($text -notmatch $script:PlaceholderPattern) { return $paragraph }

        $names = @([regex]::Matches($text, $script:PlaceholderPattern) | ForEach-Object { $_.Value })
        $intact = $true
        foreach ($name in $names) { if (-not $paragraph.Contains($name)) { $intact = $false } }

        if ($intact) { return (Expand-SpawnNewPlaceholder -Text $paragraph -Value $escaped) }

        $pPr = [regex]::Match($paragraph, '<w:pPr>.*?</w:pPr>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
        $rPr = [regex]::Match($paragraph, '<w:rPr>.*?</w:rPr>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
        $open = [regex]::Match($paragraph, '^<w:p(?:\s[^>]*)?>').Value
        $run  = ConvertTo-SpawnNewRunXml -Text (Expand-SpawnNewPlaceholder -Text $text -Value $Value) -Properties $rPr
        return ($open + $pPr + $run + '</w:p>')
    }

    return [regex]::Replace($Xml, '<w:p(?:\s[^>]*)?>.*?</w:p>', $evaluator, [System.Text.RegularExpressions.RegexOptions]::Singleline)
}

function New-SpawnNewDocxFromTemplate {
    <#
    .SYNOPSIS
    Kopiert eine .docx-Vorlage und ersetzt die Platzhalter in Text, Kopf-
    und Fusszeilen.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Value
    )

    Assert-SpawnNewNewFile -Path $Path
    if (-not $PSCmdlet.ShouldProcess($Path, 'Word-Dokument aus Vorlage erzeugen')) { return }

    [System.IO.File]::Copy($TemplatePath, $Path, $false)
    $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $targets = @($zip.Entries | Where-Object { $_.FullName -match '^word/(document|header\d*|footer\d*)\.xml$' })
        foreach ($entry in $targets) {
            $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
            try { $xml = $reader.ReadToEnd() }
            finally { $reader.Dispose() }

            $name = $entry.FullName
            $entry.Delete()
            Write-SpawnNewZipEntry -Archive $zip -Name $name -Text (Expand-SpawnNewWordXml -Xml $xml -Value $Value)
        }
    }
    finally {
        $zip.Dispose()
    }
}

function New-SpawnNewDocument {
    <#
    .SYNOPSIS
    Erzeugt ein Dokument aus der passenden Vorlage einer Aktion.
    .DESCRIPTION
    Format 'markdown' schreibt <Name>.md, Format 'docx' schreibt <Name>.docx.
    Liefert den geschriebenen Pfad. Eine vorhandene Datei wird nicht
    ueberschrieben, sondern fuehrt zu einer Ausnahme.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$ActionDirectory,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('markdown', 'docx')][string]$Format,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][hashtable]$Value,
        [string]$FileName = $Name
    )

    $template = Find-SpawnNewTemplate -ActionId $ActionId -ActionDirectory $ActionDirectory -Name $Name -Format $Format
    if ($null -eq $template) { throw "Keine Vorlage '$Name' für das Format $Format gefunden." }

    $extension = if ($Format -eq 'docx') { '.docx' } else { '.md' }
    $path = Join-Path $Directory ($FileName + $extension)
    Assert-SpawnNewNewFile -Path $path
    if (-not $PSCmdlet.ShouldProcess($path, 'Dokument erzeugen')) { return $path }

    if ($template.Kind -eq 'docx') {
        New-SpawnNewDocxFromTemplate -TemplatePath $template.Path -Path $path -Value $Value
        return $path
    }

    $text = Expand-SpawnNewPlaceholder -Text ([System.IO.File]::ReadAllText($template.Path, [System.Text.Encoding]::UTF8)) -Value $Value
    if ($Format -eq 'docx') {
        New-SpawnNewDocxFromMarkdown -Markdown $text -Path $path
    }
    else {
        [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $true))
    }
    return $path
}

Export-ModuleMember -Function Expand-SpawnNewPlaceholder, Get-SpawnNewTemplateDirectory, Find-SpawnNewTemplate, ConvertTo-SpawnNewXmlText, ConvertTo-SpawnNewBodyXml, New-SpawnNewDocxFromMarkdown, Expand-SpawnNewWordXml, New-SpawnNewDocxFromTemplate, New-SpawnNewDocument
