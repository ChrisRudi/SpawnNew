# Get-SpawnProposal.ps1
# Version 1.0 | Vorschlagsskript der Aktion 17.
# Zweck  : Das Sprachmodell nach einer Ordnerstruktur fragen, die Antwort
#          pruefen und als Vorschlag ablegen. Legt nichts an; der Vorschlag
#          erscheint in der Zusammenfassung und wird erst nach "Erstellen"
#          von Invoke-SpawnAction.ps1 umgesetzt.
# Input  : -ContextFile wie bei der Aktion; proposalFile nennt das Ziel.
# Output : proposalFile mit text und data.folders, Ergebnis nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, SpawnNew.Action.psm1, StrukturPruefung.psm1.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$ContextFile)

$ErrorActionPreference = 'Stop'

$raw = ConvertFrom-Json ([System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8))
$helper = Join-Path ([string]$raw.appDirectory) 'SpawnNew.Action.psm1'
if (-not ([string]$raw.appDirectory) -or -not [System.IO.File]::Exists($helper)) {
    [System.IO.File]::WriteAllText($raw.resultFile, '{"schemaVersion":1,"status":"failed","message":"Kein Vorschlag.","created":[],"error":{"step":"Vorbereiten","reason":"SpawnNew.Action.psm1 fehlt; SpawnNew bitte neu installieren.","details":""}}')
    exit 1
}
Import-Module $helper
Import-Module (Join-Path $PSScriptRoot 'StrukturPruefung.psm1')
$context = Initialize-SpawnNewAction -ContextFile $ContextFile

try {
    Write-SpawnNewActionStep -Text 'Voraussetzungen pruefen' -Percent 5
    $problem = Assert-SpawnNewActionEndpoint
    if ($problem) { exit (Complete-SpawnNewActionFailed -Reason $problem) }
    if (-not [string]$context.proposalFile) { exit (Complete-SpawnNewActionFailed -Reason 'Der Kontext nennt keine Vorschlagsdatei.') }

    Write-SpawnNewActionStep -Text ('Sprachmodell ' + $context.llm.model + ' fragen') -Percent 20
    $system = 'Du planst Ordnerstrukturen fuer Projekte unter Windows. Antworte ausschliesslich mit einem JSON-Array relativer Ordnerpfade mit / als Trenner, ohne Erklaerung, hoechstens 40 Eintraege und 4 Ebenen. Deutsche Ordnernamen, kurze und eindeutige Namen, nummerierte Hauptordner sind willkommen.'
    $user = 'Projektname: ' + (Get-SpawnNewActionField -Name 'name') + "`nBeschreibung:`n" + (Get-SpawnNewActionField -Name 'beschreibung')
    $answer = Invoke-SpawnNewActionChat -System $system -User $user

    Write-SpawnNewActionStep -Text 'Vorschlag pruefen' -Percent 80
    $check = ConvertTo-StrukturListe -Data (ConvertFrom-SpawnNewModelJson -Text $answer)
    if ($check.Folders.Count -eq 0) {
        exit (Complete-SpawnNewActionFailed -Reason 'Die Antwort des Modells enthält keine verwertbare Ordnerstruktur.' -Details $answer)
    }

    $text = Get-StrukturBaum -Folders $check.Folders
    if ($check.Dropped -gt 0) { $text += "`r`n`r`n(" + $check.Dropped + ' ungültige oder überzählige Einträge der Modellantwort wurden verworfen.)' }

    $proposal = [pscustomobject]@{
        text = $text
        data = [pscustomobject]@{ folders = $check.Folders; model = [string]$context.llm.model; endpoint = [string]$context.llm.name }
    }
    [System.IO.File]::WriteAllText($context.proposalFile, (ConvertTo-Json -InputObject $proposal -Depth 5), (New-Object System.Text.UTF8Encoding $false))

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Status 'success' -Message ($check.Folders.Count.ToString() + ' Ordner vorgeschlagen.'))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
