# tools/Install-DevTools.ps1
# Version 1.0 | Richtet die Pruefwerkzeuge fuer SpawnNew ein.
# Zweck  : PSScriptAnalyzer bereitstellen, auch ohne Zugriff auf die PSGallery.
# Input  : -Version der Modulversion; -Scope Installationsumfang.
# Output : Installierte Modulversion auf stdout.
# Deps   : PowerShell 7 (pwsh). Internetzugriff auf github.com.

[CmdletBinding()]
param(
    [string]$Version = '1.23.0',
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser'
)

$ErrorActionPreference = 'Stop'

$existing = Get-Module PSScriptAnalyzer -ListAvailable |
    Where-Object { $_.Version -ge [version]$Version } |
    Select-Object -First 1

if ($existing) {
    Write-Output ('PSScriptAnalyzer {0} ist vorhanden.' -f $existing.Version)
    exit 0
}

try {
    Install-Module PSScriptAnalyzer -RequiredVersion $Version -Scope $Scope `
        -Force -ErrorAction Stop
    Write-Output ('PSScriptAnalyzer {0} aus der PSGallery installiert.' -f $Version)
    exit 0
}
catch {
    Write-Output ('PSGallery nicht erreichbar: {0}' -f $_.Exception.Message)
    Write-Output 'Weiche auf das Release-Paket von github.com aus.'
}

# Fallback fuer Umgebungen, in denen powershellgallery.com gesperrt ist:
# das Release-nupkg ist ein ZIP und wird direkt in den Modulpfad entpackt.
$moduleRoot = if ($Scope -eq 'AllUsers') {
    Join-Path (Split-Path -Parent $PSHOME) (Join-Path '7' 'Modules')
}
else {
    Join-Path (Split-Path -Parent $PROFILE) 'Modules'
}

$target = Join-Path (Join-Path $moduleRoot 'PSScriptAnalyzer') $Version
$url    = 'https://github.com/PowerShell/PSScriptAnalyzer/releases/download/' +
          ('{0}/PSScriptAnalyzer.{0}.nupkg' -f $Version)

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('psa-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    $package = Join-Path $work 'psa.zip'
    Invoke-WebRequest -Uri $url -OutFile $package -UseBasicParsing

    $unpacked = Join-Path $work 'unpacked'
    Expand-Archive -LiteralPath $package -DestinationPath $unpacked -Force

    # Verpackungsdateien des NuGet-Formats gehoeren nicht in den Modulordner.
    $skip = @('_rels', 'package', '[Content_Types].xml')
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Get-ChildItem -LiteralPath $unpacked |
        Where-Object { $skip -notcontains $_.Name } |
        Copy-Item -Destination $target -Recurse -Force
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Import-Module (Join-Path $target 'PSScriptAnalyzer.psd1') -ErrorAction Stop
Write-Output ('PSScriptAnalyzer {0} nach {1} entpackt.' -f $Version, $target)
