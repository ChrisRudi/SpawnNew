<!-- README.md | Version 1.0 | 26.10.2026 -->

# SpawnNew

Explorer-Kontextmenue fuer vorbereitete Arbeitsumgebungen unter Windows 10
und Windows 11. Anforderungen und Abnahmekriterien stehen in
[`SpawnNew.md`](SpawnNew.md).

## Stand

| Umsetzungsschritt (`SpawnNew.md` Abschnitt 13) | Stand |
|---|---|
| 1. Dateinamen, Konfiguration, IDs, Prioritaet, Schnittstellenvertrag | fertig, siehe `docs/` |
| 2. Explorer-Prototyp Windows 10 und 11 | offen |
| 3. Quellen, Prioritaet, IDs, Nachladen, Cache, Beschreibungspruefung | fertig, `src/Host/SpawnNew.Config.psm1`, `.Catalog.psm1`, `.Resolve.psm1` |
| 4. Formular, Zusammenfassung, PowerShell-Start | offen |
| 5. Fortschritt, Fehler, Rechte, Aufraeumen | offen |
| 6. Sieben mitgelieferte Aktionen | offen |
| 7. Installation, Aktualisierung, Konfiguration, Deinstallation | offen |
| 8. Menueeintraege fuer Installation und Aktualisierung | offen |
| 9. Abnahme auf Windows 10 und 11 | offen |

## Aufbau

| Pfad | Inhalt |
|---|---|
| `SpawnNew.md` | Konzept und Anforderungen |
| `docs/Dateiliste.md` | festgelegte Dateinamen, Ablage, Konfigurationsschichten, ID-Regeln |
| `docs/Aktionsvertrag.md` | Vertrag zwischen Ausfuehrungsprozess und Aktionsskript |
| `config/` | mitgelieferte Standardkonfiguration |
| `src/Host/` | Ausfuehrungsprozess, Windows PowerShell 5.1 |
| `src/Explorer/` | native Explorer-Erweiterung, C++ |
| `src/Actions/` | mitgelieferte Aktionen |
| `tools/` | Pruefwerkzeuge, nicht Teil der Installation |

## Pruefen

Der Code laeuft unter Windows PowerShell 5.1. Geprueft wird mit PowerShell 7
und PSScriptAnalyzer, der die 5.1-Kompatibilitaet mitprueft
(`PSUseCompatibleSyntax`, `PSUseCompatibleCommands`).

```
pwsh -NoProfile -File tools/Install-DevTools.ps1
pwsh -NoProfile -File tools/Invoke-Lint.ps1
```

`Invoke-Lint.ps1` endet mit Rueckgabewert 1, sobald Befunde ab Stufe
`Warning` auftreten. `-Severity Information` zeigt auch Hinweise.

## Bauen

Die Explorer-Erweiterung aus `src/Explorer/` ist eine x64-DLL und braucht
Visual Studio mit dem Windows SDK. Sie ist noch nicht umgesetzt.
