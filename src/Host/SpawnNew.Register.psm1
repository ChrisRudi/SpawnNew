# SpawnNew.Register.psm1
# Version 1.0 | Registrierung des Kontextmenues.
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

function Get-SpawnNewRegistryEntry {
    <#
    .SYNOPSIS
    Alle Eintraege des Untermenues als Datenliste.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Action,
        [Parameter(Mandatory)][string]$AppDirectory,
        [Parameter(Mandatory)][string]$Root
    )

    $menu    = Get-SpawnNewMenuKey -Root $Root
    $entries = New-Object System.Collections.ArrayList

    [void]$entries.Add([pscustomobject]@{ Path = $menu; Kind = 'value'; Name = 'MUIVerb'; Value = $script:MenuName })
    [void]$entries.Add([pscustomobject]@{ Path = $menu; Kind = 'value'; Name = 'SubCommands'; Value = '' })

    $index = 1
    foreach ($entry in $Action) {
        $key = $menu + '\shell\' + (Get-SpawnNewKeyName -Index $index -Id $entry.Id)
        $command = Get-SpawnNewActionCommand -AppDirectory $AppDirectory -ActionId $entry.Id

        [void]$entries.Add([pscustomobject]@{ Path = $key; Kind = 'value'; Name = 'MUIVerb'; Value = $entry.Title })
        [void]$entries.Add([pscustomobject]@{ Path = ($key + '\command'); Kind = 'default'; Name = ''; Value = $command })
        $index++
    }

    return [object[]]$entries.ToArray()
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

Export-ModuleMember -Function Get-SpawnNewRegistryRoot, Get-SpawnNewMenuKey, Get-SpawnNewKeyName, Get-SpawnNewActionCommand, Get-SpawnNewRegistryEntry, Set-SpawnNewRegistration, Remove-SpawnNewRegistration
