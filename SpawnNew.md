<!-- SpawnNew.md | Version 1.2 | 26.10.2026 -->

# SpawnNew

Konzept und Anforderungen, Version 1.2 vom 26.10.2026.
Status: Konzept überarbeitet; Anwendung noch nicht implementiert.

## 1. Ziel

SpawnNew erzeugt über das Windows-Explorer-Kontextmenü vorbereitete Arbeitsumgebungen. Eine Aktion kann Ordner und Dokumente anlegen, ein Git-Repository initialisieren oder später auch eine virtuelle Maschine erstellen.

Die Explorer-Anbindung ist unabhängig von PowerToys. Neue Aktionen werden aus konfigurierten Verzeichnissen geladen und über Windows PowerShell 5.1 umgesetzt. Neue oder geänderte Aktionen erfordern keinen Neubau der Explorer-Erweiterung.

## 2. Festgelegte Entscheidungen

| Bereich | Festlegung |
|---|---|
| Einstieg | Ausschließlich über das Explorer-Kontextmenü |
| Darstellung | SpawnNew als Untermenü mit direkt auswählbaren Aktionen |
| Betriebssysteme | Windows 10 und Windows 11; Ziel ist die direkte Anzeige im ersten Kontextmenü. Die technische Umsetzung wird je Betriebssystem getrennt registriert und abgenommen |
| Aktionen | Genau sieben mitgelieferte Startaktionen; zusätzlich beliebig viele benutzerdefinierte Aktionen aus konfigurierten Quellen |
| Quellen | Mehrere frei konfigurierbare Verzeichnisse, lokal, OneDrive oder Netzwerkfreigabe |
| Quellenpriorität | Explizite Reihenfolge aller Quellen. Bei gleicher Aktions-ID gewinnt die zuerst konfigurierte Quelle. Persönliche Quellen werden standardmäßig vor gemeinsamen Quellen eingeordnet, können aber durch eine explizite Reihenfolge anders priorisiert werden |
| Aktions-ID | Nur eine explizit deklarierte, identische Aktions-ID darf eine andere Aktion ersetzen. Automatisch erzeugte IDs dürfen keine andere Aktion überschreiben |
| Zielpfad | Aktionsstandard im Dialog änderbar; ohne eigenen Standard gilt der Explorer-Ordner |
| Eingaben | Einheitliche Formulare; eigene Dialoge einer Aktion sind nur zulässig, wenn sie denselben Eingabe-, Zusammenfassungs- und Abbruchvertrag einhalten |
| Rechte | Standardmäßig normale Benutzerrechte. Administratorrechte nur bei `requiresAdmin: true`; die Rechteanforderung gilt ausschließlich für die fachliche Ausführung |
| PowerShell | Windows PowerShell 5.1 als einzige unterstützte Laufzeit |
| Beschreibung | Skripte allein nutzbar; optionale JSON-Dateien für zusätzliche Angaben |
| Namenskonflikte | Abbrechen, anderen Namen wählen oder vorhandenen Ordner verwenden |
| Dateikonflikte | Keine stillen Überschreibungen. Für jede betroffene Datei muss die Aktion abbrechen, einen neuen Namen verwenden oder eine ausdrücklich bestätigte Überschreibungsregel anwenden |
| Ausgabe | Fortschrittsfenster, Fehlerdetails und optionales Öffnen des Zielordners |
| Kategorien | Optional; Aktionen können direkt unter SpawnNew oder in Kategorien stehen |
| Teilfehler | Optionale Aufräumfunktion je Aktion; ohne diese bleiben erstellte Teile erhalten |
| Installation | Wahlweise für aktuellen Benutzer oder alle Benutzer |
| Nachladen | Änderungen werden beim nächsten Öffnen des Kontextmenüs berücksichtigt. Bereits geöffnete Menüs werden nicht aktualisiert |
| Quellenfehler | Fehlerhafte oder nicht erreichbare Quellen werden protokolliert, blockieren aber weder andere Quellen noch den Explorer dauerhaft |
| Dokumente | Markdown oder Word-kompatible `.docx`-Dateien auswählbar; eigene Vorlagendateien möglich |
| Vor dem Start | Zusammenfassung von Zielpfad, Eingaben und geplanten Schritten; danach ausdrücklich "Erstellen" |
| Voraussetzungen | Fehlende Voraussetzungen verständlich anzeigen; keine automatische Installation |
| Konfiguration | Quellen, Prioritäten und Installationsoptionen werden über eine separate Konfigurationsoberfläche oder eine dokumentierte Konfigurationsdatei verwaltet; diese Verwaltung ist keine fachliche Aktion |
| Installation | Einzeilige Befehle für Installation und Aktualisierung stehen zusätzlich als Menüeinträge zur Verfügung |

Die sieben mitgelieferten Startaktionen sind die Einträge 1, 2, 3, 7, 10, 11 und 14 in Abschnitt 4. Die Nummern sind stabile fachliche Kennungen und werden nicht als fortlaufende Anzahl interpretiert.

## 3. Bedienablauf

1. Im Hintergrund eines Explorer-Ordners rechts klicken.
2. SpawnNew öffnen und eine Aktion auswählen.
3. SpawnNew liest Beschreibung und prüft Voraussetzungen.
4. Das Formular zeigt Vorgaben sowie den änderbaren Zielpfad.
5. Der Benutzer ergänzt beispielsweise Projektname, Klasse, Thema oder Datum.
6. Eine Zusammenfassung zeigt Zielpfad, Eingaben und geplante Schritte.
7. "Erstellen" startet die Aktion. Falls deklariert, erfolgt dabei die Windows-Abfrage für Administratorrechte.
8. Das Fortschrittsfenster zeigt den Ablauf und das Ergebnis.
9. Optional wird der Zielordner geöffnet.

Zusätzlich stehen im SpawnNew-Untermenü folgende Verwaltungsbefehle zur Verfügung:

- SpawnNew installieren: Führt den konfigurierten Einzeiler für die Installation aus.
- SpawnNew aktualisieren: Führt den konfigurierten Einzeiler für die Aktualisierung aus.

Die Einzeiler werden nicht automatisch ausgeführt. Vor der Ausführung werden Befehl, Ziel und erforderliche Rechte angezeigt und ausdrücklich bestätigt. Die Befehle dürfen nur die SpawnNew-Installation beziehungsweise deren Programmdateien aktualisieren. Persönliche Aktionen, Quellen und Konfiguration dürfen nicht überschrieben werden.

Abbrechen vor "Erstellen" darf keine fachlichen Änderungen durchführen. Das Öffnen des Menüs darf keine Aktionsskripte ausführen.

Bei eigenen Aktionsdialogen gelten dieselben Anforderungen an Eingaben, Vorprüfung, Zusammenfassung, Rechteabfrage und Abbruch. Das Formular ist Teil des aufgerufenen Ablaufs, kein eigenständiger Aktionsstarter.

## 4. Mitgelieferte Aktionen der ersten Version

Die erste Version enthält genau sieben mitgelieferte Aktionen:

| Nr. | Aktion | Eingaben und Ergebnis |
|---|---|---|
| 1 | Ordnerstruktur | Name, Zielpfad, Strukturvorlage; Unterordner und vorbereitete Dateien |
| 2 | Git-Projekt | Name, Zielpfad, passende Gitignore-Vorlage; lokales Repository mit README und optionalem ersten Commit |
| 3 | PowerShell-Werkzeug | Name, Zielpfad, Beschreibung; Skript mit Dateiname und Version im Kopf, Konfiguration und Kurzdokumentation |
| 7 | Werkstättenprotokoll | Klasse, Thema, Datum, Ausgabeformat; Protokollvorlage sowie Bilder- und Messdatenordner |
| 10 | Fehleranalyse | Titel, Umgebung, Datum; Fehlerbeschreibung, Reproduktionsschritte, Logs, Screenshots und Lösungsnachweis |
| 11 | Sitzung | Gremium, Thema, Datum, Ausgabeformat; Tagesordnung, Unterlagen, Protokoll und Beschlussliste |
| 14 | Eigene Aktion | Name und Aktions-ID; dokumentiertes Grundgerüst mit Skript und optionaler JSON-Beschreibung |

Hyper-V, Webprojekte und weitere Aktionen bleiben Erweiterungsmöglichkeiten. Sie sind nicht Bestandteil der ersten sieben mitgelieferten Aktionen. Git-Projekte werden lokal erstellt; Remote-Erstellung und Veröffentlichung gehören nicht zum Standardablauf.

## 5. Aktionsformat

### Einzelnes Skript

Ein PowerShell-Skript in einer konfigurierten Aktionsquelle genügt. Ohne Beschreibung bestimmt der Dateiname den sichtbaren Namen. Die Aktion verwendet Windows PowerShell 5.1 und normale Benutzerrechte.

Für ein einzelnes Skript wird die Aktions-ID deterministisch aus der kanonischen Quelle und dem relativen Pfad gebildet. Diese automatisch erzeugte ID darf keine andere Aktion ersetzen. Ein bewusstes Überschreiben zwischen persönlichen und gemeinsamen Quellen ist nur mit einer explizit angegebenen Aktions-ID zulässig.

### Aktionsordner

Ein Aktionsordner bündelt Einstiegsskript, optionale JSON-Beschreibung, Vorlagendateien, Ressourcen und Kurzdokumentation. Die Erkennung erfolgt ausschließlich über eine eindeutige Beschreibung oder ein festgelegtes Einstiegsskript, damit interne Hilfsskripte nicht als zusätzliche Menüaktionen erscheinen.

Ein Aktionsordner wird nur dann als Aktion erkannt, wenn sein Einstiegspunkt vorhanden und die Beschreibung syntaktisch gültig ist. Ungültige oder unvollständige Aktionsordner werden nicht ausgeführt und als Diagnose erfasst.

### Technischer Entwurf der Beschreibung

Die folgenden Angaben sind ein Schnittstellenentwurf, kein bereits implementiertes Schema:

| Angabe | Zweck |
|---|---|
| `schemaVersion` | Version des Beschreibungsformats |
| `id` | Feste, von Anzeigename und Pfad unabhängige Aktions-ID |
| `title` | Sichtbarer Menüname |
| `category` | Optionale Menükategorie |
| `icon` | Optionales lokales Symbol |
| `entryPoint` | Relativer Pfad zum Einstiegsskript |
| `requiresAdmin` | Deklarierter Bedarf an Administratorrechten |
| `defaultTarget` | Optionaler Standardzielpfad |
| `fields` | Beschriebene Formularfelder mit Vorgaben und Prüfung |
| `prerequisites` | Benötigte Programme, Module oder Dateien |
| `plannedSteps` | Für die Zusammenfassung geeignete Schrittbeschreibung |
| `cleanup` | Optionaler relativer Einstiegspunkt für das Aufräumen nach Teilfehlern |

`requiresAdmin: true` darf nicht allein aus einer Beschreibung zu einer erhöhten Ausführung führen, wenn die Aktion die Rechte nicht tatsächlich benötigt. Die Anwendung zeigt die deklarierte Rechteanforderung vor dem Start an und fordert erhöhte Rechte erst nach ausdrücklicher Bestätigung an.

## 6. Quellen und dynamisches Nachladen

- Mehrere Quellen sind gleichzeitig aktiv und als persönlich oder gemeinsam gekennzeichnet.
- Jede Quelle besitzt eine eindeutige, vom Benutzer festgelegte Prioritätsnummer oder Position.
- Die effektive Reihenfolge wird zuerst nach dieser expliziten Reihenfolge und bei Gleichstand nach der Ebene bestimmt: persönliche Quellen vor gemeinsamen Quellen.
- Bei gleicher expliziter Aktions-ID wird ausschließlich die Aktion aus der zuerst priorisierten Quelle angezeigt.
- Eine Aktion ohne explizite ID kann keine Aktion mit expliziter ID ersetzen.
- Gleiche Anzeigenamen mit unterschiedlichen IDs bleiben verschiedene Aktionen und werden bei Bedarf mit Quellenangabe unterscheidbar gemacht.
- Eine ungültige Beschreibung darf andere Aktionen nicht blockieren; der Fehler muss nachvollziehbar sein.
- Nicht erreichbare Netzwerkquellen dürfen das Explorer-Menü nicht auf unbestimmte Zeit blockieren. Für die Erkennung gilt ein begrenztes Zeitlimit.
- Änderungen werden beim nächsten Öffnen des Kontextmenüs eingelesen. Ein begrenzter Metadaten-Cache darf nur verwendet werden, wenn die Quelle nicht rechtzeitig erreichbar ist; zwischengespeicherte Aktionen werden als möglicherweise veraltet behandelt.
- Vor der Ausführung werden Skript, Beschreibung, Quelle und Aktions-ID erneut geprüft, damit veraltete Menüeinträge nicht blind ausgeführt werden.
- Wird eine Aktion zwischen Anzeige und Ausführung entfernt oder geändert, wird sie nicht gestartet; der Benutzer erhält eine verständliche Meldung.

Quellverzeichnisse enthalten ausführbaren Code und werden bewusst konfiguriert. Die Menüerkennung liest ausschließlich Metadaten. Es gibt keinen dauerhaft laufenden PowerShell-Prozess nur zum Beobachten der Quellen.

## 7. Zielpfade und Konflikte

Der Explorer-Pfad wird als Kontext übergeben. Ein Aktionsstandard kann ihn ersetzen; der Benutzer kann das Ziel im Formular ändern. Der bestätigte Pfad wird vor dem Start geprüft und normalisiert.

Bei vorhandenem Zielnamen erscheint die vereinbarte Auswahl: abbrechen, umbenennen oder vorhandenen Ordner verwenden. "Vorhandenen Ordner verwenden" ist keine pauschale Erlaubnis zum Überschreiben bestehender Dateien.

Dateikonflikte müssen ohne stillen Datenverlust behandelt werden. Standardmäßig bricht die Aktion bei einem Konflikt ab oder verwendet nach ausdrücklicher Bestätigung einen neuen Namen. Überschreiben ist nur zulässig, wenn die Aktion dies ausdrücklich beschreibt, der Benutzer es vor dem Start bestätigen kann und die betroffenen Dateien eindeutig angezeigt werden.

Pfade mit Leerzeichen, Umlauten und UNC-Freigaben müssen funktionieren. Pfadparameter werden als Daten übergeben und nicht in frei zusammengesetzte PowerShell-Befehle eingesetzt.

## 8. Technische Architektur

### Explorer-Erweiterung

Eine schlanke native Erweiterung erzeugt Menüeinträge und übergibt Aktionskennung, Quelle und Explorer-Pfad an den Ausführungsprozess. Sie führt keine fachliche Aktionslogik im Explorer-Prozess aus.

Für Windows 11 wird die Einbindung in das moderne Menü über IExplorerCommand und die dafür erforderliche Paket- oder COM-Registrierung prototypisch geprüft. Windows 10 verwendet den klassischen Kontextmenüpfad. Die direkte Anzeige im ersten Kontextmenü ist für beide Systeme ein Abnahmekriterium. Falls die direkte Anzeige unter einer unterstützten Windows-11-Version technisch nicht zuverlässig möglich ist, muss vor Implementierungsabschluss eine verbindliche Ersatzdarstellung festgelegt werden; eine bloße Anzeige im erweiterten Menü gilt dann nicht automatisch als erfüllt.

### Ausführungsprozess

Ein separater Prozess übernimmt Formular, Vorprüfung, Zusammenfassung, Fortschritt und den Start von Windows PowerShell 5.1. Seine Dialoge erscheinen nur nach Auswahl einer Aktion. Die konkrete Technologie dieses Prozesses wird beim technischen Prototyp festgelegt.

### PowerShell-Aktionen

Die Aktionen führen die eigentliche Arbeit aus. SpawnNew übergibt mindestens Explorer-Kontext, bestätigten Zielpfad, Aktionsverzeichnis und Formularwerte.

Der gemeinsame Vertrag muss vor Implementierung festlegen:

- Übergabeformat für Kontext und Formularwerte,
- Ausgabeformat für Fortschritt,
- Ergebnisstatus,
- Fehlerformat,
- Liste der erstellten Ressourcen,
- Abbruchverhalten,
- Verhalten bei Prozessbeendigung,
- Aufruf und Einschränkungen der Aufräumfunktion.

Administratorrechte werden ausschließlich für die angeforderte Ausführung angefordert. Es gibt keinen standardmäßig erhöhten Explorer und keinen dauerhaft erhöhten Hintergrundprozess. Eine abgelehnte Rechteabfrage führt zum Abbruch ohne anschließende fachliche Änderungen.

### Abgrenzung zu PowerToys

Es werden keine PowerToys-Binärdateien geändert. PowerToys-Updates überschreiben daher keine SpawnNew-Komponente. Neue Aktionen benötigen keine Neukompilierung der Explorer-Erweiterung.

## 9. Fehler, Fortschritt und Aufräumen

- Fehler zeigen betroffenen Schritt, verständliche Ursache und technische Details bei Bedarf.
- Fachliche Ausgaben werden im Fortschrittsfenster gesammelt; vertrauliche Eingaben gehören nicht in Protokolle.
- Die Aktion meldet erstellte Ressourcen, soweit möglich.
- Eine Aufräumfunktion darf nur Ressourcen entfernen, die diese Ausführung selbst erstellt hat.
- Ohne Aufräumfunktion bleiben Teilergebnisse erhalten; die Meldung muss darauf hinweisen.
- Aufräumen ist keine allgemeine Transaktion und garantiert nicht, externe Änderungen vollständig rückgängig zu machen.
- Abbrechen während der Ausführung beendet die Aktion nur, wenn der Ausführungsvertrag dies unterstützt. Andernfalls wird der Abbruch als angefordert angezeigt, bis der Prozess beendet ist.
- Eine Prozessbeendigung darf nicht als erfolgreicher Rollback dargestellt werden.
- Nach einem Abbruch oder Fehler wird eindeutig zwischen "keine Änderungen", "teilweise erstellt", "erfolgreich erstellt" und "Status unbekannt" unterschieden.

## 10. Installation und Wartung

Installationsumfang: aktueller Benutzer oder alle Benutzer. Eine systemweite Installation benötigt administrative Rechte. Eine Benutzerinstallation darf ohne Administratorrechte erfolgen, sofern die gewählte Registrierungsart dies unterstützt; andernfalls wird die erforderliche Rechteanforderung vor der Installation angezeigt.

Für Installation und Aktualisierung wird jeweils ein konfigurierter Einzeiler bereitgestellt. Beide Befehle sind als eigene Menüeinträge im SpawnNew-Untermenü verfügbar:

- SpawnNew installieren
- SpawnNew aktualisieren

Vor der Ausführung zeigt SpawnNew den vollständigen Einzeiler, das Ziel und die erforderlichen Rechte an. Die Ausführung erfolgt erst nach ausdrücklicher Bestätigung. Einzeiler dürfen keine persönlichen Aktionen, Quellen oder Konfigurationen verändern oder löschen. Fehler werden mit dem ausgeführten Befehl, dem Rückgabestatus und verständlichen Details angezeigt.

Konfiguration und persönliche Aktionen werden von installierten Programmdateien getrennt. Ein SpawnNew-Update darf diese nicht überschreiben. Deinstallation entfernt die Menüregistrierung und SpawnNew-eigene Programmdateien; benutzereigene Aktionen, Quellen und Konfiguration bleiben standardmäßig erhalten. Der Benutzer muss vor der Deinstallation ausdrücklich über verbleibende Daten informiert werden.

Eine Möglichkeit zur Quellenkonfiguration muss ohne eigenständigen Aktionsstarter erreichbar sein, beispielsweise über einen separaten Konfigurationsbefehl im SpawnNew-Untermenü oder über die installierte Anwendung. Die gewählte Darstellung und ihre Rechteanforderungen werden vor Implementierung festgelegt.

## 11. Entwicklungsregeln

- Minimaler, funktionaler Code; Windows-native APIs bevorzugen.
- Bestehende Dateinamen beibehalten; Implementierungsdateinamen vor dem ersten Code festlegen.
- Jede selbst erstellte Text-/Codedatei beginnt mit einem passenden Kommentar mit Dateiname und Version. Für JSON ein Format ohne Kommentare verwenden und die Version als Metadatum führen; keine ungültige JSON-Syntax einbauen.
- Höchstens 800 Zeilen pro Datei.
- Kompatibel mit deutschem Windows und Windows PowerShell 5.1.
- Skripte bei Bedarf als UTF-8 mit BOM ausliefern.
- Keine Unicode-Emojis; Umlaute in Texten und Pfaden korrekt unterstützen.
- Dateien bei Änderungen vollständig neu schreiben und Namen beibehalten.
- Bei Fehlerbehebungen nur das konkrete Problem ändern.
- Ausführbare Einstiegspunkte mit Kurzdokumentation ausliefern.
- Aktionsskripte dürfen keine nicht dokumentierten globalen Seiteneffekte ausführen.
- Eingaben und Pfade müssen getrennt von ausführbarem Code übergeben werden.
- Installations- und Aktualisierungseinzeiler müssen dokumentiert, überprüfbar und vor der Ausführung bestätigungspflichtig sein.

## 12. Abnahme

1. SpawnNew erscheint direkt im ersten Kontextmenü unter Windows 10 und Windows 11, sofern die unterstützte Windows-Version die dafür festgelegte Registrierung unterstützt.
2. Neue Skripte und Aktionsordner erscheinen ohne Neubau der Anwendung.
3. Genau sieben mitgelieferte Startaktionen funktionieren; zusätzliche benutzerdefinierte Aktionen werden getrennt davon geladen.
4. Persönliche Aktionen ersetzen gemeinsame ausschließlich anhand derselben expliziten ID und gemäß der festgelegten Quellenpriorität.
5. Formulare unterstützen Standardzielpfade, Änderungen und eine abschließende Zusammenfassung.
6. Fehlende Voraussetzungen führen zu einer verständlichen Meldung ohne automatische Installation.
7. Windows PowerShell 5.1 funktioniert standardmäßig und wird für alle Aktionen verwendet.
8. Normale Aktionen lösen keine Rechteabfrage aus; deklarierte erhöhte Aktionen behandeln Zustimmung und Ablehnung korrekt.
9. Bestehende Dateien werden nicht still überschrieben; Fehler und Teilergebnisse sind sichtbar.
10. Nicht erreichbare Quellen blockieren Explorer nicht dauerhaft und überschreiten das festgelegte Zeitlimit nicht.
11. Markdown- und Word-kompatible Ausgabe sowie eigene Dokumentvorlagen funktionieren ohne vorausgesetzte Word-Automatisierung für die reine Dateierzeugung.
12. Installieren, Aktualisieren und Deinstallieren erhalten persönliche Aktionen und Konfiguration entsprechend den festgelegten Regeln.
13. Die Menüeinträge für Installation und Aktualisierung zeigen den Einzeiler vor der Ausführung an und führen ihn erst nach ausdrücklicher Bestätigung aus.
14. Eine zwischen Menüanzeige und Ausführung geänderte oder entfernte Aktion wird nicht blind ausgeführt.
15. Abbruch, Prozessbeendigung und Aufräumen unterscheiden zuverlässig zwischen keinem Ergebnis, Teilergebnis, Erfolg und unbekanntem Status.
16. Die sieben mitgelieferten Aktionen verwenden eindeutige explizite IDs und sind in der Quellenauflösung nicht versehentlich durch automatisch erzeugte IDs ersetzbar.

## 13. Umsetzungsschritte

1. Dateinamen, Konfigurationsspeicher, Quellenpriorität, Aktions-ID-Regeln, Installations- und Aktualisierungseinzeiler sowie technische Schnittstellenverträge festlegen.
2. Minimalen Explorer-Prototyp auf Windows 10 und Windows 11 prüfen, einschließlich Menüregistrierung, direkter Anzeige und Pfadübergabe.
3. Aktionsquellen, Prioritätsauflösung, IDs, Nachladen, Cache-Verhalten und Beschreibungsprüfung umsetzen.
4. Einheitliche Formulare, Zusammenfassung und getrennten PowerShell-Start umsetzen.
5. Fortschritt, Fehlerbehandlung, Rechte und optionale Aufräumfunktion ergänzen.
6. Sieben ausgewählte Aktionen und Dokumentvorlagen liefern.
7. Installation, Aktualisierung, Konfigurationszugriff und Deinstallation umsetzen.
8. Menüeinträge für Installation und Aktualisierung mit Bestätigung, Rückgabestatus und Fehleranzeige integrieren.
9. Abnahmekriterien auf Windows 10 und Windows 11 mit erreichbaren und nicht erreichbaren Quellen prüfen.

Die Erstellung dieses Konzepts umfasst noch keine Implementierung, Installation oder Veröffentlichung.

## 14. Quellen und Namensstand

Der Name SpawnNew ist als Arbeitsname gewählt. Die vorangegangene Websuche zeigte Verwendungen als Funktion, Befehl oder Startparameter, aber kein eindeutig identifiziertes eigenständiges Produkt gleichen Namens. Eine verbindliche Marken- oder Domainfreigabe liegt nicht vor.

Zur Architektur untersuchte PowerToys-Dateien auf dem veränderlichen main-Branch:

- Menüaufbau
- Klick auf Vorlage
- Zielpfad und Kopierablauf
- Datei-/Ordnerkopie
- Windows-10-Menühandler

Diese Stellen dienen als Architekturbezug. SpawnNew soll als eigenständige Erweiterung entstehen.
