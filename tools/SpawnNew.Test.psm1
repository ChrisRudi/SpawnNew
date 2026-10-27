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

    # [short] gibt es erst ab PowerShell 6; [int16] gilt auch unter 5.1.
    $numeric = @([byte], [int16], [int], [long], [double], [decimal])
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

function ConvertTo-SpawnNewJsonText {
    <#
    .SYNOPSIS
    Maskiert eine Zeichenkette fuer den Einbau in eine JSON-Zeichenkette.
    .DESCRIPTION
    Windows-Pfade enthalten Rueckstriche, die in JSON als Escape gelten.
    Ungeschuetzt eingesetzt ergeben sie ungueltige JSON.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    return $Text.Replace('\', '\\').Replace('"', '\"')
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

function Invoke-SpawnNewTestAction {
    <#
    .SYNOPSIS
    Startet eine mitgelieferte Aktion in einem eigenen Prozess, wie der
    Ausfuehrungsprozess es tut, und liefert Rueckgabewert, Ausgabe,
    Fortschritt und Ergebnis.
    .DESCRIPTION
    Braucht die Module Config und Runner in der Testsitzung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][hashtable]$Value,
        [Parameter(Mandatory)][string]$TargetPath,
        [bool]$TargetExisted = $false,
        [ValidateSet('fail', 'rename', 'overwrite')][string]$ConflictPolicy = 'fail',
        $Llm = $null,
        [string]$ProposalFile = '',
        [string]$Script = 'Invoke-SpawnAction.ps1',
        [string]$ActionDirectory = '',
        [switch]$Cancel
    )

    $repo      = Split-Path -Parent $PSScriptRoot
    $hostDir   = Join-Path (Join-Path $repo 'src') 'Host'
    $actionDir = if ($ActionDirectory) { $ActionDirectory } else { Join-Path (Join-Path (Join-Path $repo 'src') 'Actions') $Folder }
    $action    = [pscustomobject]@{ Id = $Id; ActionDirectory = $actionDir }
    $run       = Get-SpawnNewRun -Root $script:WorkDirectory

    [void](Write-SpawnNewContextFile -Run $run -Action $action -ExplorerPath (Split-Path -Parent $TargetPath) -TargetPath $TargetPath -TargetExisted $TargetExisted -ConflictPolicy $ConflictPolicy -Value $Value -AppDirectory $hostDir -Llm $Llm -ProposalFile $ProposalFile)
    if ($Cancel) { Request-SpawnNewCancel -Run $run }

    $shell  = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $output = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $actionDir $Script) -ContextFile $run.ContextFile 2>&1
    $code   = $LASTEXITCODE

    return [pscustomobject]@{
        Run      = $run
        Target   = $TargetPath
        ExitCode = $code
        Output   = (@($output | ForEach-Object { [string]$_ }) -join "`r`n")
        Progress = @((Read-SpawnNewProgress -Path $run.ProgressFile -Offset 0).Entry)
        Result   = (Read-SpawnNewResult -Run $run)
    }
}

function Get-SpawnNewTestEndpoint {
    <#
    .SYNOPSIS
    Endpunktobjekt wie aus Get-SpawnNewConfig, fuer Kontextdateien in Tests.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Secret = '',
        [int]$TimeoutSeconds = 20
    )

    return [pscustomobject]@{ Name = 'Test'; BaseUrl = $Url; Model = 'testmodell'; TimeoutSeconds = $TimeoutSeconds; Secret = $Secret }
}

function Start-SpawnNewFakeLlm {
    <#
    .SYNOPSIS
    Startet einen OpenAI-kompatiblen Testserver auf 127.0.0.1.
    .DESCRIPTION
    Beantwortet GET .../models und POST .../chat/completions mit der
    vorgegebenen Antwort und zeichnet jede Anfrage mit Methode, Pfad,
    Authorization-Kopf und Inhalt auf. Laeuft in einem eigenen Runspace,
    damit auch Aktionsprozesse ihn erreichen. Ein TcpListener braucht im
    Gegensatz zu HttpListener keine URL-Reservierung.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [AllowEmptyString()][string]$Reply = 'Antwort des Testmodells',
        [int]$Status = 200,
        [int]$DelayMs = 0
    )

    if (-not $PSCmdlet.ShouldProcess('127.0.0.1', 'Testserver starten')) { return }

    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $requests = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

    $worker = {
        param($Listener, $Requests, $Reply, $Status, $DelayMs)

        $latin = [System.Text.Encoding]::GetEncoding(28591)
        while ($true) {
            try { $client = $Listener.AcceptTcpClient() }
            catch { break }

            try {
                $stream = $client.GetStream()
                $data   = New-Object System.IO.MemoryStream
                $buffer = New-Object byte[] 65536
                $end    = -1
                while ($end -lt 0) {
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                    if ($read -le 0) { break }
                    $data.Write($buffer, 0, $read)
                    $end = $latin.GetString($data.ToArray()).IndexOf("`r`n`r`n")
                }

                $head   = $latin.GetString($data.ToArray(), 0, $end)
                $length = 0
                $auth   = ''
                foreach ($line in $head.Split("`n")) {
                    if ($line -match '^Content-Length:\s*(\d+)') { $length = [int]$Matches[1] }
                    if ($line -match '^Authorization:\s*(.*?)\s*$') { $auth = $Matches[1] }
                }
                while ($data.Length -lt ($end + 4 + $length)) {
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                    if ($read -le 0) { break }
                    $data.Write($buffer, 0, $read)
                }

                $bytes = $data.ToArray()
                $body  = [System.Text.Encoding]::UTF8.GetString($bytes, $end + 4, $bytes.Length - $end - 4)
                $first = $head.Split("`n")[0].Trim().Split(' ')
                [void]$Requests.Add([pscustomobject]@{ Method = $first[0]; Path = $first[1]; Authorization = $auth; Body = $body })

                if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }

                if ($first[1] -like '*/models') {
                    $json = '{"object":"list","data":[{"id":"testmodell","object":"model"}]}'
                }
                else {
                    $answer = [pscustomobject]@{ choices = @([pscustomobject]@{ index = 0; message = [pscustomobject]@{ role = 'assistant'; content = $Reply } }) }
                    $json = ConvertTo-Json -InputObject $answer -Depth 5 -Compress
                }

                $payload = [System.Text.Encoding]::UTF8.GetBytes($json)
                $header  = 'HTTP/1.1 ' + $Status + " X`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: " + $payload.Length + "`r`nConnection: close`r`n`r`n"
                $headerBytes = $latin.GetBytes($header)
                $stream.Write($headerBytes, 0, $headerBytes.Length)
                $stream.Write($payload, 0, $payload.Length)
                $stream.Flush()
            }
            catch {
                [void]$Requests.Add([pscustomobject]@{ Method = 'ERROR'; Path = ''; Authorization = ''; Body = $_.Exception.Message })
            }
            finally {
                $client.Close()
            }
        }
    }

    $shell = [powershell]::Create()
    [void]$shell.AddScript($worker).AddArgument($listener).AddArgument($requests).AddArgument($Reply).AddArgument($Status).AddArgument($DelayMs)
    $handle = $shell.BeginInvoke()

    return [pscustomobject]@{
        Url      = ('http://127.0.0.1:' + $listener.LocalEndpoint.Port + '/v1')
        Requests = $requests
        Listener = $listener
        Shell    = $shell
        Handle   = $handle
    }
}

function Stop-SpawnNewFakeLlm {
    <#
    .SYNOPSIS
    Beendet einen Testserver aus Start-SpawnNewFakeLlm.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][AllowNull()]$Server)

    if ($null -eq $Server) { return }
    if (-not $PSCmdlet.ShouldProcess($Server.Url, 'Testserver beenden')) { return }

    $Server.Listener.Stop()
    [void]$Server.Handle.AsyncWaitHandle.WaitOne(2000)
    $Server.Shell.Dispose()
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

Export-ModuleMember -Function Write-SpawnNewTestLine, Get-SpawnNewTestDirectory, Add-SpawnNewTest, Confirm-SpawnNewValue, Test-SpawnNewNumber, Confirm-SpawnNewCondition, Confirm-SpawnNewMatch, Import-SpawnNewHostModule, ConvertTo-SpawnNewJsonText, Add-SpawnNewTestFile, Add-SpawnNewTestAction, Invoke-SpawnNewTestAction, Get-SpawnNewTestEndpoint, Start-SpawnNewFakeLlm, Stop-SpawnNewFakeLlm, Get-SpawnNewTestFile, Invoke-SpawnNewTest
