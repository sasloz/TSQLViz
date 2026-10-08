# AI-assisted SQL artifacts for restricted environments

Use an AI agent outside PROD to prepare a transparent T-SQL visualization script.
The consultant reviews it, transfers it by the permitted route, and runs it in
SSMS using existing access. Source data stays inside the environment unless a
separate disclosure is explicitly approved. No agent connection to the customer
server is part of this workflow.

## Runtime prerequisites

- SQL Server 2017+ and database compatibility level 140+.
- **Preinstalled TSQLViz Core + Charts**, matching the revision used to generate
  the artifact. The current experimental package is `0.1.0-s5a`; the API can
  change even though type names end in `_v1`.
- Library access through the existing `viz_user` database role, plus separately
  approved source permissions. A DBA installs [dist/install.sql](../dist/install.sql)
  and assigns the role; generated consumer artifacts do neither.
- SSMS with Results to Grid and Spatial Results. SSMS 22 is the primary tested
  viewer; SSMS 21 validation is incomplete. Choose `Shape`, turn native labels
  and viewer grid off, and retrieve at least 65,535 Non XML characters.

There is no promised zero-install mode. TSQLViz is installed SQL code, including
user-defined table types, procedures, functions and font data. After installation,
the artifact requires no AI SDK, API key, outbound request or extra runtime
service. The approved SSMS-to-SQL-Server connection is still required.

Run [00-preflight.sql](../examples/agents/00-preflight.sql) as a separate batch
before the chart script. It checks the selected database and visible API/access;
it does not prove source access or schema equivalence. Ask the DBA to confirm the
installed revision/version from `viz.LibraryVersion` and deployment records:
`viz_user` does not automatically grant SELECT on that metadata table.

## Prepare an artifact

1. **Define the question.** Obtain approved schema descriptions, units, time
   basis, selection criteria and maximum expected size. Use synthetic rows
   outside the environment, rather than requesting customer query text or data.
2. **Verify the API.** Read the actual type definition and chart procedure from
   the pinned revision. Avoid invented parameters, implicit column order or
   prototypes absent from the normal installer.
3. **Acquire once.** Put source reads in a clearly marked section. Use a bounded
   time/key scope, the caller's permissions and typed parameters. Materialize
   the snapshot in local variables or temporary tables. See
   [agent safety](agent-safety.md) before adding real acquisition.
4. **Normalize explicitly.** Convert units, compute weighted means, assign stable
   keys and deterministic ordering, preserve NULL versus zero, and reject an
   oversized selection. Declare any intentional Top-N or aggregation in context;
   chart budgets do not authorize silent truncation.
5. **Render from the snapshot.** Populate the appropriate `viz.*_v1` variable,
   all seven context fields, and the applicable identity mapping. Derive the
   observation field from the actual input. Call the chart with named arguments.
6. **Validate and hand off.** Execute synthetic fixtures, inspect numeric values
   and geometry budgets, and report permissions and any untested live path. SQL
   success is separate from SSMS readability. Deliver the SQL and concise review
   notes; a human controls transfer and execution in PROD.

All [agent examples](../examples/agents/README.md) execute in the database where
TSQLViz is installed. Table-valued types are database-scoped: a three-part chart
procedure name does not make a locally declared type interchangeable with a type
in a utility database. For a separate source database, execute in the library
database and use reviewed three-part source reads. Follow the existing
[Query Store recipes](../examples/query-store/README.md) for safely quoted
database identifiers and parameterized values; never concatenate arbitrary SQL.

## Choose a contract

| Output | Input and procedure | Required semantics |
|---|---|---|
| Signed categories | [`CategoryValue_v1`](../src/core/types/CategoryValue_v1.sql), [`BarChart`](../src/charts/BarChart.sql) | One series, one row per category; zero baseline; NULL is missing. |
| Ordered observations / UTC series | [`XY_v1`](../src/core/types/XY_v1.sql), [`LineChart`](../src/charts/LineChart.sql) | Unique PointOrder within each series; nondecreasing X; NULL Y breaks the line. |
| Frequency, unit cost, total cost | `XY_v1`, [`BubbleChart`](../src/charts/BubbleChart.sql) | X/Y are coordinates; SizeValue is area data, not radius. |
| Custom geometry | [`Scene_v1`](../src/core/types/Scene_v1.sql), [`AnnotateScene`](../src/core/render/AnnotateScene.sql) / [`RenderScene`](../src/core/render/RenderScene.sql) | Exact eight-column scene schema; unique element keys; valid nonempty 2D geometry, SRID 0. |

Use explicit INSERT column lists. `CategoryValue_v1` requires ItemKey,
CategoryKey, CategoryLabel, CategoryOrder, SeriesKey, SeriesLabel, SeriesOrder;
Value and DetailLabel can be NULL. `XY_v1` requires ItemKey, SeriesKey,
SeriesLabel, SeriesOrder, PointOrder and X; Y, SizeValue and DetailLabel can be
NULL. Keys have binary collation; preserve identity rather than using display
labels as keys. Consistent series labels/order are validated.

Line time axes require `@XKind='time', @XFormat='utc-time'`, with X from
`viz.TimeToEpoch(UTC_datetime2_3)`: integer UTC milliseconds since 2000-01-01,
dates 1900 through 2100. The function does not convert local time to UTC.
BubbleChart has no `@XKind` time option; use a custom scene for time bubbles.

Numeric formats are `number`, `compact`, `integer`, `percent`, `duration-ms`,
`bytes-iec`. `percent` takes a fraction (0.25 -> 25%); duration input is ms,
byte input is bytes. Label the underlying units even when display suffixes vary.
Bubble `@SizeMode='constant'` is scatter and ignores SizeValue. Log axes require
positive coordinates; they are BubbleChart options, not LineChart options.

## Context and limits

Follow [data-contracts.md](data-contracts.md#context-and-visible-identity) for
`Context_v1`: exactly `marks`, `source`, `time`, `population`, `reading`,
`observation`, `limitation`, each nonblank and at most **350 UTF-16 code units**
(the column itself holds 400). Context is optional in the library; this agent
workflow always supplies it. Structure validation cannot establish factual truth.

Bar needs an ItemLabel for every input key, including missing values. Line uses
its own series codes and requires empty ItemLabels. Bubble with context and
`@View='detail'` needs exact ItemLabels and at most eight input rows. Context
overview uses `@View='overview'` with empty ItemLabels; identity requires separate
detail pages from the same materialized snapshot. Page scales are local: compare
numeric values across pages, not bubble areas from separate calls.

| Budget | Current source limit |
|---|---|
| Bar | 20 categories including missing; one series |
| XY | 10,000 input rows; eight series |
| Line | 5,000 input rows total across series, including gaps |
| Bubble / scatter | 200 visible marks; context detail additionally eight input rows |
| Canvas | Width 320..4000, height 240..4000; readable plot space can impose tighter bounds |
| Title / subtitle / axis title | 100 / 200 / 60 UTF-16 code units |
| Data magnitude | Absolute X/Y/bar value <= 1e15; area SizeValue 0..1e15 |
| RenderScene | 2,000 rows, 100,000 points, 32,000 serialized bytes per shape, 16 MiB total, absolute coordinates <= 1,000,000 |

Limits are rejection boundaries, not readability guarantees. Context extends
below the plot and can shrink it through viewer autozoom. SSMS controls colors;
use codes and labels, never promise semantic colors or interactive drilldown.
Errors `51000` (options/layout), `51001` (contract/context), `51002` (domain/time)
and `51004` (budget) require fixing the input or declared view; `51003` reports
invalid geometry. Preserve error visibility. See [rendering](rendering.md) and
[validation](validation.md) for the full behavior and known layout problems.

## Brief to give an agent

```text
Using the pinned TSQLViz revision and its installed Core + Charts API, prepare
one reviewable T-SQL script for SSMS Spatial Results. The agent runs outside PROD.
Question: <analysis question>. Approved schema: <types and keys, no real data>.
Units/time basis: <units, UTC window or counter basis>. Selection: <scope/budget>.
Keep acquisition, normalization and rendering separate. Start with synthetic
data and make real acquisition explicit. Include complete context and identities.
State prerequisites, source permissions, scope/cost assumptions and test evidence.
Deliver an artifact for human review; installation/security changes are separate.
```
