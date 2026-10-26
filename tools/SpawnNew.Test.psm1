# SpawnNew.Test.psm1
# Version 1.0 | Minimaler Testlaeufer fuer SpawnNew.
# Zweck  : Testdateien einsammeln, jeden Fall in einem eigenen leeren
#          Arbeitsverzeichnis ausfuehren und Ergebnisse berichten.
# Input  : Testdateien nach dem Muster *.Tests.ps1, die Add-SpawnNewTest rufen.
# Output : Berichtszeilen auf stdout. Invoke-SpawnNewTest liefert die Anzahl
#          der fehlgeschlagenen Faelle.
# Deps   : Windows PowerShell 5.1. Kein externes Testframework, weil die
#          PowerShell Gallery nicht in jeder Umgebung erreichbar ist und
#          Windows PowerShell 5.1 nur das inkompatible Pester 3.4 mitbringt.

Set-StrictMode -Version 2.0

$script:Tests = New-Object System.Collections.ArrayList
$script:WorkDirectory = ''

function Write-SpawnNewTestLine {
    <#
    .SYNOPSIS
    Gibt eine Berichtszeile aus.
    .DESCRIPTION
    Der Bericht geht in den Informationsstrom, damit er auf der Konsole
    erscheint, ohne den Rueckgabewert von Invoke-SpawnNewTest zu verfaelschen.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    Write-Information -MessageData $Text -InformationAction Continue
}

function Get-SpawnNewTestDirectory {
    <#
    .SYNOPSIS
    Leeres Arbeitsverzeichnis des laufenden Testfalls.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:WorkDirectory
}

function Add-SpawnNewTest {
    <#
    .SYNOPSIS
    Meldet einen Testfall an. Das Arbeitsverzeichnis des Falls liefert
    Get-SpawnNewTestDirectory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    [void]$script:Tests.Add([pscustomobject]@{ Name = $Name; Body = $Body })
}

function Confirm-SpawnNewValue {
    <#
    .SYNOPSIS
    Vergleicht einen Istwert mit einem Sollwert und bricht bei Abweichung ab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Actual,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Expected
    )

    if ([System.Object]::Equals($Expected, $Actual)) { return }

    # ConvertFrom-Json liefert Zahlen je nach Wertebereich als Int32 oder Int64.
    # Zahlen werden daher dem Wert nach verglichen, nicht dem Typ nach.
    if ((Test-SpawnNewNumber -Value $Expected) -and (Test-SpawnNewNumber -Value $Actual)) {
        if ([decimal]$Expected -eq [decimal]$Actual) { return }
    }

    $shown   = if ($null -eq $Actual)   { '<null>' } else { [string]$Actual }
    $wanted  = if ($null -eq $Expected) { '<null>' } else { [string]$Expected }
    throw "$Label : erwartet '$wanted', erhalten '$shown'"
}

function Test-SpawnNewNumber {
    <#
    .SYNOPSIS
    Prueft, ob ein Wert ein Zahlentyp ist.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowNull()]$Value)

    if ($null -eq $Value) { return $false }

    $numeric = @([byte], [short], [int], [long], [double], [decimal])
    return ($numeric -contains $Value.GetType())
}

function Confirm-SpawnNewCondition {
    <#
    .SYNOPSIS
    Prueft eine Bedingung und bricht ab, wenn sie nicht zutrifft.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][bool]$Condition
    )

    if (-not $Condition) { throw "$Label : Bedingung nicht erfüllt" }
}

function Confirm-SpawnNewMatch {
    <#
    .SYNOPSIS
    Prueft, ob ein Text ein Muster enthaelt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Actual,
        [Parameter(Mandatory)][string]$Pattern
    )

    if ($Actual -match $Pattern) { return }
    throw "$Label : '$Actual' enthält nicht '$Pattern'"
}

function Import-SpawnNewHostModule {
    <#
    .SYNOPSIS
    Laedt Module des Ausfuehrungsprozesses in die aufrufende Sitzung.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Name)

    $hostRoot = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Host'

    foreach ($entry in $Name) {
        Import-Module (Join-Path $hostRoot ('SpawnNew.' + $entry + '.psm1')) -ErrorAction Stop
    }
}

function Add-SpawnNewTestFile {
    <#
    .SYNOPSIS
    Schreibt eine Textdatei als UTF-8 ohne BOM und legt fehlende Ordner an.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
    return $Path
}

function Add-SpawnNewTestAction {
    <#
    .SYNOPSIS
    Legt einen Aktionsordner mit Einstiegsskript und optionaler Beschreibung an.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$Json,
        [switch]$NoEntryPoint
    )

    if (-not $NoEntryPoint) {
        $entry = Join-Path $Directory 'Invoke-SpawnAction.ps1'
        [void](Add-SpawnNewTestFile -Path $entry -Content "param([string]`$ContextFile)`r`n")
    }

    if ($PSBoundParameters.ContainsKey('Json')) {
        [void](Add-SpawnNewTestFile -Path (Join-Path $Directory 'action.json') -Content $Json)
    }

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Directory -Force)
    }

    return $Directory
}

function Get-SpawnNewTestFile {
    <#
    .SYNOPSIS
    Sammelt Testdateien aus Dateien und Verzeichnissen.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string[]]$Path)

    $files = New-Object System.Collections.ArrayList

    foreach ($entry in $Path) {
        if (-not (Test-Path -LiteralPath $entry)) { continue }

        if (Test-Path -LiteralPath $entry -PathType Container) {
            foreach ($file in @(Get-ChildItem -LiteralPath $entry -Recurse -File -Filter '*.Tests.ps1')) {
                [void]$files.Add($file.FullName)
            }
        }
        else {
            [void]$files.Add((Resolve-Path -LiteralPath $entry).ProviderPath)
        }
    }

    return [string[]]@($files | Sort-Object)
}

function Invoke-SpawnNewTest {
    <#
    .SYNOPSIS
    Fuehrt alle Testfaelle der angegebenen Testdateien aus.
    .DESCRIPTION
    Jeder Fall laeuft in einem eigenen, leeren Arbeitsverzeichnis, das
    Get-SpawnNewTestDirectory liefert und das danach entfernt wird.
    LOCALAPPDATA zeigt waehrend
    des Falls in dieses Verzeichnis, damit Cache und Protokolle den Rechner
    des Entwicklers nicht beschreiben.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string[]]$Path,
        [string]$Filter = '*'
    )

    $files    = @(Get-SpawnNewTestFile -Path $Path)
    $passed   = 0
    $failures = New-Object System.Collections.ArrayList
    $saved    = $env:LOCALAPPDATA

    foreach ($file in $files) {
        $script:Tests.Clear()
        . $file

        Write-SpawnNewTestLine -Text ([System.IO.Path]::GetFileName($file))

        foreach ($test in @($script:Tests)) {
            if ($test.Name -notlike $Filter) { continue }

            $work = Join-Path ([System.IO.Path]::GetTempPath()) ('spawnnew-test-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $work -Force)
            $env:LOCALAPPDATA = $work
            $script:WorkDirectory = $work

            try {
                & $test.Body
                Write-SpawnNewTestLine -Text ('  ok   ' + $test.Name)
                $passed++
            }
            catch {
                Write-SpawnNewTestLine -Text ('  FEHL ' + $test.Name)
                Write-SpawnNewTestLine -Text ('       ' + $_.Exception.Message)
                [void]$failures.Add($test.Name)
            }
            finally {
                $env:LOCALAPPDATA = $saved
                $script:WorkDirectory = ''
                Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-SpawnNewTestLine -Text ''
    Write-SpawnNewTestLine -Text ('{0} Testdatei(en), {1} bestanden, {2} fehlgeschlagen.' -f $files.Count, $passed, $failures.Count)

    return $failures.Count
}

Export-ModuleMember -Function Write-SpawnNewTestLine, Get-SpawnNewTestDirectory, Add-SpawnNewTest, Confirm-SpawnNewValue, Test-SpawnNewNumber, Confirm-SpawnNewCondition, Confirm-SpawnNewMatch, Import-SpawnNewHostModule, Add-SpawnNewTestFile, Add-SpawnNewTestAction, Get-SpawnNewTestFile, Invoke-SpawnNewTest
