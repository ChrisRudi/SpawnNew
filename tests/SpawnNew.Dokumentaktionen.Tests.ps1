# tests/SpawnNew.Dokumentaktionen.Tests.ps1
# Version 1.0 | Prueft die Aktionen 7, 10 und 11 gegen den Ausfuehrungsvertrag.
# Zweck  : Werkstaettenprotokoll, Fehleranalyse und Sitzung: Ordner,
#          Dokumente in Markdown und Word, eigene Vorlagen, optionale
#          Entwuerfe vom Sprachmodell und deren Fehlerfaelle.

Import-SpawnNewHostModule -Name 'Config', 'Runner'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-DocxText {
    param([string]$Path)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $reader = New-Object System.IO.StreamReader($zip.GetEntry('word/document.xml').Open(), [System.Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally { $zip.Dispose() }
}

function Invoke-Werkstatt {
    param([hashtable]$Value, $Llm = $null)
    $all = @{ klasse = 'E1a'; thema = 'Löten'; datum = '2026-10-26'; format = 'Markdown'; entwurf = $false }
    foreach ($key in $Value.Keys) { $all[$key] = $Value[$key] }
    $target = Join-Path (Get-SpawnNewTestDirectory) ('2026-10-26 ' + $all['klasse'] + ' ' + $all['thema'])
    return (Invoke-SpawnNewTestAction -Folder 'Werkstattprotokoll' -Id 'spawnnew.workshoplog' -Value $all -TargetPath $target -Llm $Llm)
}

Add-SpawnNewTest 'Werkstaettenprotokoll in Markdown mit Bilder- und Messdatenordner' {
    $run = Invoke-Werkstatt -Value @{}

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    $text = [System.IO.File]::ReadAllText((Join-Path $run.Target 'Protokoll.md'))
    Confirm-SpawnNewMatch -Label 'Thema' -Actual $text -Pattern 'Werkstättenprotokoll: Löten'
    Confirm-SpawnNewMatch -Label 'Datum deutsch' -Actual $text -Pattern '\| Datum \| 26\.10\.2026 \|'
    foreach ($ordner in @('Bilder', 'Messdaten')) {
        Confirm-SpawnNewCondition -Label $ordner -Condition (Test-Path -LiteralPath (Join-Path $run.Target $ordner) -PathType Container)
    }
}

Add-SpawnNewTest 'Werkstaettenprotokoll in Word ist ein gueltiges Dokument' {
    $run = Invoke-Werkstatt -Value @{ format = 'Word' }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    $xml = Read-DocxText -Path (Join-Path $run.Target 'Protokoll.docx')
    [void]([xml]$xml)
    Confirm-SpawnNewMatch -Label 'Thema' -Actual $xml -Pattern 'Löten'
    Confirm-SpawnNewMatch -Label 'Tabelle' -Actual $xml -Pattern '<w:tbl>'
}

Add-SpawnNewTest 'Eigene Vorlage des Benutzers wird verwendet' {
    $own = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'SpawnNew\Vorlagen') 'spawnnew.workshoplog') 'Protokoll.md'
    [void](Add-SpawnNewTestFile -Path $own -Content 'EIGENE VORLAGE {{klasse}}')
    $run = Invoke-Werkstatt -Value @{}

    Confirm-SpawnNewValue -Label 'Inhalt' -Actual ([System.IO.File]::ReadAllText((Join-Path $run.Target 'Protokoll.md')).Trim([char]0xFEFF).Trim()) -Expected 'EIGENE VORLAGE E1a'
}

Add-SpawnNewTest 'Entwurf wird gekennzeichnet neben das Protokoll gelegt' {
    $server = Start-SpawnNewFakeLlm -Reply "## Ziel`nLötstellen herstellen."
    try { $run = Invoke-Werkstatt -Value @{ entwurf = $true } -Llm (Get-SpawnNewTestEndpoint -Url $server.Url) }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    $draft = [System.IO.File]::ReadAllText((Join-Path $run.Target 'Protokoll.Entwurf.md'))
    Confirm-SpawnNewMatch -Label 'Kennzeichnung' -Actual $draft -Pattern '\*\*ENTWURF\*\*'
    Confirm-SpawnNewMatch -Label 'Modell genannt' -Actual $draft -Pattern 'Modell testmodell'
    Confirm-SpawnNewMatch -Label 'Antwort' -Actual $draft -Pattern 'Lötstellen herstellen'
    Confirm-SpawnNewMatch -Label 'Anfrage nennt Thema' -Actual $server.Requests[0].Body -Pattern 'Löten'
}

Add-SpawnNewTest 'Entwurf ohne Endpunkt bricht vor jeder Aenderung ab' {
    $run = Invoke-Werkstatt -Value @{ entwurf = $true }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 1
    Confirm-SpawnNewMatch -Label 'Grund' -Actual $run.Result.Error.Reason -Pattern 'kein KI-Endpunkt'
    Confirm-SpawnNewCondition -Label 'nichts angelegt' -Condition (-not (Test-Path -LiteralPath $run.Target))
}

Add-SpawnNewTest 'Modellfehler laesst die Dokumente stehen und meldet partial' {
    $server = Start-SpawnNewFakeLlm -Reply 'x' -Status 500
    try { $run = Invoke-Werkstatt -Value @{ entwurf = $true } -Llm (Get-SpawnNewTestEndpoint -Url $server.Url) }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 2
    Confirm-SpawnNewCondition -Label 'Protokoll da' -Condition (Test-Path -LiteralPath (Join-Path $run.Target 'Protokoll.md'))
    Confirm-SpawnNewMatch -Label 'Warnung' -Actual (@($run.Progress | Where-Object { $_.Type -eq 'warn' })[0].Text) -Pattern 'HTTP 500'
}

Add-SpawnNewTest 'Fehleranalyse mit Dokument und drei Ordnern' {
    $target = Join-Path (Get-SpawnNewTestDirectory) '2026-10-26 Drucker'
    $run = Invoke-SpawnNewTestAction -Folder 'Fehleranalyse' -Id 'spawnnew.incident' -Value @{ titel = 'Drucker'; umgebung = "Windows 11`r`nTreiber 5.2"; datum = '2026-10-26'; entwurf = $false } -TargetPath $target

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    $text = [System.IO.File]::ReadAllText((Join-Path $target 'Fehleranalyse.md'))
    Confirm-SpawnNewMatch -Label 'Titel' -Actual $text -Pattern 'Fehleranalyse: Drucker'
    Confirm-SpawnNewMatch -Label 'Umgebung' -Actual $text -Pattern 'Treiber 5\.2'
    foreach ($ordner in @('Logs', 'Screenshots', 'Loesungsnachweis')) {
        Confirm-SpawnNewCondition -Label $ordner -Condition (Test-Path -LiteralPath (Join-Path $target $ordner) -PathType Container)
    }
}

Add-SpawnNewTest 'Fehleranalyse mit Entwurf vom Modell' {
    $server = Start-SpawnNewFakeLlm -Reply '1. Spooler neu starten'
    $target = Join-Path (Get-SpawnNewTestDirectory) 'F'
    try { $run = Invoke-SpawnNewTestAction -Folder 'Fehleranalyse' -Id 'spawnnew.incident' -Value @{ titel = 'Drucker'; umgebung = ''; datum = '2026-10-26'; entwurf = $true } -TargetPath $target -Llm (Get-SpawnNewTestEndpoint -Url $server.Url) }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewMatch -Label 'Entwurf' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'Fehleranalyse.Entwurf.md'))) -Pattern 'Spooler neu starten'
    Confirm-SpawnNewMatch -Label 'Platzhalter fuer leere Umgebung' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'Fehleranalyse.md'))) -Pattern 'Betriebssystem, Version'
}

Add-SpawnNewTest 'Sitzung legt drei Word-Dokumente und Unterlagen an' {
    $target = Join-Path (Get-SpawnNewTestDirectory) 'S'
    $run = Invoke-SpawnNewTestAction -Folder 'Sitzung' -Id 'spawnnew.meeting' -Value @{ gremium = 'Fachkonferenz'; thema = 'Prüfungen'; datum = '2026-11-03'; format = 'Word'; entwurf = $false } -TargetPath $target

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    foreach ($name in @('Tagesordnung', 'Protokoll', 'Beschlussliste')) {
        $xml = Read-DocxText -Path (Join-Path $target ($name + '.docx'))
        Confirm-SpawnNewMatch -Label $name -Actual $xml -Pattern 'Fachkonferenz'
    }
    Confirm-SpawnNewCondition -Label 'Unterlagen' -Condition (Test-Path -LiteralPath (Join-Path $target 'Unterlagen') -PathType Container)
}

Add-SpawnNewTest 'Sitzung in Markdown mit Entwurf und Abbruch' {
    $server = Start-SpawnNewFakeLlm -Reply '| TOP | Gegenstand |'
    $target = Join-Path (Get-SpawnNewTestDirectory) 'M'
    try { $run = Invoke-SpawnNewTestAction -Folder 'Sitzung' -Id 'spawnnew.meeting' -Value @{ gremium = 'SV'; thema = 'Fest'; datum = '2026-11-03'; format = 'Markdown'; entwurf = $true } -TargetPath $target -Llm (Get-SpawnNewTestEndpoint -Url $server.Url) }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewCondition -Label 'Beschlussliste.md' -Condition (Test-Path -LiteralPath (Join-Path $target 'Beschlussliste.md'))
    Confirm-SpawnNewCondition -Label 'Entwurf' -Condition (Test-Path -LiteralPath (Join-Path $target 'Tagesordnung.Entwurf.md'))

    $cancelled = Invoke-SpawnNewTestAction -Folder 'Sitzung' -Id 'spawnnew.meeting' -Value @{ gremium = 'SV'; thema = 'Fest'; datum = '2026-11-03'; format = 'Markdown'; entwurf = $false } -TargetPath (Join-Path (Get-SpawnNewTestDirectory) 'C') -Cancel
    Confirm-SpawnNewValue -Label 'Abbruch' -Actual $cancelled.Result.Status -Expected 'cancelled'
    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $cancelled.ExitCode -Expected 3
}

Add-SpawnNewTest 'Die Aktionen schreiben nichts auf stdout' {
    $run = Invoke-Werkstatt -Value @{}
    Confirm-SpawnNewValue -Label 'Ausgabe' -Actual $run.Output -Expected ''
}
