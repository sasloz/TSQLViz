# Test fixtures

`install-core-s2.sql` is the earlier Core installer used only in the runner's isolated upgrade fixture database. It checks migration while preserving table-type identity and an existing consumer procedure. It is test input, not the current release installer.

`frk-raw.sql` is synthetic input matching the tested BlitzCache profile's required schema. Two separate tables reuse identifiers and timestamps with different totals to check capture separation. It contains no query texts, plan XML or upstream implementation.

`frk-workload.sql` creates a synthetic table and query patterns only in the disposable laboratory. The real-capture runner records these through the separately downloaded, hash-checked BlitzCache procedure. Variable cache observations are compared row by row with the adapter rather than treated as fixed expected totals.

These fixtures are included so the tests can be reproduced without archived test runs. See the [validation summary](../../docs/validation.md) and [development guide](../../docs/development.md).
