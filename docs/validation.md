# Validation and known limitations

This is a summary of recorded checks for the early `0.1.0-s5a` implementation. Most runs took place on 14–16 September 2026; the native vector example was also checked on 5 October 2026. These results describe the tested versions, not a stable API or a guarantee for future changes.

## SQL checks

| Area | Recorded coverage |
|---|---|
| Core and charts | SQL Server 2017 / compatibility 140, 2019 / 150, 2022 / 140 and 160, and 2025 / 170 |
| Installation and access | Clean installation, repeat installation, migration from the earlier Core package, collision handling, rollback, case-sensitive databases, restricted users and concurrent calls |
| Data and geometry | Coordinate mapping, bubble area ratios, NULL versus zero, line gaps, text measurement, scene schema and geometry budgets |
| Context and identity | 106 runner cases across five engine/compatibility combinations; field validation, label mapping, detail pages and numerical assertions |
| BlitzCache adapter | Fixed 8.34 source commit, synthetic normalization checks, real laboratory captures, source drift, permissions and capture separation; 63 cases in the recorded final SQL Server 2022 run |
| Workbook | All 24 tagged SQL examples passed on SQL Server 2017 / 140 and 2022 / 160 under `viz_user` |
| Query Store recipes | SQL Server 2022 / 160; weighted duration, CPU totals, execution status, UTC, gaps and real reads across databases under a restricted login |
| Native vector demo | SQL Server 2025 / 170; all 18 shapes valid, including labels and axes, with the expected Euclidean, cosine and negative dot-product results |

The later Query Store recipes have SQL checks but no new visual acceptance record for their exact layouts. The vector screenshot in the [README](../README.md) shows one small example; it does not establish acceptance of every chart.

On 5 October 2026, the context suite was rerun after limiting its synthetic example selection to `00` through `04`. All 22 cases and 57 assertions passed on SQL Server 2022 (`16.0.4125.3`, compatibility 160), including the performance and geometry budgets. This was SQL validation; no new SSMS visual review was performed.

### Agent artifact checks, 8 October 2026

The [agent suite](../tools/test-agents.ps1) exported its 14 ordered cases with
`-PrepareOnly`. Those exact SQL files were executed with error-stopping `sqlcmd`
in dedicated remote Docker lab containers, using existing pinned images:

| Engine | Compatibility | Agent cases | Existing SQL contract files |
|---|---|---|---|
| SQL Server 2017 `14.0.3550.4` | 140 | 14/14 passed | `core.sql`, `charts.sql`, `context.sql` passed |
| SQL Server 2022 `16.0.4295.3` | 160 | 14/14 passed | `core.sql`, `charts.sql`, `context.sql` passed |

Coverage includes installation/test-principal setup and cleanup, consumer
preflight, the four [agent examples](../examples/agents/README.md), signed/zero/
missing values, an independent UTC millisecond oracle, CPU conversions and equal
bubble areas, changed-input observations, visible context and geometry budgets.
Synthetic scripts passed under a database user with only `viz_user` access.
The live wait branch passed as a lab administrator and was rejected under a
login lacking server diagnostic permissions. Observed counter decreases,
excessive context detail input and missing library access were also rejected.

The containers used two CPUs and a 3 GiB memory limit and were removed with
their own anonymous volumes. These were functional checks, not performance
benchmarks. The local Docker provisioning/.NET execution path of the new runner
was not exercised in this run; its exported cases were. No production system
or customer data was accessed, and no new SSMS visual acceptance was performed.
Existing autozoom, zero-marker and connector limitations still apply.

## Performance

The recorded context-enabled benchmark used SQL Server 2022, compatibility 160, with two CPUs and a 4 GiB container limit. After one warm-up, five runs gave these medians:

| Input | Server-side median |
|---|---:|
| 20 bars with labels and context | 717 ms |
| 200 bubbles as an overview | 746 ms |
| 5,000 line points with context | 778 ms |
| Eight bubble details with labels and context | 626 ms |

These runs passed the 3,000 ms median budget and the scene limits. They measure SQL scene generation, not SSMS display time or performance on other hardware.

## Visual checks and open issues

Earlier primitive, bar, line, bubble and diagnostic views were inspected in SSMS 22.4.11612.150. Subsequent text and context changes still need complete visual review. SSMS 21 and the remaining viewer checks against SQL Server 2017 and 2025 are also pending.

Recorded review of the context-enabled bar and line examples found:

- Long context sections increase the scene extent. SSMS autozoom can make the whole drawing, including explanatory text, too small to read comfortably.
- A zero cross can be difficult to distinguish beside its numeric label.
- A line's connector to its end label can resemble an additional flat data segment. Increasing the window size did not resolve that interpretation problem.

These observations were made by an AI reviewer using prepared expectations, not an independent participant study. The reading and interpretation cases did not pass. Valid geometry and the presence of text do not establish that a reader can understand a chart.

SSMS controls colors and can blend overlapping shapes. Dense views and the Query Store recipe's status grouping still need inspection in the target viewer. See [rendering and limits](rendering.md) for setup and budgets.

## Reproduce the checks

The executable suites and fixtures are included in the repository. Follow the [development guide](development.md) for commands and the [laboratory guide](../tests/visual/README.md) for SSMS inspection.

Runners write logs, manifests and source hashes to `tests/results/`. Archived runs, screenshots, scene exports and historical project reports are retained locally but excluded from the public repository. The tests do not require those archives. Run the suites for the source version you intend to use, and inspect the resulting picture separately.
