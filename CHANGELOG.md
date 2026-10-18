# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); release tags will be
annotated `vX.Y.Z` cut by `scripts/release.sh`.

## [Unreleased]

### Fixed
- System-process notes require a system executable path, except for the
  kernel's PID 0, and no longer promise that quitting is safe.
- The history size cap no longer drops more history on every write
  after the store first exceeds it.

### Added
- Network bytes per app in the ledger, stored history, range reports
  ("Top network"), daily totals, `get_top_processes` and `coreo diagnose`.
- An alert for a startup disk under 10% free, and Settings > Alerts to
  run one of your Shortcuts when a rule is raised.
- The Dock icon can show a live CPU or memory graph (Settings > Dock).
- Per-process and per-app network: a Network in/out column and sort in
  the process table, the inspector's rate and `coreo traffic`, from the
  same source nettop uses.
- A month of history: 1-minute minimum, maximum and mean kept 30 days,
  7 d and 30 d ranges, per-app daily CPU and disk totals and
  `coreo apps --days N`. Retention presets include the new tier.
- Bottleneck hints in the CPU lane and HUD: "Looks GPU-bound", "Looks
  CPU-bound" and "Possibly throttling", each with the readings that
  tripped it.
- Apple Silicon CPU, GPU, ANE and DRAM power from IOReport's energy
  model, and each CPU tier's activity and frequency, in the CPU and
  Power lanes, the HUD, diagnostics and `coreo silicon`. All are
  estimates; a virtual machine or a stalled counter says so.
- Command-Shift-P opens a command palette listing every window action
  by name, with the reason any of them cannot run now.
- Shortcuts actions for the system summary, top apps, recording, and
  who uses a port or has a file open; `coreography://` links that
  navigate, filter, select a process, set the range, record or toggle
  the HUD.
- The inspector shows Time Machine backup progress for `backupd` and
  whether Spotlight indexes the startup disk for its processes;
  diagnostics report both and flag a running backup.
- Diagnostic process role notes and current sleep-preventing assertion
  types, with read time, availability and omissions. Private assertion
  names stay out of diagnostic results.
- Sample a process's call stacks for 3 seconds and read or save the report.
- A HUD with CPU, GPU, temperature and power over full-screen apps
  (Option-Command-H or the menu bar extra).
- Command-R records a session; its report shows minimum, mean, 95th
  percentile and maximum per metric and the top apps. Two sessions
  compare overlaid; sessions export as JSON or CSV and can be renamed.
- `file:` in the process filter finds which process holds a file or
  folder; the inspector lists open files.
- Wakeups per second for every process and app, and in Coreography's
  own cost against its budget.
- Suspend, Resume, Send Signal, Lower Priority, Reveal in Finder and
  Copy for processes, each identity-checked and confirmed.
- Process filters can be saved as chips.
- The Power lane names what keeps the Mac awake; the inspector lists a
  process's sleep assertions; `#preventing-sleep` filters to them.
- Settings: history retention presets with their disk cost and the
  measured size, and a Data sources section.
- A 24 h range drawn from a week of 10-second minimum, maximum and mean
  history.
- Lanes mark sleep and wake, power source changes and pressure
  transitions; range reports list the markers inside them.
- Range exports redact app names by default; names can be included.
- `port:443` in the process filter finds which process holds a port.
- An inspector for the selected process: identity, parent chain,
  signature, launchd job, arguments, sockets, a plain-language note for
  known system processes and Quit; with nothing selected, this Mac.
- A Startup tab listing launch agents and daemons with their enabled
  state, signer and current cost; Apple items hidden by default.
- A Sensors tab with current, minimum, maximum and average for every
  temperature, fan and the system power rail, with a reset.
- A Connections tab listing each app's TCP and UDP sockets, the
  `#listening` filter token and `coreo connections`.
- On the 6 h range, range reports and the scoped app's overlay include
  recorded history; export says it covers live data only.
- The per-app ledger is recorded to the history store for six hours;
  `coreo apps` totals recorded app activity.
- A 6 h range: lanes show recorded history behind the live hour, with
  gaps kept.
- Sleep and wake history from the power-management log: sleep periods
  with dark wakes and battery change, for `get_sleep_history`, Ask and
  `coreo sleep`.
- Six hours of system history recorded to a private SQLite store, with
  one-click deletion and `coreo history`.
- Process filter grammar: predicates such as `cpu:>10` and `mem:>1GB` and
  tokens such as `#apps`, `#mine` and `#new`; unusable terms are named.
- Process pane heat-shaded cells, briefly tinted new processes and a
  30-second list of exited processes.
- Alerts: critical memory pressure, heavy thermal pressure and low battery
  tint their lanes and drop markers; memory and battery also notify.
- Ask Coreography: plain-language questions answered by Claude through the
  diagnostic tools, with a Keychain-stored key and listed evidence.
- `coreo mcp --stdio`: a read-only MCP server for the six diagnostic tools,
  with snapshot reuse, cursors and a call budget.
- The shared diagnostic contract and `coreo diagnose`: a summary with
  fact-only signals, paged top apps, bounded history and data sources.
- Menu bar extra with CPU in the title, mini lanes, the top CPU app, hold
  and Open Coreography; sampling continues while the window is closed.
- App scope: a scoped app's CPU share overlays the CPU lane, its disk
  rate shows in the disk lane, and the process pane filters to it.
- Quit and Force Quit for processes with identity re-checks, stated
  consequences and timeline markers.
- JSON and CSV export of a selected range; missing readings stay empty.
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
