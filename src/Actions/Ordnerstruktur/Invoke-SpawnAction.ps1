# Invoke-SpawnAction.ps1
# Version 1.1 | Aktion 1: Ordnerstruktur.
# Zweck  : Zielordner anlegen, die Unterordner der gewaehlten Strukturvorlage
#          erzeugen, deklarierte NTFS-Rechte setzen und eine README.md
#          schreiben.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
# Output : Fortschritt in progressFile, Ergebnis in resultFile.
#          Rueckgabewert nach Abschnitt 5 des Vertrags.
# Deps   : Windows PowerShell 5.1, Vorlagen.json im Aktionsverzeichnis.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$ContextFile)

$ErrorActionPreference = 'Stop'

$utf8    = New-Object System.Text.UTF8Encoding $false
$context = ConvertFrom-Json ([System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8))
$created = New-Object System.Collections.ArrayList

function Write-ProgressLine {
    param([Parameter(Mandatory)][hashtable]$Entry)

    $line = (ConvertTo-Json -InputObject ([pscustomobject]$Entry) -Compress) + "`r`n"
    [System.IO.File]::AppendAllText($context.progressFile, $line, $utf8)
}

function Add-Created {
    param([string]$Kind, [string]$Path)

    [void]$created.Add([pscustomobject]@{ kind = $Kind; path = $Path })
    Write-ProgressLine -Entry @{ type = 'created'; kind = $Kind; path = $Path }
}

function Write-Result {
    param([string]$Status, [string]$Message, $Failure = $null)

    $result = [pscustomobject]@{
        schemaVersion = 1
        status        = $Status
        message       = $Message
        created       = $created.ToArray()
        error         = $Failure
    }
    $json = ConvertTo-Json -InputObject $result -Depth 5
    [System.IO.File]::WriteAllText($context.resultFile, $json, $utf8)
}

function Test-Cancelled {
    return [System.IO.File]::Exists($context.cancelFile)
}

function Get-RuleIdentity {
    # AKTUELLER_BENUTZER, eine SID mit fuehrendem * oder ein Kontoname.
    # SIDs sind sprachunabhaengig; 'Administratoren' heisst nur auf
    # deutschem Windows so.
    param([string]$Name)

    if ($Name -eq 'AKTUELLER_BENUTZER') { return [System.Security.Principal.WindowsIdentity]::GetCurrent().User }
    if ($Name.StartsWith('*')) { return (New-Object System.Security.Principal.SecurityIdentifier($Name.Substring(1))) }
    return (New-Object System.Security.Principal.NTAccount($Name))
}

function Grant-FolderRight {
    # Setzt die deklarierten NTFS-Rechte selbst. Ein Kopieren ueber den
    # Explorer wuerde nur die Rechte des Elternordners erben.
    param([string]$Path, $Rule)

    $directory = New-Object System.IO.DirectoryInfo($Path)
    $acl = $directory.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [System.Security.AccessControl.PropagationFlags]::None

    $trennen = ($Rule.PSObject.Properties.Name -contains 'vererbungTrennen') -and [bool]$Rule.vererbungTrennen
    if ($trennen) {
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($existing in @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))) { [void]$acl.RemoveAccessRuleSpecific($existing) }
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', $inherit, $none, 'Allow')))
    }

    $regeln = @()
    if ($Rule.PSObject.Properties.Name -contains 'regeln') { $regeln = @($Rule.regeln) }
    foreach ($regel in $regeln) {
        $typ = 'Allow'
        if ($regel.PSObject.Properties.Name -contains 'typ') { $typ = [string]$regel.typ }
        $identity = Get-RuleIdentity -Name ([string]$regel.identitaet)
        $right = [System.Security.AccessControl.FileSystemRights]([string]$regel.recht)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $right, $inherit, $none, $typ)))
    }

    $directory.SetAccessControl($acl)
}

try {
    Write-ProgressLine -Entry @{ type = 'step'; text = 'Zielordner anlegen'; percent = 10 }

    if (-not [System.IO.Directory]::Exists($context.targetPath)) {
        [void](New-Item -ItemType Directory -Path $context.targetPath -Force)
        Add-Created -Kind 'folder' -Path $context.targetPath
    }

    $vorlagenDatei = Join-Path $context.actionDirectory 'Vorlagen.json'
    $vorlagen = (ConvertFrom-Json ([System.IO.File]::ReadAllText($vorlagenDatei, [System.Text.Encoding]::UTF8))).vorlagen
    $name = [string]$context.fields.vorlage

    if (-not ($vorlagen.PSObject.Properties.Name -contains $name)) {
        Write-Result -Status 'partial' -Message ("Die Strukturvorlage '$name' ist in Vorlagen.json nicht enthalten.") `
            -Failure ([pscustomobject]@{ step = 'Vorlage lesen'; reason = "Unbekannte Strukturvorlage '$name'."; details = '' })
        exit 2
    }

    # Eintraege sind Ordnernamen oder Objekte mit pfad und rechte.
    $eintraege = @($vorlagen.$name | ForEach-Object {
            if ($_ -is [string]) { [pscustomobject]@{ Pfad = $_; Rechte = $null } }
            else { [pscustomobject]@{ Pfad = [string]$_.pfad; Rechte = $(if ($_.PSObject.Properties.Name -contains 'rechte') { $_.rechte } else { $null }) } }
        })
    $ordner = @($eintraege | ForEach-Object { $_.Pfad })
    Write-ProgressLine -Entry @{ type = 'step'; text = ('Unterordner der Vorlage ' + $name + ' anlegen'); percent = 40 }

    foreach ($eintrag in $eintraege) {
        if (Test-Cancelled) {
            Write-Result -Status 'cancelled' -Message 'Abbruch nach dem Anlegen der bisherigen Ordner.'
            exit 3
        }

        $pfad = Join-Path $context.targetPath $eintrag.Pfad
        if (-not [System.IO.Directory]::Exists($pfad)) {
            [void](New-Item -ItemType Directory -Path $pfad -Force)
            Add-Created -Kind 'folder' -Path $pfad
        }

        if ($null -ne $eintrag.Rechte) {
            Grant-FolderRight -Path $pfad -Rule $eintrag.Rechte
            Write-ProgressLine -Entry @{ type = 'info'; text = ('Rechte gesetzt: ' + $eintrag.Pfad) }
        }
    }

    Write-ProgressLine -Entry @{ type = 'step'; text = 'README.md anlegen'; percent = 80 }
    $readme = Join-Path $context.targetPath 'README.md'

    if ([System.IO.File]::Exists($readme) -and $context.conflictPolicy -ne 'overwrite') {
        Write-ProgressLine -Entry @{ type = 'warn'; text = 'README.md ist vorhanden und wird nicht angetastet.' }
        Write-Result -Status 'partial' -Message 'Ordnerstruktur angelegt, vorhandene README.md unveraendert.'
        exit 2
    }

    $zweck = [string]$context.fields.zweck
    if ($zweck.Length -eq 0) { $zweck = '(kein Zweck angegeben)' }

    $zeilen = @(
        ('# ' + $context.fields.name),
        '',
        ('Angelegt am ' + (Get-Date -Format 'dd.MM.yyyy') + ' mit SpawnNew, Strukturvorlage ' + $name + '.'),
        '',
        '## Zweck',
        '',
        $zweck,
        '',
        '## Ordner',
        ''
    )
    foreach ($eintrag in $ordner) { $zeilen += ('- `' + $eintrag + '`') }

    [System.IO.File]::WriteAllText($readme, ($zeilen -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding $true))
    Add-Created -Kind 'file' -Path $readme

    Write-ProgressLine -Entry @{ type = 'step'; text = 'Fertig'; percent = 100 }
    Write-Result -Status 'success' -Message ('Ordnerstruktur ' + $name + ' angelegt.')
    exit 0
}
catch {
    $failure = [pscustomobject]@{
        step    = 'Ordnerstruktur anlegen'
        reason  = $_.Exception.Message
        details = ([string]$_.ScriptStackTrace)
    }
    $status = if ($created.Count -gt 0) { 'partial' } else { 'failed' }
    Write-Result -Status $status -Message 'Die Aktion wurde nicht vollstaendig ausgefuehrt.' -Failure $failure
    if ($status -eq 'partial') { exit 2 }
    exit 1
}
