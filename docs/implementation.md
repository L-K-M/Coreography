# Implementation ledger

Track actual delivery against the [product plan](plan.md). A stage is
complete only after its relevant checks and review pass and its PR merges.

## Current slice: on-disk history

The native foundation merged in [PR #5](https://github.com/L-K-M/Coreography/pull/5)
at `aee9494` after two GLM rounds and passing CI. Process monitoring merged
in [PR #6](https://github.com/L-K-M/Coreography/pull/6) at `65d2377`, also
after two GLM rounds and passing CI. The network slice in
[PR #7](https://github.com/L-K-M/Coreography/pull/7) passed native CI at
`e62fac1` and now integrates the reviewed process fixes. Its latest
integration checks and GLM review still gate delivery.
Scoped storage-driver rates and a fourth lane follow in
[PR #8](https://github.com/L-K-M/Coreography/pull/8); memory composition,
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
This slice records six hours of system history to disk.

Implemented:

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
  bounds. Footprint sums are always estimates. A flat view remains.
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
  app). CPU, memory and disk headers show them live or, under the cursor,
  from the process sample within 2.5 s ("Top at …"), never a distant one.
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
  a marker; unknown readings pause the clocks rather than count. Only the
  memory and battery rules notify, through UserNotifications (so Focus
  applies), with a 15-minute cooldown and one banner per rule. The
  startup-disk rule waits for a volume capacity provider; user-defined
  rules and Shortcut actions remain M6.
- Process pane change highlighting: CPU, footprint and disk cells are
  shaded in their subsystem hue by share of the column's top row; a
  process first seen within 10 s (not present at launch) tints its name;
  processes gone within 30 s are listed with their app as ghosts. Exit
  status is not claimed, and samples across sleep are not read as exits.
- Process filter grammar: whitespace-separated terms that all must match:
  free text, `cpu:>10`, `mem:>1GB`, `disk:>5MB`, `pid:42`, `user:root|me|UID`
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
  one click; `coreo history --json METRIC` reads it, and the CLI never
  records samples. Rollups remain (S7, M4).
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
- Startup tab, first part: launch agents and daemons from the user,
  global and system folders, with launchd's own enabled state from
  `launchctl print-disabled` (no root needed; when it fails the state is
  marked unconfirmed rather than guessed from the plist) and whether the
  program is Apple-signed (basic validation only). Apple's items are
  hidden by default. Each row is joined to its running processes'
  current CPU and footprint and their apps' CPU-seconds over the last
  hour. Read on request, never polled. Login and background items need
  the helper and are named as missing.
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

The live buffers hold one hour per monitor. Process history/attribution,
per-volume disk accounting and per-process network attribution remain outstanding.
There is no disk store, IOReport power or frequency provider, per-app GPU
time, helper, MCP or model integration in this slice.

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

`PROC_PIDTBSDINFO` and `RUSAGE_INFO_V2` are public but access may be denied
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
