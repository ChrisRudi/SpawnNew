# SpawnNew.Settings.psm1
# Version 1.0 | Verwaltungsbefehle ohne Fensterdarstellung.
# Zweck  : Uebersicht ueber Konfiguration, Quellen, KI-Endpunkte und
#          Geheimnisse; Benutzerkonfiguration anlegen; Menue abgleichen;
#          Installations- und Aktualisierungseinzeiler vorbereiten, starten
#          und auswerten. Die Fenster dazu stehen in SpawnNew.SettingsForm.psm1.
# Input  : Konfiguration aus Get-SpawnNewConfig, Programmverzeichnis.
# Output : Texte, Pfade und Ergebnisobjekte; schreibt nur Benutzerdaten und
#          die Menueregistrierung.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config/Catalog/Resolve/Register/
#          Secret/Llm.psm1.

Set-StrictMode -Version 2.0

foreach ($name in @('Config', 'Catalog', 'Resolve', 'Register', 'Secret', 'Llm')) {
    Import-Module (Join-Path $PSScriptRoot ('SpawnNew.' + $name + '.psm1'))
}

function Get-SpawnNewSettingsReport {
    <#
    .SYNOPSIS
    Lesbare Uebersicht der wirksamen Einstellungen. Enthaelt nie den Wert
    eines Geheimnisses.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('Programmverzeichnis: ' + $AppDirectory)
    $mode = if (Test-SpawnNewPortable -AppDirectory $AppDirectory) { 'Cloudordner, auf allen Rechnern gleich' } else { 'lokal' }
    [void]$lines.Add('Datenverzeichnis:    ' + (Get-SpawnNewDataDirectory -AppDirectory $AppDirectory) + '  (' + $mode + ')')
    [void]$lines.Add('Nur dieser Rechner:  ' + (Get-SpawnNewLocalDirectory) + '  (Geheimnisse, Cache, Protokolle)')
    [void]$lines.Add('')
    [void]$lines.Add('Konfigurationsschichten, die erste gewinnt:')
    foreach ($layer in @($Config.LayerPath)) {
        $mark = if ([System.IO.File]::Exists($layer)) { 'vorhanden' } else { 'fehlt    ' }
        [void]$lines.Add('  [' + $mark + '] ' + $layer)
    }

    [void]$lines.Add('')
    [void]$lines.Add('Aktionsquellen in Prioritaetsreihenfolge:')
    foreach ($source in @($Config.Sources)) {
        $mark = if ([System.IO.Directory]::Exists($source.Path)) { 'erreichbar' } else { 'fehlt     ' }
        [void]$lines.Add('  [' + $mark + '] ' + $source.Order + ' ' + $source.Scope + '  ' + $source.Name + '  ' + $source.Path)
    }

    [void]$lines.Add('')
    [void]$lines.Add('KI-Endpunkte:')
    $endpoints = @($Config.Llm.Endpoints)
    if ($endpoints.Count -eq 0) { [void]$lines.Add('  keiner konfiguriert') }
    $default = Get-SpawnNewEndpoint -Config $Config
    foreach ($endpoint in $endpoints) {
        $flag = if ($null -ne $default -and $endpoint.Name -eq $default.Name) { '*' } else { ' ' }
        $kind = if (Test-SpawnNewLocalUri -Uri $endpoint.BaseUrl) { 'lokal' } else { 'Web' }
        $line = '  ' + $flag + ' ' + $endpoint.Name + '  ' + $kind + '  ' + $endpoint.BaseUrl + '  Modell ' + $endpoint.Model + '  Zeitlimit ' + $endpoint.TimeoutSeconds + ' s'
        if ($endpoint.Secret.Length -gt 0) {
            $state = if (Test-SpawnNewSecret -Name $endpoint.Secret) { 'gespeichert' } else { 'FEHLT' }
            $line += '  Geheimnis ' + $endpoint.Secret + ' (' + $state + ')'
        }
        [void]$lines.Add($line)
    }
    if ($endpoints.Count -gt 0) { [void]$lines.Add('  * = Vorgabe') }

    [void]$lines.Add('')
    $names = @(Get-SpawnNewSecretName)
    [void]$lines.Add('Gespeicherte Geheimnisse: ' + $(if ($names.Count -gt 0) { $names -join ', ' } else { 'keine' }))

    $problems = @($Config.Diagnostics | Where-Object { $_.Severity -ne 'info' })
    if ($problems.Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('Hinweise:')
        foreach ($entry in $problems) { [void]$lines.Add('  [' + $entry.Severity + '] ' + $entry.Message) }
    }

    return ($lines.ToArray() -join "`r`n")
}

function Initialize-SpawnNewUserSetting {
    <#
    .SYNOPSIS
    Legt die Benutzerkonfiguration an, falls sie fehlt, und liefert ihren
    Pfad. Eine vorhandene Datei bleibt unveraendert.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()

    $path = Join-Path (Get-SpawnNewDataDirectory) 'spawnnew.settings.json'
    if ([System.IO.File]::Exists($path)) { return $path }
    if (-not $PSCmdlet.ShouldProcess($path, 'Benutzerkonfiguration anlegen')) { return $path }

    $skeleton = @(
        '{',
        '  "schemaVersion": 1,',
        '  "comment": "Eigene Einstellungen. Werte hier gehen der mitgelieferten Konfiguration vor. Beispiele fuer Endpunkte: LM Studio http://localhost:1234/v1; Webdienst mit \"secret\": \"name\" und dem unter SpawnNew konfigurieren gespeicherten Schluessel.",',
        '  "sources": [],',
        '  "llm": {',
        '    "endpoints": []',
        '  }',
        '}'
    ) -join "`r`n"

    $directory = Split-Path -Parent $path
    if (-not [System.IO.Directory]::Exists($directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
    [System.IO.File]::WriteAllText($path, $skeleton + "`r`n", (New-Object System.Text.UTF8Encoding $false))
    return $path
}

function Update-SpawnNewMenu {
    <#
    .SYNOPSIS
    Gleicht das Kontextmenue mit dem aktuellen Katalog ab.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    $catalog = Get-SpawnNewCatalog -Config $Config
    $scope   = Get-SpawnNewInstallScope -AppDirectory $AppDirectory
    $root    = Get-SpawnNewRegistryRoot -Scope $scope
    $entries = Get-SpawnNewRegistryEntry -Action $catalog.Actions -AppDirectory $AppDirectory -Root $root -Command (Get-SpawnNewMenuCommand -Config $Config)
    $count   = @($catalog.Actions).Count

    if (Test-SpawnNewRegistration -Entry $entries -Root $root) {
        return [pscustomobject]@{ Rewritten = $false; Count = $count; Message = "Das Menü ist aktuell ($count Aktionen)." }
    }
    if (-not $PSCmdlet.ShouldProcess($root, 'Menue abgleichen')) {
        return [pscustomobject]@{ Rewritten = $false; Count = $count; Message = 'Nicht ausgeführt.' }
    }

    try {
        [void](Sync-SpawnNewRegistration -Entry $entries -Root $root)
    }
    catch {
        return [pscustomobject]@{ Rewritten = $false; Count = $count; Message = ('Das Menü konnte nicht geschrieben werden: ' + $_.Exception.Message + ' Bei einer Installation für alle Benutzer sind Administratorrechte nötig.') }
    }
    return [pscustomobject]@{ Rewritten = $true; Count = $count; Message = "Das Menü wurde neu geschrieben ($count Aktionen)." }
}

function Get-SpawnNewCommandPlan {
    <#
    .SYNOPSIS
    Was ein Verwaltungseinzeiler tut, vollstaendig fuer die Bestaetigung.
    Liefert $null, wenn er nicht konfiguriert ist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][ValidateSet('install', 'update')][string]$Name,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    $entry = if ($Name -eq 'install') { $Config.Install } else { $Config.Update }
    if ($null -eq $entry) { return $null }

    $title = if ($Name -eq 'install') { 'SpawnNew installieren' } else { 'SpawnNew aktualisieren' }
    $rights = if ($entry.RequiresAdmin) { 'Administratorrechte; Windows fragt vor dem Start nach.' } else { 'normale Benutzerrechte' }

    $text = @(
        ($title + ' führt diesen Befehl aus:'),
        '',
        $entry.Command,
        '',
        ('Ziel:   ' + $AppDirectory),
        ('Rechte: ' + $rights),
        '',
        'Ersetzt werden nur die Programmdateien unter App und die Menüregistrierung.',
        'Einstellungen, persönliche Aktionen, eigene Vorlagen und Geheimnisse bleiben erhalten.'
    ) -join "`r`n"

    return [pscustomobject]@{ Title = $title; Command = $entry.Command; RequiresAdmin = [bool]$entry.RequiresAdmin; Text = $text }
}

function Get-SpawnNewCommandArgument {
    <#
    .SYNOPSIS
    Argumente fuer cmd.exe: den Befehl unveraendert ausfuehren und alle
    Ausgaben in eine Protokolldatei leiten.
    .DESCRIPTION
    Mit /s entfernt cmd.exe nur das aeussere Anfuehrungszeichenpaar; die
    Anfuehrungszeichen im Befehl selbst bleiben erhalten. Die Klammer sorgt
    dafuer, dass die Umleitung fuer den ganzen Befehl gilt und nicht nur fuer
    dessen letzten Teil nach einem '&'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$LogFile
    )

    return ('/d /s /c "(' + $Command + ') > "' + $LogFile + '" 2>&1"')
}

function Start-SpawnNewCommandLine {
    <#
    .SYNOPSIS
    Startet einen Einzeiler verborgen. Liefert $null, wenn die
    Rechteabfrage abgelehnt wurde.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$LogFile,
        [bool]$RequiresAdmin = $false
    )

    if (-not $PSCmdlet.ShouldProcess($Command, 'Befehl ausfuehren')) { return $null }

    $parameter = @{
        FilePath         = $env:ComSpec
        ArgumentList     = (Get-SpawnNewCommandArgument -Command $Command -LogFile $LogFile)
        PassThru         = $true
        WindowStyle      = 'Hidden'
        WorkingDirectory = [System.IO.Path]::GetTempPath()
    }
    if ($RequiresAdmin) { $parameter['Verb'] = 'RunAs' }

    try { return (Start-Process @parameter) }
    catch [System.ComponentModel.Win32Exception] { return $null }
}

function Get-SpawnNewCommandReport {
    <#
    .SYNOPSIS
    Ergebnistext eines Einzeilers mit Befehl, Rueckgabewert und Ausgabe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$LogFile
    )

    $output = ''
    if ([System.IO.File]::Exists($LogFile)) {
        $raw = [System.IO.File]::ReadAllBytes($LogFile)
        $output = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString($raw)
        if ($output.Length -gt 6000) { $output = '...' + $output.Substring($output.Length - 6000) }
    }

    $head = if ($ExitCode -eq 0) { 'Erfolgreich abgeschlossen.' } else { 'Fehlgeschlagen.' }
    return (@($head, ('Rückgabewert: ' + $ExitCode), '', 'Befehl:', $Command, '', 'Ausgabe:', $output.Trim()) -join "`r`n")
}

Export-ModuleMember -Function Get-SpawnNewSettingsReport, Initialize-SpawnNewUserSetting, Update-SpawnNewMenu, Get-SpawnNewCommandPlan, Get-SpawnNewCommandArgument, Start-SpawnNewCommandLine, Get-SpawnNewCommandReport
