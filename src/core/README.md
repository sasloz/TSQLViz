# Core 0.1.0-s5a

Installierbare T-SQL-Bausteine für eigene Scenes. S1 umfasst Installation, Typen und Renderer; S2 umfasst Geometrie und Skalen. S3/S4 ergänzen den eigenen Glyphenatlas, Text/Formatierung, automatische Domains, Canvas/Achsen und drei Chart-Prozeduren. Die [Chart- und Layoutanleitung](../charts/README.md) beschreibt die zusätzlichen Interfaces.

## Installation und Rechte

[Installer](../../dist/install-core.sql) vollständig in einer ausgewählten Benutzerdatenbank ausführen. Er enthält keine SQLCMD-Includes oder externen Downloads. Ein Schema `viz` mit Eigentümer `dbo` darf bereits leer existieren. Fremde Objekte im Namespace und ein fremder Principal `viz_user` führen vor der Mutation zu Fehler `51001` mit dem betroffenen Namen bzw. Grund.

Die [Manifestdatei](manifest.json) legt Version, Objektart, Reihenfolge, Quelldatei und öffentliche Rechte fest. [Build-Skript](../../tools/build.ps1) erzeugt Installation und Deinstallation. Jede Quelldatei definiert genau ein Objekt; interne Helfer erhalten keine direkten Runtime-Grants.

Das installierte `viz.ObjectManifest` speichert Quellhashes und Katalogsignaturen der Tabellen/TVPs. Zusammen mit den Eigentumsmarkierungen erkennt der Preflight Namenskollisionen und Strukturänderungen. Die Metadaten schützen vor versehentlichem Überschreiben; sie sind keine Sicherheitsgrenze gegen Datenbankadministratoren.

Der Installer sperrt konkurrierende Core-Installationen innerhalb der Datenbank und führt DDL als verschachtelte Batches in einer Transaktion aus. Syntax- und Laufzeitfehler werden zurückgerollt. Identische Wiederholungen erhalten Typ-IDs und den ursprünglichen Installationszeitpunkt; Glyphendaten werden reproduzierbar gesetzt. Neben Clean Install und Wiederholung ist die Migration von `0.1.0-s2` nach `0.1.0-s5a` enthalten. Geänderte persistierte Verträge und andere Paketversionen verlangen eine eigene Migration.

Einen bereits vorhandenen Datenbankbenutzer für Core freigeben:

```sql
ALTER ROLE viz_user ADD MEMBER [MeinDatenbankbenutzer];
```

Die Rolle erhält `EXECUTE` auf öffentliche Skalarfunktionen/Prozeduren, `SELECT` auf öffentliche TVFs sowie `EXECUTE`/`REFERENCES` auf die vier TVPs. Sie benötigt keine Serverrolle und keine Schreibrechte auf Core-Tabellen. Der Zugriff auf interne Helfer läuft über die gemeinsame Ownership-Chain.

[uninstall-core.sql](../../dist/uninstall-core.sql) entfernt ausdrücklich nur Core. Vorher müssen Rollenmitglieder entfernt und fremde SQL-/Typabhängigkeiten aufgelöst werden. Der gesamte Vorgang ist transaktional. Quelltabellen außerhalb von `viz`, die Datenbank und das Schema selbst bleiben erhalten. Nicht im SQL-Katalog sichtbare Abhängigkeiten, etwa dynamisches SQL einer Anwendung, muss der Betreiber vor Deinstallation berücksichtigen.

## Datentypen und Renderer

Die zentralen Dataset-/Geometrietypen sind `CategoryValue_v1`, `XY_v1`, `Vertex_v1` und `Scene_v1`. Die [Datenverträge](../../docs/data-contracts.md) beschreiben auch Tick-, Text-, Kontext- und Kennzeichentypen mit Links zu ihren SQL-Definitionen. Interval-, Node- und Edge-Typen sind noch nicht implementiert.

```sql
DECLARE @Scene viz.Scene_v1;
INSERT @Scene VALUES
 (30,0,N'box','mark',NULL,N'box',N'Area 1200',viz.Rect(0,0,30,40));
EXEC viz.RenderScene @Scene;
```

`RenderScene` liefert genau acht Spalten, geordnet nach `Layer`, `ElementOrder`, `ElementKey`. Ein einmaliges `INSERT @Captured EXEC viz.RenderScene @Scene` ist möglich. Eine direkt übergebene leere Scene liefert null Zeilen im gleichen Schema. Der geometrische `NO DATA`-Hinweis ist Aufgabe der späteren Chart-Prozeduren, die Canvas und Layout kennen.

Ungültiger `Kind` ergibt `51001`; ungültige, leere, dreidimensionale oder nicht auf SRID 0 beruhende Shapes ergeben `51003`. Zeilen-, Punkt-, Byte- und Koordinatenüberschreitungen ergeben `51004`. Der Renderer prüft alle vier Mengenbudgets getrennt und gibt bei Fehlern keine partielle Scene aus. Keine automatische Reparatur, Aufteilung oder Datenreduktion findet im Renderer statt.

## Geometrie

| Funktion | Verhalten |
|---|---|
| `Point(x,y)` | POINT, SRID 0 |
| `Segment(x1,y1,x2,y2)` | LINESTRING; gleiche Endpunkte ergeben NULL |
| `Rect(x,y,width,height)` | Geschlossenes Rechteck mit positiven Maßen |
| `Circle(cx,cy,radius)` | Deterministisches 64-Eck mit 65 Punkten einschließlich Abschluss |
| `Polyline(@Vertices)` | Ein PathId, nach VertexOrder sortiert; aufeinanderfolgende Duplikate entfernt |
| `Polygon(@Vertices)` | Einfacher Außenring; ergänzt fehlenden Abschluss genau einmal |

Alle Parameter sind `float`, Vertex ist ein `viz.Vertex_v1 READONLY`-TVP. Fehlende numerische Argumente, ungültige Größen und Koordinaten außerhalb ±1.000.000 liefern NULL. Auch ein durch Floatauflösung kollabierendes Rechteck/ein solcher Kreis liefert NULL. Vertexhelfer erlauben maximal 100.000 Eingabevertices und genau einen PathId; unzureichende verschiedene Punkte liefern NULL. Mehrere Ringe und Löcher sind nicht implementiert.

Polygon ist ein Konstruktor und führt kein `MakeValid` aus. Ein selbstüberschneidender Ring kann als ungültige Geometrie entstehen oder einen Enginefehler verursachen; spätestens `RenderScene` lehnt ihn vor Ausgabe ab. Primitive teilen große Shapes nicht selbst auf. Das einzelne 32.000-Byte-Limit wird beim Rendern erzwungen; die spätere Line-Komposition baut kleinere Teilstücke.

WKT verwendet Floatformat 3 mit 17 signifikanten Stellen, stabile Sortierung und MAX-Strings vor Aggregation. Wissenschaftliche Schreibweise ist auf beiden geprüften Engines getestet. Sprachoptionen ändern keine Koordinaten.

## Skalen und Zeit

| Öffentliches Interface | Rückgabe |
|---|---|
| `ScaleLinear(value,domainMin,domainMax,rangeMin,rangeMax,clamp)` | Float; umgekehrte Range und optionale Begrenzung erlaubt |
| `ScaleLog(value,domainMin,domainMax,rangeMin,rangeMax,base)` | Float; positive Werte/Domain, Basis > 1 |
| `ScaleBand(index,count,rangeMin,rangeMax,paddingInner,paddingOuter)` | Eine Zeile: BandStart, BandWidth, BandCenter |
| `BandCenter(rank,count,rangeStart,rangeEnd)` | Float; Mitte des Bands `rank` (1 = bei `rangeStart`), Abstände wie ScaleBand mit 0,2/0,1. Umgekehrte Range legt Rang 1 nach oben. Nimmt `ROW_NUMBER()`/`COUNT(*) OVER()` direkt als Argument |
| `BandWidth(count,rangeStart,rangeEnd)` | Float; nutzbare Dicke eines BandCenter-Bands |
| `BubbleRadius(value,maxSizeValue,maxRadius)` | Float; Flächenkodierung durch Quadratwurzel |
| `TicksLinear(domainMin,domainMax,targetCount)` | TickOrder, Value |
| `NiceDomain(domainMin,domainMax,targetCount)` | DomainMin, DomainMax, Step |
| `TicksLog(domainMin,domainMax)` | TickOrder, Value; Zehnerpotenzen, höchstens 12 |
| `TicksTime(domainMin,domainMax,targetCount)` | TickOrder, Value; Epoch-Millisekunden |
| `TicksDuration(domainMin,domainMax,targetCount)` | TickOrder, Value; Dauer in ms auf Uhrschritten (1/2/5/10/15/30 s, 1/2/5/10/15/30 min, 1/2/3/6/12 h), darüber 1/2/5 × 10^k Tage |
| `TicksBytes(domainMin,domainMax,targetCount)` | TickOrder, Value; Bytes auf Zweierpotenzen (256 MiB, 512 MiB, 1 GiB) |
| `TimeToEpoch(utc datetime2(3))` | Float mit ganzzahligen Millisekunden seit 2000-01-01 UTC |
| `EpochToTime(milliseconds float)` | datetime2(3), ganzzahlige Millisekunden erforderlich |

Ungültige Skalarargumente liefern NULL, ungültige TVF-Argumente null Zeilen. Aufrufer ordnen Ticktabellen ausdrücklich nach `TickOrder`; Tabellenfunktionen garantieren keine physische Reihenfolge. Parameterdefaults werden in diesen Helfern explizit übergeben, etwa sechs Ticks oder Bandpadding 0,2/0,1.

Lineare/Log-Domainendpunkte und direkte Scalar-Werte sind auf ±1e16 begrenzt, Rangeendpunkte und gemappte Koordinaten auf ±1.000.000. Das engere Datasetbudget von ±1e15 wird später am Chart-Interface geprüft. Konstanten oder leere Domains werden hier nicht automatisch erweitert; diese Datenentscheidung gehört zum Chart. Numerisch nicht darstellbare Extrapolation liefert NULL. Log-Basis ist auf 1 < Basis ≤ 1e16 begrenzt; ihre Wahl kürzt sich beim Mapping heraus.

Band benötigt eine aufsteigende Range, 1–10.000 Bänder, 0 ≤ inneres Padding < 1 und 0 ≤ äußeres Padding ≤ 10.000. Bubble-Größe benötigt 0 < Value ≤ MaxSizeValue ≤ 1e15 und 0 < MaxRadius ≤ 1.000.000; Wert 0 und NULL liefern NULL, sodass der Chart später Nullmarker und fehlenden Wert getrennt behandeln kann.

Numerische Ticks verwenden Schritte 1/2/2,5/5/10 × 10^k und ein Ziel von 2–12 Ticks. Liegen weniger als zwei passende Ticks in der Domain, werden die Grenzen ausgegeben. Der rohe Tickabstand muss mindestens 1e-300 sein; kleinere Abstände liefern keine Ticks. Log-Ticks unterstützen Minima ab 1e-300. NiceDomain verwirft Ergebnisse außerhalb ±1e16.

Zeitwerte sind auf 1900-01-01 einschließlich bis 2101-01-01 ausschließlich begrenzt. Negative Epochwerte werden über ganze Tage und einen nichtnegativen Millisekundenrest zurückgerechnet. Feste Zeitticks reichen von einer Sekunde bis zu einer Woche; größere Spannen verwenden ganzzahlige Wochenvielfache mit Montag als Anker. Zeitzonen werden ausdrücklich vor Übergabe normalisiert:

```sql
DECLARE @Local datetimeoffset(3)='2024-01-01T01:00:00+01:00';
SELECT viz.TimeToEpoch(CONVERT(datetime2(3),SWITCHOFFSET(@Local,'+00:00')));
```

## Tests

Siehe [Validierungsübersicht](../../docs/validation.md). `tools/test-core.ps1` erstellt standardmäßig ein eigenes Labor und räumt es auch bei Testfehlern auf. `-RunId <id>` verwendet ein bereits mit `tools/lab.ps1` angelegtes Labor und lässt es zur weiteren Arbeit bestehen. Innerhalb des Labors benötigt die Installationsmatrix den freien Datenbanknamen `TSQLVizInstallFixture`; ein bestehender Namenskonflikt wird nicht überschrieben.

Unter `tests/results/<RunId>/` liegen SQL-Dateien, Logs, Engine-/Imageinformationen, Quellhashes und `core-tests.json`. Die dauerhaft abgelegten Nachweise unter `tests/evidence/` enthalten keine Zugangsdaten.
