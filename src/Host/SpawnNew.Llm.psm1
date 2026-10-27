# SpawnNew.Llm.psm1
# Version 1.0 | OpenAI-kompatibler Client fuer lokale und Webendpunkte.
# Zweck  : Erreichbarkeit pruefen und Chat-Anfragen stellen. Lokale
#          Endpunkte werden ohne Proxy angesprochen, damit kein Inhalt den
#          Rechner verlaesst. Ein API-Schluessel kommt ausschliesslich aus
#          dem Geheimnisspeicher und erscheint in keiner Meldung.
# Input  : Endpunkt aus Get-SpawnNewConfig (Name, BaseUrl, Model,
#          TimeoutSeconds, Secret), Systemanweisung, Benutzertext.
# Output : Antworttext des Modells; Fehler als Ausnahme mit Endpunkt,
#          Ursache und Zeitlimit.
# Deps   : Windows PowerShell 5.1, SpawnNew.Secret.psm1.

Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Secret.psm1')

function Get-SpawnNewEndpointUri {
    <#
    .SYNOPSIS
    Adresse eines Unterpfades der Schnittstelle, etwa 'models'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Endpoint,
        [Parameter(Mandatory)][string]$Path
    )

    return ([string]$Endpoint.BaseUrl).TrimEnd('/') + '/' + $Path.TrimStart('/')
}

function Test-SpawnNewLocalUri {
    <#
    .SYNOPSIS
    Prueft, ob eine Adresse auf diesen Rechner zeigt.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Uri)

    try { $parsed = New-Object System.Uri $Uri }
    catch { return $false }

    if ($parsed.IsLoopback) { return $true }
    return ($parsed.Host -eq [System.Environment]::MachineName)
}

function Invoke-SpawnNewHttp {
    <#
    .SYNOPSIS
    HTTP-Aufruf mit Zeitlimit, Antwort als UTF-8-Text.
    .DESCRIPTION
    Invoke-RestMethod unter Windows PowerShell 5.1 dekodiert Antworten ohne
    Zeichensatzangabe als ISO-8859-1 und zerstoert Umlaute. Darum direkt
    ueber HttpWebRequest.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [string]$Body,
        [string]$ApiKey,
        [Parameter(Mandatory)][int]$TimeoutMs
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

    $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Uri)
    $request.Method           = $Method
    $request.Timeout          = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.Accept           = 'application/json'
    if (Test-SpawnNewLocalUri -Uri $Uri) { $request.Proxy = $null }
    if ($ApiKey) { $request.Headers['Authorization'] = 'Bearer ' + $ApiKey }

    if ($Method -eq 'POST') {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Body)
        $request.ContentType   = 'application/json; charset=utf-8'
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bytes, 0, $bytes.Length) }
        finally { $stream.Dispose() }
    }

    $response = $null
    try {
        try { $response = [System.Net.HttpWebResponse]$request.GetResponse() }
        catch [System.Net.WebException] {
            if ($null -eq $_.Exception.Response) { throw }
            $response = [System.Net.HttpWebResponse]$_.Exception.Response
        }

        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { $text = $reader.ReadToEnd() }
        finally { $reader.Dispose() }

        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Text = $text }
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Get-SpawnNewEndpointKey {
    <#
    .SYNOPSIS
    API-Schluessel eines Endpunkts aus dem Geheimnisspeicher, sonst leer.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Endpoint)

    $name = [string]$Endpoint.Secret
    if ($name.Length -eq 0) { return '' }
    return (Get-SpawnNewSecret -Name $name)
}

function Get-SpawnNewEndpointText {
    <#
    .SYNOPSIS
    Kurzbezeichnung eines Endpunkts fuer Meldungen, ohne Schluessel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Endpoint)

    return ("'" + $Endpoint.Name + "' (" + $Endpoint.BaseUrl + ', Modell ' + $Endpoint.Model + ')')
}

function Test-SpawnNewEndpoint {
    <#
    .SYNOPSIS
    Prueft die Erreichbarkeit ueber GET models mit kurzem Zeitlimit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Endpoint,
        [int]$TimeoutMs = 3000
    )

    try {
        $key = Get-SpawnNewEndpointKey -Endpoint $Endpoint
        $answer = Invoke-SpawnNewHttp -Method 'GET' -Uri (Get-SpawnNewEndpointUri -Endpoint $Endpoint -Path 'models') -ApiKey $key -TimeoutMs $TimeoutMs
    }
    catch {
        return [pscustomobject]@{ Reachable = $false; Message = ('Endpunkt ' + (Get-SpawnNewEndpointText -Endpoint $Endpoint) + ' ist nicht erreichbar: ' + $_.Exception.Message) }
    }

    if ($answer.StatusCode -eq 401 -or $answer.StatusCode -eq 403) {
        return [pscustomobject]@{ Reachable = $false; Message = ('Endpunkt ' + (Get-SpawnNewEndpointText -Endpoint $Endpoint) + ' lehnt den Zugang ab (HTTP ' + $answer.StatusCode + '). Schlüssel prüfen.') }
    }
    if ($answer.StatusCode -ge 400) {
        return [pscustomobject]@{ Reachable = $false; Message = ('Endpunkt ' + (Get-SpawnNewEndpointText -Endpoint $Endpoint) + ' antwortet mit HTTP ' + $answer.StatusCode + '.') }
    }
    return [pscustomobject]@{ Reachable = $true; Message = '' }
}

function Invoke-SpawnNewChat {
    <#
    .SYNOPSIS
    Stellt eine Chat-Anfrage und liefert den Antworttext.
    .DESCRIPTION
    Fehler enthalten Endpunkt, Ursache und Zeitlimit, aber nie den Schluessel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Endpoint,
        [Parameter(Mandatory)][string]$System,
        [Parameter(Mandatory)][string]$User,
        [double]$Temperature = 0.3
    )

    $timeout = [int]$Endpoint.TimeoutSeconds
    if ($timeout -le 0) { $timeout = 120 }

    $payload = [pscustomobject]@{
        model       = [string]$Endpoint.Model
        temperature = $Temperature
        stream      = $false
        messages    = @(
            [pscustomobject]@{ role = 'system'; content = $System },
            [pscustomobject]@{ role = 'user'; content = $User }
        )
    }
    $body = ConvertTo-Json -InputObject $payload -Depth 5 -Compress
    $where = Get-SpawnNewEndpointText -Endpoint $Endpoint

    try {
        $key = Get-SpawnNewEndpointKey -Endpoint $Endpoint
        $answer = Invoke-SpawnNewHttp -Method 'POST' -Uri (Get-SpawnNewEndpointUri -Endpoint $Endpoint -Path 'chat/completions') -Body $body -ApiKey $key -TimeoutMs ($timeout * 1000)
    }
    catch {
        throw ('Modellaufruf an ' + $where + ' fehlgeschlagen (Zeitlimit ' + $timeout + ' s): ' + $_.Exception.Message)
    }

    if ($answer.StatusCode -ge 400) {
        $detail = $answer.Text
        if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) + ' ...' }
        throw ('Modellaufruf an ' + $where + ' endete mit HTTP ' + $answer.StatusCode + ': ' + $detail)
    }

    try { $parsed = ConvertFrom-Json -InputObject $answer.Text }
    catch { throw ('Antwort von ' + $where + ' ist keine gültige JSON.') }

    $content = ''
    try { $content = [string]@($parsed.choices)[0].message.content }
    catch { $content = '' }

    if ($content.Trim().Length -eq 0) { throw ('Antwort von ' + $where + ' enthält keinen Text.') }
    return $content.Trim()
}

function ConvertFrom-SpawnNewModelJson {
    <#
    .SYNOPSIS
    Liest JSON aus einer Modellantwort, auch wenn sie in einem Codeblock
    oder zwischen erklaerendem Text steht. Liefert $null, wenn keine
    gueltige JSON enthalten ist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $candidates = New-Object System.Collections.ArrayList
    [void]$candidates.Add($Text.Trim())

    $fence = [regex]::Match($Text, '```(?:json)?\s*(.*?)```', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($fence.Success) { [void]$candidates.Add($fence.Groups[1].Value.Trim()) }

    foreach ($pair in @(@('[', ']'), @('{', '}'))) {
        $start = $Text.IndexOf($pair[0])
        $end   = $Text.LastIndexOf($pair[1])
        if ($start -ge 0 -and $end -gt $start) { [void]$candidates.Add($Text.Substring($start, $end - $start + 1)) }
    }

    foreach ($candidate in $candidates) {
        try { $value = ConvertFrom-Json -InputObject $candidate }
        catch { continue }
        # Komma: ein Feld bleibt ein Feld, auch mit einem einzigen Element.
        return , $value
    }
    return $null
}

Export-ModuleMember -Function Get-SpawnNewEndpointUri, Test-SpawnNewLocalUri, Invoke-SpawnNewHttp, Get-SpawnNewEndpointText, Test-SpawnNewEndpoint, Invoke-SpawnNewChat, ConvertFrom-SpawnNewModelJson
