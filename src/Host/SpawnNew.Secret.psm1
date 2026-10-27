# SpawnNew.Secret.psm1
# Version 1.0 | Geheimnisse benutzer- und rechnergebunden speichern.
# Zweck  : API-Schluessel und aehnliche Werte getrennt von Konfiguration,
#          Aktionen und Programmdateien ablegen. Verschluesselung ueber DPAPI
#          im Benutzerkontext; die Maschinenkennung geht als zusaetzliche
#          Entropie ein, damit eine kopierte Datei auf einem anderen Rechner
#          nicht entschluesselt werden kann.
# Input  : Name des Geheimnisses, Wert als SecureString oder Zeichenkette.
# Output : Get-SpawnNewSecret liefert den Klartext nur an den Aufrufer. Kein
#          Wert erscheint je in Protokoll, Fortschritt oder Kontextdatei.
# Deps   : Windows PowerShell 5.1, System.Security, SpawnNew.Config.psm1.

Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Security

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')

$script:NamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

function Test-SpawnNewSecretName {
    <#
    .SYNOPSIS
    Prueft den Namen eines Geheimnisses. Der Name wird Dateiname.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    return ($Name -match $script:NamePattern)
}

function Get-SpawnNewSecretDirectory {
    <#
    .SYNOPSIS
    Ablage der Geheimnisse, immer lokal: DPAPI bindet sie an Benutzer und Rechner.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return (Join-Path (Get-SpawnNewLocalDirectory) 'Secrets')
}

function Get-SpawnNewSecretPath {
    <#
    .SYNOPSIS
    Datei eines Geheimnisses. Wirft bei ungueltigem Namen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Test-SpawnNewSecretName -Name $Name)) {
        throw "Ungültiger Name für ein Geheimnis: '$Name'. Erlaubt sind Buchstaben, Ziffern, Punkt, Strich und Unterstrich."
    }
    return (Join-Path (Get-SpawnNewSecretDirectory) ($Name + '.secret'))
}

function Get-SpawnNewSecretEntropy {
    <#
    .SYNOPSIS
    Zusaetzliche Entropie aus der Maschinenkennung.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param()

    $machine = ''
    try {
        $key = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop
        $machine = [string]$key.MachineGuid
    }
    catch {
        $machine = [System.Environment]::MachineName
    }
    return [System.Text.Encoding]::UTF8.GetBytes('SpawnNew|' + $machine)
}

function ConvertTo-SpawnNewPlainText {
    <#
    .SYNOPSIS
    Klartext aus einem SecureString, nur fuer die Verschluesselung.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Security.SecureString]$Value)

    $pointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Set-SpawnNewSecret {
    <#
    .SYNOPSIS
    Speichert ein Geheimnis verschluesselt.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.Security.SecureString]$Value
    )

    $path = Get-SpawnNewSecretPath -Name $Name
    if (-not $PSCmdlet.ShouldProcess($Name, 'Geheimnis speichern')) { return }

    $plain = ConvertTo-SpawnNewPlainText -Value $Value
    if ($plain.Length -eq 0) { throw 'Ein leeres Geheimnis wird nicht gespeichert.' }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
    $scope = [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    $cipher = [System.Security.Cryptography.ProtectedData]::Protect($bytes, (Get-SpawnNewSecretEntropy), $scope)
    [System.Array]::Clear($bytes, 0, $bytes.Length)

    $directory = Split-Path -Parent $path
    if (-not [System.IO.Directory]::Exists($directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
    [System.IO.File]::WriteAllText($path, [System.Convert]::ToBase64String($cipher), (New-Object System.Text.UTF8Encoding $false))
}

function Test-SpawnNewSecret {
    <#
    .SYNOPSIS
    Prueft, ob ein Geheimnis gespeichert ist und entschluesselt werden kann.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Test-SpawnNewSecretName -Name $Name)) { return $false }
    try { return ((Get-SpawnNewSecret -Name $Name).Length -gt 0) }
    catch { return $false }
}

function Get-SpawnNewSecret {
    <#
    .SYNOPSIS
    Liest ein Geheimnis als Klartext. Nur fuer den unmittelbaren Gebrauch,
    nie fuer Ausgaben.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)

    $path = Get-SpawnNewSecretPath -Name $Name
    if (-not [System.IO.File]::Exists($path)) { throw "Das Geheimnis '$Name' ist nicht gespeichert." }

    try {
        $cipher = [System.Convert]::FromBase64String([System.IO.File]::ReadAllText($path).Trim())
        $scope  = [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        $bytes  = [System.Security.Cryptography.ProtectedData]::Unprotect($cipher, (Get-SpawnNewSecretEntropy), $scope)
    }
    catch {
        throw "Das Geheimnis '$Name' lässt sich nicht entschlüsseln. Es wurde für einen anderen Benutzer oder Rechner gespeichert."
    }

    try { return [System.Text.Encoding]::UTF8.GetString($bytes) }
    finally { [System.Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-SpawnNewSecretName {
    <#
    .SYNOPSIS
    Namen aller gespeicherten Geheimnisse, ohne Werte.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $directory = Get-SpawnNewSecretDirectory
    if (-not [System.IO.Directory]::Exists($directory)) { return [string[]]@() }
    return [string[]]@(Get-ChildItem -LiteralPath $directory -Filter '*.secret' -File | ForEach-Object { $_.BaseName } | Sort-Object)
}

function Remove-SpawnNewSecret {
    <#
    .SYNOPSIS
    Entfernt ein Geheimnis.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)

    $path = Get-SpawnNewSecretPath -Name $Name
    if (-not [System.IO.File]::Exists($path)) { return }
    if ($PSCmdlet.ShouldProcess($Name, 'Geheimnis entfernen')) { Remove-Item -LiteralPath $path -Force }
}

Export-ModuleMember -Function Test-SpawnNewSecretName, Get-SpawnNewSecretDirectory, Get-SpawnNewSecretPath, Set-SpawnNewSecret, Test-SpawnNewSecret, Get-SpawnNewSecret, Get-SpawnNewSecretName, Remove-SpawnNewSecret
