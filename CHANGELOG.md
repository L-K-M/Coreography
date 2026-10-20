# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); release tags will be
annotated `vX.Y.Z` cut by `scripts/release.sh`.

## [Unreleased]

### Fixed
- App grouping and `#apps` recognize bundles whose extension is not
  lowercase, such as `Old.APP`.
- A user name the account database failed to read is asked for again,
  instead of showing a bare UID until the view is chosen again.
- A percentage between 0 and 1 reads "<1%" instead of a decimal that
  claims more precision than the sample has; a measured zero stays 0%.
- Lower Priority leaves a process that already runs at a lower priority
  alone instead of failing, and Hang Up and Interrupt on the window
  server or login window warn that they log you out.
- The Sensors tab no longer shows the last good readings as current
  after a sample in which no sensor could be read.
- Startup items take launchd's enable state from their own domain, so an
  agent and a daemon with the same label no longer share it.
- Quitting writes the history recorded since the last write instead of
  dropping up to 30 seconds of it.
- History retention deletes seek each table's key instead of scanning
  six hours of samples on every write.
- `coreo history` waits for the app's write instead of failing with
  "database is locked", and an older build no longer relabels a newer
  history store; it reports that it needs updating.
- Battery draw is recorded as system power on Macs without a sensors
  frame, as the window shows it.
- Delete history asks for confirmation, and a write that fails while
  history is being deleted no longer brings the deleted readings back.
- System-process notes require a system executable path, except for the
  kernel's PID 0, and no longer promise that quitting is safe.
- The history size cap no longer drops more history on every write
  after the store first exceeds it.

### Added
- The lanes mark apps starting and exiting, such as "Mail started".
- The app ledger keeps each app's modeled CPU energy: range reports,
  per-day app totals and `get_top_processes` rank apps by it.
- A sampling rate in the toolbar: every second or every two seconds.
- An opt-in Threads column and sort in the process table, and the
  header's thread total. `coreo top --sort threads` ranks by them.
- The network lane names its top apps by traffic, live and under the
  cursor, as the CPU, memory and disk lanes do.
- The GPU and power lanes name the apps using the most GPU time and
  modeled CPU power.
- Pointing at stored history names the apps leading CPU, disk and
  network then, not only within the live hour.
- An opt-in Architecture column (Apple, Intel, or Intel under Rosetta)
  and a `#rosetta` filter.
- An opt-in Signed by column: Apple, the developer team, or Unsigned.
- The process pane shows how much CPU and network no readable process
  accounts for.
- Process rows show their app's icon.
- Ask Coreography answers link to their evidence: the range read, the
  apps ranked and the processes looked up.
- The network and disk lanes expand into one small chart per interface
  or storage device that moved data, the memory lane into swap and
  page-ins over time, and the power lane into battery capacity bars and
  the sleep assertions held.
- With an app shown in the lanes, the network lane names its traffic, in
  plus out, as the CPU and disk lanes do.
- With an app shown in the lanes, the memory and GPU lanes name its
  footprint and GPU time, and its rank among apps.
- The process filter takes an account name, as in `user:_spotlight`.
- `coreo stats --json [--minutes N]` summarizes every recorded metric:
  minimum, median, 95th percentile, maximum and mean.
- `coreo export (--json | --csv) [--minutes N]` prints every recorded
  sample; a gap is an empty CSV cell, never zero.
- The by-user process view names accounts ("You, alice", "_spotlight")
  instead of bare UIDs, and free text finds a group by its name.
- The CPU lane's detail, from its menu or a double-click on its title,
  shows every core's activity as a heat strip under the graph.
- Scrolling sideways over a lane pans back through the history held, and
  pinching steps through the ranges; Return to Now goes back to live.
- Annotate in the range panel names a selected range; the name marks
  where it starts and ends on every lane.
- The process table's columns can be shown, hidden and reordered from the
  header, with new opt-in CPU time and start time columns and sorts;
  wakeups move to the opt-in set, as the plan's default columns have it.
- Each lane's menu shows its facts and sources in the inspector: chip,
  core tiers, memory, GPUs, storage devices and volumes, interfaces,
  adapter and battery, sensors and fans, and where each reading comes from.
- `coreo top` ranks the busiest apps, live or once as JSON, and
  `coreo holders` says which of your processes hold a port or a file.
- Your own alert rules in Settings: a reading above or below a threshold
  for a while raises it, a second threshold clears it, and it can notify
  and run a Shortcut like the shipped rules.
- The Startup tab opens Login Items & Extensions in System Settings, and each item
  reveals its property list in Finder or copies its label.
- The process pane groups as a parent-child tree or by user, besides by
  app and flat; filters and app scope keep the parents of each match.
- The CPU lane shows each core tier's activity as a strip under the
  graph.
- Sampling slows to half rate while Low Power Mode is on, and the window
  says so.
- The Disk lane shows each mounted volume's used share and free space;
  `coreo volumes --json` reports the same.
- Settings > Processes shows per-process CPU as one core = 100 %
  (`top`-style) instead of a share of the whole machine; `cpu:` filters
  follow the choice.
- Each lane's menu moves, resizes or hides it; Settings > Lanes brings
  hidden lanes back and restores the default order.
- The CPU lane stacks user time under system time, and its header
  names both.
- The process table and inspector show GPU time (ms/s) for every
  process and estimated CPU power from the kernel's energy model;
  both sum per app and sort the table.
- Save Recording… keeps a selected range as a `.coreotrace` file that
  opens back in Coreography (Command-O, Finder or the Dock) for replay,
  range reports and comparison; redacted by default.
- The inspector shows the selected process's thread count and its CPU
  and footprint since it was selected.
- Settings > Menu bar shows up to three readings (CPU, memory, GPU,
  download, upload, temperature), each a value, a one-minute graph or
  both.
- Command-drag a second range to compare it with the selection: CPU
  and memory, and the apps that changed most. With a selection, sorting
  by CPU ranks apps by their use inside it.
- The HUD has four levels of detail (Control-Command-J cycles them),
  corner presets, dragging with a remembered position per display,
  opacity, text size, an optional dark backing and click-through.
- Pause Recording (toolbar, menu bar extra, palette) stops sampling and
  leaves a labelled gap; Command-0 returns to now; M drops a named marker
  shown on every lane.
- MCP access through the running app: off by default, one approval per
  client app (identified by its signature, not by the name it sends),
  revocable in Settings, with session and call limits. `coreo mcp --stdio`
  now bridges to the app; `--standalone` keeps in-process sampling.
- Network bytes per app in the ledger, stored history, range reports
  ("Top network"), daily totals, `get_top_processes` and `coreo diagnose`.
  A range that read network in only some intervals marks its totals as
  lower bounds.
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
- Apple Silicon CPU, GPU and ANE power from IOReport's energy model,
  and each CPU tier's activity and frequency, in the CPU and Power
  lanes, the HUD, diagnostics and `coreo silicon` (which also reports
  DRAM power). All are
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
  (Control-Command-H or the menu bar extra).
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
- `port:443` in the process filter finds processes with a socket on that
  local or remote port.
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
