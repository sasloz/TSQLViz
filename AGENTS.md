# Working with TSQLViz

TSQLViz turns caller-supplied data into SQL Server `geometry` for SSMS Spatial
Results. Its experimental API is defined by the SQL source, not by plausible
chart-library conventions. Pin the repository revision and installed package
before generating a consumer script.

## Generate a visualization artifact

1. Read [docs/agent-guide.md](docs/agent-guide.md) for the workflow and API map,
   and [docs/agent-safety.md](docs/agent-safety.md) before designing acquisition
   from tables, DMVs or Query Store in a restricted environment.
2. Inspect the selected type in `src/core/types/` and procedure in `src/charts/`.
   Use [examples/agents/](examples/agents/README.md) as runnable starting points.
3. Deliver a reviewable T-SQL script with separate acquisition, normalization
   and rendering sections; declare units, scope, ordering, missing values,
   permissions and runtime prerequisites. Include all seven context fields.
4. Execute the artifact on synthetic or explicitly approved lab data. Check
   values and scene budgets; report SQL execution and SSMS visual acceptance
   separately. A script is ready for review when its dependencies, source reads,
   limits, test results and remaining assumptions are explicit.

The agent works outside PROD. A human reviews and transfers the SQL artifact
and executes it using existing approved access. The runtime needs preinstalled
TSQLViz Core + Charts and SSMS; it needs no AI service or additional network
connection. Installation and permission grants are separate DBA operations.

## Change this repository

Read [docs/development.md](docs/development.md) for build and test commands.
Change library SQL in `src/`; regenerate `dist/` with the build scripts when
library code changes. Prototypes are outside the normal installer. Keep examples
and contract references synchronized with API changes.

For agent examples run `./tools/test-agents.ps1` (PowerShell 7, an inspected
existing local Docker SQL Server image), or its `-PrepareOnly` mode to export
the same SQL cases for an approved remote lab. This is test tooling, never a
PROD deployment step. Preserve unrelated lab resources.
