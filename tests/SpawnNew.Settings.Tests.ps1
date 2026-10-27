# tests/SpawnNew.Settings.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Settings.psm1.
# Zweck  : Uebersicht ohne Geheimniswerte, Benutzerkonfiguration,
#          Einzeiler mit Bestaetigungstext, Ausfuehrung mit Rueckgabewert und
#          Ausgabe. Deckt Abnahme 12, 13 und 19.

Import-SpawnNewHostModule -Name 'Config', 'Secret', 'Settings'

function Get-TestConfig {
    param([string]$Json)
    $Work = Get-SpawnNewTestDirectory
    $file = Add-SpawnNewTestFile -Path (Join-Path $Work 'default.json') -Content $Json
    return (Get-SpawnNewConfig -AppDirectory $Work -LayerPath @($file))
}

Add-SpawnNewTest 'Uebersicht nennt Endpunkte und Geheimnisse ohne Werte' {
    $secure = New-Object System.Security.SecureString
    foreach ($char in 'sk-sehr-geheim'.ToCharArray()) { $secure.AppendChar($char) }
    Set-SpawnNewSecret -Name 'web' -Value $secure

    $config = Get-TestConfig -Json '{ "llm": { "defaultEndpoint": "Web", "endpoints": [ { "name": "Lokal", "baseUrl": "http://localhost:11434/v1", "model": "llama3.2" }, { "name": "Web", "baseUrl": "https://api.example.org/v1", "model": "m", "secret": "web" } ] } }'
    $text = Get-SpawnNewSettingsReport -Config $config -AppDirectory 'C:\App'

    Confirm-SpawnNewMatch -Label 'lokal' -Actual $text -Pattern 'Lokal  lokal  http://localhost:11434/v1'
    Confirm-SpawnNewMatch -Label 'Vorgabe' -Actual $text -Pattern '\* Web  Web'
    Confirm-SpawnNewMatch -Label 'Geheimnis gespeichert' -Actual $text -Pattern 'Geheimnis web \(gespeichert\)'
    Confirm-SpawnNewCondition -Label 'kein Wert' -Condition ($text -notmatch 'sk-sehr-geheim')
}

Add-SpawnNewTest 'Benutzerkonfiguration wird angelegt, aber nie ueberschrieben' {
    $path = Initialize-SpawnNewUserSetting
    [void](ConvertFrom-Json ([System.IO.File]::ReadAllText($path)))
    Confirm-SpawnNewValue -Label 'Ort' -Actual $path -Expected (Join-Path (Join-Path $env:LOCALAPPDATA 'SpawnNew') 'spawnnew.settings.json')

    [System.IO.File]::WriteAllText($path, '{ "eigen": true }')
    [void](Initialize-SpawnNewUserSetting)
    Confirm-SpawnNewValue -Label 'unveraendert' -Actual ([System.IO.File]::ReadAllText($path)) -Expected '{ "eigen": true }'
}

Add-SpawnNewTest 'Einzeiler wird vollstaendig mit Ziel und Rechten gezeigt' {
    $config = Get-TestConfig -Json '{ "update": { "command": "powershell.exe -Command \"& { x }\"", "requiresAdmin": true } }'
    $plan = Get-SpawnNewCommandPlan -Config $config -Name 'update' -AppDirectory 'C:\App'

    Confirm-SpawnNewMatch -Label 'Befehl' -Actual $plan.Text -Pattern ([regex]::Escape('powershell.exe -Command "& { x }"'))
    Confirm-SpawnNewMatch -Label 'Ziel' -Actual $plan.Text -Pattern 'Ziel:   C:\\App'
    Confirm-SpawnNewMatch -Label 'Rechte' -Actual $plan.Text -Pattern 'Administratorrechte'
    Confirm-SpawnNewMatch -Label 'Erhalt' -Actual $plan.Text -Pattern 'Geheimnisse bleiben erhalten'
    Confirm-SpawnNewValue -Label 'ohne Installation' -Actual (Get-SpawnNewCommandPlan -Config $config -Name 'install' -AppDirectory 'C:\App') -Expected $null
}

Add-SpawnNewTest 'Mitgelieferte Einzeiler fuer Installation und Aktualisierung sind gleich' {
    $default = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'config') 'spawnnew.settings.default.json'
    $config = Get-SpawnNewConfig -AppDirectory (Get-SpawnNewTestDirectory) -LayerPath @($default)

    Confirm-SpawnNewValue -Label 'gleich' -Actual $config.Install.Command -Expected $config.Update.Command
    Confirm-SpawnNewMatch -Label 'TLS' -Actual $config.Update.Command -Pattern 'Tls12'
    Confirm-SpawnNewMatch -Label 'Benutzerumfang' -Actual $config.Update.Command -Pattern '-Scope CurrentUser'
}

Add-SpawnNewTest 'Einzeiler laeuft, Rueckgabewert und Ausgabe werden gemeldet' {
    $log = Join-Path (Get-SpawnNewTestDirectory) 'ausgabe.log'
    $command = 'echo Hallo Welt& exit /b 3'
    $process = Start-SpawnNewCommandLine -Command $command -LogFile $log
    $process.WaitForExit()

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $process.ExitCode -Expected 3
    $report = Get-SpawnNewCommandReport -Command $command -ExitCode $process.ExitCode -LogFile $log
    Confirm-SpawnNewMatch -Label 'Kopf' -Actual $report -Pattern '^Fehlgeschlagen\.'
    Confirm-SpawnNewMatch -Label 'Ausgabe' -Actual $report -Pattern 'Hallo Welt'
    Confirm-SpawnNewMatch -Label 'Befehl' -Actual $report -Pattern ([regex]::Escape($command))
}

Add-SpawnNewTest 'Anfuehrungszeichen im Einzeiler bleiben erhalten' {
    $log = Join-Path (Get-SpawnNewTestDirectory) 'zwei.log'
    $command = 'powershell.exe -NoProfile -Command "& { Write-Output (''A'' + ''B''); exit 0 }"'
    $process = Start-SpawnNewCommandLine -Command $command -LogFile $log
    $process.WaitForExit()

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $process.ExitCode -Expected 0
    Confirm-SpawnNewMatch -Label 'Ausgabe' -Actual (Get-SpawnNewCommandReport -Command $command -ExitCode 0 -LogFile $log) -Pattern '(?m)^AB\s*$'
}

Add-SpawnNewTest 'Fenstermodule und Einstiegspunkte laden ohne Fehler' {
    $hostDir = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Host'
    $probe = Add-SpawnNewTestFile -Path (Join-Path (Get-SpawnNewTestDirectory) 'probe.ps1') -Content (@(
            'param($HostDir)',
            '$ErrorActionPreference = ''Stop''',
            'foreach ($n in ''Config'',''Catalog'',''Resolve'',''Register'',''Secret'',''Llm'',''Settings'',''Input'',''Target'',''Runner'',''Form'',''Progress'',''SettingsForm'',''Action'',''Document'') { Import-Module (Join-Path $HostDir (''SpawnNew.'' + $n + ''.psm1'')) }',
            'foreach ($f in ''Show-SpawnNewActionForm'',''Invoke-SpawnNewProgressWindow'',''Show-SpawnNewSettingsDialog'',''Show-SpawnNewWaitWindow'',''Show-SpawnNewSecretInput'') { if (-not (Get-Command $f -ErrorAction SilentlyContinue)) { throw ''fehlt: '' + $f } }',
            'foreach ($s in ''SpawnNew.Host.ps1'',''SpawnNew.Command.ps1'',''SpawnNew.Catalog.ps1'',''SpawnNew.Diagnose.ps1'') { $t = $null; $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $HostDir $s), [ref]$t, [ref]$e); if (@($e).Count -gt 0) { throw ($s + '': '' + $e[0].Message) } }',
            'Write-Output ''geladen'''
        ) -join "`r`n")

    $shell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $ErrorActionPreference = 'Continue'
    $output = @(& $shell -NoProfile -ExecutionPolicy Bypass -File $probe -HostDir $hostDir 2>&1 | ForEach-Object { [string]$_ })

    Confirm-SpawnNewValue -Label 'Ausgabe' -Actual ($output -join ' | ') -Expected 'geladen'
}
