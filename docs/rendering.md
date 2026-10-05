# Rendering in SSMS

TSQLViz returns `geometry` values for SSMS Spatial Results. A direct `SELECT` can return shapes, while chart procedures return a shared scene containing marks, layout and text.

## Viewer setup

Use **Results to Grid**, open **Spatial Results**, and select `Shape`. Set **Tools > Options > Query Results > SQL Server > Results to Grid > Maximum Characters Retrieved > Non XML data** to at least **65535**. Turn native labels and the viewer grid off for charts that draw their own labels and axes.

SSMS zooms to the extent of the complete result, including text and context outside the plot. Y increases upward. Equal scaling on X and Y preserves angles and length ratios in custom drawings.

The viewer assigns colors to geometry rows. TSQLViz cannot prescribe a stable palette or arbitrary fill/stroke styles. Use names, codes, shapes and the current legend to identify data. Transparent overlap and row order do not provide a dependable opaque masking mechanism.

## Scene output

Charts and [RenderScene](../src/core/render/RenderScene.sql) return the eight columns of [Scene_v1](../src/core/types/Scene_v1.sql), ordered by `Layer`, `ElementOrder`, then `ElementKey`. The only spatial column is `Shape`. See [data contracts](data-contracts.md) for the full column order.

Each shape must be valid, nonempty, two-dimensional geometry with SRID 0. `RenderScene` validates the complete input before returning it. It does not repair invalid shapes, split oversized shapes, remove observations or sample data. Line charts build smaller pieces before rendering; adjacent pieces share an endpoint and preserve the observations.

## Current budgets

These are implementation limits for this early version. They are project choices, not universal SQL Server or SSMS limits.

| Scope | Limit |
|---|---:|
| Scene rows | 2,000 |
| Total points, summed across shapes | 100,000 |
| Serialized bytes per shape | 32,000 |
| Total serialized scene size | 16 MiB |
| Absolute scene coordinate | 1,000,000 |
| Chart canvas width / height | 320–4,000 / 240–4,000 drawing units |
| Drawn text in chart assembly | 4,000 characters |
| Chart series | 8 |
| Bar categories | 20 |
| Bubble/scatter marks | 200 |
| Line observations | 5,000 |
| Context-enabled bubble detail input | 8 rows |

Serialization budgets use `DATALENGTH(Shape.Serialize())`; point counts use `STNumPoints()`. Numeric dataset values are bounded by `1e15` and domains by `1e16`. Chart-specific validation can reject input before scene assembly. See the [chart reference](../src/charts/README.md) and [source](../src/core/render/RenderScene.sql) for the current checks.

A direct call to `Circle`, `Segment` or another shape constructor does not validate the complete scene. Use `RenderScene` when you need scene-level checks. It enforces the geometry budgets; the chart assembly helpers additionally account for text.

In the recorded SSMS 22 probe, 5,001 output rows caused a warning that only the first 5,000 objects would be shown. That was an object limit, not a total point limit. Smaller retrieval settings can also truncate shapes. Raising the setting does not make every large scene readable or fast.

## Failures and readability

Invalid scene kinds produce `51001`, invalid geometry produces `51003`, and exceeded scene budgets produce `51004`. Chart option/layout failures use `51000`; invalid domains use `51002`. SQL type constraints or geometry parsing may also raise native SQL errors.

An empty direct scene returns zero rows. Chart procedures can draw a `NO DATA` notice. Missing observations and observed zero values have different meanings and must stay distinct.

Inspect labels, endpoints, overlap and the full scene at the intended window size. Known context and connector problems are described in the [validation summary](validation.md). This version's API and rendering behavior may change.
