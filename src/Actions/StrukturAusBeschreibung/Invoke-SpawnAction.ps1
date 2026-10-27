# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 17: Ordnerstruktur aus Beschreibung.
# Zweck  : Die in der Zusammenfassung gezeigte und bestaetigte Struktur
#          anlegen. Fragt das Modell nicht erneut; angelegt wird genau der
#          Vorschlag aus proposalFile, nach erneuter Pruefung jedes Pfades.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: name, beschreibung. proposalFile aus Get-SpawnProposal.ps1.
# Output : Fortschritt, Ergebnis und Rueckgabewert nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, SpawnNew.Action.psm1, StrukturPruefung.psm1.

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
Import-Module (Join-Path $PSScriptRoot 'StrukturPruefung.psm1')
$context = Initialize-SpawnNewAction -ContextFile $ContextFile

try {
    $target = [string]$context.targetPath

    Write-SpawnNewActionStep -Text 'Vorschlag lesen' -Percent 5
    $file = [string]$context.proposalFile
    if (-not $file -or -not [System.IO.File]::Exists($file)) {
        exit (Complete-SpawnNewActionFailed -Reason 'Es liegt kein bestätigter Vorschlag vor.')
    }
    $proposal = ConvertFrom-Json ([System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8))
    $check = ConvertTo-StrukturListe -Data $proposal.data.folders
    if ($check.Folders.Count -eq 0 -or $check.Dropped -gt 0) {
        exit (Complete-SpawnNewActionFailed -Reason 'Der Vorschlag ist nicht mehr gültig.')
    }

    Write-SpawnNewActionStep -Text 'Zielordner anlegen' -Percent 15
    New-SpawnNewActionFolder -Path $target

    Write-SpawnNewActionStep -Text ($check.Folders.Count.ToString() + ' Ordner anlegen') -Percent 30
    $index = 0
    foreach ($folder in $check.Folders) {
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
        New-SpawnNewActionFolder -Path (Join-Path $target ($folder.Replace('/', '\')))
        $index++
    }

    Write-SpawnNewActionStep -Text 'README.md anlegen' -Percent 85
    $text = @(
        ('# ' + (Get-SpawnNewActionField -Name 'name')),
        '',
        (Get-SpawnNewActionField -Name 'beschreibung'),
        '',
        '## Struktur',
        '',
        (Get-StrukturBaum -Folders $check.Folders),
        '',
        ('Angelegt am ' + (Get-Date -Format 'dd.MM.yyyy') + ' mit SpawnNew. Die Struktur hat das Sprachmodell ' + $proposal.data.model + ' vorgeschlagen; sie wurde vor dem Anlegen bestätigt.')
    ) -join "`r`n"
    [void](Write-SpawnNewActionText -Path (Join-Path $target 'README.md') -Text ($text + "`r`n"))

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Message ('Struktur mit ' + $index + ' Ordnern angelegt.'))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
