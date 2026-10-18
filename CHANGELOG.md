# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); release tags will be
annotated `vX.Y.Z` cut by `scripts/release.sh`.

## [Unreleased]

### Added
- Memory composition (app, wired, compressed, cached), swap use, swap and
  page-in rates, compression ratio and kernel pressure, with a stacked
  memory lane, pressure band and numeric table.
- Per-storage-driver disk rates, explicit device scope, a disk lane and
  JSON inventory; shared transfer-chart accessibility and native-scan executor.
- A scoped network lane, interface selection and JSON capture using
  full-width public interface MIB counters, with mirrored receive/send graphs.
- PID/start-time-safe process CPU, footprint and disk rates through public
  libproc, a sortable/filterable process pane and process JSON capture.
- Native CPU/memory graph foundation, numeric readings, display hold and
  an embedded diagnostic CLI.
- Typed availability, counter-rate and bounded-history primitives with
  portable tests; native build, artifact and release workflows.
- Project furniture: agent brief, canonical `CLAUDE.md`, this changelog,
  documentation checks in CI, Dependabot for Actions, and the two-tier
  Z.ai review workflow.
