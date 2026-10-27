# tests/SpawnNew.Llm.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Llm.psm1 und die KI-Konfiguration.
# Zweck  : Endpunkte aus den Konfigurationsschichten, Erreichbarkeit,
#          Chat-Anfrage, Schluesselbehandlung, Fehlermeldungen und das
#          Lesen von JSON aus Modellantworten. Deckt Abnahme 18, 19 und 22.

Import-SpawnNewHostModule -Name 'Config', 'Secret', 'Llm'

function Get-TestEndpoint {
    param([string]$Url, [string]$Secret = '', [int]$Timeout = 10)
    return [pscustomobject]@{ Name = 'Test'; BaseUrl = $Url; Model = 'testmodell'; TimeoutSeconds = $Timeout; Secret = $Secret }
}

function ConvertTo-TestSecure {
    param([Parameter(Mandatory)][string]$Text)
    $secure = New-Object System.Security.SecureString
    foreach ($char in $Text.ToCharArray()) { $secure.AppendChar($char) }
    return $secure
}

Add-SpawnNewTest 'Endpunkte werden ueber Schichten verbunden, die erste gewinnt' {
    $Work = Get-SpawnNewTestDirectory
    $user = Add-SpawnNewTestFile -Path (Join-Path $Work 'user.json') -Content '{ "llm": { "defaultEndpoint": "Web", "endpoints": [ { "name": "Lokal", "baseUrl": "http://localhost:1234/v1", "model": "eigen" }, { "name": "Web", "baseUrl": "https://api.example.org/v1", "model": "m", "secret": "web" } ] } }'
    $base = Add-SpawnNewTestFile -Path (Join-Path $Work 'default.json') -Content '{ "llm": { "defaultEndpoint": "Lokal", "endpoints": [ { "name": "Lokal", "baseUrl": "http://localhost:11434/v1", "model": "llama3.2" } ] } }'

    $config = Get-SpawnNewConfig -AppDirectory $Work -LayerPath @($user, $base)

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual @($config.Llm.Endpoints).Count -Expected 2
    Confirm-SpawnNewValue -Label 'Benutzerwert gewinnt' -Actual (Get-SpawnNewEndpoint -Config $config -Name 'Lokal').Model -Expected 'eigen'
    Confirm-SpawnNewValue -Label 'Vorgabe' -Actual (Get-SpawnNewEndpoint -Config $config).Name -Expected 'Web'
    Confirm-SpawnNewValue -Label 'Geheimnisname' -Actual (Get-SpawnNewEndpoint -Config $config -Name 'Web').Secret -Expected 'web'
    Confirm-SpawnNewValue -Label 'Zeitlimit-Vorgabe' -Actual (Get-SpawnNewEndpoint -Config $config -Name 'Web').TimeoutSeconds -Expected 120
}

Add-SpawnNewTest 'Ungueltiger Endpunkt wird als Diagnose gemeldet' {
    $Work = Get-SpawnNewTestDirectory
    $file = Add-SpawnNewTestFile -Path (Join-Path $Work 'default.json') -Content '{ "llm": { "endpoints": [ { "name": "Kaputt", "baseUrl": "ftp://x" } ] } }'

    $config = Get-SpawnNewConfig -AppDirectory $Work -LayerPath @($file)

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual @($config.Llm.Endpoints).Count -Expected 0
    Confirm-SpawnNewValue -Label 'kein Endpunkt' -Actual (Get-SpawnNewEndpoint -Config $config) -Expected $null
    Confirm-SpawnNewCondition -Label 'Diagnose' -Condition (@($config.Diagnostics | Where-Object { $_.Message -match 'Kaputt' }).Count -eq 1)
}

Add-SpawnNewTest 'Mitgelieferte Konfiguration nennt einen lokalen Endpunkt' {
    $default = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'config') 'spawnnew.settings.default.json'
    $config = Get-SpawnNewConfig -AppDirectory (Get-SpawnNewTestDirectory) -LayerPath @($default)
    $endpoint = Get-SpawnNewEndpoint -Config $config

    Confirm-SpawnNewCondition -Label 'lokal' -Condition (Test-SpawnNewLocalUri -Uri $endpoint.BaseUrl)
    Confirm-SpawnNewValue -Label 'kein Geheimnis' -Actual $endpoint.Secret -Expected ''
}

Add-SpawnNewTest 'Chat-Anfrage liefert die Antwort mit Umlauten' {
    $server = Start-SpawnNewFakeLlm -Reply 'Grüße aus dem Modell'
    try {
        $text = Invoke-SpawnNewChat -Endpoint (Get-TestEndpoint -Url $server.Url) -System 'Sei knapp.' -User 'Prüfe Ä'
    }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Antwort' -Actual $text -Expected 'Grüße aus dem Modell'
    $request = $server.Requests[0]
    Confirm-SpawnNewValue -Label 'Pfad' -Actual $request.Path -Expected '/v1/chat/completions'
    Confirm-SpawnNewMatch -Label 'Modell' -Actual $request.Body -Pattern '"model":"testmodell"'
    Confirm-SpawnNewMatch -Label 'Umlaut gesendet' -Actual $request.Body -Pattern 'Prüfe Ä'
    Confirm-SpawnNewValue -Label 'ohne Schluessel kein Kopf' -Actual $request.Authorization -Expected ''
}

Add-SpawnNewTest 'Schluessel geht nur als Kopf und nie in den Inhalt' {
    Set-SpawnNewSecret -Name 'web' -Value (ConvertTo-TestSecure 'sk-abc-123')
    $server = Start-SpawnNewFakeLlm -Reply 'ok'
    try {
        [void](Invoke-SpawnNewChat -Endpoint (Get-TestEndpoint -Url $server.Url -Secret 'web') -System 's' -User 'u')
    }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'Kopf' -Actual $server.Requests[0].Authorization -Expected 'Bearer sk-abc-123'
    Confirm-SpawnNewCondition -Label 'nicht im Inhalt' -Condition ($server.Requests[0].Body -notmatch 'sk-abc')
}

Add-SpawnNewTest 'Fehlendes Geheimnis verhindert die Anfrage' {
    $server = Start-SpawnNewFakeLlm -Reply 'ok'
    $message = ''
    try { [void](Invoke-SpawnNewChat -Endpoint (Get-TestEndpoint -Url $server.Url -Secret 'fehlt') -System 's' -User 'u') }
    catch { $message = $_.Exception.Message }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewMatch -Label 'Meldung' -Actual $message -Pattern 'nicht gespeichert'
    Confirm-SpawnNewValue -Label 'keine Anfrage' -Actual $server.Requests.Count -Expected 0
}

Add-SpawnNewTest 'HTTP-Fehler nennt Endpunkt und Status, nie den Schluessel' {
    Set-SpawnNewSecret -Name 'web' -Value (ConvertTo-TestSecure 'sk-xyz-999')
    $server = Start-SpawnNewFakeLlm -Reply 'x' -Status 500
    $message = ''
    try { [void](Invoke-SpawnNewChat -Endpoint (Get-TestEndpoint -Url $server.Url -Secret 'web') -System 's' -User 'u') }
    catch { $message = $_.Exception.Message }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewMatch -Label 'Status' -Actual $message -Pattern 'HTTP 500'
    Confirm-SpawnNewMatch -Label 'Endpunkt' -Actual $message -Pattern "'Test'"
    Confirm-SpawnNewCondition -Label 'kein Schluessel' -Condition ($message -notmatch 'sk-xyz')
}

Add-SpawnNewTest 'Zeitlimit wird eingehalten und in der Meldung genannt' {
    $server = Start-SpawnNewFakeLlm -Reply 'zu spaet' -DelayMs 4000
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $message = ''
    try { [void](Invoke-SpawnNewChat -Endpoint (Get-TestEndpoint -Url $server.Url -Timeout 1) -System 's' -User 'u') }
    catch { $message = $_.Exception.Message }
    finally { $watch.Stop(); Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewMatch -Label 'Zeitlimit' -Actual $message -Pattern 'Zeitlimit 1 s'
    Confirm-SpawnNewCondition -Label 'nicht abgewartet' -Condition ($watch.ElapsedMilliseconds -lt 3500)
}

Add-SpawnNewTest 'Erreichbarkeit wird geprueft' {
    $server = Start-SpawnNewFakeLlm
    try { $ok = Test-SpawnNewEndpoint -Endpoint (Get-TestEndpoint -Url $server.Url) }
    finally { Stop-SpawnNewFakeLlm -Server $server }

    Confirm-SpawnNewValue -Label 'erreichbar' -Actual $ok.Reachable -Expected $true
    Confirm-SpawnNewValue -Label 'Pfad' -Actual $server.Requests[0].Path -Expected '/v1/models'

    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()
    $down = Test-SpawnNewEndpoint -Endpoint (Get-TestEndpoint -Url ('http://127.0.0.1:' + $port + '/v1')) -TimeoutMs 1500

    Confirm-SpawnNewValue -Label 'nicht erreichbar' -Actual $down.Reachable -Expected $false
    Confirm-SpawnNewMatch -Label 'Meldung' -Actual $down.Message -Pattern 'nicht erreichbar'
}

Add-SpawnNewTest 'Lokale Adressen werden erkannt' {
    Confirm-SpawnNewValue -Label 'localhost' -Actual (Test-SpawnNewLocalUri -Uri 'http://localhost:11434/v1') -Expected $true
    Confirm-SpawnNewValue -Label '127.0.0.1' -Actual (Test-SpawnNewLocalUri -Uri 'http://127.0.0.1:1234/v1') -Expected $true
    Confirm-SpawnNewValue -Label 'Web' -Actual (Test-SpawnNewLocalUri -Uri 'https://api.openai.com/v1') -Expected $false
}

Add-SpawnNewTest 'JSON wird aus Codeblock und Fliesstext gelesen' {
    $plain = ConvertFrom-SpawnNewModelJson -Text '["a","b"]'
    Confirm-SpawnNewValue -Label 'rein' -Actual (@($plain) -join ',') -Expected 'a,b'

    $fenced = ConvertFrom-SpawnNewModelJson -Text ("Hier der Vorschlag:`n" + '```json' + "`n[`"Eins`"]`n" + '```' + "`nViel Erfolg.")
    Confirm-SpawnNewValue -Label 'Codeblock, ein Element' -Actual @($fenced).Count -Expected 1
    Confirm-SpawnNewValue -Label 'Wert' -Actual @($fenced)[0] -Expected 'Eins'

    Confirm-SpawnNewValue -Label 'keine JSON' -Actual (ConvertFrom-SpawnNewModelJson -Text 'nur Text') -Expected $null
}
