# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 7: Werkstaettenprotokoll.
# Zweck  : Ordner 'Datum Klasse Thema' mit Protokollvorlage in Markdown oder
#          Word sowie Bilder- und Messdatenordner anlegen. Optional legt ein
#          Sprachmodell einen gekennzeichneten Entwurf daneben.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: klasse, thema, datum, format, entwurf.
# Output : Fortschritt, Ergebnis und Rueckgabewert nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, SpawnNew.Action.psm1 im Programmverzeichnis,
#          Vorlage Protokoll im Unterordner Vorlagen oder als eigene Vorlage.

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
    $target  = [string]$context.targetPath
    $entwurf = Test-SpawnNewActionFlag -Name 'entwurf'
    $datum   = Get-SpawnNewActionField -Name 'datum'
    $value   = @{
        klasse    = Get-SpawnNewActionField -Name 'klasse'
        thema     = Get-SpawnNewActionField -Name 'thema'
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

    Write-SpawnNewActionStep -Text 'Protokollvorlage anlegen' -Percent 35
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    [void](New-SpawnNewActionDocument -Name 'Protokoll' -Format (Get-SpawnNewActionFormat) -Directory $target -Value $value)

    Write-SpawnNewActionStep -Text 'Ordner Bilder und Messdaten anlegen' -Percent 55
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    New-SpawnNewActionFolder -Path (Join-Path $target 'Bilder')
    New-SpawnNewActionFolder -Path (Join-Path $target 'Messdaten')

    if ($entwurf) {
        Write-SpawnNewActionStep -Text 'Entwurf vom Sprachmodell anfordern' -Percent 70
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }

        $system = 'Du unterstuetzt Lehrkraefte an einer deutschen Berufsschule. Antworte auf Deutsch in Markdown, sachlich und knapp. Erfinde keine Messwerte; lass Messwerttabellen leer.'
        $user = "Erstelle einen Entwurf fuer ein Werkstaettenprotokoll.`nKlasse: $($value.klasse)`nThema: $($value.thema)`nDatum: $($value.datumText)`n`nAbschnitte: Ziel der Arbeit, Werkzeuge und Material, Sicherheitshinweise, Arbeitsschritte, Messwerte (leere Tabelle mit sinnvollen Groessen), Hinweise zur Auswertung."
        try {
            $text = Invoke-SpawnNewActionChat -System $system -User $user
            [void](Write-SpawnNewActionDraft -Path (Join-Path $target 'Protokoll.Entwurf.md') -Text $text)
        }
        catch {
            Write-SpawnNewActionNote -Warning -Text ('Kein Entwurf: ' + $_.Exception.Message)
        }
    }

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Message ('Werkstättenprotokoll ' + $value.thema + ' angelegt.'))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
