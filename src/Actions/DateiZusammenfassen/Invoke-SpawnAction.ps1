# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 18: Datei zusammenfassen.
# Zweck  : Eine Textdatei vom gewaehlten Sprachmodell zusammenfassen lassen
#          und das Ergebnis als gekennzeichnete Entwurfsdatei neben der
#          Quelle ablegen. Vorhandene Dateien werden nie ueberschrieben.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: datei, umfang, modell.
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

try {
    $source = Get-SpawnNewActionField -Name 'datei'
    $ausfuehrlich = (Get-SpawnNewActionField -Name 'umfang') -eq 'Ausführlich'

    Write-SpawnNewActionStep -Text 'Voraussetzungen pruefen' -Percent 5
    $problem = Assert-SpawnNewActionEndpoint
    if ($problem) { exit (Complete-SpawnNewActionFailed -Reason $problem) }
    if (-not [System.IO.File]::Exists($source)) { exit (Complete-SpawnNewActionFailed -Reason "Die Datei ist nicht vorhanden: $source") }
    if ((Get-Item -LiteralPath $source).Length -gt $maxBytes) { exit (Complete-SpawnNewActionFailed -Reason 'Die Datei ist größer als 2 MB und wird nicht verarbeitet.') }

    Write-SpawnNewActionStep -Text 'Datei lesen' -Percent 15
    $text = Read-TextFile -Path $source
    if ($null -eq $text) { exit (Complete-SpawnNewActionFailed -Reason 'Die Datei ist keine Textdatei.') }
    if ($text.Trim().Length -eq 0) { exit (Complete-SpawnNewActionFailed -Reason 'Die Datei ist leer.') }

    $basis = Split-Path -Leaf $source
    if ($text.Length -gt $maxChars) {
        $text = $text.Substring(0, $maxChars)
        $basis += ', nur die ersten ' + $maxChars + ' Zeichen'
        Write-SpawnNewActionNote -Text ('Die Datei ist lang; zusammengefasst werden die ersten ' + $maxChars + ' Zeichen.')
    }

    Write-SpawnNewActionStep -Text ('Sprachmodell ' + $context.llm.model + ' fragen') -Percent 30
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    $laenge = if ($ausfuehrlich) { 'ausfuehrlich mit Zwischenueberschriften, Kernaussagen, Zahlen und offenen Punkten' } else { 'kurz: hoechstens zehn Stichpunkte und ein Satz Fazit' }
    $system = 'Du fasst Dokumente sachlich auf Deutsch in Markdown zusammen. Gib nur wieder, was im Text steht, und kennzeichne Unklares. Keine Einleitung wie "Hier ist".'
    $user = "Fasse die folgende Datei $laenge zusammen.`nDateiname: $(Split-Path -Leaf $source)`n`n---`n$text"
    $summary = Invoke-SpawnNewActionChat -System $system -User $user

    Write-SpawnNewActionStep -Text 'Entwurf neben der Quelle ablegen' -Percent 85
    $name = [System.IO.Path]::GetFileNameWithoutExtension($source) + '.Zusammenfassung.Entwurf.md'
    $path = Write-SpawnNewActionDraft -Path (Join-Path (Split-Path -Parent $source) $name) -Text ('# Zusammenfassung: ' + (Split-Path -Leaf $source) + "`r`n`r`n" + $summary) -Source $basis

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Message ('Zusammenfassung als Entwurf: ' + (Split-Path -Leaf $path)))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
