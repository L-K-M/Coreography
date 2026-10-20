# Implementation ledger

Track actual delivery against the [product plan](plan.md). A stage is
complete only after its relevant checks and review pass and its PR merges.

## Current slice: review fixes

The native foundation merged in [PR #5](https://github.com/L-K-M/Coreography/pull/5)
at `aee9494` after two GLM rounds and passing CI. Process monitoring merged
in [PR #6](https://github.com/L-K-M/Coreography/pull/6) at `65d2377`, also
after two GLM rounds and passing CI. The network slice in
[PR #7](https://github.com/L-K-M/Coreography/pull/7) merged at `9ae6ca3`;
storage-driver rates and a fourth lane merged in
[PR #8](https://github.com/L-K-M/Coreography/pull/8) at `dc3d6bd`.
Later slices, each merged after CI and review:
memory composition,
swap and pressure in [PR #9](https://github.com/L-K-M/Coreography/pull/9);
app grouping in [PR #10](https://github.com/L-K-M/Coreography/pull/10);
GPU and thermal-pressure lanes in [PR #11](https://github.com/L-K-M/Coreography/pull/11);
the power lane in [PR #12](https://github.com/L-K-M/Coreography/pull/12);
the shared cursor in [PR #13](https://github.com/L-K-M/Coreography/pull/13);
SMC sensors in [PR #14](https://github.com/L-K-M/Coreography/pull/14);
time ranges in [PR #15](https://github.com/L-K-M/Coreography/pull/15);
the self-cost readout in [PR #16](https://github.com/L-K-M/Coreography/pull/16);
range selection in [PR #17](https://github.com/L-K-M/Coreography/pull/17);
range export in [PR #18](https://github.com/L-K-M/Coreography/pull/18);
shared continuity in [PR #19](https://github.com/L-K-M/Coreography/pull/19);
process actions in [PR #20](https://github.com/L-K-M/Coreography/pull/20);
app scope in [PR #21](https://github.com/L-K-M/Coreography/pull/21);
the menu bar extra in [PR #22](https://github.com/L-K-M/Coreography/pull/22);
the diagnostic contract in [PR #23](https://github.com/L-K-M/Coreography/pull/23);
MCP over stdio in [PR #24](https://github.com/L-K-M/Coreography/pull/24);
Ask Coreography in [PR #25](https://github.com/L-K-M/Coreography/pull/25);
alerts in [PR #26](https://github.com/L-K-M/Coreography/pull/26);
process change highlighting in [PR #27](https://github.com/L-K-M/Coreography/pull/27);
the filter grammar in [PR #28](https://github.com/L-K-M/Coreography/pull/28).
Process role notes and current assertion facts are shared with
diagnostic clients in [PR #52](https://github.com/L-K-M/Coreography/pull/52).
Maintenance states follow in [PR #53](https://github.com/L-K-M/Coreography/pull/53)
and automation in [PR #54](https://github.com/L-K-M/Coreography/pull/54),
the command palette in [PR #55](https://github.com/L-K-M/Coreography/pull/55).
IOReport power and frequency (M2, first rung) follow in
[PR #56](https://github.com/L-K-M/Coreography/pull/56), and bottleneck
hints in [PR #57](https://github.com/L-K-M/Coreography/pull/57).
The Month tier follows in [PR #58](https://github.com/L-K-M/Coreography/pull/58).
Per-process network (S3) follows in [PR #59](https://github.com/L-K-M/Coreography/pull/59).
The Dock icon follows in [PR #60](https://github.com/L-K-M/Coreography/pull/60).
Alert actions follow in [PR #61](https://github.com/L-K-M/Coreography/pull/61).
Network in the ledger follows in [PR #62](https://github.com/L-K-M/Coreography/pull/62).
MCP access through the app follows in [PR #64](https://github.com/L-K-M/Coreography/pull/64).
Time controls follow in [PR #65](https://github.com/L-K-M/Coreography/pull/65).
HUD levels follow in [PR #66](https://github.com/L-K-M/Coreography/pull/66).
Range comparison, menu bar items, inspector history and recordings follow
in PRs [#68](https://github.com/L-K-M/Coreography/pull/68) to
[#71](https://github.com/L-K-M/Coreography/pull/71); GPU time and CPU power,
the CPU split, lane layout, history fixes, the CPU scale, volume capacity,
the Low Power Mode cadence and the core-tier band in
[#72](https://github.com/L-K-M/Coreography/pull/72) to
[#79](https://github.com/L-K-M/Coreography/pull/79). This slice fixes what
the reviews of the merged slices found, in
[#80](https://github.com/L-K-M/Coreography/pull/80) and
[#81](https://github.com/L-K-M/Coreography/pull/81).

Implemented:

- Recordings (plan: a frozen copy of a range as a portable
  `.coreotrace` package): Save Recording… in the range panel writes the
  selection's frames, its per-app ledger intervals and its markers as
  versioned JSON (`ch.lkmc.coreography.trace`, conforming to JSON; the
  schema is documented in `Recording.swift`), redacted unless names are
  included: apps become numbered placeholders in CPU order, the same
  placeholder for the same app throughout, and the person's marker names
  become "Marker". Command-O, Finder or the Dock opens one into the held
  display with its own markers and range reports, without live process
  detail mixed in; Return to live goes back. Files over 256 MB, newer
  schemas, unreadable files and backwards ranges are refused with the
  reason shown. Only the live hour can be recorded so far.

- Inspector history and threads: the selected process's CPU,
  footprint, disk and network readings are kept from each live sample
  since it was selected (an hour at most; a new selection starts over;
  interrupted samples split segments), and the inspector draws CPU and
  footprint. Its thread count comes from `PROC_PIDTASKINFO` inside the
  same identity bracket as every other read; another user's process
  says the helper is needed.

- Menu bar items (plan: up to three, each a value, a sparkline or
  both): CPU, memory, GPU, download, upload or the hottest temperature,
  one per reading, saved; the default stays CPU as plain text. Richer
  layouts render as one template image, so the menu bar tints them, with
  the values as its accessibility label. Sparklines show the last minute
  on a fixed scale for shares and memory and their own range for rates
  and temperatures, with gaps kept. Held displays hold the values too.

- Range comparison (plan P7): with a range selected, Command-drag
  across any lane selects a second range, shaded orange on every lane.
  The range panel compares CPU mean and memory peak and lists the apps
  whose average cores changed most (at least a hundredth of a core),
  as rates over each range's covered time, so ranges of different
  lengths compare fairly; lower bounds are marked. A new plain drag
  replaces the selection and drops the comparison. With a selection,
  sorting the grouped table by CPU ranks apps by CPU-seconds inside it,
  and the table says so; the flat table keeps live order, since the
  ledger counts apps, not single processes.

- HUD levels (plan P16): one value (frame rate when available, else
  CPU), one line (CPU, GPU, power, temperature), a block (adding the top
  core tier, GPU clock, thermal pressure and the bottleneck hint) or
  everything (every core tier, memory pressure, swap, network, battery
  time at this draw and fans). The frame-rate slot is left out rather
  than drawn empty until macOS 27's source is wired (S4). Settings > HUD
  sets the level, corner, opacity, text size, a dark backing for bright
  scenes and click-through; with click-through off the panel can be
  dragged and remembers its place per display, and choosing a corner
  forgets dragged places. Control-Command-J cycles the level (Option-Command-H
  is macOS's Hide Others, so the HUD uses Control).

- Pan and zoom: two-finger sideways scrolling over any lane pans the
  window back (detaching from live, as scrubbing does) and forward, never
  past the oldest data held or the newest; pinching steps through the
  range pills, apart for closer and together for wider. Short ranges pan
  through the live hour; longer ranges pan only within the stored part
  already loaded, so loading stored history for a window further back
  remains. Return to Now and Return to live end the pan.
- Time controls: Pause Recording (toolbar, menu bar extra and palette)
  stops sampling, so every series and the store keep a gap, marked
  "Recording paused" and "Recording resumed"; reopening the window does
  not resume it, and the status line and menu bar title say so. Hold
  still only freezes the display. Command-0 returns to the live edge,
  ending hold and clearing the cursor but keeping the range and
  selection. M (or the palette) drops a named marker, up to 120
  characters, a blank name becoming the time; the person's markers
  draw solid in the accent colour with their name, the others stay
  dashed and unlabelled. Markers last for the session. Annotate in the
  range panel names the selected range: the name marks its start and
  "End of" the name its end.

- MCP access through the app: off by default (Settings > MCP access).
  When on, the app listens on a Unix socket in a 0700 Application
  Support directory, the socket file 0600. A connection is checked with
  the kernel's peer credentials: another user's process is refused
  before anything else. The client is identified from the connecting
  process (an app that speaks the socket itself) or, for Coreography's
  own CLI, by walking up to the first ancestor inside an app bundle,
  whose outermost bundle's signature names it (team and identifier,
  Apple's identifier, or for unsigned code its location); without an app
  ancestor, the top of its tree. Names a client sends are never used.
  A lock beside the socket keeps a second copy of the app from taking
  the endpoint over, and a file left by a crash is replaced.
  An unknown client waits for the person's answer in the window (120 s,
  one request shown at a time); approval is saved per identity, so the
  same app does not ask again, and Settings lists approved clients with
  their last use, live sessions and Revoke. Each session gets its own
  MCP server over the app's shared sampler and store, at most four
  sessions and 20 tool calls a second across them (10 per session). The
  grant is checked when a call is dispatched and again before its result
  goes out; revoking closes the client's sessions and disabling closes
  them all and removes the socket. `coreo mcp --stdio` only pipes stdio
  to the app and fails with the reason when the app is not running, the
  switch is off or the client was refused; `--standalone` keeps sampling
  in its own process, without history.
  What approval is and is not: a record of consent per client, not a
  security boundary against your own account. Any program you run can
  read the same process data through `--standalone` or the system's own
  interfaces. Approval binds to the nearest app, so approving a terminal
  or editor covers every program started from it (the prompt says so),
  and a team-signed grant covers what that team ships under one
  identifier. The process tree is read after the connection arrives, so
  a PID reused in between could name the wrong client.

- Scoped network: with an app shown in the lanes, the network lane
  names its TCP and UDP in plus out per second from the ledger, across
  every interface, live and from stored intervals; an interval that did
  not read network breaks the series rather than reading zero.
- Scoped memory and GPU: the memory lane names the app's summed process
  footprints and the GPU lane its GPU time in ms/s, each with the app's
  rank among apps with a readable, positive value, from the displayed
  process sample. Neither is additive the way CPU is (shared pages count
  per process; ms/s is not busy %), so the lines say so, and neither has
  a series yet, as the ledger keeps neither per app.
- Network in the ledger: each interval integrates every app's TCP and
  UDP rates (in plus out) from the traffic sample of the same moment
  and records whether network was read; a process's first interval with
  traffic has no rate yet and adds nothing. Range totals give network
  bytes only when some interval in the range read network, so a range
  without coverage says unknown rather than zero. Stored intervals,
  entries and the Month tier's daily totals keep the figures; an older
  store gains the columns in place on open, its earlier rows reading as
  not covering network. The range panel lists the top network apps,
  `get_top_processes` and `coreo diagnose` rank by network (every user's
  processes, since NetworkStatistics sees them all), and `coreo apps`
  and `--days` include it. Exports and session reports keep it under
  redaction.

- Alert actions: the fourth shipped rule, startup disk under 10% free
  (public URL resource values, read once a minute off the sampling path;
  raises at once, clears after a minute above, tints the Disk lane and
  notifies). Settings > Alerts picks one of the person's Shortcuts per
  rule (listed by `/usr/bin/shortcuts list`), saved. A raised rule runs
  its Shortcut through `/usr/bin/shortcuts run` with the name as one
  argument (no shell), a 60 s limit and an output cap, never two runs of
  one rule at once and at most once per 15 minutes per rule, so a
  flapping rule cannot loop a Shortcut. A run marks the timeline; a
  failure names the rule, the Shortcut and why. Names over 256
  characters or with control characters are refused.

- Dock icon (plan: optional live CPU or memory graph, as Activity
  Monitor offers): Settings > Dock picks the app icon (default), a CPU
  graph or a memory graph, saved. The graph draws the last minute of
  live samples on a fixed scale (the whole machine, or physical memory)
  with gaps kept, even while the window is held, and redraws once per
  sample only while a graph is chosen.

- Per-process network: the private NetworkStatistics framework
  (owner-approved; what nettop uses), loaded at run time, with one
  manager for the app's life on its own queue (creating one floods it
  with every open socket). Each process sample queries descriptions and
  counts, with a 2 s limit. Per-connection counters fold into totals
  per unique process ID, which a reused PID never shares; a closed
  connection's bytes move to a retired total, so a process's total never
  drops as connections churn, and retired totals of a process with no
  open socket leave after being reported once. Connections that close
  before naming their process, and the kernel's, are unattributed rather
  than guessed, and the process pane's summary shows that rate. The same
  line shows the CPU not attributed to a readable process: the host CPU
  averaged over the process interval less the readable processes' CPU,
  never below zero, and nothing when a host sample in the interval is
  unreadable or the process sample follows an interruption. Disk has no
  remainder: per-process I/O counts bytes the file cache may never send
  to a device. Rates are deltas over the real interval. Rows join by PID
  and name (the kernel's short name prefixes the full one), so a reused
  PID borrows nothing; a process with no open socket reads a measured
  zero. Groups total their members with the usual lower-bound rule. The
  process table gains a Network in/out column and sort, the inspector a
  rate, the palette a sort entry, and `coreo traffic --once --json`
  prints two seconds. Native CI streams loopback TCP from one process
  and requires its PID with measured bytes both ways. The per-app ledger,
  history and diagnostic tools do not carry network yet.

- Month tier (plan: 1 min for 30 days, per-app daily totals): every
  write also folds readings into 1-minute buckets keeping minimum,
  maximum, sum and count, and each ledger interval into its app's total
  for the local day it ends in (an interval spanning midnight counts
  for the later day). A replaced interval takes its old figures out of
  its day; an app left with nothing loses its row. Names stay while
  either their ledger intervals or their days are kept, then leave with
  the hourly sweep. Daily totals hold CPU-seconds and disk bytes; energy
  and network join when per-app sources for them exist. Presets keep
  7, 30 or 60 days; deletion, the size cap and its oldest-tenth pruning
  cover both new tables. The window gains 7 d (Day tier) and 30 d
  (Month tier) ranges, reloading only when a new chart bucket fills
  (every two hours for 30 d). `coreo apps --json --days N` prints
  per-app totals per day.

- Bottleneck hints (plan: PresentMon and RTSS style) over the last
  5 s of displayed data: "Looks GPU-bound" when the busiest GPU averages
  at least 90% while the top core tier is at most 50% active; "Looks
  CPU-bound" when the top tier is at least 90% active within 5% of its
  table's top frequency with the GPU at most 70% busy; "Possibly
  throttling" under moderate or higher thermal pressure when the top
  tier, at least half active, ran 10% slower than in the 5 s before.
  Each names the readings that tripped it; no tier table, no CPU-bound
  hint. They appear under the CPU lane's tiers and in the HUD. Frame
  rate joins them with performance mode (S4).

- Apple Silicon power and frequency: the private IOReport library
  (owner-approved), loaded at run time from the shared cache, subscribed
  to the Energy Model, CPU Core Performance States and GPU Performance
  States channels and sampled every second as deltas over the real
  elapsed interval. CPU energy is the sum of `…CPU Energy` channels
  (cluster and SRAM subtotals would double count), GPU `GPU Energy`,
  ANE `ANE…` and DRAM `DRAM…`, in mJ, µJ or nJ. Each core tier is named
  as IOReport names it (E, M or P): its cores' mean active residency and
  the residency-weighted frequency from the power manager's DVFS table,
  M1-M4 keys first and `acc-clusters` otherwise, scaled from hertz or
  kilohertz by which gives a plausible top frequency. A table that does
  not fit the reported states gives no frequency; an idle tier is a gap,
  not its lowest frequency. Everything is estimated with its method. A
  virtual machine is unsupported, a missing channel unavailable, and a
  CPU counter that stays still for five busy intervals is unavailable as
  frozen rather than read as zero. The CPU lane shows tiers, the Power
  lane block watts, the HUD the top tier and GPU clock; diagnostics add
  them to the summary and data sources; `coreo silicon --once --json`
  prints one interval. The CLPC and PMP fallback rungs, per-cluster
  history and S1 validation against `powermetrics` remain.

- Command palette (Command-Shift-P): every window action by name:
  inspector, hold, recording, HUD, Settings, each range, pane, grouping
  and sort, filter presets and saved filters, clearing the filter, scope
  and selection, sensor reset, startup refresh, and the selected
  process's actions, sample and copy. Typed words must all match a
  title, ranked by title prefix, word prefix, substring and then letters
  in order. Unavailable entries stay listed with their reason. Process
  entries name their target and confirm through the same dialog as the
  menus; the model never acts on them unconfirmed.

- Automation: a `coreography://` scheme registered in the app's
  Info.plist, received through the app delegate so links work with the
  window closed. Links only navigate: `show`, `filter?q=`, `find?port=`
  and `find?file=` (the filter's reverse lookups), `process?pid=`,
  `range?seconds=` (the window's ranges only), `record/start?name=`,
  `record/stop` and `hud/toggle`. Any app or page can open a link, so
  nothing quits, signals, exports or reads data back; unknown commands,
  out-of-range ports, control characters, texts over 256 characters and
  paths with spaces (which the filter cannot hold) are refused with the
  reason shown in the window. App Intents for Shortcuts and Spotlight:
  the system summary, top apps over the last minute, start and stop a
  recording, and who uses a port or has a file open, each from one
  on-demand read with what it could not cover (other users' processes,
  truncated or failed reads). An intent that launches the app waits up
  to 5 s for first readings. Native CI checks the scheme and that Xcode
  extracted every intent's metadata; running them in Shortcuts is an
  owner check.

- Maintenance states: `tmutil status` (whether a backup runs, its phase,
  progress and time left) and `mdutil -s /` (only whether the startup
  disk is indexed) run with fixed paths and arguments, a 5-second limit
  and a 64 KB cap, off the sampling path. Reads happen every five
  minutes and when `backupd` or a Spotlight process is selected with a
  status older than 10 s, never twice at once. The inspector shows the state under the
  role note with its read time. Only a reported running backup says it
  finishes on its own; Spotlight never does, because `mdutil` reports no
  progress. A cut-off, failed or unrecognised answer is unavailable, not
  idle. `get_system_summary` and `coreo diagnose` carry the state, and a
  running backup is a `backupRunning` signal. Photo analysis, iCloud sync
  and software updates have no status source and keep role notes only.

- Diagnostic context: the inspector and `get_process_details` share role
  notes qualified by name and a system executable path. Missing paths and
  writable `/usr/local` paths get no note; PID 0 identifies `kernel_task`
  without a path. Quitting guidance names possible interruption, never
  guarantees safety. Signature/version matching remains pending.
- `get_sleep_history` and `coreo sleep` include up to 200 current
  sleep-preventing assertions, their read time, omitted count and explicit
  unavailable reasons. Names that may contain private paths or document
  titles are withheld. Process names require observations within 2.5 s;
  held diagnostic snapshots retain the held assertion sample.
- Swift 6 package boundaries: drivers, engine, application services and CLI.
- Public Mach CPU ticks and VM counters, with explicit source failures.
- Whole-machine CPU share, derived used-memory bytes, bounded sample
  history, real-interval rates and nonnumeric collecting/gap states.
- One native window with CPU/memory lanes, numeric readings, chart
  accessibility descriptors and display hold independent of collection.
- Xcode project, embedded CLI, shared build/release adapters, verified
  universal packaging and CI development artifacts.
- Bounded libproc enumeration with PID/start-time identity checks before
  and after usage, whole-machine CPU share, physical footprint and disk
  read/write rates for readable processes. Permission failures remain
  explicit, and all identified processes are retained in each snapshot.
- A collapsed process table with name/PID/UID filtering and CPU, memory,
  disk and name sorting. The same dashboard scheduler polls processes
  every two seconds. Display hold includes the process table.
- `coreo processes --once --json` captures a real two-sample interval.
- Full-width public interface MIB byte counters, primary IPv4/IPv6 route
  selection, explicit interface scope, mirrored receive/send graphs,
  a chart accessibility descriptor and a numeric table. Network samples
  share the dashboard loop and display hold; source changes split lines.
- `coreo network --once --json` captures per-interface rates and coverage.
- Public IOKit storage-driver byte counters, stable registry identities,
  per-device rates and coverage, explicit device scope, and disk numeric
  history. Automatic selection requires a single device and complete
  inventory. Physical and virtual driver counters are kept separate.
- `coreo disks --once --json` captures available storage rates and failures.
- Disk and network share a mirrored chart and accessibility renderer.
  Native scanning actors share an executor implementation while each owns
  a serial queue and retains its task's cancellation context.
- Memory composition from the same `HOST_VM_INFO64` read: app, wired,
  compressed and cached bytes, compression ratio, and page-in, swap-in
  and swap-out byte rates over the real interval. Swap use comes from
  `vm.swapusage`; pressure from `kern.memorystatus_vm_pressure_level`.
- App grouping: each process carries its `proc_pidpath` executable and
  the PID macOS holds responsible for it. Helpers fold under a live
  responsible app that started no later, otherwise under their
  outermost `.app` bundle. Group CPU and disk totals are measured only
  when every member is readable; otherwise they are labelled lower
  bounds. Footprint sums are always estimates. A flat view remains, a
  tree nests each process under its parent (a parent younger than its
  child is a reused PID, so the child becomes a root; a parent loop
  lists each process once) with its own readings, and a by-user view
  totals each UID like an app, named by its account (looked up off the
  main actor with `getpwuid_r` and kept; a UID without an account
  keeps its number, and a lookup the user database could not answer is
  tried again on a later refresh). A filter or app
  scope in the tree keeps the parents leading to each match. A row
  running from an app bundle shows the outermost bundle's icon, read
  once per app; others keep a blank space so names align. The
  table's columns can be shown, hidden and reordered from the header
  and the choice is kept; CPU time (user plus system over each
  process's life, summed for an app) and start time are opt-in columns
  and sorts, and wakeups join them as the plan's default set has it.
  Threads are an opt-in column and sort too, read with each sample's
  task info; another user's count is restricted, never zero, and the
  header totals the counts it read ("at least" when some were not).
  Architecture is opt-in as well: Apple, Intel, or Intel under Rosetta
  from the process's `P_TRANSLATED` flag, read once per process; an app
  lists each kind its members run, and `#rosetta` filters to translated
  processes. An opt-in Signed by column names Apple, the developer team
  or Unsigned; signatures are checked off the main actor once per
  program, four at a time, starting only while the column shows, and an
  app lists each signer.
  QoS, instructions and ports columns remain.
- The memory lane stacks the composition under the physical-memory line,
  draws a pressure band above it, and has a ten-column numeric table and
  per-layer chart accessibility. `coreo snapshot` exports the same detail.
- A GPU lane from each IOAccelerator's published `PerformanceStatistics`:
  busy, renderer and tiler percentages and memory in use, one line per GPU,
  with a numeric table and `coreo gpu --once --json`.
- A power lane: battery charge with an external-power band, battery
  charge/discharge watts from the gas gauge, time estimate, health, cycles
  and adapter rating. System draw is shown only on battery, where the
  battery's discharge supplies the whole Mac; `coreo power --once --json`.
- One shared cursor: hovering any lane draws a hairline through all seven
  lanes, and every header shows the sample nearest that time, or nothing
  when no sample lies within 1.5 s. The toolbar names the cursor time.
- Top contributors: each process sample records the three leading apps
  for CPU, memory footprint and disk I/O (own-user processes grouped by
  app), TCP and UDP traffic in plus out (from the traffic sample of the
  same moment; a sample without one names no one), GPU time (ms per
  second, not a busy share) and the CPU power the kernel's energy model
  gives each app (an estimate). Every lane but thermal shows them live
  or, under the cursor, from the process sample within 2.5 s ("Top at
  …"), never a distant one. Before the live samples, the stored ledger
  interval under the cursor names the CPU, disk and network leaders;
  memory, GPU and power say they were not kept, and a cursor between
  stored intervals names no one.
- AppleSMC sensors through a read-only C bridge: temperature keys are
  discovered once, then read each second. The thermal lane draws the
  hottest plausible sensor (10-130 °C) over pressure bands, names its key
  and community region, and splits the line when the hottest key changes.
  Fans show actual rpm. The power hero prefers an SMC system rail (`PSTR`,
  then desktop `PDTR`) over battery discharge; `coreo sensors --once --json`.
- One hour of in-memory history per monitor (3,600 one-second frames)
  and of contributor samples. A toolbar picker shows 1 min, 10 min or 1 h.
  Charts draw each bucket's minimum and maximum (360 buckets), so spikes
  survive and nothing is averaged; stacked memory layers decimate together
  on the stack total, and contiguous pressure or power spans merge.
- Self-cost: the window header shows Coreography's own CPU, converted
  from whole-machine share to percent of one core, and its footprint,
  beside the plan's 1% and 150 MB budgets. Over-budget readings say so.
  Wakeups are not measured yet; S2 still owns the published numbers.
- Range selection: dragging across any lane selects one range, shaded in
  all seven; Esc or the clear button removes it. A range panel reports CPU
  mean and peak, memory, GPU and temperature peaks, and the top apps by
  CPU-seconds and disk bytes, with the span the process samples cover.
- An in-memory per-app ledger for the live hour: each process interval
  records every active app's CPU-seconds and disk bytes (rate × the real
  interval), so tail apps count, idle apps cost nothing, interrupted
  samples are excluded, and unreadable members mark lower bounds. The
  persistent ledger and its write budget remain S7/M4.
- Range export from the range panel: JSON keeps every reading in range
  with availability, provenance and reasons, plus per-app ledger totals;
  CSV has one row per host sample with paired GPU, sensor and power values
  within 1.5 s. Missing readings are empty cells, never zero. Export
  redaction checks remain S8.
- Process actions: a process row's context menu offers Quit and Force
  Quit. A confirmation states the consequences (logout for loginwindow or
  WindowServer, child processes, no chance to save). Quit asks a regular
  app through AppKit and sends SIGTERM otherwise; Force Quit sends
  SIGKILL. Every send re-checks PID and start time immediately before
  acting, never targets a process group, and success drops a dashed
  marker in all lanes. Refusals name their reason.
- App scope: "Show … in lanes" on any process row scopes the window to
  that app. The CPU lane overlays the app's share from the ledger as a
  dashed second series, the disk header shows its read + write rate, the
  process pane filters to it, and a toolbar pill clears it. Idle intervals
  are zero; missing intervals stay gaps. Memory and GPU shares need
  per-app footprint and GPU-time series, which the ledger does not keep yet.
- Menu bar extra: the title shows whole-machine CPU; its window has mini
  CPU, memory and download lanes for the last minute, the top CPU app, a
  hold toggle and Open Coreography. It reads the window's model, so one
  sampler serves both. Sampling now starts at launch and continues while
  the window is closed; the 10-second record-only cadence for when nothing
  is visible remains with the full scheduler.
- The shared diagnostic contract (plan: one service for the window, CLI,
  MCP and Ask): a question freezes one `DiagnosticSnapshot`; tools return
  a system summary with units, evidence references and fact-only signals
  (CPU saturation, sustained memory pressure, swapping, heavy thermal
  pressure, sampling gaps), paged top apps by CPU-seconds or disk bytes
  with cursors bound to the snapshot, metric and range, bounded metric
  history with gaps as segments, process details without paths, and data
  sources. Ranges over an hour, oversized pages and foreign cursors fail
  explicitly; sleep history arrived with the sleep import below.
  `coreo diagnose --json [--seconds N]` samples 3-60 s and prints a report
  an assistant can use. MCP transport and the app bridge remain M5.
- `coreo top [--json] [--count N] [--sort KEY]` ranks apps and lone
  processes, grouped as the pane groups them, after a two-second
  baseline, and without `--json` redraws every two seconds.
  `coreo holders --json --port N` and `--file TEXT` answer which of your
  processes hold a port or an open file, with the same limitations the
  app's reverse lookup names. Native CI checks the memory order and that
  a listener holding a port and a file is found. `record` and `export`
  from the command line remain, since recordings belong to the app.
- `coreo mcp --stdio`: a read-only MCP server (JSON-RPC 2.0, protocol
  2025-06-18, also accepting 2025-03-26 and 2024-11-05) exposing the six
  contract tools with JSON schemas and read-only annotations. It runs the
  dashboard sampler in-process, retains the last eight snapshots so
  `snapshot_id` and cursors continue one question, refuses more than ten
  tool calls per second, and returns tool failures as `isError` results.
  Interim scope: the plan's bridge to the running app over authenticated
  IPC, per-client approval, revocation and shared budgets remain M5; this
  server trusts the local client that launched it, like any CLI.
- Ask Coreography: a collapsed panel takes a plain-language question and
  answers with Claude Opus 5.5 through the same six read-only tools as MCP,
  against one frozen snapshot, listing the tool calls it read. The
  Anthropic key is stored only in the login Keychain (this device, when
  unlocked) from Settings and sent only to the Messages API. Thinking is
  adaptive; refusals opt into Anthropic's server-side fallback
  (`fallbacks: "default"`). A refused, truncated or runaway turn never runs
  a partial tool call; invalid keys, rate limits and overload are named.
  Monitoring does not wait on the model, and nothing is sent until asked.
  Both clients now share one tool catalog. S9 still owns model evaluation
  on recorded fixtures and the on-device option.
- Alerts: the plan's shipped rules with durations and hysteresis
  (critical memory pressure for 30 s, heavy thermal pressure for 30 s,
  battery under 15% while discharging), evaluated on live data even while
  the display is held. A raised rule tints its lane, names itself and drops
  a marker; unknown readings pause the clocks rather than count. The
  memory, battery and startup-disk rules notify, through UserNotifications
  (so Focus applies), with a 15-minute cooldown and one banner per rule;
  Shortcut actions are described above. Settings > Your alert rules
  adds up to 20 of the person's own: a metric (CPU, memory used, GPU,
  hottest sensor, system power, battery, download, upload, disk read or
  write), above or below a threshold for a wait, clearing back past a
  second threshold for another wait, optionally notifying. They read what
  history records (the primary interface, a lone storage device and a
  lone GPU), ignore readings older than 10 s so a stopped sampler cannot
  hold them raised, and an edited rule starts cleared. Rules sharing a
  lane name themselves together in its tint.
- Process pane change highlighting: CPU, footprint and disk cells are
  shaded in their subsystem hue by share of the column's top row; a
  process first seen within 10 s (not present at launch) tints its name;
  processes gone within 30 s are listed with their app as ghosts. Exit
  status is not claimed, and samples across sleep are not read as exits.
- Process filter grammar: whitespace-separated terms that all must match:
  free text, `cpu:>10`, `mem:>1GB`, `disk:>5MB`, `pid:42`, `user:root|me|UID|name`
  and the tokens `#apps`, `#mine`, `#root`, `#third-party` and `#new`. An
  unreadable reading never satisfies a numeric predicate. Tokens awaiting
  data (`#listening`, `#not-responding`, `#preventing-sleep`) and
  unreadable terms are named under the field rather than dropped; saved
  filter chips and reverse lookup remain.
- On-disk history, first part: the app records 17 system series (CPU,
  memory composition and pressure, swap, thermal, GPU, battery, system
  power, hottest sensor, primary network, automatic disk) to the system
  SQLite in WAL mode, in a 0700 directory with a 0600 file excluded from
  backups. Readings keep their availability, so gaps replay as gaps.
  Writes batch into one transaction every 30 s; each batch also enforces
  the 6-hour time cap and a 256 MB size cap. Settings deletes history in
  one click; `coreo history --json METRIC` reads it, `coreo stats --json`
  gives every metric's minimum, nearest-rank median and 95th percentile,
  maximum and mean (none for pressure levels, which are ordinals) with
  the count of samples without a value, `coreo export` prints every
  sample as JSON or one CSV row each (gaps empty, metrics never paired
  by time), and the CLI never records samples. Rollups remain (S7, M4).
- The app ledger on disk: every two-second process interval, idle ones
  included, is written with the sample batches as per-app CPU-seconds,
  disk bytes and a lower-bound flag, under the same 6-hour and size
  caps. App names are interned and swept hourly once their intervals age
  out, and one-click deletion clears them. `coreo apps --json` totals the
  recorded apps over the last N minutes. The size cap now counts live
  pages only and, once exceeded, prunes the oldest tenths of samples and
  ledger intervals together down to 90% of it; it used to count freed
  pages and drop another tenth on every batch after the first overflow.
  A batch leaves the recorder before it is written, so readings arriving
  meanwhile are kept rather than cleared with it, and readings taken
  before a deletion are dropped even when they arrive after it.
- The 6 h range: lanes draw stored history behind the live hour. Each
  minute while that range is shown (not while the display is held), the
  model reads the store off the main actor and reduces every series once
  to bucket minimum and maximum, so redraws never touch the disk. CPU,
  memory composition and used, both pressure bands, battery, the hottest
  sensor and, on a single-GPU Mac, GPU utilization are extended; network
  and disk only for the primary interface and the automatic storage
  device, as recorded. Silences over 3 s and unreadable samples stay
  gaps, the recorder stores a gap where the primary interface, storage
  device, GPU or hottest sensor changes, and no line joins stored and
  live points. Deleting history clears the stored part at once. Without
  a store the toolbar says older history is unavailable. A range report
  reaching into stored history totals stored and live ledger intervals
  without counting one twice, and takes CPU mean and peaks from raw
  stored readings; a stored hottest peak has no sensor key. A scoped
  app's overlay extends into stored history. Export still covers live
  data only and says so; cursor readouts and contributors over the
  stored part, exporting it, and the 24 h range (the Day tier) remain.
- Sample: "Sample for 3 Seconds" in the process menu runs the
  allowlisted `/usr/bin/sample` (fixed path, validated pid and duration,
  runtime and output caps) after an identity check, and opens the report
  in the app to read or save. Spindump needs root and waits for the
  helper.
- HUD, first part: Control-Command-H or the menu bar extra shows a small
  readout of CPU, GPU, the hottest sensor and system power in the top
  right corner, above full-screen apps and on every Space. It never takes
  focus or clicks and reads the window's own model. Frame rate waits for
  the performance-mode spikes (S4, S6); whether the panel stays above
  every full-screen game is the S6 owner check.
- Sessions, first part: Command-R records a session at full
  resolution, kept apart from the live hour so long sessions lose
  nothing; stopping saves a report with minimum, mean, maximum and a
  95th percentile taken from every raw reading (never from rollups), and
  top apps from every ledger interval recorded. Sessions are private
  files beside history (0700 folder, 0600 files, excluded from backups)
  and the Sessions tab lists them. Two picked sessions overlay per
  shared metric, aligned at their starts and reduced to bucket extremes;
  a session exports as JSON (app names redacted unless included) or as
  CSV of every raw reading, and can be renamed.
- Reverse lookup by file: `file:~/Downloads` or `file:report.pdf` keeps
  the processes with an open file whose path contains it, from open
  files read through libproc only while the filter asks, inside the
  identity bracket; the inspector lists the selected process's open
  files. Other users' processes need the helper and are named.
- Wakeups: each process's package-idle and interrupt wakeups per second
  from the same `proc_pid_rusage` read as CPU and disk, summed per app,
  shown in the process table and the inspector, and checked against the
  self-cost budget of 5 a second beyond the sampling tick. Gaps and
  restricted processes stay unknown, never zero.
- Cluster sub-band: under the CPU graph, one row per core tier shaded
  by its IOReport activity per sample, aligned with the graph's time axis;
  samples without a reading leave holes, and a compact lane sheds it.
- Low Power Mode: every sampling cadence halves while it is on (2 s
  for the lanes, 4 s for processes), within each monitor's gap limit, and
  the window says so. The 10-second record-only cadence for when nothing
  is visible remains.
- Volume capacity: the Disk lane lists every visible mounted volume,
  startup first, with its used share and space available for important
  use (purgeable files count as available, as in Finder), read once a
  minute off the sampling path; red marks a volume over 90 % full.
  Volumes without a readable size are left out rather than shown empty.
  `coreo volumes --json` reports the same list.
- Per-process CPU scale: Settings > Processes switches the table, the
  inspector, the Startup tab and `cpu:` filters between whole-machine
  shares and one core = 100 % (`top`'s convention, above 100 % for
  multithreaded work). Lanes, reports, MCP and the CLI keep the
  whole-machine scale.
- Lane layout: each lane's menu moves it past its visible neighbours,
  sizes its graph (compact, regular, tall) or hides it; Settings > Lanes
  shows hidden lanes again and restores the default order. The last
  visible lane cannot be hidden, and a saved layout from another version
  keeps its known lanes in order, with new lanes after their default
  predecessor. Shedding header detail in compact lanes remains.
- CPU user under system: the kernel's share comes from the same Mach
  tick deltas as the busy total, so the lane stacks user (with nice)
  under system and the header names both. Stored history keeps only the
  total, so the split covers the live hour; recordings made before it
  decode without it.
- GPU time and CPU power per process: GPU milliseconds per second from
  the GPU user clients under each `IOAccelerator` (`IOUserClientCreator`
  names the PID, `AppUsage` sums `accumulatedGPUTime` per command queue),
  counted per client so a closed client never pulls its process back.
  It reads for every process, other users' included, and a process with
  no client reads as zero; it is labelled ms/s, not busy %. CPU power is
  the estimate from `ri_energy_nj` (`RUSAGE_INFO_V6`, which every
  supported macOS has; the app needs macOS 26); a process that ran
  with a zero counter has no energy model on that Mac and reads as
  unsupported. Both sum per app and sort the table.
- More process actions: Suspend and Resume, Send Signal (hang-up,
  interrupt), Lower Priority (nice 10), Reveal in Finder and Copy as
  text or JSON join Quit and Force Quit, in the process menu and the
  inspector. Signals and renice go through the same identity check as
  Quit and confirm with their consequences; suspending the window
  server, the login window or Coreography itself is refused, because
  nothing could resume it. Lower Priority only lowers: a process already
  at nice 10 or beyond keeps its own value. Hang-up and interrupt on the
  window server or login window warn that they log you out, as Quit does.
  Raising priority again needs an administrator and says so. Sample and
  spindump remain.
- Saved filters: the current process filter can be kept as a chip
  under the field (up to 12, newest first, no duplicates); a click
  applies it and its menu removes it. Chips are saved in preferences.
- Sleep assertions: live power assertions from one public IOKit call to
  powerd (`IOPMCopyAssertionsByProcess`), read with each process sample.
  The Power lane names who keeps the Mac or its display awake and for
  how long, the inspector lists the selected process's assertions, and
  `#preventing-sleep` filters to their holders. Released assertions are
  left out; past assertions are not reconstructed (plan). Assertions
  name a PID only, so they are matched to processes observed at the same
  moment.
- Settings: history retention presets (1 h detailed with 1 day
  summarised, the plan's 6 h with 7 days, or 12 h with 14 days), each
  with an estimated disk cost and the measured size beside it, all under
  the 256 MB cap; the choice is saved and applies with the next write.
  Ranges longer than the detailed retention read the Day tier. A Data
  sources section lists every reading's availability with its reason or
  provenance.
- The Day tier and the 24 h range: each batch is also folded into 10 s
  buckets keeping minimum, maximum, total and count, kept for 7 days
  under the same size cap and deletion. Buckets fill across batches by
  upsert, and readings without values are left out, so an empty bucket
  stays a gap. The 24 h range draws each bucket's minimum and maximum,
  so spikes survive, and range reports weigh bucket means by count, so
  means stay exact; percentiles are never taken from rollups. The app
  ledger stays in the Recent tier, so app totals over 24 h cover its
  six hours, which the report's coverage states. The Month tier follows below.
- Automatic markers: memory and thermal pressure transitions, power
  source changes and imported sleep, wake and dark-wake records mark
  every lane, lighter than the person's own actions and alerts, and a
  range report lists the markers inside it. They are rebuilt from the
  displayed data, so a held display keeps them; unknown samples neither
  start nor end a level. Apps starting and exiting are marked too ("Mail
  started", "Safari exited"), keyed by their outermost `.app` bundle so
  helpers coming and going change nothing; daemons and other processes
  outside a bundle would crowd the lanes and are left to the process
  pane. A start is its first observed sample and an exit its last, only
  between complete, continuous samples, for the live hour.
- Redacted exports: range exports number apps (`App 1`, `App 2`, in CPU
  order) unless names are asked for, and say which in `appNames`
  (schema version 2). Interfaces, storage drivers and sensor keys
  describe the Mac rather than the person and stay.
- Reverse lookup by port: `port:443` in the process filter keeps the
  processes with a socket on that local or remote port, from the same
  on-demand connection data as `#listening`. Lookup by file or path
  needs open-file enumeration and remains.
- Inspector, first part: selecting a process opens the right-hand
  inspector with identity (name, app, PID, user, start time, path), the
  parent chain up to launchd, code signature and team, its launchd job,
  a plain-language note and quit consequence for 25 well-known system
  processes, current CPU, footprint and disk rates, its arguments and
  its sockets, plus Quit and Force Quit with the same confirmations.
  Arguments are read through `KERN_PROCARGS2` inside the same identity
  bracket as every other read; the environment that follows them is
  never parsed. With nothing selected it shows the chip, model, macOS
  build, uptime, load averages and Coreography's own cost. Per-process
  history lanes, open files, assertions, threads and wakeups remain.
- CPU lane detail: Show Cores in the lane's menu, or a double-click on
  its title, adds a heat strip with one row per logical CPU, each core's
  busy ticks over its own ticks between samples (`host_processor_info`,
  `PROCESSOR_CPU_LOAD_INFO`), so it holds across cadences; a change in
  the core count or an interruption starts over, and a core without a
  reading leaves a hole. Rows follow CPU numbers: grouping them by
  cluster needs the CPU-to-cluster map, which remains, as do the other
  lanes' detail views. Native CI checks one measured 0-100 share per core.
- Lane inspector: a lane's menu shows its static facts (chip, model,
  logical CPUs and core tiers; physical memory; each GPU; storage devices
  and volume sizes; primary and observed interfaces; adapter rating,
  battery health and cycles; sensor and fan counts) and each reading's
  availability and source, from the displayed frames so a held window
  describes what it shows. Facts never read are left out, not guessed.
  SMART status remains (it needs the helper or an IOKit SMART client).
- Startup tab, first part: launch agents and daemons from the user,
  global and system folders, with launchd's own enabled state from
  `launchctl print-disabled` (no root needed; when it fails the state is
  marked unconfirmed rather than guessed from the plist) and whether the
  program is Apple-signed (basic validation only). Apple's items are
  hidden by default. Each row is joined to its running processes'
  current CPU and footprint and their apps' CPU-seconds over the last
  hour. Read on request, never polled. Login and background items need
  the helper and are named as missing. Coreography changes nothing:
  Open Login Items & Extensions uses `SMAppService`'s documented link to
  System Settings, and each item's menu reveals its property list or
  copies its label.
- Sensors tab: every plausible SMC temperature, each fan and the system
  power rail with current, minimum, maximum and mean since a reset,
  grouped by region (plan P15). Statistics accumulate on live samples
  while the tab is hidden and redraw only while it shows; a sensor
  missing from the newest sample keeps its statistics without a current
  value, and unreadable values never count as zero. Only the newest
  sample's full temperature list is kept, not an hour of it. Voltages
  and currents are not read yet.
- Connections, first part: a Processes | Connections switch under the
  lanes. The Connections tab lists each app's TCP and UDP sockets
  (listening first, then connected by peer) with state and endpoints,
  read through public libproc calls only for the exact process identity
  seen, and only while the tab shows or the filter uses `#listening`,
  which now works. Other users' processes are counted as needing the
  helper, not dropped. `coreo connections --once --json` prints the same
  data. Per-connection traffic, domain names and the helper remain.
- Sleep and wake history, first part: `pmset -g log` runs with a fixed
  path and arguments, a 20-second limit and an 8 MB tail cap, off the
  sampling path: once at launch and 10 s after each wake (an interrupted
  sample), never twice at once. Sleep, Wake and DarkWake records keep the
  logged reason, power source and charge; a period runs from a Sleep to
  the next full Wake, counts dark wakes and reports the battery change
  over sleep. A cap reached, a non-zero exit or a missing tool is named as
  partial coverage or unavailability. `get_sleep_history` (1-168 hours,
  at most 200 newest records) and `coreo sleep --json` read it; reasons
  are evidence, not proven causes. The bounded `log show` import, wake
  markers on the timeline and the battery-over-sleep view remain (S8).
- A thermal lane showing system thermal pressure as a band, from the public
  `com.apple.system.thermalpressurelevel` notify state. Temperatures, fans
  and the hottest-sensor line wait for the sensor provider.

The live buffers hold one hour per monitor. Per-volume disk accounting
remains outstanding.
IOReport fallback rungs (CLPC, PMP) and the privileged helper remain
outstanding. The store, MCP and model features above await stack delivery.

## Verification

| Check | Status |
| --- | --- |
| Swift tests | Storage slice: 75 passed on Linux; prior native process 49-test and network 60-test runs passed; latest native run pending |
| `coreo doctor` on Linux | Reports unsupported native sampling with no numeric Mac readings |
| Build-script regression tests | 30 passed locally and in CI; includes actual release-step rejection, fixture isolation and exact archive selection |
| Xcode/macOS compilation and live CPU/memory smoke | Passed [native network CI](https://github.com/L-K-M/Coreography/actions/runs/39104361427) at `e62fac1`; latest integration checks tracked on PR #7 |
| Universal app and CLI slices, code signature and archive | Passed the same native CI; ad-hoc signing only |
| Native chart rendering, VoiceOver and display-hold behavior | Owner reported the [PR #7 candidate](https://github.com/L-K-M/Coreography/actions/runs/39108879660/artifacts/12130410052) (CPU, memory, processes, network) looks fine on their Mac, 2026-10-18 |
| Native process collection, cancellation and CPU units | Passed [native review-fix CI](https://github.com/L-K-M/Coreography/actions/runs/39105964147) at `7df03ec`, including cancellation, saturation and `getrusage` cross-checks |
| Native network MIB, wide-counter mapping and three-lane UI | Passed at `e62fac1`, including native C fixtures, live CLI and both executable architectures; integrated candidate pending |
| Native IOKit storage counters and four-lane renderer | Passed [native CI](https://github.com/L-K-M/Coreography/actions/runs/39110306993) at `6434722`: 75 tests, 16 drivers, 32 measured rate fields, no inventory issues; owner checks pending |
| On-disk history store and recorder | History slice: 148 Swift tests pass on Linux against the real system SQLite (round trip with gaps, duplicates, retention, reopen, permissions, WAL, batching); native CI checks the CLI and file permissions |
| Cluster sub-band | 307 Swift tests pass on Linux (cells reaching the next sample, breaks not bridged, holes for missing readings, clamped shares); the strip compiles only in native CI and its look is an owner check |
| Low Power Mode cadence | 306 Swift tests pass on Linux (the cadence following the mode both ways, the interval doubling); reading the flag and the note compile only in native CI; behaviour with Low Power Mode on is an owner check |
| Volume capacity | 305 Swift tests pass on Linux (important-use space with a plain-space fallback, names, kinds, clamping, unknown sizes left out, ordering, the model's minute read); the native smoke requires one startup volume at `/` whose size agrees with `statvfs`; the bars compile only in native CI |
| Per-process CPU scale | 303 Swift tests pass on Linux (filter bounds in the chosen scale, the factor never zero, the saved choice); the column titles, cells and Settings picker compile only in native CI |
| History review fixes | 295 Swift tests pass on Linux against the system SQLite (retention deletes planned as key searches, a held write lock waited for, a newer store refused and left labelled, battery draw recorded without a sensors frame, buffered history written before quitting returns; each failed before its fix); the quit hand-off and the confirmation compile only in native CI |
| Lane layout | 290 Swift tests pass on Linux (moves past hidden lanes, the last visible lane kept, sizes, saved layouts with unknown, duplicate and missing lanes); the lane menus and Settings section compile only in native CI |
| CPU user and system | 286 Swift tests and 33 tooling tests pass on Linux (shares from one set of ticks, gaps breaking the area, old recordings decoding); the native snapshot gate requires a measured system share no larger than the total; the stacked area compiles only in native CI |
| GPU time and CPU power per process | 283 Swift tests and the Linux C contract pass (per-client deltas with closed, new and reset clients, incomplete walks, gaps and clock changes, creator and queue decoding, the energy estimate and its missing counter, app totals and sorting); the native smoke requires a measured zero GPU time for `coreo` and an estimated or unsupported power; the registry walk and columns compile only in native CI |
| Recordings | 274 Swift tests pass on Linux (round trip, consistent redaction of apps and marker names, newer, unreadable and backwards files refused, opening into the held display and returning to live); document registration and the open and save panels compile only in native CI |
| Inspector history and threads | 271 Swift tests and the Linux C contract pass (history only after selection, cleared on change, threads through the model); the native contract counts this process's threads and refuses a wrong start time |
| Menu bar items | 270 Swift tests pass on Linux (one per reading, three at most, never empty, saved); the label image compiles only in native CI and its look is an owner check |
| Range comparison | 269 Swift tests pass on Linux (rate-based changes across ranges of different lengths, the noise floor, no coverage, no shared readings); Command-drag and the bands compile only in native CI and are an owner check |
| HUD levels | 267 Swift tests pass on Linux (items per level, no empty frame-rate slot, the cycle wrapping, saved and clamped settings); the panel compiles only in native CI; staying above full-screen games remains an owner check (S6) |
| Time controls | 265 Swift tests pass on Linux (no sampling while paused even when started, pause markers, resume, return to now keeping the selection, marker names); the toolbar, menu and alert compile only in native CI |
| MCP access through the app | 263 Swift tests pass on Linux with real Unix sockets (off by default, 0700 directory and 0600 socket, approval once per identity, refusal and denial, another user's peer refused first, revocation closing sessions, disabling removing the socket, the bridge client's refusals and a piped session, identity from signed, unsigned and app-less trees); native CI checks the bridge fails without the app; approving a real assistant is an owner check |
| Network in the ledger | 259 Swift tests pass on Linux against the system SQLite (a schema-4 store migrated in place with its rows kept, network per interval and per day, unknown without coverage, the diagnostic ranking and its unavailable case) |
| Alert actions | 257 Swift tests pass on Linux (the disk rule's thresholds and unknown readings, saved Shortcuts per rule, name validation, one run per raise through the model with its failure named, the listed Shortcuts); running real Shortcuts is an owner check |
| Dock icon | 254 Swift tests pass on Linux (saved choice, live points while the window is held, fixed scale); the tile view compiles only in native CI and its look is an owner check |
| Per-process network | 252 Swift tests pass on Linux (totals that survive closed connections, retired processes leaving once reported, unattributed bytes, rates per unique process, reused PIDs, PID and name joins, idle zero, unavailable reasons, group sums and sort); the NetworkStatistics session compiles and runs only in native CI |
| Month tier | 245 Swift tests pass on Linux against the system SQLite (minute extremes and means, the tier outliving the Day tier and ageing out, per-day totals across midnight, replacement without double counting, names kept with their days then swept); native CI checks `coreo apps --days` |
| Bottleneck hints | 242 Swift tests pass on Linux (each hint's thresholds and evidence, no CPU-bound hint without a top frequency, no throttling without thermal pressure, no data no hints); the lane and HUD lines compile only in native CI |
| Apple Silicon power and frequency | 238 Swift tests pass on Linux (block sums without subtotals, units, residency weighting, idle and unfitting tables, hertz or kilohertz tables, legacy and `acc-clusters` assignment, baseline, frozen counters, virtual machines); the IOReport driver compiles only in native CI, whose virtual runner must report unsupported with its reason. Accuracy against `powermetrics` is an owner check (S1) |
| Command palette | 229 Swift tests pass on Linux (ranking, unavailable reasons, target names, actions applied through the model, unconfirmed process actions ignored); the palette view compiles only in native CI; keyboard use awaits its owner check |
| Automation | 227 Swift tests pass on Linux (every link form, refusals with reasons, holder lookups with their limits, commands applied through the model); intents and link delivery compile only in native CI, which checks the scheme and intent metadata |
| Maintenance states | 222 Swift tests pass on Linux (running, unknown-progress, idle and unrecognised `tmutil` answers; `mdutil` states; cut-off and failed tools unavailable; path-qualified processes only; no end promised for Spotlight; the summary's state and signal; one read per refresh window through the model). Native CI compares `coreo diagnose` with independent `tmutil` and `mdutil` reads; the inspector's display is an owner check |
| Diagnostic context | 212 Swift tests pass on Linux; privacy and unsafe-quit regressions failed before the fix. One completed Devin review found the missing kernel note; its PID-0 regression also failed before the fix. Native compilation and current stack review remain pending |
| Sample | Sample slice: 208 Swift tests pass on Linux (report and failure states through the model); the native tool run and the sheet are owner checks |
| HUD | HUD slice: App-only, no Swift tests; the panel and its project registration compile only in native CI; staying above full-screen games is an owner check (S6) |
| Sessions | Session slices: 207 Swift tests pass on Linux (raw-reading summaries with gaps skipped, nearest-rank 95th percentile, top apps, private files newest first, recording and renaming through the model, comparisons of shared metrics aligned at start, redacted JSON and raw CSV exports); UI compile pending |
| File reverse lookup | File slice: 203 Swift tests and the Linux C contract pass (paths by process, restricted, exited and truncated processes counted, home expansion, name matching, no match without data); the native contract finds this process's own temporary file and refuses a wrong start time; UI compile pending |
| Wakeups | Wakeup slice: 201 Swift tests and the Linux C contract pass (rates over each process's own interval, collecting first, the budget beyond sampling); the native smoke requires a measured own wakeup rate; UI compile pending |
| More process actions | Actions slice: 201 Swift tests and the Linux C contract pass (identity-checked signals and renice, refusals, administrator message, copy text and JSON); the native contract stops, continues and renices a forked child and refuses a wrong start time; UI compile pending |
| Saved filter chips | Filter-chip slice: 200 Swift tests pass on Linux (order, duplicates, blanks, limit, model save and remove); UI compile pending |
| Sleep assertions | Assertion slice: 198 Swift tests pass on Linux (released and untyped assertions dropped, ages kept, effects classified, the filter token waiting for data); native powerd reads and the UI compile are pending |
| Settings: retention and data sources | Settings slice: 195 Swift tests pass on Linux (plans applied from the next write, measured size, presets ordered and under the cap, saved choice, tier choice by retention); Settings UI compile pending |
| Day tier and 24 h range | Day-tier slice: 192 Swift tests pass on Linux against the system SQLite (bucket extremes and means, merging across batches, gaps left out, 7-day retention past the 6-hour one, deletion; spikes and exact means through the 24 h load) |
| Automatic markers | Marker slice: 190 Swift tests pass on Linux (transitions skipping unknown samples, sleep events since the displayed start, stable identity across rebuilds); UI compile pending |
| Redacted exports | Export slice: 187 Swift tests pass on Linux (figures kept, names absent from the JSON, naming recorded) |
| Port reverse lookup | Port slice: 186 Swift tests pass on Linux (local and remote ports, unreadable and zero ports named, no match without connection data) |
| Inspector | Inspector slice: 186 Swift tests and the Linux C contract pass (argument blocks without the environment, malformed blocks, missing-argument reasons, signer mapping, parent chains ending at launchd or an unobserved parent, launchd labels, selection opening the inspector); the native contract reads this process's own argument block and refuses a wrong start time; UI compile pending |
| Startup tab | Startup slice: 182 Swift tests pass on Linux (plist parsing with unreadable and unlabelled files, override spellings, overrides winning over plists, unconfirmed state, Apple hiding, process and ledger join); native signature checks, `launchctl` output and the UI compile are pending |
| Sensors tab | Sensors slice: 178 Swift tests pass on Linux (full temperature list with faults excluded, statistics since reset, absent sensors, unreadable values); native readings and the UI compile are pending |
| Connections and `#listening` | Connections slice: 177 Swift tests and the Linux C contract pass (identity-checked reads, restricted, exited, failed and truncated processes counted, UDP and TCP listening, `inet_ntop` text, on-demand reads, the filter token); the native contract opens TCP and UDP sockets and checks ports, state, a wrong start time and truncation, and native CI finds a real listener through `coreo connections`; UI compile pending |
| Reports and scope over stored history | Stored-range slice: 172 Swift tests pass on Linux (stored and live ledger totals without double counting, true means from raw readings, keyless stored peaks, scoped overlay and report through the model, export clamped to live data); native compile pending |
| App ledger on disk | Ledger slice: 168 Swift tests pass on Linux against the system SQLite (round trip with idle intervals, whole-interval replacement, retention with name sweep, deletion, rebuilt totals equal live ones; size-cap, ledger-only cap and post-deletion regressions observed failing first; the batch race has no deterministic test); native CI smoke reads `coreo apps` |
| 6 h replay | Replay slice: 162 Swift tests pass on Linux (reduction keeps peaks, gaps and silences; stack alignment; bands do not bridge silences; the model puts stored points behind live without joining them and drops them for short ranges or on deletion; source changes recorded as gaps; a missing store is named); native compile and the owner's look at a long range are pending |
| Sleep and wake import | Sleep slice: 156 Swift tests pass on Linux (record parsing with tab or space columns, cut lines, periods across dark wakes, caps as partial coverage, the tool's window and record cap, a runner that stops a child at its limit); native CI compares parsed records with an independent count of the real `pmset -g log` |
| Process filter grammar | Filter slice: 143 Swift tests pass on Linux (predicates, units, tokens, reported issues, unknown-is-not-zero, group visibility) |
| Process heat, new and exited rows | Lifecycle slice: 139 Swift tests pass on Linux (new-row window, ghost expiry, sleep not read as exits); UI compile pending |
| Alerts | Alerts slice: 137 Swift tests pass on Linux (debounce, hysteresis, unknown readings, cooldown, permission-once delivery, end-to-end tint, marker and notification); native notification permission and banners are owner checks |
| Ask Coreography | Ask slice: 131 Swift tests pass on Linux with a scripted transport (tool loop echo, batched results, request shape, every failure path, key handling); live provider calls and the UI are owner checks |
| MCP stdio server | MCP slice: 128 Swift tests pass on Linux (handshake, version negotiation, notifications, catalog, cursor reuse of one snapshot, protocol and tool errors, call budget); native CI smoke drives a real stdio session |
| Diagnostic contract and `coreo diagnose` | Contract slice: 125 Swift tests pass on Linux (signals, cursor binding, bounds, gaps, no paths, unavailable sleep history); native CI smoke checks units, evidence and that no path leaks |
| Menu bar extra and launch-time sampling | Menu slice: Swift tests unchanged (121); the menu view and project registration compile only in native CI; owner check for the title, mini lanes and Open Coreography |
| App scope overlays and filtering | Scope slice: 121 Swift tests pass on Linux, including idle-as-zero and gap segments in the scoped series; UI compile pending |
| Process actions and markers | Actions slice: 120 Swift tests and the Linux C contract pass; the native contract forks a child, refuses a wrong start time and terminates it with the right one; UI compile pending |
| Range export (JSON, CSV) | Export slice: 117 Swift tests pass on Linux, including range filtering, JSON round trip and empty cells for missing readings; save panel compile pending |
| Range selection, ledger and range report | Range slice: 115 Swift tests pass on Linux (integration over real intervals, tail apps, interruptions, midpoint inclusion, lower bounds); native compile pending |
| Time ranges, decimation and one-hour buffers | Range slice: 110 Swift tests pass on Linux, including spike survival and segment isolation; native compile and S2 rendering cost pending |
| AppleSMC bridge, sensor decoding and thermal line | Sensor slice: 107 Swift tests and the Linux SMC contract pass; the Apple branch compiles against stub headers locally; native CI pending. A VM without AppleSMC shows unsupported sensors; real readings are an owner check |
| Shared cursor, hover tracking and contributor lines | Cursor slice: 101 Swift tests pass on Linux; native compile pending. Hover behavior is an owner check |
| Native IOKit power sources and seven-lane UI | Power slice: 99 Swift tests pass on Linux; native CI pending. A virtual runner has no battery, so its smoke checks explicit unsupported states; battery accuracy is an owner check |
| Native GPU statistics, thermal notify state and six-lane UI | GPU slice: 93 Swift tests, 34 tooling tests and the Linux thermal C contract pass; native CI pending. The C bridge asserts the level constants against the SDK at compile time |
| Native executable paths, responsibility lookup and grouped table | App-grouping slice: 88 Swift tests pass on Linux, including a fail-first regression for bundle-less owners combining unrelated apps; current native CI pending |
| Native swap/pressure sysctls, memory composition and stacked lane | Passed [native CI](https://github.com/L-K-M/Coreography/actions/runs/39112973077) at `1274ff0`: 83 tests including real sysctl reads, and the snapshot gate's composition sum |
| CPU, memory and wakeup budgets | In-app readout of own CPU and footprint against budget (111 Swift tests pass on Linux); wakeups and S2 measurements pending |
| Developer ID, notarization and signed update delivery | Pending credentials and M7 |

Portable tests use declared fixtures. They do not validate private APIs,
sensor calibration, fullscreen behavior or Mac energy overhead.

## Remaining delivery

| Stage | Outstanding outcome |
| --- | --- |
| M0 / S1-S8 | Native CI foundation and reproducible probes; record hardware findings and missing environments |
| M1 | CPU/memory depth, process app grouping/lifecycle/history, disk review/native validation, network review, full cadence scheduler and attribution contracts |
| M2 | GPU, clusters, frequency, power, sensors, thermals and honest chip profiles |
| M3 | Seven aligned lanes, shared cursor, scoped selection, process pane, inspector, self-cost and accessibility |
| M4 | SQLite history, app ledger, sleep/log import, retention/deletion, replay, ranges and exports |
| M5 | Secure optional helper, diagnostics, files/ports, startup/connections, filters and bounded read-only MCP |
| M6 / S9 | Menu bar, HUD, raw-frame-qualified session statistics, comparisons, alerts, explanations and optional Ask |
| M7 | Localization, full integration/soak/performance checks, updater and production release validation |

## Owner Mac checks

The owner will test downloadable builds. The owner checked the PR #7
candidate and reported no problems; private macOS APIs are approved for
this direct-download app. For a trusted ad-hoc build blocked on
first launch, use System Settings > Privacy & Security > Open Anyway.
This is not a notarized production release. Check:

1. Open the app and compare CPU and memory trends with Activity Monitor.
   Memory is an estimate and is not memory pressure.
2. Hold the display with Space, wait, and return to live. Collection must
   have continued; holding is distinct from pausing recording.
3. Sleep/wake the Mac. Missing intervals must remain gaps, including in
   the memory line.
4. Check light/dark appearance, keyboard access and VoiceOver chart/table
   readings. Return the OS/build, architecture and concrete discrepancies.

More specific S1/S6 probes follow when those providers and HUD exist.
Do not mark a physical-Mac gate passed from a cross-compile or fixture.

For the process-counter candidate, compare own-user process trends with
Activity Monitor. Its default process CPU scale is one core equals 100%;
Coreography uses the whole machine, so divide Activity Monitor's process
CPU by the logical CPU count before comparing. Check CPU/memory/disk sort,
filters containing spaces, display hold, and unreadable/restricted counts.
Enumeration can miss short-lived processes and is capped at 16,384 PIDs.
No per-process network is claimed yet. With grouping by app, check that
Safari's web content and Chrome's helpers fold under their apps, that a
filter matching one helper still shows its app's full totals, and that
totals with unreadable members read "est." with a lower-bound tooltip.

For a verified network candidate, check primary/interface selection with
and without a VPN, receive/send direction and byte units, interface
disappearance, hold/resume, and VoiceOver/numeric-table equivalence.
Primary means the SystemConfiguration IPv4 interface, falling back to
IPv6; it is not a sum of physical and tunnel traffic.

For a verified memory candidate, compare App Memory, Wired, Compressed,
Cached Files, Swap Used and the pressure colour with Activity Monitor's
Memory tab. Open a large workload to raise pressure and check that the
band and header change together, swap rates rise only while swapping, and
VoiceOver reads each layer's own bytes rather than its stacked height.

For a verified storage candidate, select the same device when comparing
read/write trends, check external-drive and disk-image attach/detach,
automatic versus manual scope, held history and accessibility. Driver
counters describe device I/O, not cached file operations or per-volume
totals. An absent driver is unavailable data, not measured idle.

## Process source and units

`PROC_PIDTBSDINFO` and `RUSAGE_INFO_V6` are public but access may be denied
for other users' processes. Those identity failures appear in coverage;
they are not empty zero-usage rows. A failed usage read on an identified
process keeps a restricted/unavailable row and drops its rate baseline.

The CPU fields in `proc_pid_rusage` are Mach timebase ticks, not already
nanoseconds. The bridge converts with `mach_timebase_info` using checked
128-bit intermediates. The native C contract test compares busy-loop CPU
deltas against `getrusage`'s microseconds to catch timebase/unit mistakes.
Primary source chain: Apple's [fill_task_rusage](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/bsd_kern.c),
[task_power_info_locked](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c)
and [recount metrics](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/recount.h).
The [libproc wrapper](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/libsyscall/wrappers/libproc/libproc.c)
calls `__proc_info` directly, and
[proc_get_rusage](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_resource.c)
copies the gathered record without a hidden nanosecond conversion.

## Sensor sources

AppleSMC is private (owner-approved). The C bridge uses its user client's
struct method 2 with the community-documented 80-byte key-data layout,
which `_Static_assert` pins: key info first (size, type), then the bytes;
enumeration reads the key at an index. No write command exists in the
bridge. `spXY`/`fpXY` are signed/unsigned big-endian fixed point with Y
hex fraction bits, and `flt ` is a little-endian float on Apple Silicon.

Temperature keys start with `T` and use `flt ` or `sp78`. Values outside
10-130 °C are counted as implausible, not shown. The hottest key labels
`Tp`, `Te`, `Tg` and `TB` with community region names only. `PSTR` and
`PDTR` are community-verified on specific chips, so system power is an
estimate until S1 validates each chip; non-positive rails are faults.

## Power sources

Battery charge, power source, charging state and time estimates come from
the public `IOPSCopyPowerSourcesInfo` descriptions (keys from IOPSKeys.h);
`-1` while macOS calculates and `0` when not applicable become absent
estimates, never zero minutes. The adapter rating comes from
`IOPSCopyExternalPowerAdapterDetails`. `AppleSmartBattery` registry
properties give gas-gauge millivolts and signed milliamps, cycle count,
design and full-charge capacity; their product is battery power, positive
while charging.

Only while unplugged does battery discharge equal system draw. On
external power the charge rate is not system draw, so the hero reading is
unavailable until the SMC system-power provider (`PSTR`/`PDTR`) lands.
Macs without a battery show unsupported battery readings, not zeros.

## GPU and thermal sources

Each `IOAccelerator` registry entry publishes a `PerformanceStatistics`
table without opening a user client, so no privilege is needed. Its keys
are driver-defined: AGX uses `Device Utilization %`, `Renderer
Utilization %`, `Tiler Utilization %` and `In use system memory`; AMD and
Intel may use `GPU Activity(%)`. Percentages outside 0-100, booleans and
strings are rejected. Busy percentage is the driver's own window, not
per-app GPU time, and memory in use is unified system memory, not VRAM.
A runner or Mac without an accelerator shows no GPU rather than 0%.

Thermal pressure reads the state of `kOSThermalNotificationPressureLevelName`
from the public `libkern/OSThermalNotification.h`, as powermetrics and
mactop do. macOS levels are 0 nominal, 1 moderate, 2 heavy, 3 trapping and
4 sleeping; the C bridge `_Static_assert`s them against the SDK. Pressure
alone does not prove throttling.

## App grouping sources

`proc_pidpath` is public and has no same-user check. The responsible PID
comes from `responsibility_get_pid_responsible_for_pid`, private libsystem
SPI that Activity Monitor-style tools such as Stats resolve at runtime.
The bridge resolves it once with `dlsym`; a missing symbol or failed
lookup leaves the PID absent, and grouping falls back to the app bundle.
Both reads sit inside the existing PID/start-time bracket. A responsible
PID is a bare PID, so grouping requires that app process to be observed and
to have started no later than its member; otherwise the PID was reused.
Bundle-less owners such as launchd never combine unrelated apps.

CLI tools launched from a terminal are its responsibility, so they fold
under that terminal app, as macOS attributes them. Group footprints add
member physical footprints and can count shared pages more than once.

## Network source and units

Use public `IFMIB_IFDATA / IFDATA_GENERAL`: its
[SDK structure](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/net/if_mib.h#L65-L86)
contains `if_data64`, and the
[read-only kernel handler](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/net/if_mib.c#L97-L139)
copies full-width byte counters without a platform-binary gate. Counters
are differenced over each interface's actual monotonic interval; index
and name identify its series. A detached interface's successful but
zero-filled reply has an empty name and is unavailable, not zero traffic.

Reject the tempting routing-statistics byte source: although
`NET_RT_IFLIST2` has 64-bit fields, its
[non-platform output path](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/net/rtsock.c#L2196-L2205)
uses [a 32-bit cast and 1 KiB floor](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/net/rtsock.c#L158-L161).
The interface MIB avoids that truncation and quantization. No private
NStat API, helper or subprocess is needed for these interface counters.

The primary route comes from SystemConfiguration's `PrimaryInterface`
for IPv4, then IPv6. Missing or ambiguous primary metadata stays explicit;
observed interfaces remain selectable. Interfaces are never summed into
an ambiguous system total. Native C fixtures use the SDK's real
`ifmibdata` type and verify values above 4 GiB, bounded names and detached
responses. Linux tests verify the unsupported path, not a copied Mac ABI.

## Memory source and units

One `host_statistics64(HOST_VM_INFO64)` read supplies the page counts and
lifetime counters in the
[SDK structure](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/vm_statistics.h#L142-L177).
Used memory keeps the existing composition; app memory subtracts wired
and compressed pages from it, and cached files are purgeable plus
file-backed pages. A derivation that would go negative or exceed physical
memory is unavailable, never clamped. `compressor_page_count` is the
physical footprint of compressed data; the ratio divides
`total_uncompressed_pages_in_compressor` by it and is unavailable when
the compressor is empty.

`pageins`, `swapins` and `swapouts` are lifetime page counts. The
compressor's swap path adds each segment's
[I/O size in pages](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/vm/vm_compressor_backing_store.c#L1456),
so rates multiply page deltas by the host page size. Like CPU, these
rates are gaps across interrupted sampling; composition gauges remain.

`vm.swapusage` returns `xsw_usage`, whose
[handler](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_sysctl.c#L4097-L4119)
derives used swap from total minus available. On macOS the
[pressure sysctl](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_memorystatus_notify.c#L1884-L1910)
has no privilege check and reports the public `DISPATCH_MEMORYPRESSURE_*`
values: 1 normal, 2 warning, 4 critical. Unknown values are unavailable.
The reading stores the severity ordinal 0-2; it is never averaged. A
pressure-event source can replace polling when the full scheduler lands.

## Storage source and units

IOKit exposes `IOBlockStorageDriver`'s `Statistics` dictionary. The
[declared keys](https://github.com/apple-oss-distributions/IOStorageFamily/blob/7edb88fbae296fb7c8ce2f64e115e116e566d51c/IOBlockStorageDriver.h)
`Bytes (Read)` and `Bytes (Write)` name byte counts, backed by
[64-bit OSNumber accumulation](https://github.com/apple-oss-distributions/IOStorageFamily/blob/7edb88fbae296fb7c8ce2f64e115e116e566d51c/IOBlockStorageDriver.cpp).
The decoder accepts unsigned integer numbers and rejects absent, boolean,
fractional, negative or non-finite values. Device rates use each read's
actual monotonic timestamp. Registry entry identity, not a display name
or BSD-name suffix, owns the rate baseline.

The native iterator and every service/child reference are released after
use. Immediate whole-media children may supply a BSD name; otherwise the
label includes registry identity. A registry change, capacity bound or
failed identity lookup makes inventory incomplete. Identified devices
remain listed when their statistics are restricted or unavailable.

Automatic scope requires exactly one observed device, no inventory issues
and no truncation. This avoids guessing a boot disk through ambiguous
APFS/Fusion ancestry. Virtual drivers and physical drivers may overlap,
so their rates are not summed. Explicit selection remains pinned when a
device disappears. Native CI reports the actual driver/rate coverage; an
empty virtual-machine inventory does not validate hardware rates.

## Review decisions carried forward

- Network parent integration: derive numeric-cell tooltips from reading
  provenance, show interface inventory issues/capacity, and remove the
  unused selected-interface accessor. These low-risk local-review notes
  are applied with the required base integration rather than a nit-only push.
- The first network Mac CI failed because the SDK returns a non-optional
  `CFString` from `SCDynamicStoreKeyCreateNetworkGlobalEntity`. Replace
  optional binding with direct assignment. The corrected native compile,
  C contracts, SwiftUI build and live network smoke passed at `e62fac1`.
- Process review round 2: verify the complete libproc wrapper, gather and
  copyout path and retain Mach-timebase conversion. The new nanosecond
  blocker claim contradicts that source path and ARM64 native checks.
  Command-first CLI grammar is intentional. Defer clearer smoke-test
  failure messages; no confirmed important finding remains.
- Process review round 1: reproduce saturated CPU rounding at
  1,500,000,015 ns across four logical CPUs. Allow a few floating-point
  ULPs at capacity and bound the displayed reading at 100%; genuinely
  excessive deltas remain gaps. The regression failed before the fix.
- Native process reads now use an owned serial actor executor rather
  than a cooperative-pool thread. Running actor jobs on that executor
  preserves `Task.isCancelled`; a cancelled-read test guards this without
  a separate unchecked cancellation flag.
- Refute the reported V2 build blocker: Apple's
  [rusage_info_v2](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/resource.h)
  already contains both disk-byte fields. Native CI built the code and
  exercised disk readings, kernel_task and the Apple Silicon timebase.
- Keep unexpected sampler errors visible. Native failures already become
  nonnumeric readings; current validated process samples throw only for
  cancellation. Silently swallowing errors would hide stale process data.
- Hold release synchronously republishes the latest process snapshot, so
  the immediate assertion is intentional. Keep identity errors internal
  until a consumer needs typed recovery. Capacity copy is conservative;
  cancelled raw scans are rejected before dashboard publication. C tests
  now reject `NDEBUG` and pin invalid-argument output preservation.
- Foundation review round 2: no actionable or important findings. Defer
  clearer test-extraction failure messages. Production signing remains
  M7; adding placeholder credentials would break the current build.
  The app does not launch its embedded CLI through bundle lookup APIs;
  build and smoke-test paths explicitly use `Contents/Helpers/coreo`.
- Process slice independent review: accept PID 0 as kernel_task and let
  libproc return its real reading or permission failure. The old positive-
  only guard fabricated an `EINVAL` before making the named syscall.
  Reproduced the C contract failure before fixing the guard on both
  platforms; native CI also checks kernel_task's actual result.
- Foundation review round 1: strengthen the release smoke test to reject
  unavailable, non-finite or out-of-range values using the same validator
  as CI. Exercise archive-mutating tests in the output-isolation guard.
- Refuted compile claims: `Duration.nanoseconds` accepts generic integer
  values, and native Xcode 26.6 CI compiled both architectures. Display
  hold freezes `frames`, `latest` and its timestamp; the expanded hold test
  feeds more than a full buffer while checking that displayed points stay.
- Transient Mach failures are already nonnumeric readings returned by the
  engine, not thrown loop errors. Reading factories and decoding reject
  numeric unavailable states. Counter decreases become gaps, not unsigned
  underflow. Keep these invariants rather than adding reviewer workarounds.
- Preserve exact CLI flag validation: both permutations of its two flags
  work; set comparison would also accept unintended duplicate flags.
- No entitlements are configured in this unprivileged, unsandboxed target.
  Production entitlements and signing remain an explicit M7 gate. Space
  with focused controls still needs the owner's native accessibility check.
- Numeric evidence is separate from explanatory hypotheses. Memory/GPU
  quantities and modeled app energy are not universally additive.
- A zero/unset wired-memory setting is not zero effective GPU capacity;
  a recommendation is not an enforced allocation ceiling.
- S1 must define freeze confirmation and fallback validation per source;
  unchanged idle counters alone do not establish freezing.
- Privileged targets use PID plus start time, checked at dispatch.
  Tool paths, argument templates, environment, runtime and output are bounded.
- MCP peer identity needs kernel-attested connection evidence. Client
  names are display data, grants are scoped/revocable and stored securely,
  and revocation cancels that client's queries and suppresses delivery.
- Cursor retries can be idempotent but are reauthorized and charged to
  budgets; revoked/narrowed scopes and expired snapshots invalidate access.
- Release arch tokens are `arm64`, `x86_64`, `universal`; the last requires
  both app and embedded CLI slices.
