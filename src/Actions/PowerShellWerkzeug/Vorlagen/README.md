<!-- README.md | Version 1.0 | {{datum}} -->

# {{name}}

{{zweck}}

## Aufruf

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\{{name}}.ps1
```

## Parameter

| Parameter | Bedeutung |
|---|---|
| `-ConfigFile` | Pfad zur Konfiguration; Vorgabe ist `{{name}}.config.json` neben dem Skript |
| `-Verbose` | Zeigt, welche Konfiguration gilt und was das Skript tut |

## Konfiguration

{{konfiguration}}

## Voraussetzungen

Windows PowerShell 5.1. Angelegt am {{datum}} mit SpawnNew.
