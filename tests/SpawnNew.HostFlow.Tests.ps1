# tests/SpawnNew.HostFlow.Tests.ps1
# Version 1.0 | Prueft den Ausfuehrungsprozess SpawnNew.Host.ps1 als Ganzes.
# Zweck  : Eine Installation wie vom Installer aufbauen, nur die beiden
#          Fenstermodule durch Stellvertreter ersetzen, die vorgegebene
#          Antworten liefern und jede Anzeige protokollieren. So laufen
#          Katalog, Nachpruefung, Voraussetzungen, Namensvorlage,
#          Vorschlagsphase, Kontextdatei und Aktion echt durch.

Import-SpawnNewHostModule -Name 'Config'

$script:FormStub = @'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Input.psm1')
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Target.psm1')
function Write-StubEvent { param($Kind, $Text) [System.IO.File]::AppendAllText($env:SPAWNNEW_TEST_LOG, (ConvertTo-Json -InputObject ([pscustomobject]@{ kind = $Kind; text = $Text }) -Compress) + "`r`n") }
function Get-StubPlan { return (ConvertFrom-Json ([System.IO.File]::ReadAllText($env:SPAWNNEW_TEST_PLAN, [System.Text.Encoding]::UTF8))) }
function Show-SpawnNewActionForm {
    param($Action, [object[]]$Field, [string]$BasePath)
    $plan = Get-StubPlan
    $raw = @{}
    foreach ($p in $plan.values.PSObject.Properties) { $raw[$p.Name] = [string]$p.Value }
    foreach ($f in $Field) { if (-not $raw.ContainsKey($f.Name)) { $raw[$f.Name] = Get-SpawnNewFieldDefault -Field $f } }
    Write-StubEvent 'form' (($Field | ForEach-Object { $_.Name + '=' + (@($_.Choices) -join '/') }) -join ';')
    $check = Test-SpawnNewFieldValueSet -Field $Field -Value $raw
    if (-not $check.Valid) { Write-StubEvent 'invalid' ($check.Errors -join ' | '); return [pscustomobject]@{ Confirmed = $false; BasePath = $BasePath; Value = @{} } }
    return [pscustomobject]@{ Confirmed = $true; BasePath = $BasePath; Value = $check.Value }
}
function Show-SpawnNewSummary { param([string]$Text) Write-StubEvent 'summary' $Text; return [bool](Get-StubPlan).summary }
function Show-SpawnNewConflictChoice { param($TargetPath, $FreeName) Write-StubEvent 'conflict' $TargetPath; return [string](Get-StubPlan).conflict }
function Show-SpawnNewMessage { param($Title, $Text, $Icon) Write-StubEvent 'message' ($Title + ': ' + $Text) }
function Show-SpawnNewConfirmation { param($Title, $Text) Write-StubEvent 'confirm' $Title; return $false }
'@

$script:ProgressStub = @'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Runner.psm1')
function Invoke-SpawnNewProgressWindow {
    param($Run, $Action, $Process, [switch]$AutoClose)
    $Process.WaitForExit()
    $progress = @((Read-SpawnNewProgress -Path $Run.ProgressFile -Offset 0).Entry)
    return (Get-SpawnNewRunStatus -ExitCode $Process.ExitCode -Result (Read-SpawnNewResult -Run $Run) -Progress $progress)
}
function Get-SpawnNewResultReport { param($Status) return ($Status.Status + ' ' + $Status.Message) }
'@

function Initialize-TestInstallation {
    param([string]$LlmUrl)

    $Work = Get-SpawnNewTestDirectory
    $repo = Split-Path -Parent $PSScriptRoot
    $app = Join-Path $Work 'app'
    [void](New-Item -ItemType Directory -Path (Join-Path $app 'Actions') -Force)
    Copy-Item -Path (Join-Path $repo 'src\Host\*') -Destination $app -Recurse
    Copy-Item -Path (Join-Path $repo 'src\Actions\*') -Destination (Join-Path $app 'Actions') -Recurse
    Copy-Item -LiteralPath (Join-Path $repo 'config\spawnnew.settings.default.json') -Destination $app

    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText((Join-Path $app 'SpawnNew.Form.psm1'), $script:FormStub, $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $app 'SpawnNew.Progress.psm1'), $script:ProgressStub, $utf8Bom)

    if ($LlmUrl) {
        $settings = '{ "llm": { "defaultEndpoint": "Lokal", "endpoints": [ { "name": "Lokal", "baseUrl": "' + $LlmUrl + '", "model": "testmodell", "timeoutSeconds": 20 } ] } }'
        [void](Add-SpawnNewTestFile -Path (Join-Path (Join-Path $env:LOCALAPPDATA 'SpawnNew') 'spawnnew.settings.json') -Content $settings)
    }
    return $app
}

function Invoke-TestHost {
    param([string]$App, [string]$ActionId, [hashtable]$Values, [bool]$Summary = $true, [string]$Conflict = 'cancel')

    $Work = Get-SpawnNewTestDirectory
    $base = Join-Path $Work 'Basis'
    [void](New-Item -ItemType Directory -Path $base -Force)
    $plan = Add-SpawnNewTestFile -Path (Join-Path $Work 'plan.json') -Content (ConvertTo-Json -InputObject ([pscustomobject]@{ values = [pscustomobject]$Values; summary = $Summary; conflict = $Conflict }) -Depth 4)
    $log = Join-Path $Work 'events.jsonl'

    # Eigener Prozess mit Zeitlimit: zeigt der Host wider Erwarten ein echtes
    # Fenster, wird er beendet, statt den Testlauf zu blockieren.
    $env:SPAWNNEW_TEST_PLAN = $plan
    $env:SPAWNNEW_TEST_LOG = $log
    try {
        $shell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $App 'SpawnNew.Host.ps1') + '" -ActionId ' + $ActionId + ' -ExplorerPath "' + $base + '"'
        $process = Start-Process -FilePath $shell -ArgumentList $arguments -PassThru -WindowStyle Hidden
        if (-not $process.WaitForExit(90000)) {
            Stop-Process -Id $process.Id -Force
            throw 'Der Host hat nach 90 s nicht geendet; vermutlich wartet ein echtes Fenster.'
        }
        $code = $process.ExitCode
    }
    finally {
        Remove-Item Env:\SPAWNNEW_TEST_PLAN, Env:\SPAWNNEW_TEST_LOG -ErrorAction SilentlyContinue
    }

    $events = @()
    if ([System.IO.File]::Exists($log)) { $events = @([System.IO.File]::ReadAllLines($log) | Where-Object { $_ } | ForEach-Object { ConvertFrom-Json $_ }) }
    $hostLog = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'SpawnNew') 'Logs') 'host.log'
    $hostText = if ([System.IO.File]::Exists($hostLog)) { [System.IO.File]::ReadAllText($hostLog) } else { '' }

    return [pscustomobject]@{ ExitCode = $code; Base = $base; Events = $events; HostLog = $hostText }
}

function Get-EventText {
    # Alle Anzeigen einer Art als ein Text; ein einzelnes Element wuerde
    # PowerShell sonst zur Zeichenkette auspacken.
    param($Run, [string]$Kind)
    return (@($Run.Events | Where-Object { $_.kind -eq $Kind } | ForEach-Object { [string]$_.text }) -join "`n---`n")
}

function Get-EventCount {
    param($Run, [string]$Kind)
    return @($Run.Events | Where-Object { $_.kind -eq $Kind }).Count
}

Add-SpawnNewTest 'Werkstaettenprotokoll laeuft durch den Host mit Namensvorlage' {
    $app = Initialize-TestInstallation
    $run = Invoke-TestHost -App $app -ActionId 'spawnnew.workshoplog' -Values @{ klasse = 'E1a'; thema = 'Löten'; datum = '26.10.2026'; format = 'Word'; entwurf = 'False' }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 0
    $target = Join-Path $run.Base '2026-10-26 E1a Löten'
    Confirm-SpawnNewCondition -Label 'Ordner aus Vorlage' -Condition (Test-Path -LiteralPath (Join-Path $target 'Protokoll.docx'))
    $summary = (Get-EventText -Run $run -Kind 'summary')
    Confirm-SpawnNewMatch -Label 'Zusammenfassung' -Actual $summary -Pattern 'Klasse: E1a'
    Confirm-SpawnNewMatch -Label 'Ja/Nein' -Actual $summary -Pattern 'Entwurf vom Sprachmodell: Nein'
}

Add-SpawnNewTest 'Abbrechen in der Zusammenfassung legt nichts an' {
    $app = Initialize-TestInstallation
    $run = Invoke-TestHost -App $app -ActionId 'spawnnew.pstool' -Values @{ name = 'Get-Test'; beschreibung = 'x'; konfiguration = 'True' } -Summary $false

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 0
    Confirm-SpawnNewCondition -Label 'nichts angelegt' -Condition (-not (Test-Path -LiteralPath (Join-Path $run.Base 'Get-Test')))
}

Add-SpawnNewTest 'Vorschlag erscheint in der Zusammenfassung und wird genau so angelegt' {
    $server = Start-SpawnNewFakeLlm -Reply '["01 Idee", "02 Bau/Teile"]'
    try {
        $app = Initialize-TestInstallation -LlmUrl $server.Url
        $run = Invoke-TestHost -App $app -ActionId 'spawnnew.structurefromtext' -Values @{ name = 'Robo'; beschreibung = 'Roboterbau' }
    }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 0
    Confirm-SpawnNewMatch -Label 'Vorschlag in Zusammenfassung' -Actual (Get-EventText -Run $run -Kind 'summary') -Pattern "Vorschlag des Modells[\s\S]*- 02 Bau[\s\S]*  - Teile"
    Confirm-SpawnNewCondition -Label 'angelegt' -Condition (Test-Path -LiteralPath (Join-Path $run.Base 'Robo\02 Bau\Teile') -PathType Container)

    $chats = @($server.Requests | Where-Object { $_.Path -like '*chat/completions' })
    Confirm-SpawnNewValue -Label 'genau ein Modellaufruf' -Actual $chats.Count -Expected 1
}

Add-SpawnNewTest 'Vorschlag ohne Bestaetigung legt nichts an' {
    $server = Start-SpawnNewFakeLlm -Reply '["A"]'
    try {
        $app = Initialize-TestInstallation -LlmUrl $server.Url
        $run = Invoke-TestHost -App $app -ActionId 'spawnnew.structurefromtext' -Values @{ name = 'Robo'; beschreibung = 'x' } -Summary $false
    }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewCondition -Label 'nichts angelegt' -Condition (-not (Test-Path -LiteralPath (Join-Path $run.Base 'Robo')))
}

Add-SpawnNewTest 'Nicht erreichbarer Endpunkt verhindert den Start mit Meldung' {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()
    $app = Initialize-TestInstallation -LlmUrl ('http://127.0.0.1:' + $port + '/v1')
    $run = Invoke-TestHost -App $app -ActionId 'spawnnew.documentfolder' -Values @{ zweck = '' }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 1
    Confirm-SpawnNewMatch -Label 'Meldung' -Actual (Get-EventText -Run $run -Kind 'message') -Pattern 'Voraussetzungen fehlen[\s\S]*nicht erreichbar'
    Confirm-SpawnNewValue -Label 'kein Formular' -Actual (Get-EventCount -Run $run -Kind 'form') -Expected 0
}

Add-SpawnNewTest 'Endpunktfeld zeigt die konfigurierten Endpunkte' {
    $server = Start-SpawnNewFakeLlm -Reply 'Zusammenfassung'
    try {
        $app = Initialize-TestInstallation -LlmUrl $server.Url
        $source = Add-SpawnNewTestFile -Path (Join-Path (Get-SpawnNewTestDirectory) 'Basis\Notiz.txt') -Content 'Inhalt'
        $run = Invoke-TestHost -App $app -ActionId 'spawnnew.summarizefile' -Values @{ datei = $source; umfang = 'Kurz' }
    }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 0
    Confirm-SpawnNewMatch -Label 'Auswahl' -Actual (Get-EventText -Run $run -Kind 'form') -Pattern 'modell=Lokal'
    Confirm-SpawnNewCondition -Label 'Entwurf' -Condition (Test-Path -LiteralPath (Join-Path $run.Base 'Notiz.Zusammenfassung.Entwurf.md'))
}

Add-SpawnNewTest 'Vorhandener Zielordner fragt nach und Abbrechen aendert nichts' {
    $app = Initialize-TestInstallation
    $Work = Get-SpawnNewTestDirectory
    [void](Add-SpawnNewTestFile -Path (Join-Path $Work 'Basis\Projekt\alt.txt') -Content 'alt')
    $run = Invoke-TestHost -App $app -ActionId 'spawnnew.folderstructure' -Values @{ name = 'Projekt'; vorlage = 'Minimal'; zweck = '' } -Conflict 'cancel'

    Confirm-SpawnNewValue -Label 'Konfliktfrage' -Actual (Get-EventCount -Run $run -Kind 'conflict') -Expected 1
    Confirm-SpawnNewCondition -Label 'nichts angelegt' -Condition (-not (Test-Path -LiteralPath (Join-Path $Work 'Basis\Projekt\Dokumente')))
}

Add-SpawnNewTest 'Host findet sein Programmverzeichnis auch beim Start mit -File' {
    $app = Initialize-TestInstallation
    $run = Invoke-TestHost -App $app -ActionId 'spawnnew.gibtesnicht' -Values @{}

    Confirm-SpawnNewMatch -Label 'Programmverzeichnis' -Actual $run.HostLog -Pattern ('AppDirectory=' + [regex]::Escape($app) + '\s')
    Confirm-SpawnNewCondition -Label 'kein Fehler' -Condition ($run.HostLog -notmatch 'FEHLER')
}

Add-SpawnNewTest 'Unbekannte Aktion meldet sich verstaendlich' {
    $app = Initialize-TestInstallation
    $run = Invoke-TestHost -App $app -ActionId 'spawnnew.gibtesnicht' -Values @{}

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 1
    Confirm-SpawnNewMatch -Label 'Meldung' -Actual (Get-EventText -Run $run -Kind 'message') -Pattern 'nicht mehr vorhanden'
}
