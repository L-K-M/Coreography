# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); release tags will be
annotated `vX.Y.Z` cut by `scripts/release.sh`.

## [Unreleased]

### Added
- Range selection across all lanes with a range report backed by an
  in-memory per-app ledger of CPU-seconds and disk bytes.
- Self-cost readout: Coreography's own CPU and footprint beside the
  plan's budgets.
- One hour of in-memory history with 1 min, 10 min and 1 h ranges and
  spike-preserving min/max decimation.
- AppleSMC sensors: hottest temperature line over thermal-pressure bands,
  fan speeds, SMC system power for the power lane, and `coreo sensors`.
- A shared hover cursor across all lanes with values at the cursor, and
  per-lane top app contributors recorded from each process sample.
- Power lane: battery charge, external-power band, gas-gauge watts, time
  estimate, health, cycles, adapter rating and on-battery system draw;
  `coreo power`.
- GPU lane with per-GPU busy, renderer and tiler percentages and memory in
  use, `coreo gpu`, and a thermal-pressure lane from the public notify key.
- App grouping in the process pane: helpers fold under their responsible
  app or enclosing app bundle, with honest group totals and a flat view.
  Estimated values show "est." with their method on hover.
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
