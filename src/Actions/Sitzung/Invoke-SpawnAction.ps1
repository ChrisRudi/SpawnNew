# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 11: Sitzung.
# Zweck  : Ordner 'Datum Gremium Thema' mit Tagesordnung, Protokoll und
#          Beschlussliste in Markdown oder Word sowie einem Ordner fuer
#          Unterlagen anlegen. Optional legt ein Sprachmodell einen
#          Tagesordnungsentwurf daneben.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: gremium, thema, datum, format, entwurf.
# Output : Fortschritt, Ergebnis und Rueckgabewert nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, SpawnNew.Action.psm1 im Programmverzeichnis,
#          Vorlagen Tagesordnung, Protokoll und Beschlussliste.

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
    $format  = Get-SpawnNewActionFormat
    $datum   = Get-SpawnNewActionField -Name 'datum'
    $value   = @{
        gremium   = Get-SpawnNewActionField -Name 'gremium'
        thema     = Get-SpawnNewActionField -Name 'thema'
        datum     = $datum
        datumText = ([datetime]::ParseExact($datum, 'yyyy-MM-dd', $null)).ToString('dd.MM.yyyy')
    }

    Write-SpawnNewActionStep -Text 'Voraussetzungen pruefen' -Percent 5
    if ($entwurf) {
        $problem = Assert-SpawnNewActionEndpoint
        if ($problem) { exit (Complete-SpawnNewActionFailed -Reason $problem) }
    }

    Write-SpawnNewActionStep -Text 'Zielordner anlegen' -Percent 10
    New-SpawnNewActionFolder -Path $target

    $percent = 25
    foreach ($dokument in @('Tagesordnung', 'Protokoll', 'Beschlussliste')) {
        Write-SpawnNewActionStep -Text ($dokument + ' anlegen') -Percent $percent
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
        [void](New-SpawnNewActionDocument -Name $dokument -Format $format -Directory $target -Value $value)
        $percent += 15
    }

    Write-SpawnNewActionStep -Text 'Ordner Unterlagen anlegen' -Percent 70
    New-SpawnNewActionFolder -Path (Join-Path $target 'Unterlagen')

    if ($entwurf) {
        Write-SpawnNewActionStep -Text 'Entwurf vom Sprachmodell anfordern' -Percent 80
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }

        $system = 'Du unterstuetzt die Vorbereitung von Gremiensitzungen an einer Schule. Antworte auf Deutsch in Markdown, knapp und neutral. Erfinde keine Namen, Beschluesse oder Zahlen.'
        $user = "Gremium: $($value.gremium)`nThema: $($value.thema)`nDatum: $($value.datumText)`n`nSchlage eine Tagesordnung als Tabelle (TOP, Gegenstand, Ziel, Zeitbedarf) vor und nenne darunter Unterlagen, die vorab verteilt werden sollten, sowie offene Fragen zur Klaerung."
        try {
            $text = Invoke-SpawnNewActionChat -System $system -User $user
            [void](Write-SpawnNewActionDraft -Path (Join-Path $target 'Tagesordnung.Entwurf.md') -Text $text)
        }
        catch {
            Write-SpawnNewActionNote -Warning -Text ('Kein Entwurf: ' + $_.Exception.Message)
        }
    }

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Message ('Sitzung ' + $value.gremium + ' ' + $value.thema + ' angelegt.'))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
