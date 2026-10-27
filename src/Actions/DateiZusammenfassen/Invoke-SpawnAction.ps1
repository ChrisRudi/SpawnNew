# Invoke-SpawnAction.ps1
# Version 1.1 | Aktion 18: Datei zusammenfassen.
# Zweck  : Eine oder mehrere Textdateien vom gewaehlten Sprachmodell
#          zusammenfassen lassen und je Datei eine gekennzeichnete
#          Entwurfsdatei neben die Quelle legen. Vorhandene Dateien werden
#          nie ueberschrieben. Bei mehreren Dateien wird eine unpassende
#          uebersprungen; die anderen werden trotzdem zusammengefasst.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: datei (ein Pfad oder eine Liste), umfang, modell.
# Output : Fortschritt, Ergebnis und Rueckgabewert nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, SpawnNew.Action.psm1 im Programmverzeichnis.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$ContextFile)

$ErrorActionPreference = 'Stop'

$raw = ConvertFrom-Json ([System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8))
$helper = Join-Path ([string]$raw.appDirectory) 'SpawnNew.Action.psm1'
if (-not ([string]$raw.appDirectory) -or -not [System.IO.File]::Exists($helper)) {
    [System.IO.File]::WriteAllText($raw.resultFile, '{"schemaVersion":1,"status":"failed","message":"Es wurde nichts angelegt.","created":[],"error":{"step":"Vorbereiten","reason":"SpawnNew.Action.psm1 fehlt; SpawnNew bitte neu installieren.","details":""}}')
    exit 1
}
Import-Module $helper
$context = Initialize-SpawnNewAction -ContextFile $ContextFile

$maxBytes = 2MB
$maxChars = 60000

function Read-TextFile {
    # Liest UTF-8 mit oder ohne BOM, UTF-16 mit BOM und sonst die
    # ANSI-Codepage. Liefert $null bei Binaerinhalt.
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom16 = $bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))
    if (-not $hasBom16) {
        $probe = [System.Math]::Min($bytes.Length, 8000)
        for ($i = 0; $i -lt $probe; $i++) { if ($bytes[$i] -eq 0) { return $null } }
    }

    $reader = New-Object System.IO.StreamReader((New-Object System.IO.MemoryStream (, $bytes)), (New-Object System.Text.UTF8Encoding($false, $true)), $true)
    try { return $reader.ReadToEnd() }
    catch [System.Text.DecoderFallbackException] { return [System.Text.Encoding]::Default.GetString($bytes) }
    finally { $reader.Dispose() }
}

function Get-FileProblem {
    # Grund, warum eine Datei nicht zusammengefasst werden kann, sonst ''.
    param([string]$Path, [ref]$Text)

    if (-not [System.IO.File]::Exists($Path)) { return "Die Datei ist nicht vorhanden: $Path" }
    if ((Get-Item -LiteralPath $Path).Length -gt $maxBytes) { return ((Split-Path -Leaf $Path) + ' ist größer als 2 MB und wird nicht verarbeitet.') }
    $content = Read-TextFile -Path $Path
    if ($null -eq $content) { return ((Split-Path -Leaf $Path) + ' ist keine Textdatei.') }
    if ($content.Trim().Length -eq 0) { return ((Split-Path -Leaf $Path) + ' ist leer.') }
    $Text.Value = $content
    return ''
}

try {
    $sources = @(Get-SpawnNewActionList -Name 'datei')
    $ausfuehrlich = (Get-SpawnNewActionField -Name 'umfang') -eq 'Ausführlich'

    Write-SpawnNewActionStep -Text 'Voraussetzungen pruefen' -Percent 5
    $problem = Assert-SpawnNewActionEndpoint
    if ($problem) { exit (Complete-SpawnNewActionFailed -Reason $problem) }
    if ($sources.Count -eq 0) { exit (Complete-SpawnNewActionFailed -Reason 'Es ist keine Datei gewählt.') }

    # Erst alle Dateien pruefen; bei nur einer Datei bricht ein Problem ab,
    # bei mehreren wird die Datei uebersprungen.
    $work = New-Object System.Collections.ArrayList
    foreach ($source in $sources) {
        $text = ''
        $reason = Get-FileProblem -Path $source -Text ([ref]$text)
        if ($reason) {
            if ($sources.Count -eq 1) { exit (Complete-SpawnNewActionFailed -Reason $reason) }
            Write-SpawnNewActionNote -Warning -Text ('Übersprungen: ' + $reason)
            continue
        }
        [void]$work.Add([pscustomobject]@{ Path = $source; Text = $text })
    }
    if ($work.Count -eq 0) { exit (Complete-SpawnNewActionFailed -Reason 'Keine der gewählten Dateien lässt sich zusammenfassen.') }

    $laenge = if ($ausfuehrlich) { 'ausfuehrlich mit Zwischenueberschriften, Kernaussagen, Zahlen und offenen Punkten' } else { 'kurz: hoechstens zehn Stichpunkte und ein Satz Fazit' }
    $system = 'Du fasst Dokumente sachlich auf Deutsch in Markdown zusammen. Gib nur wieder, was im Text steht, und kennzeichne Unklares. Keine Einleitung wie "Hier ist".'

    $done = New-Object System.Collections.ArrayList
    $index = 0
    foreach ($item in $work) {
        $index++
        $leaf = Split-Path -Leaf $item.Path
        $percent = 10 + [int](85 * ($index - 1) / $work.Count)
        Write-SpawnNewActionStep -Text ($leaf + ': Sprachmodell ' + $context.llm.model + ' fragen (' + $index + ' von ' + $work.Count + ')') -Percent $percent
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }

        $text = $item.Text
        $basis = $leaf
        if ($text.Length -gt $maxChars) {
            $text = $text.Substring(0, $maxChars)
            $basis += ', nur die ersten ' + $maxChars + ' Zeichen'
            Write-SpawnNewActionNote -Text ($leaf + ' ist lang; zusammengefasst werden die ersten ' + $maxChars + ' Zeichen.')
        }

        try {
            $summary = Invoke-SpawnNewActionChat -System $system -User "Fasse die folgende Datei $laenge zusammen.`nDateiname: $leaf`n`n---`n$text"
        }
        catch {
            if ($work.Count -eq 1) { throw }
            Write-SpawnNewActionNote -Warning -Text ($leaf + ': ' + $_.Exception.Message)
            continue
        }

        $name = [System.IO.Path]::GetFileNameWithoutExtension($item.Path) + '.Zusammenfassung.Entwurf.md'
        $path = Write-SpawnNewActionDraft -Path (Join-Path (Split-Path -Parent $item.Path) $name) -Text ('# Zusammenfassung: ' + $leaf + "`r`n`r`n" + $summary) -Source $basis
        [void]$done.Add((Split-Path -Leaf $path))
    }

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    if ($done.Count -eq 0) { exit (Complete-SpawnNewActionFailed -Reason 'Für keine Datei liegt eine Zusammenfassung vor.') }
    exit (Complete-SpawnNewAction -Message ('Zusammenfassung als Entwurf: ' + ($done.ToArray() -join ', ')))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
