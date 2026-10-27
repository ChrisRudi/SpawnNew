# SpawnNew.Command.ps1
# Version 1.0 | Verwaltungsbefehle im SpawnNew-Untermenue.
# Zweck  : 'configure' oeffnet das Konfigurationsfenster. 'install' und
#          'update' zeigen den konfigurierten Einzeiler mit Ziel und Rechten,
#          fuehren ihn erst nach ausdruecklicher Bestaetigung aus und melden
#          Befehl, Rueckgabewert und Ausgabe.
# Input  : -Command configure, install oder update.
# Output : Keine Ausgabe auf stdout. Protokoll in
#          %LOCALAPPDATA%\SpawnNew\Logs\command.log. Rueckgabewert des
#          Einzeilers, 0 bei Abbruch oder Konfiguration.
# Deps   : Windows PowerShell 5.1, die Module in diesem Verzeichnis.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('configure', 'install', 'update')][string]$Command,
    [string]$AppDirectory = ''
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot ist in Windows PowerShell 5.1 bei -File mit CmdletBinding in
# den param()-Vorgaben leer; so startet der Explorer dieses Skript.
if (-not $AppDirectory) { $AppDirectory = $PSScriptRoot }

$neutral = [System.IO.Path]::GetTempPath()
Set-Location -LiteralPath $neutral
[System.Environment]::CurrentDirectory = $neutral

$logDirectory = Join-Path (Join-Path $env:LOCALAPPDATA 'SpawnNew') 'Logs'
$logFile = Join-Path $logDirectory 'command.log'

function Write-SpawnNewCommandLog {
    <#
    .SYNOPSIS
    Haengt eine Zeile an das Protokoll an.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    try {
        if (-not [System.IO.Directory]::Exists($logDirectory)) { [void][System.IO.Directory]::CreateDirectory($logDirectory) }
        [System.IO.File]::AppendAllText($logFile, ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $Text + "`r`n"), (New-Object System.Text.UTF8Encoding $true))
    }
    catch {
        Write-Error -Message ('Protokoll nicht schreibbar: ' + $_.Exception.Message) -ErrorAction Continue
    }
}

Write-SpawnNewCommandLog ('--- Start  Command=' + $Command + '  AppDirectory=' + $AppDirectory)

try {
    # Global importieren: die Ereignis-Closures der Fenster sehen nur
    # Funktionen, die im globalen Bereich bekannt sind.
    foreach ($name in @('Config', 'Catalog', 'Resolve', 'Register', 'Secret', 'Llm', 'Settings', 'Input', 'Target', 'Form', 'SettingsForm')) {
        Import-Module (Join-Path $AppDirectory ('SpawnNew.' + $name + '.psm1')) -ErrorAction Stop
    }

    if ($Command -eq 'configure') {
        Show-SpawnNewSettingsDialog -AppDirectory $AppDirectory
        exit 0
    }

    $config = Get-SpawnNewConfig -AppDirectory $AppDirectory
    $plan = Get-SpawnNewCommandPlan -Config $config -Name $Command -AppDirectory $AppDirectory

    if ($null -eq $plan) {
        Show-SpawnNewMessage -Title 'Nicht konfiguriert' -Icon 'Warning' -Text "Für '$Command' ist kein Einzeiler konfiguriert."
        exit 1
    }

    if (-not (Show-SpawnNewTextDialog -Title ('SpawnNew - ' + $plan.Title) -Text $plan.Text -AcceptText 'Ausführen' -CancelText 'Abbrechen')) {
        Write-SpawnNewCommandLog '    abgebrochen'
        exit 0
    }

    $output = Join-Path $neutral ('spawnnew-' + $Command + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.log')
    Write-SpawnNewCommandLog ('    Ausfuehrung, Ausgabe in ' + $output)

    $process = Start-SpawnNewCommandLine -Command $plan.Command -LogFile $output -RequiresAdmin $plan.RequiresAdmin
    if ($null -eq $process) {
        Show-SpawnNewMessage -Title $plan.Title -Icon 'Warning' -Text 'Die Rechteabfrage wurde abgelehnt. Es wurde nichts geändert.'
        exit 0
    }

    Show-SpawnNewWaitWindow -Process $process -Text ($plan.Title + ' läuft ...')
    $code = $process.ExitCode
    Write-SpawnNewCommandLog ('    Rueckgabewert ' + $code)

    $report = Get-SpawnNewCommandReport -Command $plan.Command -ExitCode $code -LogFile $output
    [void](Show-SpawnNewTextDialog -Title ('SpawnNew - ' + $plan.Title) -Text $report -AcceptText 'OK' -CancelText 'Schließen')
    exit $code
}
catch {
    Write-SpawnNewCommandLog ('FEHLER: ' + $_.Exception.Message)
    Write-SpawnNewCommandLog ('        ' + [string]$_.ScriptStackTrace)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show(($_.Exception.Message + "`r`n`r`nEinzelheiten: " + $logFile), 'SpawnNew - Fehler')
    }
    catch {
        Write-SpawnNewCommandLog 'Der Fehler konnte nicht angezeigt werden.'
    }
    exit 1
}
