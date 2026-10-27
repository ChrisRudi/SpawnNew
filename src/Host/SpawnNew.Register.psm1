# SpawnNew.Register.psm1
# Version 1.2 | Registrierung des Kontextmenues.
# Zweck  : Die Registrierungseintraege fuer die SpawnNew-Untermenues aus dem
#          Katalog bilden, abgleichen, schreiben und entfernen. Aufbau siehe
#          docs/Dateiliste.md Abschnitt 13. Je Aktion bis zu drei Orte:
#          Hintergrund eines Ordners, Rechtsklick auf einen Ordner und
#          Rechtsklick auf Dateien.
#          Gelesen und geschrieben wird ueber die .NET-Registrierungs-API:
#          Dateien haengen unter '*\shell', und im PowerShell-Provider ist
#          '*' ein Platzhalter. Anzeigetexte stehen in MUIVerb; nur die
#          Befehlszeile ist der unbenannte Standardwert ihres Schluessels.
# Input  : Aktionen aus Get-SpawnNewCatalog, Programmverzeichnis, Umfang.
# Output : Get-SpawnNewRegistryEntry liefert die Eintraege als Daten, damit
#          sie ohne Schreibzugriff pruefbar sind.
# Deps   : Windows PowerShell 5.1.

Set-StrictMode -Version 2.0

$script:MenuName = 'SpawnNew'
$script:ContextPath = [ordered]@{
    background = 'Directory\Background\shell'
    folder     = 'Directory\shell'
    file       = '*\shell'
}

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
    Schluessel des SpawnNew-Untermenues fuer einen Ort.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [ValidateSet('background', 'folder', 'file')][string]$Context = 'background'
    )

    return ($Root.TrimEnd('\') + '\' + $script:ContextPath[$Context] + '\' + $script:MenuName)
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
    .DESCRIPTION
    %V ist der Ordner, in dessen leeren Bereich geklickt wurde, %1 der
    angeklickte Ordner oder die angeklickte Datei.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$AppDirectory,
        [Parameter(Mandatory)][string]$ActionId,
        [ValidateSet('background', 'folder', 'file')][string]$Context = 'background'
    )

    $script = $AppDirectory.TrimEnd('\') + '\SpawnNew.Host.ps1'
    $target = switch ($Context) {
        'folder' { '-ExplorerPath "%1"' }
        'file'   { '-FilePath "%1"' }
        default  { '-ExplorerPath "%V"' }
    }
    return ('powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass ' +
        '-File "' + $script + '" -ActionId "' + $ActionId + '" ' + $target)
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

function Get-SpawnNewActionContext {
    <#
    .SYNOPSIS
    Orte einer Aktion; ohne Angabe nur der Hintergrund eines Ordners.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Action)

    if ($Action.PSObject.Properties.Name -contains 'Contexts' -and @($Action.Contexts).Count -gt 0) {
        return [string[]]@($Action.Contexts)
    }
    return [string[]]@('background')
}

function Get-SpawnNewRegistryEntry {
    <#
    .SYNOPSIS
    Alle Eintraege der Untermenues als Datenliste.
    .DESCRIPTION
    Je Ort ein Untermenue mit den Aktionen dieses Ortes, nach Titel
    sortiert. Im Hintergrundmenue folgen, durch eine Trennlinie abgesetzt,
    die Verwaltungsbefehle: CommandFlags 0x20 setzt die Trennlinie davor,
    der Schluesselname 'zz' sortiert sie hinter alle Aktionen. Ein Ort ohne
    Aktionen bekommt kein Untermenue.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Action,
        [Parameter(Mandatory)][string]$AppDirectory,
        [Parameter(Mandatory)][string]$Root,
        [AllowEmptyCollection()][object[]]$Command = @()
    )

    $entries = New-Object System.Collections.ArrayList

    foreach ($context in @($script:ContextPath.Keys)) {
        $members = @($Action | Where-Object { (Get-SpawnNewActionContext -Action $_) -contains $context } | Sort-Object -Property Title)
        if ($context -ne 'background' -and $members.Count -eq 0) { continue }

        $menu = Get-SpawnNewMenuKey -Root $Root -Context $context
        [void]$entries.Add([pscustomobject]@{ Path = $menu; Kind = 'value'; Name = 'MUIVerb'; Value = $script:MenuName })
        [void]$entries.Add([pscustomobject]@{ Path = $menu; Kind = 'value'; Name = 'SubCommands'; Value = '' })

        $index = 1
        foreach ($entry in $members) {
            $key = $menu + '\shell\' + (Get-SpawnNewKeyName -Index $index -Id $entry.Id)
            $line = Get-SpawnNewActionCommand -AppDirectory $AppDirectory -ActionId $entry.Id -Context $context

            [void]$entries.Add([pscustomobject]@{ Path = $key; Kind = 'value'; Name = 'MUIVerb'; Value = $entry.Title })
            [void]$entries.Add([pscustomobject]@{ Path = ($key + '\command'); Kind = 'default'; Name = ''; Value = $line })
            $index++
        }

        if ($context -ne 'background') { continue }

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

function Open-SpawnNewRegistryKey {
    <#
    .SYNOPSIS
    Oeffnet einen Schluessel ueber die .NET-API; Pfade wie 'HKCU:\...'.
    Liefert $null, wenn er fehlt und nicht angelegt werden soll.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Create,
        [switch]$Writable
    )

    $match = [regex]::Match($Path, '^(HKCU|HKLM):\\(.+)$')
    if (-not $match.Success) { throw "Registrierungspfad nicht unterstützt: $Path" }

    $hive = if ($match.Groups[1].Value -eq 'HKLM') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $sub = $match.Groups[2].Value.TrimEnd('\')
    if ($Create) { return $hive.CreateSubKey($sub) }
    return $hive.OpenSubKey($sub, [bool]$Writable)
}

function Get-SpawnNewSubKeyName {
    <#
    .SYNOPSIS
    Namen der Unterschluessel, sortiert; leer, wenn der Schluessel fehlt.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Path)

    $key = Open-SpawnNewRegistryKey -Path $Path
    if ($null -eq $key) { return [string[]]@() }
    try { return [string[]]@($key.GetSubKeyNames() | Sort-Object) }
    finally { $key.Dispose() }
}

function Get-SpawnNewRegistryValue {
    <#
    .SYNOPSIS
    Wert eines Schluessels; '' ist der unbenannte Standardwert. $null, wenn
    Schluessel oder Wert fehlen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )

    $key = Open-SpawnNewRegistryKey -Path $Path
    if ($null -eq $key) { return $null }
    try { return $key.GetValue($Name) }
    finally { $key.Dispose() }
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
    foreach ($name in (Get-SpawnNewSubKeyName -Path $shell)) {
        $directory = ConvertFrom-SpawnNewCommandLine -Line ([string](Get-SpawnNewRegistryValue -Path ($shell + '\' + $name + '\command') -Name ''))
        if ($directory) { return $directory }
    }
    return ''
}

function Test-SpawnNewRegistration {
    <#
    .SYNOPSIS
    Prueft, ob die Registrierung genau den erwarteten Eintraegen entspricht,
    an allen drei Orten.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry,
        [Parameter(Mandatory)][string]$Root
    )

    foreach ($context in @($script:ContextPath.Keys)) {
        $menu = Get-SpawnNewMenuKey -Root $Root -Context $context
        $shell = $menu + '\shell'
        $mine = @($Entry | Where-Object { $_.Path -eq $menu -or $_.Path.StartsWith($menu + '\') })

        if ($mine.Count -eq 0) {
            if ($null -ne (Get-SpawnNewRegistryValue -Path $menu -Name 'MUIVerb')) { return $false }
            continue
        }

        $expected = @($mine | Where-Object { $_.Path.StartsWith($shell + '\') } | ForEach-Object { $_.Path.Substring($shell.Length + 1).Split('\')[0] } | Sort-Object -Unique)
        if (($expected -join '|') -ne ((Get-SpawnNewSubKeyName -Path $shell) -join '|')) { return $false }
    }

    foreach ($item in $Entry) {
        $actual = Get-SpawnNewRegistryValue -Path $item.Path -Name $item.Name
        if ($null -eq $actual -or [string]$actual -ne [string]$item.Value) { return $false }
    }
    return $true
}

function Sync-SpawnNewRegistration {
    <#
    .SYNOPSIS
    Schreibt die Untermenues neu, wenn sie nicht mehr dem Katalog entsprechen.
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
    Kind 'default' setzt den unbenannten Standardwert, 'dword' einen
    DWORD-Wert, 'value' einen benannten Zeichenkettenwert.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry)

    foreach ($item in $Entry) {
        if (-not $PSCmdlet.ShouldProcess($item.Path, 'Registrierungswert setzen')) { continue }

        $key = Open-SpawnNewRegistryKey -Path $item.Path -Create
        try {
            switch ($item.Kind) {
                'default' { $key.SetValue('', [string]$item.Value, [Microsoft.Win32.RegistryValueKind]::String) }
                'dword'   { $key.SetValue($item.Name, [int]$item.Value, [Microsoft.Win32.RegistryValueKind]::DWord) }
                default   { $key.SetValue($item.Name, [string]$item.Value, [Microsoft.Win32.RegistryValueKind]::String) }
            }
        }
        finally {
            $key.Dispose()
        }
    }
}

function Remove-SpawnNewRegistration {
    <#
    .SYNOPSIS
    Entfernt die SpawnNew-Untermenues an allen drei Orten.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Root)

    foreach ($context in @($script:ContextPath.Keys)) {
        $menu = Get-SpawnNewMenuKey -Root $Root -Context $context
        $parentPath = $menu.Substring(0, $menu.Length - $script:MenuName.Length - 1)
        $parent = Open-SpawnNewRegistryKey -Path $parentPath -Writable
        if ($null -eq $parent) { continue }
        try {
            if ($parent.GetSubKeyNames() -contains $script:MenuName -and $PSCmdlet.ShouldProcess($menu, 'Registrierungsschluessel entfernen')) {
                $parent.DeleteSubKeyTree($script:MenuName)
            }
        }
        finally {
            $parent.Dispose()
        }
    }
}

Export-ModuleMember -Function Get-SpawnNewRegistryRoot, Get-SpawnNewMenuKey, Get-SpawnNewKeyName, Get-SpawnNewActionCommand, Get-SpawnNewManagementCommand, Get-SpawnNewMenuCommand, Get-SpawnNewActionContext, Get-SpawnNewRegistryEntry, Get-SpawnNewInstallScope, Open-SpawnNewRegistryKey, Get-SpawnNewSubKeyName, Get-SpawnNewRegistryValue, ConvertFrom-SpawnNewCommandLine, Get-SpawnNewRegisteredAppDirectory, Test-SpawnNewRegistration, Sync-SpawnNewRegistration, Set-SpawnNewRegistration, Remove-SpawnNewRegistration
