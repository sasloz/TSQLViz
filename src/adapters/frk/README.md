# BlitzCache-Adapter (S5)

Eigenständiges Paket `0.1.0-s5a`, benötigt Core/Charts `0.1.0-s5a`.
Installation: [install-frk-adapter.sql](../../../dist/install-frk-adapter.sql),
Build: `./tools/build-frk.ps1`. Der Installer lädt keinen Drittcode und verändert keine FRK-Prozedur.

## Freigegebener Datenvertrag

Profil **`blitzcache-8.34-cpu50-v1`**: `sp_BlitzCache` **8.34**, VersionDate **2026-07-02**,
[Commit 756206859c23aa98cdb41643763c5f1d3c10cbab](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/blob/756206859c23aa98cdb41643763c5f1d3c10cbab/sp_BlitzCache.sql).
Die geladene Originaldatei hat SHA-256 `ABA9ED53ABA3EBABAC30B696DEEC97F83AB5AA84490173315D4A21DB45762AAC`.
SQL-Prüfungen und konkrete Engine-Freigaben stehen im [Validierungsübersicht](../../../docs/validation.md).

Feste Parameter: `Top=50`, `SortOrder=cpu`, `QueryFilter=statements`, eine explizite `DatabaseName`,
`SkipAnalysis=1`, `HideSummary=1`, `OutputType=NONE`, lokale Outputdatenbank, neue physische Tabelle je Capture,
`CheckDateOverride` mit UTC-Offset. Alle übrigen Parameter entsprechen den Defaults dieses Commits;
keine Konfigurationstabelle, zusätzliche Filter, Reanalyse oder AI-Aufrufe.
`NONE` unterdrückt die unmittelbaren Resultsets; der physische Tabellenoutput wird weiterhin geschrieben.
Upstream-Filter und Deduplizierung bleiben wirksam. Die Auswahl ist keine vollständige Workloadhistorie.

Die Zeilenspalte `Version` im Tabellenoutput bezeichnet die **SQL-Engine**, nicht die FRK-Version.
Der Erfassungsprozess muss die exakte Toolherkunft prüfen und bestätigen. Ein Caller kann eine falsche
Herkunftsangabe nicht durch Schemaerkennung beweisen; die Registrierung ist keine Signaturprüfung fremden Codes.

## Öffentliche Aufrufe

```sql
EXEC viz_frk.RegisterCapture
    @CaptureId=@Id, @SchemaName=N'viz_capture', @TableName=@NewTable,
    @SourceVersion='8.34',
    @SourceCommit='756206859c23aa98cdb41643763c5f1d3c10cbab',
    @ProfileId='blitzcache-8.34-cpu50-v1',
    @ServerKey=@Server, @DatabaseKey=@SourceDatabase,
    @CapturedAtUtc=@Utc, @CheckDate=@CheckDateWithOffset,
    @ExpectedRows=@Rows, @DataBasis='user', @Complete=1;

EXEC viz_frk.InspectCapture @Id;
EXEC viz_frk.ReadBlitzCacheDataset @Id;
EXEC viz_frk.BlitzCacheWorkloadMap @Id;
EXEC viz_frk.BlitzCacheWorkloadMap @Id, @DetailPage=1; -- CPU-ranked detail from the same capture
-- Optional: @Title, @XScale='log', @YScale='log' (only with positive axis values).
```

Das [Capturebeispiel](../../../examples/frk/capture-blitzcache.sql) führt Erfassung und Registrierung aus
und liefert genau ein Scene-Resultset. Die drei lesenden Aufrufe erfassen nichts erneut. Auch
`INSERT @Scene EXEC viz_frk.BlitzCacheWorkloadMap @Id` ist möglich.
`InspectCapture` liefert ein Resultset mit Manifest, Quelltabelle, Hashes, Zeilenzahl sowie
`MissingAverageCount` und `AverageMismatchCount`. Registrierung emittiert kein Resultset.

`RegisterCapture` verlangt eine abgeschlossene Erfassung außerhalb einer bestehenden Transaktion.
Es prüft Schema, maximal 50 Rows, exakte erwartete Zeilenzahl, eindeutige positive Source-IDs,
nichtnegative Zähler und einheitliche Herkunft/CheckDate. CaptureId und Quelltabelle dürfen nicht wiederverwendet werden.
Ein gemeinsames CheckDate allein verbindet keine Captures.

`CaptureManifest` enthält Herkunft, Profil, UTC-Zeit, Parameterset, Coverage und Datenbasis
(`synthetic`, `lab`, `user`). Es gibt kein erfundenes gemeinsames Zeitfenster.
`CaptureSource` speichert Tabellenname, ObjectId, Erstellungszeit, Rowzahl und SHA-256 für
Pflichtspaltenschema sowie gelesene Rohwerte. Jeder Leseaufruf lädt die Quelle genau einmal und vergleicht diese Werte.
Zusätzliche unbenutzte Spalten dürfen existieren; Änderungen an gelesenen Daten nach Abschluss werden abgelehnt.
Querytext und Plan-XML sind nicht Teil des Fingerprints und werden nicht gelesen.

## Dataset und Einheiten

Die Spaltenreihenfolge ist fest; das Interface hat genau ein Resultset, sortiert nach `TotalCpuMs DESC, SourceRowId`:

| Spalte | SQL-Typ / Bedeutung |
|---|---|
| CaptureId | uniqueidentifier |
| ItemKey | nvarchar(200), `CaptureId:SourceRowId` |
| Label | nvarchar(400), `Q` plus SourceRowId |
| ExecutionCount | bigint, exakte Anzahl |
| TotalCpuMs / TotalDurationMs | decimal(28,3), bereits vorhandene Millisekunden |
| LogicalReads | bigint, 8-KiB-Seitenzugriffe |
| CounterBasis | varchar(20), `cache-lifetime` |
| WindowSeconds | decimal(28,3), NULL |
| AvgCpuMs | decimal(28,6), TotalCpuMs / ExecutionCount; Count=0 → NULL |
| ExecutionsPerMinute | decimal(28,6), NULL; keine ungesicherte Ratenübernahme |
| SourceRowId | bigint, unveränderte ID aus der Quelltabelle |
| QueryHash | binary(8), zusätzliche Information, kein Gruppierungsschlüssel |
| AverageMismatch | bit, Abweichung vom Quellmittel > 1 ms |

Der Upstream teilt DMV-Mikrosekunden bereits durch 1000 und konvertiert im physischen Tabellenoutput nach `bigint`.
Eine weitere Division durch 1000 wäre falsch. Die verlorenen Submillisekunden können nicht rekonstruiert werden.
Die Toleranz von 1 ms berücksichtigt die separate Abschneidung von Summe und Durchschnitt.
Ungenaue Quellmittel ändern den nachgerechneten Wert nicht; das Protokoll kennzeichnet die Abweichung.
Zähler bleiben bis zur XY-Projektion exakt; danach gelten die Größen-/Koordinatenbudgets des Charts.

Die WorkloadMap zeigt X=Count, Y=CPU-Mittel, Fläche=CPU-Summe. Count=0 wird als fehlend gezählt.
Jede Datenmarke hat denselben ItemKey wie das Dataset und ist im Grid zurückverfolgbar.
Titel/Subtitle nennen Datenbasis, CPU-Auswahl, Rowzahl, UTC-Capturezeit und Cachelebenszeit.

## Rechte und Paketgrenzen

- `viz_user`: EXECUTE auf InspectCapture, ReadBlitzCacheDataset und BlitzCacheWorkloadMap.
- `viz_frk_capture`: EXECUTE auf RegisterCapture, plus explizites SELECT auf die Source.
- Quellen benötigen die tatsächlichen SELECT-Rechte des Aufrufers; dynamische Reads umgehen sie nicht.
- Kein SELECT/INSERT/UPDATE/DELETE auf Manifesttabellen für Runtime-Rollen; kein direkter Aufruf interner Loader.
- Keine Fremdprozedur, Serverrechte oder Querytexte sind für synthetische Adaptertests nötig.

Fehler: `51012` fehlender/unvollständiger/gemischter/geänderter Capture, `51011` Profil/Schema/Datenvertrag,
`51010` fehlende Quelle oder SELECT-Rechte. Ein vom Chart abgelehnter Wert verwendet dessen bestehenden Fehlercode.
DMV-Rezepte verwenden `51013` für verworfene Zählerintervalle.

[Deinstallation](../../../dist/uninstall-frk-adapter.sql) verweigert registrierte Captures, fremde Abhängigkeiten
und bestehende Mitglieder der Capture-Rolle. Ein Administrator muss benötigte Metadaten vorher sichern
und bewusst entfernen. Die Source-Tabellen, ihr Stagingschema, Core/Charts und die Datenbank bleiben bestehen.
Vor Charts/Core zuerst den Adapter deinstallieren. Tabellenänderungen erfordern eine explizite Migration;
Wiederinstallation aktualisiert Prozeduren, ohne Capture-Metadaten neu zu erzeugen.

## Sichtbarer Kontext und Details ab S5a

Die Ansicht enthält Quelle/DB, UTC-Capturezeit, unterschiedliche Cachelebenszeiten, Auswahl und Restmenge, berechnete CPU-Summe/Maximum/Gleichstände und Aussagegrenze. Bis acht Zeilen erscheinen als aufgelöste Detailansicht, größere Captures als ausdrücklich benannte Übersicht. [detail-workload.sql](../../../examples/frk/detail-workload.sql) liest einzelne CPU-Ränge aus demselben registrierten Capture. Q-Codes entstehen über dessen komplette SourceRowId-Reihenfolge; die Auflösung nennt den exakten Quellschlüssel. Die `Label`-Spalte des Rohdatasets bleibt unverändert und darf nicht mit dem neuen Display-Code gleichgesetzt werden.

[Konkreter Vertrag](../../../docs/data-contracts.md) · [SQL-Nachweise und ausstehende SSMS-Abnahme](../../../docs/validation.md).
