# Agent artifact examples

Run [00-preflight.sql](00-preflight.sql) separately, then one complete chart
script in the database with preinstalled **Core + Charts 0.1.0-s5a**. SQL Server
2017+, compatibility level 140+, library access (`viz_user`) and SSMS Spatial
Results are required. Installation/role assignment are separate DBA steps.
These are ordinary T-SQL scripts, with no SQLCMD mode, AI connection or network
request at runtime. They create no persistent objects.

| Script | Demonstrates | Default / real permissions |
|---|---|---|
| [01-signed-bars.sql](01-signed-bars.sql) | Signed, zero and missing values; exact item labels | Synthetic, library only |
| [02-utc-line.sql](02-utc-line.sql) | UTC epoch conversion, midnight, explicit gap and observed zero | Synthetic, library only |
| [03-cpu-bubbles.sql](03-cpu-bubbles.sql) | Exact raw counters, CPU unit conversion, equal area and missing CPU | Synthetic, library only |
| [04-wait-interval.sql](04-wait-interval.sql) | Separate two-snapshot acquisition, deltas, zero and reset rejection | Synthetic by default; real mode requires server state/performance-state access |

Each script separates acquisition, normalization and rendering. All context
fields are supplied and observations are computed from the input. Local fixture
values are deliberately small; adapt scope and budgets before replacing them
with an approved source query.

For the wait script, leave `@UseSynthetic=1` to run without diagnostic access or
delay. Only after reviewing [agent-safety.md](../../docs/agent-safety.md), set it
to `0` for two real reads and a 1..10 second delay. Four explicitly listed wait
types are retained, rather than an implicit Top-N of the server. Counter deltas
can exceed elapsed wall time. No counters are reset. Zero live deltas are valid;
they do not demonstrate a busy or healthy server.

For Query Store, use the existing [source-specific recipes](../query-store/README.md)
and add the agent guide's context where applicable. Those examples document
cross-database typed inputs, weighted means and permissions; they are not
synthetic-default scripts. FRK is a separate optional installation.

Select Results to Grid, open Spatial Results and choose `Shape`. Disable native
labels and grid; Non XML retrieval must be at least 65,535. Known context/autozoom
and connector issues remain: [validation](../../docs/validation.md). Do not infer
SQL correctness or visual readability from the other alone.

## Reproduce SQL checks outside PROD

With PowerShell 7 and an inspected existing local Docker image:

```powershell
./tools/test-agents.ps1
./tools/test-agents.ps1 -Image mcr.microsoft.com/mssql/server:2017-latest -CompatibilityLevel 140
```

The suite captures the actual examples' chart result sets and checks numerical
oracles, gaps, equal bubble areas, visible context and scene budgets. Synthetic
examples run under a user with only `viz_user`; the real wait path runs in the
isolated test lab. Cases also reject an observed counter reset, excessive bubble
detail input, denied live DMV access and missing library access. Tests create
their own lab fixtures and are not consumer scripts.

For an approved remote lab, `./tools/test-agents.ps1 -PrepareOnly` exports the
same numbered SQL cases and `agent-cases.json` under `tests/results/<RunId>/`.
Execute them in manifest order, in one dedicated disposable database with Core +
Charts installed, as a test administrator. Use a client that stops on SQL errors
(for example `sqlcmd -b`), preserve the case logs and always run the final cleanup
case if an earlier case fails. This mode provisions no container and executes
no SQL. The test scripts never require an agent connection to PROD.

See [agent-guide.md](../../docs/agent-guide.md) for artifact generation and the
[development guide](../../docs/development.md) for validation tooling.
