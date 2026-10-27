# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 10: Fehleranalyse.
# Zweck  : Ordner 'Datum Titel' mit Analysedokument sowie Ordnern fuer
#          Logs, Screenshots und Loesungsnachweis anlegen. Optional legt ein
#          Sprachmodell Pruefschritte als gekennzeichneten Entwurf daneben.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: titel, umgebung, datum, entwurf.
# Output : Fortschritt, Ergebnis und Rueckgabewert nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, SpawnNew.Action.psm1 im Programmverzeichnis,
#          Vorlage Fehleranalyse im Unterordner Vorlagen oder als eigene Vorlage.

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

try {
    $target   = [string]$context.targetPath
    $entwurf  = Test-SpawnNewActionFlag -Name 'entwurf'
    $datum    = Get-SpawnNewActionField -Name 'datum'
    $umgebung = Get-SpawnNewActionField -Name 'umgebung'
    if ($umgebung.Length -eq 0) { $umgebung = 'Betriebssystem, Version, Konfiguration, betroffene Geräte:' }

    $value = @{
        titel     = Get-SpawnNewActionField -Name 'titel'
        umgebung  = $umgebung
        datum     = $datum
        datumText = ([datetime]::ParseExact($datum, 'yyyy-MM-dd', $null)).ToString('dd.MM.yyyy')
    }

    Write-SpawnNewActionStep -Text 'Voraussetzungen pruefen' -Percent 5
    if ($entwurf) {
        $problem = Assert-SpawnNewActionEndpoint
        if ($problem) { exit (Complete-SpawnNewActionFailed -Reason $problem) }
    }

    Write-SpawnNewActionStep -Text 'Zielordner anlegen' -Percent 15
    New-SpawnNewActionFolder -Path $target

    Write-SpawnNewActionStep -Text 'Fehleranalyse.md anlegen' -Percent 35
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    [void](New-SpawnNewActionDocument -Name 'Fehleranalyse' -Format 'markdown' -Directory $target -Value $value)

    Write-SpawnNewActionStep -Text 'Ordner Logs, Screenshots und Loesungsnachweis anlegen' -Percent 55
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    foreach ($ordner in @('Logs', 'Screenshots', 'Loesungsnachweis')) { New-SpawnNewActionFolder -Path (Join-Path $target $ordner) }

    if ($entwurf) {
        Write-SpawnNewActionStep -Text 'Entwurf vom Sprachmodell anfordern' -Percent 70
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }

        $system = 'Du bist erfahrener IT-Administrator. Antworte auf Deutsch in Markdown, knapp und pruefbar. Kennzeichne Vermutungen als Vermutungen.'
        $user = "Fehler: $($value.titel)`nUmgebung: $($value.umgebung)`n`nGib aus: 1. Rueckfragen, die zur Eingrenzung fehlen. 2. Wahrscheinliche Ursachen mit kurzer Begruendung. 3. Pruefschritte in sinnvoller Reihenfolge mit konkreten Befehlen oder Orten fuer Logs. 4. Was als Loesungsnachweis taugt."
        try {
            $text = Invoke-SpawnNewActionChat -System $system -User $user
            [void](Write-SpawnNewActionDraft -Path (Join-Path $target 'Fehleranalyse.Entwurf.md') -Text $text)
        }
        catch {
            Write-SpawnNewActionNote -Warning -Text ('Kein Entwurf: ' + $_.Exception.Message)
        }
    }

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Message ('Fehleranalyse ' + $value.titel + ' angelegt.'))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
