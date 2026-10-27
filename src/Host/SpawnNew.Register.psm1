# SpawnNew.Register.psm1
# Version 1.1 | Registrierung des Kontextmenues.
# Zweck  : Die Registrierungseintraege fuer das SpawnNew-Untermenue aus dem
#          Katalog bilden, schreiben und entfernen. Aufbau siehe
#          docs/Dateiliste.md Abschnitt 13.
#          Anzeigetexte stehen in MUIVerb, also in benannten Werten. Nur die
#          Befehlszeile muss der unbenannte Standardwert ihres Schluessels
#          sein; der wird mit Set-Item geschrieben. New-ItemProperty mit dem
#          Namen '(default)' legt dagegen einen Wert an, der woertlich
#          '(default)' heisst, und den liest die Shell nicht.
# Input  : Aktionen aus Get-SpawnNewCatalog, Programmverzeichnis, Umfang.
# Output : Get-SpawnNewRegistryEntry liefert die Eintraege als Daten, damit
#          sie ohne Schreibzugriff pruefbar sind.
# Deps   : Windows PowerShell 5.1.

Set-StrictMode -Version 2.0

$script:MenuName    = 'SpawnNew'
$script:MenuSubPath = 'Directory\Background\shell'

function Get-SpawnNewRegistryRoot {
    <#
    .SYNOPSIS
    Wurzel der Klassenregistrierung fuer den gewaehlten Installationsumfang.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][ValidateSet('CurrentUser', 'AllUsers')][string]$Scope)

    if ($Scope -eq 'AllUsers') { return 'HKLM:\Software\Classes' }
    return 'HKCU:\Software\Classes'
}

function Get-SpawnNewMenuKey {
    <#
    .SYNOPSIS
    Schluessel des SpawnNew-Untermenues.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Root)

    return ($Root.TrimEnd('\') + '\' + $script:MenuSubPath + '\' + $script:MenuName)
}

function Get-SpawnNewKeyName {
    <#
    .SYNOPSIS
    Schluesselname einer Aktion mit Zahlenpraefix.
    .DESCRIPTION
    Unterschluessel werden alphabetisch sortiert, darum der Praefix. Zeichen
    ausserhalb von Buchstaben, Ziffern, Punkt, Strich und Unterstrich werden
    ersetzt, damit automatisch erzeugte IDs mit Doppelpunkt nutzbar sind.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$Id
    )

    return ('{0:D2}_{1}' -f $Index, ($Id -replace '[^A-Za-z0-9._-]', '_'))
}

function Get-SpawnNewActionCommand {
    <#
    .SYNOPSIS
    Befehlszeile, die der Explorer fuer eine Aktion aufruft.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$AppDirectory,
        [Parameter(Mandatory)][string]$ActionId
    )

    $script = $AppDirectory.TrimEnd('\') + '\SpawnNew.Host.ps1'
    return ('powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass ' +
        '-File "' + $script + '" -ActionId "' + $ActionId + '" -ExplorerPath "%V"')
}

function Get-SpawnNewManagementCommand {
    <#
    .SYNOPSIS
    Befehlszeile eines Verwaltungsbefehls im Untermenue.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$AppDirectory,
        [Parameter(Mandatory)][ValidateSet('configure', 'update', 'install')][string]$Name
    )

    $script = $AppDirectory.TrimEnd('\') + '\SpawnNew.Command.ps1'
    return ('powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass ' +
        '-File "' + $script + '" -Command ' + $Name)
}

function Get-SpawnNewMenuCommand {
    <#
    .SYNOPSIS
    Verwaltungsbefehle fuer das Untermenue. Konfigurieren gibt es immer,
    Aktualisieren und Installieren nur mit konfiguriertem Einzeiler.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)]$Config)

    $commands = New-Object System.Collections.ArrayList
    [void]$commands.Add([pscustomobject]@{ Name = 'configure'; Title = 'SpawnNew konfigurieren' })
    if ($null -ne $Config.Update)  { [void]$commands.Add([pscustomobject]@{ Name = 'update'; Title = 'SpawnNew aktualisieren' }) }
    if ($null -ne $Config.Install) { [void]$commands.Add([pscustomobject]@{ Name = 'install'; Title = 'SpawnNew installieren' }) }
    return [object[]]$commands.ToArray()
}

function Get-SpawnNewRegistryEntry {
    <#
    .SYNOPSIS
    Alle Eintraege des Untermenues als Datenliste.
    .DESCRIPTION
    Erst die Aktionen, dann durch eine Trennlinie abgesetzt die
    Verwaltungsbefehle. CommandFlags 0x20 setzt die Trennlinie davor; der
    Schluesselname 'zz' sortiert die Befehle hinter alle Aktionen.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Action,
        [Parameter(Mandatory)][string]$AppDirectory,
        [Parameter(Mandatory)][string]$Root,
        [AllowEmptyCollection()][object[]]$Command = @()
    )

    $menu    = Get-SpawnNewMenuKey -Root $Root
    $entries = New-Object System.Collections.ArrayList

    [void]$entries.Add([pscustomobject]@{ Path = $menu; Kind = 'value'; Name = 'MUIVerb'; Value = $script:MenuName })
    [void]$entries.Add([pscustomobject]@{ Path = $menu; Kind = 'value'; Name = 'SubCommands'; Value = '' })

    $index = 1
    # Im Menue nach Titel sortiert; die Katalogreihenfolge folgt den
    # Ordnernamen und ist fuer Benutzer nicht nachvollziehbar.
    foreach ($entry in @($Action | Sort-Object -Property Title)) {
        $key = $menu + '\shell\' + (Get-SpawnNewKeyName -Index $index -Id $entry.Id)
        $line = Get-SpawnNewActionCommand -AppDirectory $AppDirectory -ActionId $entry.Id

        [void]$entries.Add([pscustomobject]@{ Path = $key; Kind = 'value'; Name = 'MUIVerb'; Value = $entry.Title })
        [void]$entries.Add([pscustomobject]@{ Path = ($key + '\command'); Kind = 'default'; Name = ''; Value = $line })
        $index++
    }

    $position = 1
    foreach ($entry in $Command) {
        $key = $menu + '\shell\zz' + $position + '_spawnnew.' + $entry.Name
        $line = Get-SpawnNewManagementCommand -AppDirectory $AppDirectory -Name $entry.Name

        [void]$entries.Add([pscustomobject]@{ Path = $key; Kind = 'value'; Name = 'MUIVerb'; Value = $entry.Title })
        if ($position -eq 1) {
            [void]$entries.Add([pscustomobject]@{ Path = $key; Kind = 'dword'; Name = 'CommandFlags'; Value = 32 })
        }
        [void]$entries.Add([pscustomobject]@{ Path = ($key + '\command'); Kind = 'default'; Name = ''; Value = $line })
        $position++
    }

    return [object[]]$entries.ToArray()
}

function Get-SpawnNewInstallScope {
    <#
    .SYNOPSIS
    Installationsumfang aus dem Programmverzeichnis ableiten.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$AppDirectory)

    # Nur unter den Programmverzeichnissen von Windows ist es eine
    # Installation fuer alle Benutzer; lokal und im Cloudordner gehoert sie
    # dem angemeldeten Benutzer.
    foreach ($system in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432)) {
        if (-not $system) { continue }
        if ($AppDirectory.StartsWith($system.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return 'AllUsers' }
    }
    return 'CurrentUser'
}

function ConvertFrom-SpawnNewCommandLine {
    <#
    .SYNOPSIS
    Programmverzeichnis aus einer registrierten Befehlszeile, sonst ''.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)

    $match = [regex]::Match($Line, '-File "([^"]+)\\SpawnNew\.(Host|Command)\.ps1"')
    if ($match.Success) { return $match.Groups[1].Value }
    return ''
}

function Get-SpawnNewRegisteredAppDirectory {
    <#
    .SYNOPSIS
    Programmverzeichnis, auf das das registrierte Menue zeigt, sonst ''.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Root)

    $shell = (Get-SpawnNewMenuKey -Root $Root) + '\shell'
    if (-not (Test-Path -LiteralPath $shell)) { return '' }

    foreach ($key in @(Get-ChildItem -LiteralPath $shell)) {
        $command = Get-Item -LiteralPath (Join-Path $key.PSPath 'command') -ErrorAction SilentlyContinue
        if ($null -eq $command) { continue }
        $directory = ConvertFrom-SpawnNewCommandLine -Line ([string]$command.GetValue(''))
        if ($directory) { return $directory }
    }
    return ''
}

function Test-SpawnNewRegistration {
    <#
    .SYNOPSIS
    Prueft, ob die Registrierung genau den erwarteten Eintraegen entspricht.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry,
        [Parameter(Mandatory)][string]$Root
    )

    $menu = Get-SpawnNewMenuKey -Root $Root
    $shell = $menu + '\shell'

    $expectedKeys = @($Entry | Where-Object { $_.Path.StartsWith($shell + '\') } | ForEach-Object { $_.Path.Substring($shell.Length + 1).Split('\')[0] } | Sort-Object -Unique)
    $actualKeys = @()
    if (Test-Path -LiteralPath $shell) { $actualKeys = @(Get-ChildItem -LiteralPath $shell | ForEach-Object { $_.PSChildName } | Sort-Object) }
    if (($expectedKeys -join '|') -ne ($actualKeys -join '|')) { return $false }

    foreach ($item in $Entry) {
        $key = Get-Item -LiteralPath $item.Path -ErrorAction SilentlyContinue
        if ($null -eq $key) { return $false }
        $actual = $key.GetValue($item.Name)
        if ($null -eq $actual -or [string]$actual -ne [string]$item.Value) { return $false }
    }
    return $true
}

function Sync-SpawnNewRegistration {
    <#
    .SYNOPSIS
    Schreibt das Untermenue neu, wenn es nicht mehr dem Katalog entspricht.
    Liefert $true, wenn neu geschrieben wurde.
    .DESCRIPTION
    Uebergangsloesung bis zur Explorer-Erweiterung: so erscheinen neue
    Aktionen nach dem naechsten Aufruf eines SpawnNew-Eintrags.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry,
        [Parameter(Mandatory)][string]$Root
    )

    if (Test-SpawnNewRegistration -Entry $Entry -Root $Root) { return $false }
    if (-not $PSCmdlet.ShouldProcess((Get-SpawnNewMenuKey -Root $Root), 'Menue neu schreiben')) { return $false }

    Remove-SpawnNewRegistration -Root $Root
    Set-SpawnNewRegistration -Entry $Entry
    return $true
}

function Set-SpawnNewRegistration {
    <#
    .SYNOPSIS
    Schreibt die Eintraege in die Registrierung.
    .DESCRIPTION
    Kind 'default' setzt den unbenannten Standardwert des Schluessels ueber
    Set-Item. Kind 'value' schreibt einen benannten Wert.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry)

    foreach ($item in $Entry) {
        if (-not $PSCmdlet.ShouldProcess($item.Path, 'Registrierungswert setzen')) { continue }

        if (-not (Test-Path -LiteralPath $item.Path)) {
            [void](New-Item -Path $item.Path -Force)
        }

        if ($item.Kind -eq 'default') {
            Set-Item -LiteralPath $item.Path -Value $item.Value
        }
        elseif ($item.Kind -eq 'dword') {
            [void](New-ItemProperty -Path $item.Path -Name $item.Name -Value ([int]$item.Value) -PropertyType DWord -Force)
        }
        else {
            [void](New-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -PropertyType String -Force)
        }
    }
}

function Remove-SpawnNewRegistration {
    <#
    .SYNOPSIS
    Entfernt das SpawnNew-Untermenue samt Aktionen.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Root)

    $menu = Get-SpawnNewMenuKey -Root $Root
    if (-not (Test-Path -LiteralPath $menu)) { return }
    if (-not $PSCmdlet.ShouldProcess($menu, 'Registrierungsschluessel entfernen')) { return }

    Remove-Item -LiteralPath $menu -Recurse -Force
}

Export-ModuleMember -Function Get-SpawnNewRegistryRoot, Get-SpawnNewMenuKey, Get-SpawnNewKeyName, Get-SpawnNewActionCommand, Get-SpawnNewManagementCommand, Get-SpawnNewMenuCommand, Get-SpawnNewRegistryEntry, Get-SpawnNewInstallScope, ConvertFrom-SpawnNewCommandLine, Get-SpawnNewRegisteredAppDirectory, Test-SpawnNewRegistration, Sync-SpawnNewRegistration, Set-SpawnNewRegistration, Remove-SpawnNewRegistration
