# Query Store visualizations

Both examples use the TSQLViz installation in `_SQLMaint` and read a selectable user database on the same SQL Server instance. They require no library update and create no persistent objects.

## One plan's average duration

[plan-duration.sql](plan-duration.sql) draws a single line using the TSQLViz installation in `_SQLMaint` and Query Store data from a selectable user database on the same SQL Server instance. It adds no context footer and creates no persistent objects.

1. Open the script in SSMS and set `@SourceDatabase` and `@PlanId`.
2. Optionally change `@FromUtc` and `@ToUtc`; the default is the last 24 hours.
3. Execute the complete script. It switches to `_SQLMaint` to use that database's table types and chart procedure.
4. Choose **Spatial Results**, select `Shape`, and turn native labels and the viewer grid off. Non XML Data retrieval must be at least 65,535.

The line shows execution-count-weighted average duration in **milliseconds**, one point at each selected interval's UTC start. Only successful executions (`execution_type=0`) are included. Multiple runtime-statistics rows for the same plan and interval are aggregated before plotting, including the persisted/in-memory split of the active interval. See Microsoft's [runtime statistics contract](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql).

The window selects interval **start times** in `[FromUtc, ToUtc)`. Each point represents that interval's available statistics, not a measurement at a single instant or an exact arbitrary sub-interval. The active interval can still change. Existing intervals without successful executions for the plan get NULL, producing line gaps. Intervals absent from Query Store itself are not reconstructed.

Required access: `viz_user` in `_SQLMaint` and Query Store read permissions in the source database: `VIEW DATABASE STATE` for SQL Server 2017/2019 or `VIEW DATABASE PERFORMANCE STATE` for 2022 and later. The script uses the caller's existing permissions and does not enable Query Store or alter database security. [Microsoft interval-view permissions](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-interval-transact-sql).

An unknown plan, an empty time window, or no successful executions produces an explicit message. More than 5,000 selected intervals requires a narrower window; points are not silently removed.

[Validation](../../docs/validation.md) covers weighted means, UTC, gaps, successful-execution filtering, and an actual Query Store read across databases under a restricted login on SQL Server 2022.

## One query's CPU, execution count, and status over time

[query-cpu-bubbles.sql](query-cpu-bubbles.sql) produces a bubble chart across **all plans of one `query_id`**. Change `@SourceDatabase` and `@QueryId`, optionally set `@FromUtc`/`@ToUtc`, and execute the complete script. Use the same SSMS settings and permissions as above.

| Encoding | Meaning |
|---|---|
| X | UTC start of the Query Store interval |
| Y | **Total CPU in milliseconds**, summed for this query, interval, and execution status |
| Bubble area | Execution count for that same interval/status, summed across the query's plans |
| Status grouping / legend | R = Regular (0), A = Aborted (3), E = Exception (4) |

Each interval can contain up to three bubbles. CPU is `SUM(avg_cpu_time * count_executions) / 1000`, not a percentage and not mean CPU per execution. Multiple statistics rows for an active interval are included in the sum. Records with zero executions are ignored; an actual CPU total of zero with positive executions remains a bubble on the zero level. The active interval is provisional. These meanings follow the [Query Store runtime-statistics fields](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql).

The chart has a title, UTC/CPU axes, status legend, and size legend, with no additional context footer. Up to 200 interval/status observations are accepted. A larger selection gives an explicit error and requires a shorter time window; it does not silently remove points or change the aggregation granularity.

### Status colors in SSMS

This is a custom Scene built with public Core helpers because the current high-level BubbleChart has no time-axis parameter or semantic color API. SSMS assigns its palette to output geometry rows. The example puts every bubble of one status **and its legend swatch in the same GeometryCollection row**, so the swatch shares the row's rendering style. The three groups have a stable output order. R/A/E labels beside the bubbles provide another status encoding.

The example does not prescribe green, yellow, or red. Actual hues depend on the viewer and can change between charts when other scene elements change. Overlapping colors can blend. Use the legend in the current view and the letter codes; identical positions are not jittered apart or merged.

Compact native `CurvePolygon` circles keep even 200 observations of one status within the per-shape byte budget. A circle is represented by five arc points, with radius from `viz.BubbleRadius`. [SQL Server CollectionAggregate](https://learn.microsoft.com/en-us/sql/t-sql/spatial-geometry/collectionaggregate-geometry-data-type) preserves the separate circle members; it does not union overlapping areas. Grouping affects output storage, not the sum of executions or the CPU calculation.

This differs from the standard BubbleChart's one-output-row-per-observation convention. The grouped scene rows carry a status `SeriesKey` and `ItemKey=NULL`. Individual interval/status values remain in the local `@Runtime` table; if needed, inspect it with a separate SELECT in the same batch. The status-row label reports the number of data bubbles separately from its legend swatch.

Native curves and collections have historical SSMS 22 evidence, and the new example has passed [SQL validation](../../docs/validation.md), including a real Query Store read. This particular grouped-color view has not received a new SSMS visual acceptance test; color, contrast, and dense-label readability still need confirmation in the target viewer.
