# Mac window dashboards and trace-analyzer UIs (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

Scope: (A) a head-to-head teardown of window-based macOS system monitors,
the niche Coreography targets, and (B) interaction patterns from trace
analyzers and observability UIs that solved selection, comparison, and
dense-timeline legibility. Notes 02 and 06 cover the same apps at survey
level; this file goes deeper on window layout, history mechanics, and
attribution. Depth ratings below are as published on 2026-10-17.

## Summary

- Three current commercial tools attempt a real graph window: Vitals
  (tabbed cards plus an "Over Time" history view), TMOG (graph-first but
  neon skin, covered in notes 06), and System Dashboard Pro (draggable
  tile grid, seconds of history). Two non-commercial ones do too: XRG
  (the original graph-strip window, dormant since 2024) and the
  open-source MacStats (per-metric panes plus a process table). Most
  everything else is a menu bar app whose detail surface is a popover
  (Usage, tstats, macstats.app) or an always-on-top widget panel (System
  Monitor Panel); Orcylo's tabbed panel is advertised but pre-launch.
- History depth is the loudest differentiator in 2026: Vitals went from
  30 days to a year (v1.6, 2026-10-11, confirmed in its changelog) and
  Tempo ships 30 days at one point per minute (Orcylo advertises the
  same but is pre-launch). Vitals is the only surveyed app claiming
  per-hour app ranks inside history (vendor copy, "for recent days";
  top-app coverage extends to a year), the closest any Mac monitor gets
  to attribution-in-time.
- Live-history scrubbing is absent from the surveyed set. No reviewed
  shipping Mac monitor offers
  zoomable, pannable stored history or a crosshair that reads values at
  an arbitrary past instant; the nearest are TMOG's Flight Recorder
  (records, scrubs and replays captured panels, Pro-only) and Tempo's
  "hover any point" readout over coarse 1-point/minute data. Per-hour
  ranked lists (Vitals) are the attribution ceiling. WPA, Perfetto,
  DevTools and Grafana all solved this years ago.
- Cluster awareness is a marketing checkbox, not an analysis surface:
  Vitals and Orcylo print "8 P + 4 E" counts, System Dashboard Pro draws
  per-core bars (and patched M5 super cores in 4.5.0), TMOG has a
  Power & Freq page, but none of the reviewed shipping windows pairs
  frequency with
  residency or shows watts per cluster except Vitals at
  system-and-app level (Orcylo advertises the same, pre-launch).
- Honest availability is starting to appear as a feature: Tempo declines
  GPU and temperature rather than guess, Orcylo labels its fan readout
  "read only" (advertised, pre-launch), System Dashboard Pro and
  iStatistica gate sensors behind helper plugins and say so.
  Counterexample: iStatistica and Usage both have user reports of wrong
  temperatures on Apple Silicon.
- The business model settled on one-time $5-40 (Tempo $4.99 launch to
  $14.99, Vitals $9-15 launch to $39, System Dashboard Pro $2.99, TMOG
  Pro $39.95); subscriptions survive only in suites (Sensei $29/yr) and
  Usage's iOS-style Pro.
- The AI features are arriving sideways: Vitals exposes an MCP server
  and reads AI-plan limits (Claude, Codex, Copilot, Cursor, Grok and
  more per its changelog), macstats.app's one-time Pro includes a
  300/month AI-explanation quota for processes, Orcylo (pre-launch)
  advertises AI plan limits. None is a monitoring capability, but they
  signal where indie energy is.
- Trace UIs converge on the same grammar: one shared time axis,
  drag-to-select a range that re-aggregates every table (WPA, DevTools
  Call Tree/Bottom-up, Perfetto area aggregations), pinned tracks and
  workspaces for density, a minimap/overview strip as the zoom
  affordance (DevTools Timeline overview, Datadog full-screen minimap),
  WASD or wheel-modifier conventions, and annotations as first-class
  marks on the axis (Grafana, DevTools, Perfetto notes, Instruments
  flags).
- Baseline comparison exists and is underused: WPA's comparative
  analysis view diffs two traces' zoomed ranges in one table, and
  Datadog's Compare Time tab overlays or grids an offset window.
  Perfetto still lacks trace diffing (open issue), which is an opening.

## Window-based system monitors on macOS

### Vitals (vitalsmac.com)

- **Status/price**: v1.7.5 released 2026-10-17 (the day of writing);
  shipping for weeks (v1.6 landed history-for-a-year on 2026-10-11).
  One-time pricing, two forms: $9 for a year of updates, or lifetime at
  a stepped launch price ($15 at time of writing, rising to $39; 2 Macs
  $25, 5 for $55). macOS 15+, Apple silicon and Intel, 21 MB, notarized,
  14-day refund, no account.
- **Window layout**: single window, tab strip across the top: Overview,
  CPU, Memory, Disk, Network, GPU, Neural Engine, Battery, Sound,
  Bluetooth, Projects, Agents, Containers. Each tab stacks summary cards
  (big current value, "Average today", splits like User/System), a
  chart, and a ranked per-app table with per-app process counts. The
  Overview aggregates one card per subsystem. Optional Float on Top,
  compact spacing, custom chart colors (Vitals / Monochrome /
  Accessible palettes) and number fonts.
- **Charts/history**: live charts cover the last 5, 15 or 30 minutes
  (selectable). The "Over Time" view is the history surface: one chart
  with range tabs 1 h / 24 h / 7 d / 30 d / 90 d / 6 mo / 1 y for CPU,
  memory, energy, disk and network, whole-Mac and per-app. A Peaks card
  lists the highest CPU, memory pressure, temperature and power in the
  chosen range, when each occurred, and time spent at a limit, built on
  a 5-minute reading cadence. History is a single documented local file
  (schema published at vitalsmac.com/history-data) and exports to three
  CSVs. Memory tab charts memory pressure and swap over time (1.7.2).
- **Scrub/zoom**: range is a segmented control, not a scrubber; no
  zooming or per-point cursor was demonstrated on the site (unverified
  for the app itself). Attribution-in-time exists at hour granularity:
  "the apps that used the most, ranked hour by hour" inside Over Time,
  and top-app coverage extends to a year.
- **Clusters/watts/thermal**: shows cluster counts ("Cores 12, 8 P 4 E")
  but no per-cluster frequency in the demo. Battery tab shows system
  power draw (12.6 W) and a "Power by App" list in watts/milliwatts.
  Temperature and fan speed with a "fan you can hold" (manual fan
  control). GPU tab shows utilization, GPU memory, average/peak and a
  top-app GPU list; a Neural Engine tab does the same for ANE including
  a memory-traffic figure and a per-app ANE table (vendor demo;
  attribution mechanism unpublished).
- **Honesty/process role**: shows "Measuring…" placeholders while
  measuring; since 1.7 a reopened GPU tab shows the last measured apps
  until the new reading arrives (changelog). Process list is app-folded
  everywhere
  (about 60 apps vs about 1,000 processes), quit/force-quit available;
  dev servers grouped by project with ports and idle flags, Docker
  containers with per-container CPU/memory/ports, coding-agent sessions
  with everything they spawned. MCP server lets AI assistants query
  live and historical stats.
- **Design/reception**: clean, system-font, card-based and restrained
  compared to TMOG; buyers on X/AppSumo/Product Hunt praise it ("uninstalled iStat Menus for it"). Site copy is polished but
  marketing-heavy. Self-cost not published as a number (unverified).

### Sensei (Cindori)

- **Status/price**: v2.1.3 updated 2026-09-29 per MacUpdate; suite
  pricing $29/year (up to 3 Macs) or $59 one-time through v2 (per notes
  02 / cindori.org/store). Free trial download.
- **Window layout**: single window, left navigation (Dashboard,
  Utilities, Hardware). Dashboard is a tile page: machine header (model,
  serial, manufacture date), circular gauges for RAM and CPU load with
  continuously updated top-process lists beside each, GPU section with
  load/memory/temperature, battery gauge on portables. Hardware section
  pages (Storage, Graphics, Battery, Cooling/Thermal) give detail.
  Utilities bundle Optimize (login items), Uninstaller, Clean, Trim,
  S.M.A.R.T. report, disk benchmark.
- **Charts/history**: gauges and stat blocks dominate; charts are small
  and there is no scrubbable long history (unverified; nothing in the
  marketing or reviews shows one; absence on the site is not proof of
  absence in the app). The Monitor product line adds a
  status-bar item plus a dropdown "Monitor Panel" with a widget editor
  and themes.
- **Clusters/watts/thermal**: no cluster or frequency views in public
  materials; thermal dashboard lists sensors and fan speeds. Watts not
  shown (unverified).
- **Honesty/process role**: sensors "for Intel and Apple Silicon" per
  site; Macworld's 2020 review hit Thunderbolt/storage reporting bugs;
  top-process lists sit next to gauges (cause beside symptom, at
  survey level).
- **Design/reception**: the most consistently praised visuals in the
  niche ("gorgeous, well-organized" - Macworld; "beautifully-designed" -
  MacStories; The Sweet Setup called out friendly guidance like "within
  the normal range" on battery temperature). Critique: it is a
  maintenance suite; monitoring is one limb, and the subscription drew
  complaints historically.

### iStatistica Pro (ImageTasks)

- **Status/price**: $9.99 on the Mac App Store, v7.1.3 (2026-09-21), 10.9
  MB, macOS 10.11+, six languages. The non-Pro sibling "iStatistica" is
  $5.99
  with IAP. v7 added an "Apple Silicon Profiler" via the Sensors
  plugin.
- **Window layout**: card dashboard: realtime CPU, memory (with
  pressure breakdown), network, disk cards plus GPU, battery, sensors
  and Bluetooth sections. Separate tabs/pages: Applications (per-app
  CPU/memory with history and force quit), Network interfaces, Storage
  visualization (find-and-delete large files), Sensors and Fans.
- **Charts/history**: "CPU usage history" and "RAM map" per app; charts
  for CPU, GPU, memory, temperature exist and export to CSV. Depth and
  scrubbing are not documented; reviews describe a live dashboard, not
  a historian.
- **Clusters/watts/thermal**: per-core CPU display (one reviewer counts
  32 cores on an M3 Ultra-class chip); sensors via a separate free
  plugin app (I/O plugin) because the App Store sandbox blocks SMC.
  Watts not advertised. Notification rules can fire terminal commands
  and workflows on metric thresholds.
- **Honesty/process role**: the plugin gate is at least explicit.
  Counterpoint: App Store reviews report wrong temperatures on M1 Max
  ("cores exceeding 130 F" on a cool machine) and a sensor view that
  dropped two-thirds of the cores after a day; support did not answer.
  Process list is a real applications tab with quit/force quit
  (plugin-required) plus per-app network bytes (also plugin).
- **Extras**: web access serves a mobile-friendly dashboard plus a JSON
  REST API on the LAN (documented endpoints like summary_cpuLoad) with
  IP/passkey filtering: the only remote-visibility feature in the set
  besides TMOG's iPhone viewer.
- **Reception**: 4.7 across 5K+ App Store ratings; praised as a slick
  customizable dashboard; thermal accuracy on Apple Silicon is the
  recurring complaint.

### System Dashboard Pro (Sascha Simon)

- **Status/price**: $2.99 Mac App Store, v5.0.1 (2026-10-07); requires
  Apple silicon since 5.0 (Intel users keep the old build). 4.3 MB.
- **Window layout**: a tile dashboard in one window. Drag any tile into
  any column/position; v4.2 added layout presets (Default, Classic,
  Essentials, Performance); narrow columns automatically swap gauges
  for compact bars; a header row can pin live readings (CPU, memory,
  network, power, hottest sensor) while the board scrolls. Panels:
  Processor (current load, recent-history graph split user/system,
  per-core bars across P and E cores, top processes), Graphics
  (utilization, VRAM, apps using it), Memory (usage over time, top
  processes), Temperatures/fans (via free sensors plugin), Network
  (IPs, Wi-Fi rate/signal/noise), Network usage (up/down over time),
  Storage, Connected volumes (eject), Battery, Power (wall draw over
  time on desktop Macs, with voltage/current/adapter loss), System
  overview (incl. thermal state).
- **Charts/history**: graphs show "the last few seconds" per the App
  Store copy; v5.0 made them scroll smoothly and interpolate between
  samples. No stored history, no scrubbing.
- **Clusters/watts/thermal**: per-core bars "cover every performance and
  efficiency core"; 4.5.0 fixed M5 Pro/Max counts "including the new
  Super cores". Desktop wall-power graph is a rare real watts source.
- **Honesty/process role**: sensors honestly gated behind the plugin;
  top-process lists live inside CPU/memory/GPU panels (cause beside
  symptom, live only).
- **Design/reception**: reviewers call it "useful and gorgeous" and
  professional; pre-4.0 complaint about panels running off-screen was
  fixed with reflowing layouts. This is the cheapest tile-dashboard
  in the set and the closest existing thing to a Coreography-shaped
  window, minus any history.

### System Monitor Panel (Sascha Simon)

- **Status/price**: free on the Mac App Store, v7.0.0 (2026-10-04);
  Apple silicon only now. Sensors via the same free helper app.
- **Window layout**: not a dashboard but a floating always-on-top HUD
  panel: pick from 17 widgets (per-core CPU, load-over-time graphs,
  top processes for CPU/memory/network including other users' daemons,
  per-direction network graphs, per-volume space and per-drive I/O,
  sensors), anchor to a corner or free place on any display, spacing
  and transparency adjustable, click-through mode, eight themes
  (System, Light, GitHub, Dracula, Noctis, One Dark Pro, Palenight,
  Ayu).
- **Charts/history**: fixed short-window graphs; sampling selectable
  from 4x/sec to once per 2 s with the same time span either way.
  v6.1 added global hotkeys to toggle the panel and click-through, and
  warning colors (orange/red thresholds you set).
- **Design/reception**: closest shipping thing to a Mac performance
  HUD outside Metal's; one 2021 review reports sleep-wake crashes and
  a GPU readout that never exceeded 6%.

### Tempo (tempoformac.com)

- **Status/price**: current v1.3 ("puts your notch to work"); launch
  pricing $4.99 (first 20) / $9.99 (next 100) / $14.99 regular,
  one-time, macOS 14+, native SwiftUI, Apple silicon and Intel, sold
  direct (notarized) because "the App Store sandbox doesn't allow"
  live process reads. ~2% CPU / ~40 MB advertised; pauses process
  scanning when the list is not on screen.
- **Window layout**: tab bar with Overview, All vitals, Processor,
  Network, Processes, Settings. Overview uses health rings for CPU,
  memory and storage, a live processor line chart, mirrored bars for
  network and disk, each vital in its own color, light and dark. A
  Processes page is a focused top-10 list sortable by CPU, memory or
  energy with Quit/Force Quit. Menu bar shows up to four vitals;
  the notch island puts CPU and download speed beside the notch and
  opens rings on hover.
- **Charts/history**: 30 days of local history at one point per minute;
  the detail pages scroll back through 24 h / 7 d / 30 d and "hover any
  point to see exactly what happened". That is a scrub-style readout
  over coarse data, the best among the indie set besides Vitals.
- **Clusters/watts/thermal**: no cluster view, no watts. Deliberately
  no GPU and no exact temperatures: the FAQ says macOS has no
  supported public API for those, so Tempo shows the thermal pressure
  state instead of guessing. The honest-availability stance is the
  product's written policy.
- **Process role**: secondary and capped at top-10; no inspector.
- **Reception**: too new for press; the site demo and craft are the
  evidence (per notes 02 reviewers/users praise the notch island).

### Orcylo (orcylo.app)

- **Status/price**: v1.0 announced 2026 with "Coming soon" banner and
  launch pricing already on sale: €5 (first 20) / €7.50 (next 30) /
  €9.99 after; one-time, lifetime updates, no account, macOS 15+,
  Apple silicon and Intel. One licence sold at fetch time.
- **Window layout**: menu bar app whose detail surface is a tabbed
  panel/window with 13 tabs: Overview, CPU, Memory, Disk, Network, GPU,
  Power, Thermals, Sound, Bluetooth, Projects, Analytics, AI Tools.
  The interactive demo shows per-tab cards: big stat, sub-stats, top-app
  tables (all demo values are simulated, per the site itself). GPU
  splits Renderer vs Tiler; Thermals lists 38 sensors in 7
  physical groups (CPU Dies, GPU, SoC, Package, Storage, Battery,
  Other) with hottest sensor callout; fan shown "Read only - 38% of
  max". Projects groups dev servers by folder with ports and idle time;
  Containers and Analytics add Docker and web-analytics tabs.
- **Charts/history**: "30 days of history, one point a minute, so you
  can see which app slowed things down yesterday afternoon" (their
  framing of attribution-in-time). Scrub/zoom mechanics not documented
  (unverified).
- **Clusters/watts/thermal**: "Cores 14, 10 P 4 E" counts; Power tab
  shows system power in watts, average, adapter wattage, battery health
  and cycles, "Energy today 96.4 Wh", and per-app watts. Thermal page
  is the most sensor-complete of the indie set (short of iStat Menus).
- **Honesty/process role**: "read only" fan label is a genuine honesty
  state; per-app folding (700 processes into about 25 apps) with icons;
  top-app lists under every metric.
- **Design/reception**: same genre as Tempo (calm cards, per-metric
  color); unproven, pre-launch.

### MacStats

Two unrelated apps share this name; both are new in 2026.

- **macstats.app (commercial)**: free monitor + Pro ($14.99 one-time/1
  Mac, $39.99/5 Macs). Native Swift, macOS 13+, Apple silicon only, not
  yet notarized. Menu bar carries five metrics; the detail surface
  shows CPU history (60 s), network activity (60 s), memory pressure
  breakdown, disk/S.M.A.R.T., battery, Bluetooth, top-CPU and top-RAM
  lists. Differentiators: automatic "Incidents" (records which process
  caused a slowdown with readings across the incident window: the
  closest shipped thing to attribution-in-time), session recording,
  anomaly detection vs your own baseline, Diagnose checks, and
  plain-English AI explanations per process (300/month under Pro).
  History 24 h / 7 d / 30 d is Pro. Honest about limits: thermal state
  only, no per-sensor temps or fans, and says so on the comparison page.
  ~1% CPU / 65 MB claimed.
- **macstats.luizcastro.dev / luizhcastro/mac-stats (OSS)**: MIT, macOS
  13+ Apple silicon, ~29 stars, created 2026 (month unverified).
  Menu-bar-first, but has a real main window (window icon in the
  dropdown): Overview plus CPU, GPU, memory, disk, network, battery,
  temperature and fans panes and a filterable process table; charts
  have a 1m/1h/24h switcher. Claims ~0.5% of one core and 76 MB idle.
  A third repo (raro42/mac-stats) is a different MIT
  fork-genre app with a glass window, themes and an optional Ollama
  agent. The name collision itself is a signal: indie churn in this
  niche is heavy.

### XRG

- **Status/price**: GPL-2.0, free; v3.2.1 (2023-10-31), macOS 10.13+;
  last commit March 2024: dormant. Objective-C.
- **Window layout**: the original graph-first Mac monitor: a slim
  window of stacked graph modules (CPU per-core, memory, temperature
  sensors, network, disk, battery, plus weather and stocks), vertical
  or horizontal orientation, resize by dragging any edge or corner,
  collapsible to its title bar, auto-expand on mouseover, a condensed
  mode that draws as a slim bar at the bottom of the screen. Each
  module prints its own scale label (e.g. "10K/sec" top-to-bottom).
  Disk has a split read/write graph; network stacks or mirrors send vs
  receive.
- **History/attribution**: scrollback is whatever fits the window
  (seconds to minutes); no process list, no hover values, no storage.
- **Reception**: beloved in its era (Washington Apple Pi review); today
  it reads as a period piece proving the layout works but the craft
  moved on.

### TMOG for Mac

- **Status/price**: v1.0.0 RTM (Windows has a 1.0.1 hotfix; macOS stays
  on 1.0.0). Free plus Pro at $39.95 unlocking five destinations
  including Flight Recorder and Power & Freq. Full teardown in
  [notes 06](06-tmog-task-manager-og.md); summary here for the matrix.
- **Window layout**: left icon sidebar, twelve destinations; Summary and
  Performance lead (graph-first). Performance = rail of metrics with
  sparklines + detail page with per-logical-processor grid colored by
  P/E core, stat blocks; scrolling charts use a compressed nonlinear
  timeline and a white chevron at "now".
- **History/attribution**: compressed timeline scrolling in every
  graph; Flight Recorder (Pro) records, scrubs and replays full
  telemetry panels: the only true scrubbable capture in the Mac set.
  Hover attribution per instant is not implemented (per notes 06).
- **Clusters/watts/thermal**: P/E color coding; Power & Freq page is
  the only frequency surface in the set; power restricted states are
  explicit per platform.
- **Honesty/process role**: the measurement contract (measured /
  unavailable / restricted, gaps not interpolation) plus a full
  Processes destination with inspector (files, ports, identity,
  lifetime) and recycle-safe PID identity.
- **Reception**: praised for IA and responsiveness, panned for the neon
  phosphor skin and 3-4% CPU (PC Gamer, HN; see notes 06).

### Usage (usage.pro)

- **Status/price**: Oleh Stasula; Mac App Store + Setapp; free with Pro
  at $7.99-13.99/yr or $14.99-29.99 lifetime (tiers vary by promo);
  v2.7.18 (2026-06-15); 4.6/5 on 252 US ratings, 25k+ reviews globally
  claimed. macOS 14+.
- **Window layout**: primarily menu bar + popover + widgets, not a
  document window: 40+ menu bar components, a configurable dropdown
  panel with tabs per metric (CPU, memory incl. swap, disk, network,
  battery, fans, temperature, graphics, processes, remote volumes,
  Bluetooth), history graphs inside the popover, desktop/notification
  widgets, iCloud sync of configurations. A dedicated full-window
  dashboard is not advertised (unverified whether one exists).
- **Charts/history**: "comprehensive and clear history graph" per
  metric (depth unverified; history is a Pro feature). Process tracking
  covers apps' CPU/memory.
- **Honesty/thermal**: fans and temperatures come through an optional
  helper; one 2025 review reports stuck 130 F and fans-reading-off
  while audible, and a combative developer reply. Requests for watts
  (adapter wattage) appear in reviews, unimplemented.
- **Reception**: well-liked for price and UI polish ("the only app
  paywall I've ever seen where it's actually reasonably priced");
  accuracy complaints on sensors.

### Other window-ish monitors found

- **Unhogged** (unhogged.com): $3.99 one-time, 3 Macs, macOS 13+ Apple
  silicon. Menu-bar-first "answer, not a dashboard": one-sentence
  diagnosis of what is slowing the Mac, one-click fixes (quit, restart,
  stop a server, free a port) previewed and identity-checked before
  acting, remembers the last month. Relevant as the anti-dashboard
  pole and for its fix-verification loop.
- **GPU Monitor Pro** (Sascha Simon): MAS app, GPU-only window reading
  whatever the driver exposes ("not every driver provides all data":
  hedged availability copy).
- **System Watcher / System Dashboard (non-Pro)** (Sascha Simon):
  menu-bar-with-pages and the older tile dashboard respectively; the
  Pro remake supersedes the latter.
- **Hardware Monitor** (Marcel Bresink): the classic sensor window,
  end-of-life 2017-06-19, licenses ended 2021-07-19; absorbed into
  TinkerTool System. Graveyard evidence that sensor-window products die
  without active maintenance.
- Menu-bar-first monitors with popover detail, included for contrast:
  **tstats** (per-core history charts in a dropdown, <0.3% CPU claim),
  **Better Mac Stats** (MIT, <1 MB, module popovers), and Stats/iStat
  Menus per notes 02.

## Comparison matrix vs Coreography differentiators

Legend: Yes = ships it well; Partly = exists but thin/coarse; No = not
documented in the reviewed public sources (not proven absent at runtime);
? = could not verify from public sources.

| App | Graph-first window at AM depth | Shared time axis | Scrubbable long history | Attribution in time | Cluster-aware CPU + freq + watts | Honest availability | Live FPS/HUD for games | Power-user inspector |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Activity Monitor | No (list-first, strip graphs) | No | No (visible strip; 12 h energy) | No | No | No | No | Yes (sample, files, ports, signals) |
| Vitals | Yes (tabbed cards + charts) | Partly (per-tab charts, no shared cursor) | Partly (1 h-1 y ranges, hourly app ranks; no zoom/scrubber seen) | Partly (top apps by hour) | Partly (P/E counts; system + per-app watts; no freq) | Partly ("Measuring…" states) | No | Partly (quit/force quit, ports/dev servers; no sample/files) |
| Sensei | Partly (gauges + lists, not charts) | No | No | No | No | Partly (suite hedging; bugs reported) | No | No |
| iStatistica Pro | Partly (card dashboard + per-app history) | No | Partly (per-app CPU/mem history, depth ?) | Partly (per-app history only) | Partly (per-core display; profiler plugin; no watts) | Partly (plugin gating explicit; sensor accuracy complaints) | No | Partly (quit/force quit via plugin; REST API) |
| System Dashboard Pro | Yes (tile grid, live graphs) | Partly (per-tile graphs, same refresh) | No (seconds) | No (live top-N only) | Partly (per-core bars, M5 super cores; wall watts on desktops) | Yes (plugin-gated sensors labelled) | No | No |
| System Monitor Panel | No (HUD widget strip) | No | No | No | No | Yes (helper gating explicit) | Partly (always-on-top panel is HUD-adjacent; no FPS) | No |
| Tempo | Partly (rings + charts, low metric count) | No | Partly (30 d @ 1/min, hover point values) | No | No | Yes (declines GPU/temp, shows thermal pressure) | No | No (top-10 list only) |
| Orcylo (pre-launch; advertised) | Partly (13 tabs of cards/charts) | No | Partly (30 d @ 1/min) | Partly (claims "which app slowed things down") | Partly (P/E counts; system + per-app watts, Wh) | Yes (e.g. "read only" fan) | No | Partly (dev-server/ports views) |
| MacStats (macstats.app) | Partly (menu bar + summary window) | No | Partly (24 h/7 d/30 d Pro) | Yes-ish (auto-recorded incidents name the process) | No | Yes (thermal-state-only stance, explains gaps) | No | Partly (AI explain; no files/ports) |
| MacStats (luizcastro) | Yes (per-metric panes + process table) | No | Partly (min/hour/day charts) | No | ? | ? | No | Partly (filter/sort process table) |
| XRG | Yes (graph-only strip window) | Partly (modules share scroll window) | No | No | No | No | No | No |
| TMOG | Yes (Summary/Performance lead) | Partly (per-graph compressed timelines) | Yes (Flight Recorder, Pro) | No | Partly (P/E grid, Power & Freq page) | Yes (the contract is the feature) | No | Yes (process inspector, connections) |
| Usage | No (popover + widgets) | No | Partly (history graphs, Pro; depth ?) | No | No | Partly (helper-gated; accuracy complaints) | No | No |

Reading the matrix: Vitals is the strongest incumbent (deepest history,
most surfaces), TMOG the deepest instrument (inspector, recorder) with
the worst skin, and System Dashboard Pro the best-tiled layout with no
memory. None of the reviewed apps combines a shared time axis, zoomable
history, and
attribution-in-time; that triple is open.

## Interaction references: trace analyzers and observability UIs

### Instruments (Apple)

- Trace document = timeline pane of horizontal tracks (one lane per
  instrument/subsystem) + detail pane + inspector pane; the WWDC26
  session showed a reworked timeline/detail layout with a new Inspector
  panel.
- Drag across the timeline to select a range and filter the detail
  pane: the canonical "selection re-aggregates the table" on macOS.
- Zoom: trackpad pinch, Option+scroll wheel, or Option/Control+drag
  across a section. Flags mark points of interest and are listed in a
  Flags palette for enable/disable.
- Track pinning exists: hover the left side of an instrument lane and
  pin/unpin it.
- Instrument > Previous Run / Next Run flips between recorded runs: a
  primitive baseline-vs-current comparison.
- Detail pane switches view per selected track (tables, call trees);
  extended detail shows stack traces for the selection.

### Perfetto UI

- Navigation: WASD cluster (W/S zoom, A/D pan), Shift+Drag pans,
  Ctrl+MouseWheel zooms; '?' shows the hotkey list; command palette
  (Cmd+Shift+P or '>' in the omnibox) exposes every action with its
  binding; Ctrl+P fuzzy-finds tracks.
- Selection model: click a slice for details in the tab drawer;
  '.' and ',' step through sibling slices; 'F' fits the selection to
  the viewport; 'R' converts a slice selection into an area selection
  spanning the slice's bounds; Esc clears.
- Area selection is the analytic primitive: drag creates a
  start/end/track-list selection; checkboxes on track shells include or
  exclude tracks; the selection feeds aggregation tabs (thread state,
  sched, slice/flamegraph) computed via SQL interval-intersection of
  the exact range. 'M' marks the current area on the timeline,
  Shift+M marks persistently; '[', ']' move between connected slices.
- Density control: pin tracks to a pinned area at the top of the
  workspace; named workspaces are saved track layouts you switch
  between; non-destructive track filters; collapse/expand/pin/copy
  tracks by regex via commands; debug tracks render arbitrary SQL query
  results as slices or counters on the timeline; timeline overlays let
  plugins draw cross-track annotations (e.g. waker arrows).
- Notes: plugins and commands add point notes and span notes (colored
  range highlights with text) directly on the timeline; the UX is
  still marker-level, and a feature request asks for richer
  collaborative annotation (open).
- Comparison: multiple files merge onto one shared timeline with a
  dialog choosing clock alignment or a baseline trace and per-machine
  grouping; a "Trace Comparison" tab is stubbed and the dedicated
  diff-view issue (google/perfetto#2780) is open, with third-party
  workarounds diffing area pivot tables.
- Deep linking: URL parameters (visStart/visEnd/ts etc.) encode
  viewport and selection so a link opens a trace at an exact moment.

### Windows Performance Analyzer

- Layout: Graph Explorer rail of thumbnail graphs dragged onto an
  Analysis tab; each view pairs a graph, a legend, and a data table.
  Display modes: graph only / table only / both.
- Selection semantics: zoom a graph to an interval and the table
  re-aggregates to only that interval; a bottom timeline applies to all
  graphs, and zooming one synchronizes every graph and table on the
  tab. CTRL+. zooms to the selected range; CTRL+SHIFT+. duplicates the
  whole view zoomed-in; CTRL+M highlights a range; CTRL+SHIFT+M clears
  it; '.' toggles whether selected table rows are drawn on the graph.
- Tables: a gold "pivot bar" separates group-by columns (left) from
  data columns (right); each column picks an aggregation (sum, avg,
  min, max, weighted avg, unique count) recomputed live as you expand
  groups, filter, or zoom. CTRL+E opens the View Editor; CTRL+P picks
  presets.
- Comparative analysis: open baseline and comparison traces, zoom each
  to its own region via a per-pane trace toggle, then the diff table
  shows comparison-minus-baseline values per row (e.g. which processes
  were more active in the comparison trace's window). This is
  selection-vs-baseline done in 2009-era Win32.
- Issues window: detected issues search filters the list and
  auto-zooms all graphs to the impacted intervals: diagnosis drives
  navigation.
- Shortcuts page (full list linked in Sources): CTRL+T/L/H focus table,
  legend, headers; F3/Shift+F3 find next/prev; Backspace returns to
  the previous analysis view (a navigation history).

### Chrome DevTools Performance panel

- Timeline overview: a minimap strip (CPU + NET charts) above the
  tracks used for range selection by dragging; auto-zooms to the
  busiest region on load.
- Zoom breadcrumbs: selecting a range and clicking its size button
  builds nested breadcrumb zoom levels across the top; click any crumb
  to return (minimum nestable range 5 ms); right-click removes child
  crumbs.
- Two scroll conventions are user-selectable: Classic (wheel zooms,
  Shift+wheel scrolls vertically) and Modern (wheel scrolls
  vertically, Shift+wheel horizontally, Cmd/Ctrl+wheel zooms); WASD
  pans/zooms; trackpad two-finger swipes navigate (up = zoom out,
  down = zoom in).
- Range selection re-aggregates: Call tree, Bottom-up and the Summary
  pane all show only the selected portion of the recording.
- Legibility kit for dense flame charts: Cmd+F regex search over
  activities with next/prev; ignore-list rules collapse matching
  scripts; "Dim 3rd parties" greys out third-party code; a hover on the
  overview draws a vertical marker across the whole trace (crosshair);
  an Insights tab links findings to the trace.
- Annotations (newer feature): double-click an item or Shift-drag a
  range to label it; connections can link two annotated items; an
  Annotations sidebar tab lists, edits, deletes and hides them;
  annotations save inside the trace file for sharing; Gemini can
  generate labels from stack traces.

### Grafana

- Time model: one dashboard time picker drives every panel; relative,
  absolute and semi-relative ranges; time range is URL state
  (?from=&to=), copyable between dashboards and Explore with t+c/t+v.
- Zoom/pan on time-series panels: click+drag horizontally zooms in
  (and changes the dashboard range); double-click zooms out by
  doubling the range symmetrically; dragging the x-axis pans; buttons
  and t+/t- mirror these.
- Shared cursor: dashboard setting "Cursor sync" (formerly Graph
  tooltip) offers Off / Shared crosshair / Shared tooltip; hovering one
  panel then draws the crosshair (and optionally the full tooltip) on
  every panel at the same timestamp. Shared crosshair is the default
  for new dashboards.
- Annotations: vertical lines/icons on all graph panels from
  query-driven annotation queries (deploy events, alert state) or
  created in-panel (click a point, or Cmd/Ctrl+click and drag for a
  region annotation); each query gets a color and a per-dashboard
  targeting (all panels / selected / all-except); annotation text can
  carry links to runbooks.
- Density: legend is an interactive control (hide/show series, change
  colors and axis assignment); rows and tabs group panels; kiosk mode
  and a content outline exist for large dashboards; per-panel
  shortcuts when hovering (e edit, v fullscreen); refresh scheduling is
  advised to not exceed pixel budget ("no need to refresh more often
  than the pixels available").

### Datadog

- Time model: dashboard-level time picker; widgets inherit the board's
  window. Refresh rate scales with timeframe (10 s for 1-minute windows
  up to hourly for month+).
- Full-screen graph mode: expanding a widget opens an exploratory view
  with a mini-map below the main graph showing longer history; click and
  drag on the mini-map to switch timeframe, zoom in/out on the fly;
  apply functions (anomaly detection, forecasting, outlier detection,
  cumulative sum, historical-timeseries overlay) without editing the
  original widget; save exploratory results as new graphs.
- Compare Time tab: pick an offset (Period/Day/Week/Month/Custom) and
  view the current window vs the offset window either overlaid on one
  graph or side-by-side in a grid: selection-vs-baseline as a product
  feature.
- Event overlays: query-driven event markers (deploys, GitHub commits,
  Docker events) drawn on the shared time axis; markers draw horizontal
  threshold lines/ranges; the last incomplete interval of a timeseries
  is shaded and labelled "partial data" (an honest-availability cue on
  the chart itself).
- Legibility caps: automatic peak/trough labels max out at three per
  series and vanish entirely past six series; a consistent 16-color
  palette maps tag values to stable colors across widgets; legends
  auto-display only at large dashboard sizes; tabs organize oversized
  dashboards; Cmd+C/Cmd+V copy widgets between dashboards.

### Cross-tool patterns worth stealing

- One shared time axis is assumed; every serious tool aligns all lanes
  and keeps a single cursor (Instruments, WPA, Grafana shared
  crosshair, DevTools' full-trace marker).
- Selection is the query: dragging a range re-aggregates every table
  (WPA tables, DevTools Bottom-up/Call tree, Perfetto area aggregations,
  Grafana re-query). Coreography's process list should re-rank to the
  selected window.
- Baseline comparison is a named mode, not a workflow: WPA comparative
  views, Datadog Compare Time, Instruments Previous/Next Run, Grafana
  query-time offsets. Perfetto's absence of trace diff is considered a
  hole even there.
- Minimap/overview strip as the zoom affordance (DevTools overview,
  Datadog mini-map, WPA bottom timeline) is the proven pattern for
  navigating long ranges.
- Annotations on the axis: Grafana region annotations, DevTools
  label/connection annotations saved in the trace, Perfetto notes/span
  notes, Instruments flags.
- Density management: pinned tracks (Perfetto, Instruments), workspaces
  (Perfetto), filtering that never destroys data, caps on labels and
  series (Datadog's 3-label/6-series rule), dimming over hiding
  (DevTools "Dim 3rd parties"), and a single full-screen/kiosk escape.

## Implications for Coreography

1. The competitive window is real and still open: Vitals proves Mac
   users pay for a monitoring window, but its history is coarse (hourly
   app ranks, no scrubbing) and its tabs silo the metrics. A shared
   axis with crosshair, zoomable history and per-window attribution
   leapfrogs every incumbent at once; nothing else is required to be
   new.
2. Steal the trace-UI grammar wholesale: minimap strip for zoom
   (DevTools/Datadog), drag-select that re-ranks the process table
   (WPA/Perfetto), pinned metric rows (Perfetto/Instruments), WASD +
   wheel-modifier navigation with a discoverable '?' cheat sheet,
   Esc-to-clear, 'F'-to-fit, and annotations on the shared axis
   (Grafana/DevTools) that persist with exported history.
3. Ship selection-vs-baseline early: "compare this spike against the
   same window yesterday" is a named feature in WPA and Datadog but
   absent in the reviewed Mac monitors; a two-range process-overlap table
   (which apps were over-represented in the bad window) is a concrete,
   buildable version.
4. Match the emerging honesty bar: Tempo's refusal to guess GPU/temps,
   Orcylo's advertised "read only" labels and plugin-gating disclosures
   from Sascha Simon and ImageTasks are now normal expectations; TMOG's
   measured/unavailable/restricted contract remains the target to beat.
   Datadog's shaded "partial data" interval is a small, copyable cue.
5. Price and packaging: one-time in the $15-25 band fits between Tempo
   ($14.99) and Vitals ($39 regular); a free tier is crowded
   (System Monitor Panel, Stats, MacStats OSS) so the window itself
   must justify payment; Mac App Store is optional only if sensors and
   process tools stay behind a separate download like the category's
   plugin pattern.
6. Power-user depth is uncontested locally: only TMOG ships a real
   inspector/connections view and none of the reviewed apps ships
   sampling or
   open-files/ports; pairing Activity Monitor's tool depth with the
   window (inspector drawer for files, ports, signals, sample) is a
   differentiator that costs no graph real estate.
7. Watch the indie churn: Vitals, Orcylo, Tempo, both MacStats and
   Unhogged all launched or were announced within a year and all
   converge on app-folding, top-N lists, local history and one-time
   pricing; differentiation by
   craft (typography, honest states) and by interaction depth (shared
   axis, scrubbing, compare) is the durable moat, not metric coverage.
8. Expect the AI surface to be table stakes soon: Vitals' MCP server
   and per-agent session tracking, MacStats' explanations and Orcylo's
   plan-limit widgets point the same direction; an API/CLI over
   Coreography's history file (Vitals already documents theirs) is
   cheap insurance.

## Sources

Part A - vendors and listings:

- [Vitals](https://vitalsmac.com/) - [changelog](https://vitalsmac.com/changelog) - [history feature](https://vitalsmac.com/features/history) - [pricing](https://vitalsmac.com/pricing)
- [Sensei](https://cindori.org/sensei/) - [MacUpdate version history](https://sensei.macupdate.com/) - [Cindori news](https://cindori.com/news) - [Macworld review](https://www.macworld.com/article/233898/sensei-review-gorgeous-mac-performance-utility-hamstrung-by-thunderbolt.html) - [MacStories review](https://www.macstories.net/stories/sensei-a-beautifully-designed-dashboard-and-set-of-utilities-for-your-mac/) - [The Sweet Setup review](https://thesweetsetup.com/sensei-an-all-in-one-mac-maintenance-dashboard/) - [9to5Mac launch coverage](https://9to5mac.com/2020/01/15/sensei-app-mac-improve-software-hardware-performance/)
- [iStatistica Pro product page](https://www.imagetasks.com/istatistica/pro/) - [App Store listing](https://apps.apple.com/us/app/istatistica-pro/id1447778660)
- [System Dashboard Pro](https://sascha-simon.com/apps/system-dashboard-pro) - [App Store listing](https://apps.apple.com/us/app/system-dashboard-pro/id1672838414)
- [System Monitor Panel](https://sascha-simon.com/apps/system-monitor-panel) - [App Store listing](https://apps.apple.com/us/app/system-monitor-panel/id1564320812)
- [GPU Monitor Pro](https://sascha-simon.com/apps/gpu-monitor-pro) - [System Watcher](https://sascha-simon.com/apps/system-watcher)
- [Tempo for Mac](https://tempoformac.com/)
- [Orcylo](https://orcylo.app/)
- [MacStats](https://macstats.app/) - [pricing](https://macstats.app/pricing) - [about](https://macstats.app/about) - [download/notarization note](https://macstats.app/download) - [support](https://macstats.app/support)
- [MacStats (open source)](https://macstats.luizcastro.dev/) - [luizhcastro/mac-stats repo](https://github.com/luizhcastro/mac-stats) - [raro42/mac-stats](https://github.com/raro42/mac-stats/blob/main/README.md)
- [XRG site](https://gaucho.software/xrg.html) - [XRG repo](https://github.com/mikepj/XRG) - [changelog](https://gaucho.software/pop-xrg-changelog.html) - [Washington Apple Pi review](https://www.wap.org/journal/xrg/) - [Low End Mac writeup](https://lowendmac.com/misc/05/0815.html)
- [TMOG release notes](https://tmog.org/rtm/release-notes.html) - [notes 06](06-tmog-task-manager-og.md)
- [Usage site](https://usage.pro/) - [App Store listing](https://apps.apple.com/us/app/usage-system-activity-monitor/id1561788435) - [iOS Dev Tools review](https://iosdev.tools/blog/usage/) - [MacSources review](https://macsources.com/usage-activity-monitor-for-apple-devices-review/)
- [Unhogged](https://unhogged.com/) - [Unhogged alternatives comparison](https://unhogged.com/alternatives/)
- [Hardware Monitor EOL notice](https://www.bresink.com/osx/HardwareMonitor.html)
- [tstats](https://tstats.app/) - [Better Mac Stats](https://github.com/ariwisnu/better-mac-stats/blob/main/README.md)

Part B - documentation and code:

- [Instruments Help Topics (Apple archive)](https://developer.apple.com/library/archive/documentation/AnalysisTools/Conceptual/instruments_help-collection/Chapter/Chapter.html)
- [Perfetto UI docs](https://perfetto.dev/docs/visualization/perfetto-ui) - [merging traces](https://perfetto.dev/docs/visualization/merging-traces) - [commands/automation reference](https://perfetto.dev/docs/visualization/commands-automation-reference) - [UI plugins (workspaces, notes, overlays)](https://perfetto.dev/docs/contributing/ui-plugins) - [selection.ts](https://github.com/google/perfetto/blob/e282e10b/ui/src/public/selection.ts) - [hotkeys-as-commands commit](https://github.com/google/perfetto/commit/217de072dd37844c37cbffbe63c8716615019ea4) - [trace-comparison issue](https://github.com/google/perfetto/issues/2780) - [annotation UX issue](https://github.com/google/perfetto/issues/6626) - [aggregation issue 6872](https://github.com/google/perfetto/issues/6872)
- [WPA overview](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-analyzer) - [data tables](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/data-tables) - [analysis tab](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/analysis-tab) - [keyboard shortcuts](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpa-keyboard-shortcuts) - [comparative analysis views](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/comparative-analysis-views) - [WPA table/graph configurations](https://devblogs.microsoft.com/performance-diagnostics/wpa-table-graph-configurations-part-1/)
- [DevTools Performance features reference](https://developer.chrome.com/docs/devtools/performance/reference) - [annotations](https://developer.chrome.com/docs/devtools/performance/annotations)
- [Grafana: use dashboards](https://grafana.com/docs/grafana/latest/dashboards/use-dashboards/) - [annotate visualizations](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/annotate-visualizations/) - [time series panel](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/time-series/) - [cursor sync setting](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/modify-dashboard-settings/) - [tooltips](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/configure-tooltips/) - [cursor-sync PR 78636](https://github.com/grafana/grafana/pull/78636)
- [Datadog dashboards](https://docs.datadoghq.com/dashboards/) - [timeseries widget](https://docs.datadoghq.com/dashboards/widgets/timeseries/) - [widgets](https://docs.datadoghq.com/dashboards/widgets/) - [full-screen graph mode](https://www.datadoghq.com/blog/full-screen-graphs/) - [getting started](https://docs.datadoghq.com/getting_started/dashboards/)

## Verification log

Independent fact-check pass, 2026-10-17. Scope: the four living
incumbents (Vitals, Tempo, Orcylo, macstats.app), TMOG's release state,
the OSS MacStats window claim, and internal consistency of the summary
against this file's own matrix and sections. The trace-UI sections
(Instruments, Perfetto, WPA, DevTools, Grafana, Datadog) were not
re-verified line by line; they cite primary docs and were consistent
with prior passes. This was a source review only; no apps were
installed and no claims were validated at runtime.

Confirmed against primary sources (fetched 2026-10-17):

- Vitals: v1.7.5 dated 2026-10-17 in its changelog; v1.6 (2026-10-11)
  added history up to a year (30 d/90 d/6 mo/1 y retention), the Peaks
  card on a 5-minute reading cadence, three-file CSV export; the
  history feature page confirms "the apps that used the most, ranked
  hour by hour" (for recent days) and range tabs 1 h/24 h/7 d/30 d/90 d/
  6 mo/1 y; v1.5 added the Neural Engine tab ("which apps are using
  it"), chart palettes, compact spacing, Float on Top, 5/15/30-minute
  charts; v1.7 added the Agents tab, AI-plan limits and tokens, and
  changed the GPU tab to show last-measured apps instead of
  "Measuring...". MCP server advertised in site nav.
- Tempo: site confirms 30 days of one-minute summaries in a local file,
  "hover any point to see exactly what happened", deliberate refusal of
  GPU/exact temperatures (no supported public API; shows thermal
  pressure instead), launch pricing $4.99/$9.99/$14.99, ~2% CPU / ~40 MB
  advertised, top-10 process list, notch island in v1.3, direct
  notarized sale outside the App Store for live process reads.
- Orcylo: confirmed pre-launch: "Coming soon" banner, launch pricing
  on sale (EUR 5/7.50/9.99 tiers), "1 licence sold" at fetch time, all
  demo values simulated per the site. 13 tabs, 30 d @ 1/min history and
  per-app watts are advertised, not shipped.
- TMOG: release notes confirm macOS remains on RTM 1.0.0 while Windows
  got the 1.0.1 hotfix. Flight Recorder scrub/replay detail rests on
  notes 06 (not re-verified this pass).
- macstats.app: confirms free + Pro $14.99 one-time, incidents that name
  a responsible process with readings across the incident window,
  session recording, 300/month AI explanations under Pro (process name
  + coarse metrics leave the Mac only for explanations), thermal-state-
  only honesty stance, ~1% CPU/65 MB claimed, macOS 13+ Apple silicon.
- luizhcastro/mac-stats README confirms a real main window with
  per-metric panes (incl. GPU, temperature, fans) and a filterable
  process table with 1m/1h/24h charts, so it is a graph window, not a
  popover.

Corrections applied in this pass:

- "Only three shipping tools attempt a real graph window" was wrong on
  this file's own evidence: XRG (dormant) and the OSS MacStats both ship
  graph-forward windows. Reworded to three commercial + two
  non-commercial, and removed "MacStats OSS" from the popover list.
- "Nobody scrubs" contradicted the TMOG row (Flight Recorder scrubs
  recorded captures) and Tempo's hover readout. Reworded to
  "live-history scrubbing is absent" with both exceptions named.
- Orcylo was grouped with shipped products in the summary; it is
  pre-launch (site banner, one licence sold, simulated demo). Marked
  pre-launch/advertised in the summary, matrix row and section.
- Vitals "Measuring..." claim was backwards: 1.7 made a reopened GPU
  tab show last-measured apps instead of the placeholder; corrected.
- AI-features bullet: Vitals reads more than Claude/Codex limits
  (Copilot, Cursor, Grok, Ollama, OpenCode per changelog); macstats.app
  Pro is one-time with a 300-explanations/month quota, not "one-time AI
  explanations".
- OSS MacStats: "~23 stars" updated to ~29; "(Cmd-0)" replaced with the
  documented window-icon affordance (shortcut unverified); "created
  2026-04" softened (month unverified); "76 MB" clarified as idle.
- Vitals Neural Engine row: per-app ANE table and memory-traffic figure
  labelled vendor-demo claims (attribution mechanism unpublished).
- Sensei absence claims re-hedged: site silence is not proof a feature
  is absent.

Remaining gaps:

- All Partly/No cells for Sensei, iStatistica Pro, Usage and System
  Monitor Panel rest on vendor sites, listings and reviews; no
  hands-on installs were performed; absence claims are weakest there.
- Vitals "hour by hour" app ranks are vendor copy; the demo shows the
  list but not the interaction (scrubbing unverified for the app).
- TMOG Flight Recorder detail is inherited from notes 06; not re-checked
  against the shipping build this pass.
- raro42/mac-stats, XRG's last-commit date, Sensei's current pricing and
  iStatistica's App Store review claims were not re-verified this pass.
- Orcylo's whole feature set is unproven until it ships; treat every
  Orcylo cell as marketing.
