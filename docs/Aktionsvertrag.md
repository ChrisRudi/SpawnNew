<!-- docs/Aktionsvertrag.md | Version 1.3 | 26.10.2026 -->

# Ausfuehrungsvertrag der PowerShell-Aktionen

Verbindlicher Vertrag zwischen dem Ausfuehrungsprozess (`SpawnNew.Host.ps1`)
und einem Aktionsskript. Deckt Abschnitt 8 aus `SpawnNew.md` ab.

## 1. Aufruf

Der Ausfuehrungsprozess startet die Aktion so:

```
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass
               -File "<entryPoint>" -ContextFile "<Pfad zur Kontext-JSON>"
```

Arbeitsverzeichnis ist das Laufverzeichnis der Kontextdatei, nie der
Explorer-Ordner: ein Prozess mit dem Ziel als aktuellem Verzeichnis sperrt
es gegen Verschieben und Loeschen.

`-ContextFile` ist der einzige Parameter. Alle Eingaben und Pfade stehen in
der Kontextdatei, nicht in der Befehlszeile. Damit kann kein Eingabewert in
einen PowerShell-Ausdruck geraten (Entwicklungsregel 12, `SpawnNew.md` Abschnitt 7).

Jedes Aktionsskript beginnt mit:

```powershell
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ContextFile)
```

## 2. Kontextdatei

UTF-8 ohne BOM, vom Ausfuehrungsprozess geschrieben, von der Aktion nur
gelesen.

```json
{
  "schemaVersion": 1,
  "actionId": "spawnnew.gitproject",
  "actionDirectory": "C:\\Program Files\\SpawnNew\\App\\Actions\\GitProjekt",
  "explorerPath": "D:\\Projekte",
  "targetPath": "D:\\Projekte\\Neues Projekt",
  "targetExisted": false,
  "conflictPolicy": "fail",
  "fields": { "name": "Neues Projekt", "gitignore": "VisualStudio" },
  "progressFile": "C:\\Users\\x\\AppData\\Local\\Temp\\sn-1a2b\\progress.jsonl",
  "resultFile":   "C:\\Users\\x\\AppData\\Local\\Temp\\sn-1a2b\\result.json",
  "cancelFile":   "C:\\Users\\x\\AppData\\Local\\Temp\\sn-1a2b\\cancel.flag",
  "proposalFile": "",
  "appDirectory": "C:\\Users\\x\\AppData\\Local\\SpawnNew\\App",
  "llm": { "name": "Lokal", "baseUrl": "http://localhost:11434/v1",
           "model": "llama3.2", "timeoutSeconds": 180, "secret": "" },
  "culture": "de-DE"
}
```

| Feld | Bedeutung |
|---|---|
| `targetPath` | Vom Benutzer bestaetigter, normalisierter Zielpfad. Existiert unter Umstaenden schon |
| `targetExisted` | `true`, wenn der Benutzer "vorhandenen Ordner verwenden" gewaehlt hat |
| `conflictPolicy` | `fail`, `rename` oder `overwrite`. Gilt fuer Dateien im Zielpfad |
| `fields` | Formularwerte, Schluessel sind die Feldnamen aus `action.json` |
| `cancelFile` | Pfad. Existiert die Datei, hat der Benutzer Abbruch angefordert |
| `proposalFile` | Vorschlag aus Abschnitt 12, sonst leer |
| `appDirectory` | Programmverzeichnis mit `SpawnNew.Action.psm1` und den uebrigen Modulen |
| `llm` | Gewaehlter KI-Endpunkt oder `null`. `secret` ist nur der Name des Geheimnisses, nie der Wert |
| `culture` | Kultur des Ausfuehrungsprozesses, etwa `de-DE` |

Fuer `targetKind: folder` steht der Ordnername immer unter `fields.name`,
auch wenn er aus `nameTemplate` gebildet wurde.

`targetPath` entsteht je nach `targetKind` der Aktion: bei `folder` aus dem
bestaetigten Basisverzeichnis und dem Feld `name`, bei `inPlace` aus dem
Basisverzeichnis selbst. Die Angaben `targetKind`, `supportsCancel` und
`allowsOverwrite` sowie die zulaessigen Feldtypen stehen in
`docs/Dateiliste.md` Abschnitt 8.

Werte in `fields` sind bereits geprueft und normalisiert: Zeichenketten ohne
fuehrenden und folgenden Leerraum, Datumsangaben als `yyyy-MM-dd`,
Wahrheitswerte als echte JSON-Wahrheitswerte, Auswahlwerte aus `choices`.

`conflictPolicy` ist nie `overwrite`, wenn die Aktion das Ueberschreiben
nicht in `action.json` ueber `allowsOverwrite: true` ausdruecklich anbietet
und der Benutzer es in der Zusammenfassung bestaetigt hat.

## 3. Fortschritt

Die Aktion haengt Zeilen an `progressFile` an. Eine Zeile ist ein
JSON-Objekt, UTF-8 ohne BOM, Zeilenende `CRLF`. Der Ausfuehrungsprozess
liest die Datei alle 250 ms ab der letzten Leseposition mit und zeigt sie im
Fortschrittsfenster. Ausgewertet werden nur vollstaendige Zeilen; eine halb
geschriebene Zeile wird beim naechsten Durchgang gelesen. Eine Zeile, die
keine gueltige JSON ist, wird uebersprungen. Ein unbekannter `type` gilt als
`info`, ein `percent` ausserhalb von 0 bis 100 wird geklemmt.

| `type` | Weitere Felder | Bedeutung |
|---|---|---|
| `step` | `text`, `percent` | Neuer Arbeitsschritt, `percent` optional, 0 bis 100 |
| `info` | `text` | Nachrichtenzeile ohne Schrittwechsel |
| `warn` | `text` | Warnung, bricht nicht ab |
| `created` | `kind`, `path` | Erstellte Ressource. `kind` ist `folder`, `file` oder `repository` |

Beispiel:

```
{"type":"step","text":"Ordner anlegen","percent":10}
{"type":"created","kind":"folder","path":"D:\\Projekte\\Neues Projekt"}
```

Vertrauliche Eingaben gehoeren nicht in den Fortschritt (Abschnitt 9).

## 4. Ergebnisdatei

Die Aktion schreibt `resultFile` als letzten Schritt, UTF-8 ohne BOM.

```json
{
  "schemaVersion": 1,
  "status": "success",
  "message": "Repository angelegt.",
  "created": [ { "kind": "folder", "path": "D:\\Projekte\\Neues Projekt" } ],
  "error": null
}
```

| `status` | Bedeutung |
|---|---|
| `success` | Alles erstellt |
| `partial` | Teilweise erstellt, `created` zaehlt auf, was bleibt |
| `nochange` | Keine fachliche Aenderung erfolgt |
| `cancelled` | Abbruch beachtet. `created` zaehlt auf, was bleibt |
| `failed` | Fehlgeschlagen. `error` ist gefuellt |

`error`:

```json
{ "step": "Git initialisieren", "reason": "git.exe nicht gefunden",
  "details": "..." }
```

## 5. Rueckgabewert

| Code | Bedeutung |
|---|---|
| 0 | `success` oder `nochange` |
| 1 | `failed` |
| 2 | `partial` |
| 3 | `cancelled` |

Bei Abweichung zwischen Rueckgabewert und Ergebnisdatei gilt die
Ergebnisdatei. Fehlt die Ergebnisdatei, meldet der Ausfuehrungsprozess
`unknown` (`SpawnNew.md` Abschnitt 10: "Status unbekannt").

## 6. Abbruch

`action.json` deklariert `supportsCancel`. Bei `true` prueft die Aktion
zwischen Arbeitsschritten, ob `cancelFile` existiert, bricht ab und
schreibt `status: "cancelled"`.

Bei `false` zeigt der Ausfuehrungsprozess den Abbruch als angefordert an und
wartet auf das Ende des Prozesses. Der Ausfuehrungsprozess beendet den
Aktionsprozess nicht von sich aus. Die Abbruchdatei wird in beiden Faellen
angelegt, damit eine Aktion sie auch dann auswerten kann, wenn sie den
Abbruch nicht deklariert hat.

## 7. Prozessbeendigung

Endet der Aktionsprozess ohne Ergebnisdatei, meldet der Ausfuehrungsprozess
`unknown` und nennt die bis dahin aus dem Fortschritt bekannten Ressourcen.
Eine Prozessbeendigung wird nie als Erfolg oder als gelungenes Zuruecksetzen
dargestellt (`SpawnNew.md` Abschnitt 10).

## 8. Aufraeumen

`action.json` kann `cleanup` als relativen Pfad zu einem zweiten Skript
angeben. Aufruf nur nach `partial`, `cancelled`, `failed` oder `unknown`,
und nur nach ausdruecklicher Bestaetigung durch den Benutzer:

```
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass
               -File "<cleanup>" -ContextFile "<Kontext-JSON>"
                                 -ResultFile  "<Ergebnis-JSON der Aktion>"
```

Das Aufraeumen wird nur angeboten, wenn die Aktion `cleanup` nennt, der
Status `partial`, `cancelled`, `failed` oder `unknown` lautet und mindestens
eine Ressource erstellt wurde. Der Benutzer bestaetigt es ausdruecklich.

Das Aufraeumskript darf ausschliesslich Ressourcen entfernen, die in
`created` der Ergebnisdatei oder im Fortschritt stehen. Es schreibt eine
eigene Ergebnisdatei im Format aus Abschnitt 4. Aufraeumen ist keine
Transaktion und macht externe Aenderungen nicht zwingend rueckgaengig.

## 9. Rechte

`requiresAdmin: false` ist die Vorgabe. Bei `true` zeigt der
Ausfuehrungsprozess die Rechteanforderung in der Zusammenfassung an und
startet den Aktionsprozess erst nach "Erstellen" erhoeht. Eine abgelehnte
Rechteabfrage endet mit `status: "nochange"` ohne fachliche Aenderung.

Der Ausfuehrungsprozess selbst laeuft nicht erhoeht. Es gibt keinen
dauerhaft erhoehten Hintergrundprozess.

## 10. Erneute Pruefung vor dem Start

Direkt vor dem Start prueft der Ausfuehrungsprozess erneut:
Quelle erreichbar, `action.json` unveraendert lesbar und gueltig,
`entryPoint` vorhanden, Aktions-ID identisch. Bei Abweichung startet nichts
und der Benutzer erhaelt eine Meldung (Abschnitt 6, Abnahme 14).

## 11. Pflichten der Aktion in Kurzform

- Nur `-ContextFile` als Parameter lesen.
- Keine eigenen Konsolenabfragen, keine `Read-Host`, keine `Write-Host`.
- Jede erstellte Ressource als `created` melden.
- Keine stille Ueberschreibung. `conflictPolicy` einhalten.
- Keine undokumentierten globalen Seiteneffekte.
- Ergebnisdatei immer schreiben, auch im Fehlerfall.
- Modellausgabe nur als gekennzeichneten Entwurf oder nach Bestaetigung
  ueber einen Vorschlag schreiben, nie ueber eine vorhandene Datei.

## 12. Vorschlagsskript

`action.json` kann `proposal` als relativen Pfad zu einem zweiten Skript
nennen. Es laeuft nach dem Formular und vor der Zusammenfassung, mit
derselben Befehlszeile und einer Kontextdatei, deren `proposalFile` auf eine
noch nicht vorhandene Datei zeigt. Das Skript

- darf ausserhalb seines Laufverzeichnisses nichts anlegen oder aendern,
- schreibt `proposalFile` als UTF-8 ohne BOM:
  `{ "text": "<fuer die Zusammenfassung>", "data": <beliebig> }`,
- meldet Fortschritt und Ergebnis wie eine Aktion.

Nur bei `status: "success"` und nicht leerem `text` zeigt der
Ausfuehrungsprozess die Zusammenfassung mit dem Vorschlag; sonst endet er
ohne Aenderung. Nach "Erstellen" erhaelt die Aktion denselben Pfad in
`proposalFile` und setzt `data` um, ohne das Modell erneut zu fragen. So
entsteht genau das, was in der Zusammenfassung stand. Die Aktion prueft
`data` vor der Umsetzung noch einmal.

## 13. Hilfsmodul `SpawnNew.Action.psm1`

Aktionen koennen das Modul aus `appDirectory` laden und so den Vertrag
einhalten, ohne ihn selbst auszuprogrammieren:

| Funktion | Zweck |
|---|---|
| `Initialize-SpawnNewAction` | Kontext lesen, Laufzustand anlegen |
| `Get-SpawnNewActionField`, `Test-SpawnNewActionFlag` | Formularwerte |
| `Write-SpawnNewActionStep`, `Write-SpawnNewActionNote` | Schritt, Hinweis, Warnung |
| `New-SpawnNewActionFolder`, `Write-SpawnNewActionText` | Ordner und Dateien mit Meldung, ohne stilles Ueberschreiben |
| `New-SpawnNewActionDocument` | Dokument aus Vorlage, Markdown oder Word |
| `Assert-SpawnNewActionEndpoint`, `Invoke-SpawnNewActionChat` | KI-Endpunkt pruefen und fragen |
| `Write-SpawnNewActionDraft` | Modellausgabe als gekennzeichneten Entwurf mit freiem Namen ablegen |
| `Test-SpawnNewActionCancel` | Abbruch angefordert? |
| `Complete-SpawnNewAction` | Ergebnisdatei schreiben; liefert den Rueckgabewert |
| `Complete-SpawnNewActionCancelled`, `Complete-SpawnNewActionFailed` | dasselbe fuer Abbruch und Fehler |

Die `Complete`-Funktionen beenden den Prozess nicht selbst; das Skript ruft
`exit (Complete-SpawnNewAction ...)`. Eine Warnung ueber
`Write-SpawnNewActionNote -Warning` macht aus `success` ein `partial`.
