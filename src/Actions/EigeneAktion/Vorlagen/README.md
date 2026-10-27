<!-- README.md | Version 1.0 | {{datum}} -->

# {{name}}

{{beschreibung}}

Eigene SpawnNew-Aktion mit der Aktions-ID `{{id}}`, angelegt am {{datum}}.

## Dateien

| Datei | Inhalt |
|---|---|
| `action.json` | Beschreibung: ID, Menüname, Formularfelder, geplante Schritte |
| `Invoke-SpawnAction.ps1` | Einstiegsskript, bekommt nur `-ContextFile` |
| `README.md` | diese Datei |

## Anpassen

1. In `action.json` unter `fields` die Formularfelder festlegen. Feldtypen:
   `text`, `multiline`, `date`, `choice`, `bool`, `file`, `endpoint`.
2. In `Invoke-SpawnAction.ps1` zwischen den markierten Zeilen arbeiten.
   Formularwerte liest `Get-SpawnNewActionField`, Dateien schreibt
   `Write-SpawnNewActionText` ohne stilles Überschreiben.
3. `plannedSteps` beschreibt die Schritte für die Zusammenfassung vor dem Start.

Die Aktion erscheint nach dem nächsten Aufruf eines SpawnNew-Eintrags im
Menü, sofort über **SpawnNew konfigurieren > Menü neu einlesen**.

Dieselbe Aktions-ID wie eine mitgelieferte Aktion ersetzt diese, weil
persönliche Quellen Vorrang haben. Eine neue ID ergänzt das Menü.
