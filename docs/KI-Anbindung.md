<!-- docs/KI-Anbindung.md | Version 1.0 | 26.10.2026 -->

# KI-Anbindung

Umsetzung von `SpawnNew.md` Abschnitt 9, Umsetzungsschritte 7 und 8.

## 1. Was ein Sprachmodell darf

| Aktion | Nutzung | Weg nach Abschnitt 9 |
|---|---|---|
| 7 Werkstättenprotokoll | optional, Feld "Entwurf vom Sprachmodell" | `Protokoll.Entwurf.md` neben dem Protokoll |
| 10 Fehleranalyse | optional | `Fehleranalyse.Entwurf.md` |
| 11 Sitzung | optional | `Tagesordnung.Entwurf.md` |
| 17 Ordnerstruktur aus Beschreibung | immer | Vorschlag in der Zusammenfassung, angelegt erst nach "Erstellen" |
| 18 Datei zusammenfassen | immer | `<Name>.Zusammenfassung.Entwurf.md` neben der Quelle |
| 19 Ordner dokumentieren | immer | `README.Entwurf.md` im Ordner |

Ein Entwurf beginnt mit einem Hinweis **ENTWURF**, Datum, Modell, Endpunkt
und Grundlage. Er bekommt bei vorhandener Datei einen freien Namen
(`... (2).md`) und ueberschreibt nie etwas, auch nicht bei bestaetigter
Ueberschreibungsregel. Scheitert der Modellaufruf in 7, 10 oder 11, bleiben
die Dokumente erhalten und der Status lautet `partial`.

Das Oeffnen des Kontextmenues ruft nie ein Modell auf und erzeugt keinen
Netzzugriff.

## 2. Endpunkte

Angesprochen wird ein OpenAI-kompatibler Endpunkt: `GET <baseUrl>/models`
fuer die Erreichbarkeit, `POST <baseUrl>/chat/completions` fuer Anfragen.
Damit gehen Ollama, LM Studio und Webdienste mit diesem Format.

```json
"llm": {
  "defaultEndpoint": "Lokal",
  "endpoints": [
    { "name": "Lokal", "baseUrl": "http://localhost:11434/v1", "model": "llama3.2", "timeoutSeconds": 180 },
    { "name": "LM Studio", "baseUrl": "http://localhost:1234/v1", "model": "qwen2.5-7b-instruct" },
    { "name": "Web", "baseUrl": "https://api.example.org/v1", "model": "modellname", "secret": "web" }
  ]
}
```

| Angabe | Pflicht | Bedeutung |
|---|---|---|
| `name` | ja | Anzeigename, auch Schluessel fuer die Schichtung |
| `baseUrl` | ja | `http://` oder `https://`, ohne `/chat/completions` |
| `model` | nein | Modellname des Dienstes |
| `timeoutSeconds` | nein | Zeitlimit je Anfrage, Vorgabe 120 |
| `secret` | nein | Name des Geheimnisses mit dem API-Schluessel |

Mitgeliefert ist nur der lokale Endpunkt fuer Ollama. Eigene Endpunkte
gehoeren in `%LOCALAPPDATA%\SpawnNew\spawnnew.settings.json`; ein Eintrag
gleichen Namens ersetzt den mitgelieferten. **SpawnNew konfigurieren >
Einstellungen bearbeiten** legt die Datei an und oeffnet sie.

Adressen auf `localhost`, `127.0.0.1` oder den eigenen Rechnernamen werden
ohne Proxy angesprochen; bei einem lokalen Endpunkt verlaesst kein Inhalt
den Rechner.

Aktionen 18 und 19 haben ein Feld "Modell" mit allen konfigurierten
Endpunkten; die uebrigen nutzen `defaultEndpoint`, ohne Angabe den ersten.

## 3. Voraussetzung

Aktionen mit `{ "kind": "endpoint" }` unter `prerequisites` starten nur,
wenn der voreingestellte Endpunkt konfiguriert ist, sein Geheimnis
gespeichert ist und `GET models` innerhalb von 3 Sekunden antwortet.
Andernfalls erscheint "Voraussetzungen fehlen" mit dem Grund; es wird nichts
angelegt und nichts eingerichtet. Alle anderen Aktionen bleiben nutzbar.

Fehlt in 7, 10 oder 11 bei gewuenschtem Entwurf der Endpunkt oder das
Geheimnis, bricht die Aktion vor der ersten Aenderung ab.

## 4. Geheimnisse

- Gespeichert unter `%LOCALAPPDATA%\SpawnNew\Secrets\<Name>.secret`,
  verschluesselt mit DPAPI fuer den aktuellen Benutzer. Die Maschinenkennung
  geht als zusaetzliche Entropie ein; eine kopierte Datei laesst sich auf
  einem anderen Rechner nicht entschluesseln.
- Eingabe ueber **SpawnNew konfigurieren > Geheimnis speichern** mit
  verdecktem Feld. Entfernen ueber **Geheimnis entfernen**.
- Die Kontextdatei, der Fortschritt, die Protokolle, die Zusammenfassung und
  Fehlermeldungen enthalten nur den Namen. Die Aktion holt den Wert selbst
  unmittelbar vor der Anfrage und sendet ihn nur im Kopf
  `Authorization: Bearer`.
- Deinstallation und Aktualisierung lassen `Secrets` unberuehrt.

## 5. Fehler

Ein nicht erreichbarer Endpunkt, ein Zeitlimit oder eine HTTP-Fehlerantwort
ist ein gewoehnlicher Fehler mit Schritt, Endpunkt, Modell, Ursache und
Zeitlimit in der Meldung, etwa:

```
Modellaufruf an 'Lokal' (http://localhost:11434/v1, Modell llama3.2)
fehlgeschlagen (Zeitlimit 180 s): Die Verbindung wurde abgelehnt.
```

Antworten werden als UTF-8 gelesen, unabhaengig von der Zeichensatzangabe
des Dienstes.

## 6. Pruefung

`tests/SpawnNew.Llm.Tests.ps1`, `SpawnNew.KiAktionen.Tests.ps1`,
`SpawnNew.Dokumentaktionen.Tests.ps1` und `SpawnNew.HostFlow.Tests.ps1`
laufen gegen einen Testserver auf 127.0.0.1, der jede Anfrage aufzeichnet.
Geprueft wird unter anderem, dass der Schluessel nur im Kopf steht, dass
der Vorschlag von Aktion 17 genau einmal erzeugt und unveraendert angelegt
wird und dass Entwuerfe nichts ueberschreiben.
