# tests/SpawnNew.Secret.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Secret.psm1.
# Zweck  : Speichern, Lesen, Entfernen und die Verschluesselung der
#          Geheimnisse. Deckt Abschnitt 9 "Geheimnisse" ab.

Import-SpawnNewHostModule -Name 'Config', 'Secret'

function ConvertTo-TestSecure {
    param([Parameter(Mandatory)][string]$Text)
    $secure = New-Object System.Security.SecureString
    foreach ($char in $Text.ToCharArray()) { $secure.AppendChar($char) }
    return $secure
}

Add-SpawnNewTest 'Gespeichertes Geheimnis wird wieder gelesen' {
    Set-SpawnNewSecret -Name 'openai' -Value (ConvertTo-TestSecure 'sk-test-Ümlaut-123')

    Confirm-SpawnNewValue -Label 'Wert' -Actual (Get-SpawnNewSecret -Name 'openai') -Expected 'sk-test-Ümlaut-123'
    Confirm-SpawnNewValue -Label 'vorhanden' -Actual (Test-SpawnNewSecret -Name 'openai') -Expected $true
}

Add-SpawnNewTest 'Die Datei enthaelt den Wert nicht im Klartext' {
    Set-SpawnNewSecret -Name 'openai' -Value (ConvertTo-TestSecure 'sk-geheim-987')
    $raw = [System.IO.File]::ReadAllText((Get-SpawnNewSecretPath -Name 'openai'))
    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($raw))

    Confirm-SpawnNewCondition -Label 'kein Klartext' -Condition ($raw -notmatch 'geheim' -and $decoded -notmatch 'geheim')
}

Add-SpawnNewTest 'Geheimnisse liegen im Benutzerdatenbereich' {
    Set-SpawnNewSecret -Name 'x' -Value (ConvertTo-TestSecure 'wert')
    $expected = Join-Path (Join-Path $env:LOCALAPPDATA 'SpawnNew') 'Secrets'

    Confirm-SpawnNewValue -Label 'Ordner' -Actual (Split-Path -Parent (Get-SpawnNewSecretPath -Name 'x')) -Expected $expected
}

Add-SpawnNewTest 'Fehlendes Geheimnis wird erkannt' {
    Confirm-SpawnNewValue -Label 'vorhanden' -Actual (Test-SpawnNewSecret -Name 'fehlt') -Expected $false

    $message = ''
    try { [void](Get-SpawnNewSecret -Name 'fehlt') } catch { $message = $_.Exception.Message }
    Confirm-SpawnNewMatch -Label 'Meldung' -Actual $message -Pattern 'nicht gespeichert'
}

Add-SpawnNewTest 'Fremd verschluesselte Datei wird abgewiesen' {
    [void](Add-SpawnNewTestFile -Path (Get-SpawnNewSecretPath -Name 'kaputt') -Content ([System.Convert]::ToBase64String([byte[]](1..64))))

    Confirm-SpawnNewValue -Label 'vorhanden' -Actual (Test-SpawnNewSecret -Name 'kaputt') -Expected $false
}

Add-SpawnNewTest 'Ungueltiger Name wird abgewiesen' {
    $message = ''
    try { [void](Get-SpawnNewSecretPath -Name '..\boese') } catch { $message = $_.Exception.Message }
    Confirm-SpawnNewMatch -Label 'Meldung' -Actual $message -Pattern 'Ungültiger Name'
}

Add-SpawnNewTest 'Namen werden ohne Werte aufgelistet und lassen sich entfernen' {
    Set-SpawnNewSecret -Name 'b' -Value (ConvertTo-TestSecure '2')
    Set-SpawnNewSecret -Name 'a' -Value (ConvertTo-TestSecure '1')

    Confirm-SpawnNewValue -Label 'Namen' -Actual ((Get-SpawnNewSecretName) -join ',') -Expected 'a,b'

    Remove-SpawnNewSecret -Name 'a'
    Confirm-SpawnNewValue -Label 'nach Entfernen' -Actual ((Get-SpawnNewSecretName) -join ',') -Expected 'b'
}
