# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 19: Ordner dokumentieren.
# Zweck  : Aus Dateiliste und kurzen Auszuegen erkennbarer Schluesseldateien
#          einen README-Entwurf vom Sprachmodell schreiben lassen und als
#          README.Entwurf.md im Ordner ablegen. Nichts wird ueberschrieben.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: zweck, modell.
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

$skip      = @('.git', '.svn', '.vs', '.idea', 'node_modules', 'bin', 'obj', '__pycache__', '.venv', 'venv', 'dist', 'build')
$keyFiles  = @('README*', '*.md', 'package.json', '*.csproj', '*.sln', 'pyproject.toml', 'requirements.txt', '*.ps1', '*.psm1', 'Makefile', 'Dockerfile')
$maxList   = 400
$maxDepth  = 4
$maxPeek   = 8
$peekChars = 1500

function Get-Listing {
    # Dateiliste in Baumreihenfolge, begrenzt nach Tiefe und Anzahl.
    param([string]$Root, [string]$Prefix, [int]$Depth, [System.Collections.ArrayList]$Into)

    if ($Into.Count -ge $maxList) { return }
    foreach ($directory in @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name)) {
        if ($skip -contains $directory.Name) { continue }
        if ($Into.Count -ge $maxList) { return }
        [void]$Into.Add($Prefix + $directory.Name + '/')
        if ($Depth -lt $maxDepth) { Get-Listing -Root $directory.FullName -Prefix ($Prefix + $directory.Name + '/') -Depth ($Depth + 1) -Into $Into }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File | Sort-Object Name)) {
        if ($Into.Count -ge $maxList) { return }
        if ($file.Name -like '*.Entwurf.md') { continue }
        [void]$Into.Add($Prefix + $file.Name + '  (' + ('{0:N0}' -f [System.Math]::Ceiling($file.Length / 1KB)) + ' KB)')
    }
}

function Get-Peek {
    # Kurzer Textauszug; Binaerdateien liefern ''.
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] ([System.Math]::Min($stream.Length, $peekChars * 2))
        $read = $stream.Read($buffer, 0, $buffer.Length)
    }
    finally { $stream.Dispose() }

    for ($i = 0; $i -lt $read; $i++) { if ($buffer[$i] -eq 0) { return '' } }
    $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read).TrimStart([char]0xFEFF)
    if ($text.Length -gt $peekChars) { $text = $text.Substring(0, $peekChars) + "`n..." }
    return $text
}

try {
    $target = [string]$context.targetPath
    $zweck = Get-SpawnNewActionField -Name 'zweck'

    Write-SpawnNewActionStep -Text 'Voraussetzungen pruefen' -Percent 5
    $problem = Assert-SpawnNewActionEndpoint
    if ($problem) { exit (Complete-SpawnNewActionFailed -Reason $problem) }
    if (-not [System.IO.Directory]::Exists($target)) { exit (Complete-SpawnNewActionFailed -Reason "Der Ordner ist nicht vorhanden: $target") }

    Write-SpawnNewActionStep -Text 'Dateiliste lesen' -Percent 15
    $listing = New-Object System.Collections.ArrayList
    Get-Listing -Root $target -Prefix '' -Depth 1 -Into $listing
    if ($listing.Count -eq 0) { exit (Complete-SpawnNewActionFailed -Reason 'Der Ordner ist leer; es gibt nichts zu dokumentieren.') }
    if ($listing.Count -ge $maxList) { Write-SpawnNewActionNote -Text ('Die Dateiliste ist auf ' + $maxList + ' Einträge gekürzt.') }

    Write-SpawnNewActionStep -Text 'Schluesseldateien lesen' -Percent 30
    $peeks = New-Object System.Collections.ArrayList
    $candidates = @(Get-ChildItem -LiteralPath $target -File | Where-Object {
            $name = $_.Name
            ($name -notlike '*.Entwurf.md') -and @($keyFiles | Where-Object { $name -like $_ }).Count -gt 0
        } | Sort-Object { if ($_.Name -like 'README*') { 0 } else { 1 } }, Name | Select-Object -First $maxPeek)
    foreach ($file in $candidates) {
        $peek = Get-Peek -Path $file.FullName
        if ($peek.Trim().Length -gt 0) { [void]$peeks.Add('### ' + $file.Name + "`n" + $peek) }
    }

    Write-SpawnNewActionStep -Text ('Sprachmodell ' + $context.llm.model + ' fragen') -Percent 45
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    $system = 'Du schreibst README-Dateien auf Deutsch in Markdown. Stuetze dich nur auf Dateiliste und Auszuege; kennzeichne Vermutungen ausdruecklich als Vermutung. Gliederung: Zweck, Inhalt und Aufbau, Nutzung, Offene Punkte.'
    $user = 'Ordner: ' + (Split-Path -Leaf $target) + "`n"
    if ($zweck) { $user += 'Angegebener Zweck: ' + $zweck + "`n" }
    $user += "`nDateiliste:`n" + ($listing.ToArray() -join "`n")
    if ($peeks.Count -gt 0) { $user += "`n`nAuszuege:`n" + ($peeks.ToArray() -join "`n`n") }
    $readme = Invoke-SpawnNewActionChat -System $system -User $user

    Write-SpawnNewActionStep -Text 'README.Entwurf.md anlegen' -Percent 85
    $path = Write-SpawnNewActionDraft -Path (Join-Path $target 'README.Entwurf.md') -Text $readme -Source ($listing.Count.ToString() + ' Einträge der Dateiliste, ' + $peeks.Count + ' Auszüge')

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Message ('README-Entwurf: ' + (Split-Path -Leaf $path)))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
