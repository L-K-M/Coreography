# Activity Monitor and Apple tools (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

## Summary

- Activity Monitor is broadly unchanged in structure for over a decade: one window, five tabs (CPU, Memory, Energy, Disk, Network, plus a conditional Cache tab), a process table, and a small fixed summary strip of graphs at the bottom. The macOS 27 Golden Gate user guide documents the same feature set as earlier editions. It is the baseline Coreography must exceed, and it is weak: 5 s default refresh (faster menu options of 1 s/2 s per third-party guides; Apple documents only the 5 s default), tiny non-interactive graphs, no thermal/GPU/battery health depth, no history beyond the visible strip.
- Its best single idea is Memory Pressure: a composite green/yellow/red health signal from free memory, swap rate, wired, and file-cached pages. Second best: Energy Impact plus "12 hr Power" as a trailing average.
- Documented accuracy problems on Apple Silicon: Energy Impact does not correctly price P-core vs E-core work, per-core load reporting is misleading because it ignores frequency scaling (active residency is not throughput), and users report Network "Data sent/sec" values inflated vs actual link rate. A monitor that wants power users' trust must do better.
- Activity Monitor has a reported observer effect (anecdotal forum measurements, not a documented behavior): WindowServer CPU rising from 7-11% to 20-40% while it is open, and refresh degrading toward ~30 s under load.
- Instruments 27 (Xcode 27 era) is where Apple's real visual design for time-series lives: multi-track timelines, lanes per subsystem, drag-to-select ranges, pinch zoom, per-instrument strategy bars. Newer instruments: Power Profiler, CPU Counters with presets, Processor Trace (M4+), Swift Concurrency, Game Performance Overview.
- `powermetrics` (root) is the source of truth for power/thermal on Apple Silicon: per-cluster frequency, active residency, CPU/GPU/ANE watts (explicitly "estimated"), thermal pressure, SFI throttling, per-process energy impact. Its own disclaimer says power values are estimates not comparable across devices.
- Metal Performance HUD is Apple's only true overlay UI: configurable metrics (FPS, frame interval, GPU time, memory, thermal, disk, shader compiles), presets, charts inside the overlay, insights that flag issues, enabled for ANY Metal app via env var/defaults. `metalperftrace` (new in macOS 27) records look-back traces for hours or days, saved as .atrc for Instruments.
- Game Mode (Sonoma 14+): exclusive E-core access plus top CPU/GPU priority for a full-screen game, 2x Bluetooth sampling for input/audio latency; Tahoe adds the Game Overlay panel (Cmd-Esc).
- System Settings owns two good historical visualizations Coreography should absorb: Battery (24 h battery-level line with charging shading + screen-on bars; 10-day energy-per-day bars; Tahoe redesigned with per-app consumption) and Storage (hoverable segmented stacked bar by category, All Volumes variant).
- The CLI toolbox (top, vm_stat/meminfo, fs_usage, nettop, iostat, footprint, sample, spindump, powermetrics, memory_pressure) exposes far richer data than Activity Monitor surfaces: per-cluster frequencies, syscall counts, boosts, jetsam priority, compressor counters, microstackshots. Coreography's power-user layer should map to these.

## Tools

### Activity Monitor

**Status**

- Ships with macOS at `/Applications/Utilities/Activity Monitor.app`; free, closed-source. Apple publishes a per-version user guide; editions exist for macOS 26 Tahoe and 27 Golden Gate. The documented feature set in the 27 guide is identical in structure to earlier releases (same tabs, same panels, same menus). One reported Tahoe change: a more compact toolbar that collapses when the window is narrow (third-party blog, lower confidence). No new metrics, tabs, or graph capabilities are documented for 26 or 27.

**What it shows**

- Window layout: tab bar (CPU, Memory, Energy, Disk, Network), process table in the middle, fixed summary strip at the bottom with the tab's graphs and counters, search field, toolbar (Stop, Info "i", diagnostics "..." menu). A sixth Cache tab appears only when Content Caching is on (System Settings > General > Sharing), and reportedly requires an Activity Monitor relaunch to appear (unverified; the Apple guide does not mention a relaunch).
- CPU tab columns (View > Columns; default set per macOS Support Essentials): Process Name, % CPU, CPU Time, Threads, Idle Wake Ups, Kind (Apple vs Intel architecture), % GPU, GPU Time, PID, User. Opt-in columns reported by third-party guides: Sandbox, Restricted, App Nap, Sudden Termination, Preventing Sleep, Requires High Perf GPU.
- CPU bottom panel: System %, User %, Idle %, a scrolling CPU Load history graph, and process/thread totals.
- Memory tab columns include Real Memory, Compressed (VM Compressed per-app in the guide's description). Bottom panel: Memory Pressure timeline graph; Physical Memory; Memory Used = App Memory + Wired Memory + Compressed; Cached Files; Swap Used.
- Energy tab columns: Energy Impact (current relative score, lower better), 12 hr Power (average energy impact over last 12 h or since boot; laptops only), App Nap (Yes/No), Graphics Card (whether the app requires the high-performance GPU; multi-GPU Macs only), Preventing Sleep, User.
- Energy bottom panel (desktops): Energy Impact history graph. Laptops add: Remaining charge %, Time until full / Time on AC (plugged in), Time remaining / Time on battery (unplugged), and a "Battery (Last 12 hours)" charge-level graph. Multi-GPU Macs show which card is active.
- Disk bottom panel: Reads in/sec, Writes in/sec, Data read/sec, Data written/sec, cumulative Data read / Data written. Graph can plot IO (ops/sec) or Data throughput.
- Network bottom panel: Packets in/out totals, Packets in/sec and Packets out/sec, Data received/sent totals, Data received/sec and Data sent/sec. A pop-up above the graph chooses Packets or Data; the same selection drives the Dock icon graph.
- Cache tab (Content Caching): Data Served, Data Served From Cache, Data Dropped, Data Served From Origin / From Parents / From Peers, Data Served To Children / To Clients / To Peers, Data Uploaded, Maximum Cache Pressure (Apple: above 50% means add space/caches). A bottom pop-up selects the time period.
- Inspect window (double-click a process or "i" toolbar button): tabs Memory, Statistics, Open Files and Ports. Statistics reportedly shows threads, Mach ports, context switches, page faults, page-ins, Mach and UNIX syscall counts, and CPU time (exact field list unverified). Open Files and Ports lists open file paths and sockets (lsof-like). Buttons on the window: Sample, Quit / Force Quit.
- Diagnostics menu: Sample Process (3-second stack-sampling report), Spindump (system-wide report used for unresponsive/force-quit apps), System Diagnostics (aggregates logs into a sysdiagnose bundle), Spotlight Diagnostics.
- Window menu extras: CPU Usage (floating window, vertical bar per core), CPU History (one scrolling strip per core), GPU History (one strip per GPU; per Apple's guide it becomes Afterburner History when an Afterburner graphics card is connected).
- View menu filters: All Processes; All Processes, Hierarchically (parent/child disclosure tree); My Processes; System Processes; Other User Processes; Active Processes; Inactive Processes; GPU Processes; Windowed Processes; Selected Processes; Applications in last 12 hours; Processes, by GPU.
- View > Update Frequency: default every 5 s per Apple's guide, faster options documented as "more precise monitoring" (menu values of 1 s/2 s appear in third-party guides, unverified from Apple); Apple warns faster updates affect system performance and suggests watching its own CPU Time column.
- View > Dock Icon: Show CPU Usage, Show CPU History, Show Network Usage, Show Disk Activity, plus the plain Application Icon. (Some third-party lists also mention a Show Memory Usage mode; unverified.)
- Actions: Stop button offers Quit (graceful, same as File > Quit) or Force Quit (immediate, may lose data); View > Send Signal to Process sends an arbitrary signal. Unresponsive processes are labelled "(Not Responding)" and drawn in red.

**How it shows it**

- Bottom graphs are small fixed-height monochrome/minimal area or line charts that scroll right-to-left: green Memory Pressure strip (the only color-coded one), CPU Load, Energy Impact, a battery-level line for the last 12 h, blue GPU History bars, IO and network history lines. Scales auto-rescale silently; there are no axes you can interrogate, no hover values, no selectable range.
- CPU Usage floating window: one vertical bar per logical core. CPU History: one horizontal strip per core. On multi-cluster chips, strips simply enumerate cores.
- The Dock icon is a live miniature of the chosen graph.
- The table is a plain NSTableView: sortable columns, disclosure triangles in hierarchical mode, red "(Not Responding)".

**Ideas worth taking**

- Memory Pressure as one composite, color-coded health number: green/yellow/red computed from free memory, swap rate, wired, file-cached. Users understand a traffic light.
- Paired instantaneous + trailing metrics: Energy Impact (now) vs 12 hr Power (12 h average); Packets vs Data toggle reusing one graph surface.
- Surfaces beyond the main window: Dock icon live graph, floating CPU Usage, per-core CPU History, GPU History. Users clearly want ambient/always-visible graphs.
- "All Processes, Hierarchically" and "Processes, by GPU": process grouping as a first-class view.
- Diagnostic capture built into the monitor (Sample, Spindump, System Diagnostics) rather than a separate tool.

**Weaknesses / avoid**

- Coarse sampling: 5 s default, ~1 s floor, and reportedly degrading toward ~30 s under system load. A "live" monitor needs 250 ms-1 s.
- Observer effect: opening it measurably raises WindowServer CPU (reports of 7-11% to 20-40%); Apple itself warns its update loop costs CPU.
- Apple Silicon inaccuracy: Energy Impact mis-prices P vs E cores; per-core % reflects active residency without frequency, so "equal bars" can mean very different throughput; Network "Data sent/sec" reported doubled/inflated vs actual link throughput (forum measurements).
- Graphs are decorative, not analytical: no hover/crosshair, no min/max/avg readouts, no zoom, no time-range selection, no export, no correlation between tabs.
- Gaps: no GPU tab in the main window (GPU lives only in a floating window + % GPU columns), no temperatures/fans/thermal pressure, no per-cluster P/E visualization, no per-process network connections, no frequency data.
- Semantic confusion: Energy Impact is an undocumented relative score; users routinely misread "Cached Files"/"Memory Used" as a problem; "12 hr Power" vs "Energy Impact" distinction is not explained in-app.

**Sources**

- [Activity Monitor User Guide (welcome, version picker for macOS 26/27)](https://support.apple.com/guide/activity-monitor/welcome/mac)
- [View information about processes (macOS 27)](https://support.apple.com/guide/activity-monitor/view-information-about-processes-actmntr1001/10.14/mac/27)
- [View CPU activity (macOS 27)](https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/10.14/mac/27)
- [View GPU activity (macOS 27)](https://support.apple.com/guide/activity-monitor/view-gpu-activity-actm9329b315/10.14/mac/27)
- [View memory usage (macOS 27)](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/10.14/mac/27)
- [View energy consumption (macOS 27)](https://support.apple.com/guide/activity-monitor/view-energy-consumption-actmntr43697/10.14/mac/27)
- [View disk activity (macOS 27)](https://support.apple.com/guide/activity-monitor/view-disk-activity-actmntr1005/10.14/mac/27)
- [View network activity (macOS 27)](https://support.apple.com/guide/activity-monitor/view-network-activity-actmntr1006/10.14/mac/27)
- [View cache activity (macOS 27)](https://support.apple.com/guide/activity-monitor/view-cache-activity-actmcdbbd395/10.14/mac/27)
- [Run system diagnostics (macOS 27)](https://support.apple.com/guide/activity-monitor/run-system-diagnostics-actmntr2225/10.14/mac/27)
- [Quit an app or process (macOS 27)](https://support.apple.com/guide/activity-monitor/quit-a-process-actmntr1002/10.14/mac/27)
- [Update frequency (macOS 27)](https://support.apple.com/guide/activity-monitor/change-how-often-information-is-updated-actmntr2224/10.14/mac/27)
- [Check if your Mac needs more RAM (memory pressure colors)](https://support.apple.com/guide/activity-monitor/check-if-your-mac-needs-more-ram-actmntr34865/10.14/mac/27)
- [OWC: Using Activity Monitor, part 1 (columns and bottom-panel list)](https://eshop.macsales.com/blog/58102-using-activity-monitor-part-1-cpu-and-memory/)
- [cloudstreet-dev guide: columns, hidden columns, inspect window](https://cloudstreet-dev.github.io/macOS-and-Unix/part12-performance/activity-monitor.html)
- [AppleInsider: Activity Monitor wrong about Apple Silicon energy](https://appleinsider.com/articles/22/05/03/activity-monitor-in-macos-is-wrong-about-energy-usage-of-apple-silicon)
- [Eclectic Light: Don't trust Activity Monitor on M1 Macs (primary source for the energy claim)](https://eclecticlight.co/2022/05/02/dont-trust-activity-monitor-on-m1-macs/)
- [HN: observer effect, WindowServer spike, ~30 s updates under load](https://news.ycombinator.com/item?id=25401681)
- [HN: energy numbers are estimates, discussion](https://news.ycombinator.com/item?id=31233157)
- [MacRumors forums: network "Data sent" inflation](https://forums.macrumors.com/threads/activity-monitor-network-wrong-data-sent-calculation.2196324/)
- [Eclectic Light: Game Mode CPU/GPU measurement; residency-vs-frequency caveat](https://eclecticlight.co/2023/10/18/how-game-mode-manages-cpu-and-gpu/)
- [mac-dvd: Tahoe-era Activity Monitor notes, compact toolbar claim](https://mac-dvd.com/blog/mac-activity-monitor/)
- [AppleInsider: Electron/Liquid Glass WindowServer slowdown, fix releases](https://appleinsider.com/articles/25/10/10/update-your-slack-discord-clients-the-electron-tahoe-gpu-slowdown-bug-is-fixed)
- [Apple Energy Efficiency Guide: Energy columns (Preventing Sleep, App Nap, Avg Energy Impact)](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/MonitoringEnergyUsage.html)

### Instruments

**Status**

- Free, ships inside Xcode (developer tool, not in /Applications/Utilities). Current generation is "Instruments 27" per the WWDC26 session "Profile, fix, and verify" (Xcode 27 / macOS 27 era). Actively developed: Xcode 26-era additions include Power Profiler, CPU Counters presets, Processor Trace (M4 Macs, iPhone 16) and the Swift Concurrency instrument (its introduction version is unverified; it is present in Instruments 27); the WWDC26 session shows Instruments 27's reworked timeline/detail layout with a new Inspector panel. CLI recording via `xcrun xctrace`.

**What it shows**

- Template library (built-in templates as listed by cargo-instruments/Xcode): Activity Monitor, Allocations, Animation Hitches, App Launch, Audio System Trace, CPU Counters, CPU Profiler, Core ML, Data Persistence, File Activity, Game Memory, Game Performance, Game Performance Overview, Leaks, Logging, Metal System Trace, Network, Power Profiler, Processor Trace, RealityKit Trace, Swift Concurrency, SwiftUI, System Trace, Tailspin, Time Profiler.
- Time Profiler: low-overhead time-based sampling of processes running on the system's CPUs; per-core and per-thread tracks; call-tree detail (heaviest stack trace, invert call tree, hide system libraries, separate by thread).
- System Trace: puts the kernel in a tracing mode recording scheduling activity, system calls, VM operations; windowed mode retains roughly the last 5 s by default; "Trace Highlights" summary graphs; Points of Interest track for signposts.
- CPU Counters: hardware performance counters (cycles, instructions, cache events, stalls), presets such as "CPU Bottlenecks".
- Processor Trace (new, M4/iPhone 16+): logs every branch and call for instruction-level replay.
- Power Profiler (Xcode 26): system power usage as fraction of battery capacity consumed per hour; lanes for charging state, thermal state, display brightness, SoC sleep/wake; per-app lanes for power impact of CPU, GPU, display, networking. Available on iPhone iOS 26+ and iPad iPadOS 26+ for device recording (unverified for direct Mac profiling; the doc describes recording device traces and correlating with other instruments). Metric values explicitly not comparable across device models.
- Metal System Trace / Game Performance Overview: parallel CPU and GPU work timelines, memory usage, per-frame performance statistics, shader compile info; pair with `metalperftrace` .atrc files (macOS 27) or Game Performance template recordings.
- `xctrace`: `xcrun xctrace record --template "Time Profiler" --output out.trace --time-limit 30s`; templates listable via CLI.

**How it shows it**

- Trace document: three panes. Timeline pane up top with horizontal tracks (one lane per instrument/subsystem: cores, threads, actors/executors for Swift Concurrency, CPU/GPU/display/networking for Power Profiler); detail pane below switching per selected track (tables, call trees); new Inspector panel on the right surfacing selection details and actions.
- Interactions: record/pause/stop in toolbar; drag across the timeline to select a time range and filter the detail pane; pinch or Option-drag to zoom; playhead with inspection flags summarizing each instrument at that time; extended detail shows stack traces.
- Thread-state lanes in System Trace are color-coded scheduling states (running, runnable, blocked, idle) with a strategy control bar (Instruments vs Threads strategies) and a legend button.

**Ideas worth taking**

- Multi-lane timeline where each lane is a subsystem and selecting a range filters all detail views. This is the strongest precedent for Coreography's "one window, many live graphs".
- Windowed mode (retain last N seconds of high-frequency kernel data) maps to a rolling live buffer.
- Points of Interest / signpost lanes: user-annotatable event marks on a metrics timeline.
- Power Profiler's lanes-per-subsystem decomposition (CPU/GPU/display/network) of one "power" figure.

**Weaknesses / avoid**

- Developer tool ergonomics: heavyweight, profiling runs rather than ambient monitoring, overwhelming for consumers. Not a model for default UX, only for a power-user layer.
- Some instruments are device/SoC gated (Processor Trace needs M4+; Power Profiler documented for iPhone/iPad).

**Sources**

- [Instruments Help Topics (trace document, timeline/detail/inspector panes, zoom, range filter)](https://developer.apple.com/library/archive/documentation/AnalysisTools/Conceptual/instruments_help-collection/Chapter/Chapter.html)
- [WWDC26: Profile, fix, and verify (Instruments 27, new Inspector, Swift Concurrency)](https://developer.apple.com/videos/play/wwdc2026/268/)
- [Apple docs: Measuring your app's power use with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
- [Apple docs: Addressing CPU bottlenecks (CPU Counters)](https://developer.apple.com/documentation/xcode/addressing-cpu-bottlenecks)
- [WWDC16: System Trace in depth (windowed mode ~5 s, kdebug signposts, threads strategy)](https://developer.apple.com/videos/play/wwdc2016/411/)
- [cargo-instruments README: built-in template list, xctrace usage](https://github.com/cmyr/cargo-instruments)
- [WWDC25 new dev tools overview: CPU Counters presets, Processor Trace on M4/iPhone 16](https://yaacoub.github.io/articles/swift-tip/get-familiar-with-your-new-development-tools-wwdc25/)

### powermetrics

**Status**

- Built into macOS, requires root (`sudo`). Maintained: modern builds add Apple Silicon samplers (per-cluster frequency, ANE power, GPU active residency, SFI classes). Text or plist output; default sample interval 5000 ms, configurable with `-i`; `-n` sample count; `-f plist` for machine-readable output.

**What it shows**

- Sampler groups (`-s`): tasks (per-process CPU time user/kernel, short-timer counts, interrupt wakeups, package idle exits, DEAD_TASKS row for exited processes), battery (discharge rate, charge level, cycle count, backlight), network, disk, int_sources and interrupts (per-CPU interrupt vectors by device: ARPT, ETH0, HDAU...), cpu_power (package/core/GT watts on Intel; on Apple Silicon per-cluster frequency + active residency + power), gpu_power (GPU frequency, active residency, software P-state distribution), ane_power, thermal (thermal pressure level), smc (fan rpm, temperature sensors), sfi (Selective Forced Idle throttling per class), devices (per-device L/U/O power-state residency).
- Flags: `--show-process-energy` (per-process energy impact number), `--show-process-coalition` (group XPC child processes under the parent app, billing dead tasks), `--show-process-gpu`, `--show-process-io`, `--show-process-netstats`, `--show-process-ipc` (ARM instructions/cycles), `--show-pstates`, `--show-plimits` (forced idle, power limits, RMBS), `--show-process-wait-times`, `--show-responsible-pid`.
- Apple documents per-cluster behavior: all cores in a cluster share one frequency; "active residency" alone is not throughput.

**How it shows it**

- Plain-text periodic reports (wide tables) or plist. No visuals: this is a data source, not a UI.

**Ideas worth taking**

- The metric vocabulary Coreography should surface: per-cluster frequency AND residency (so E vs P clusters read correctly), package idle exits (explains "wake-up cost"), thermal pressure, SFI throttling, per-process energy with coalition grouping so helpers bill to their parent app.
- Apple's own caveat worth surfacing in UI: reported power is an estimate, useful for app optimization, not cross-device comparison.

**Weaknesses / avoid**

- Root requirement complicates a sandboxed/MAS-style product; wide text output is unreadable for mortals; instantaneous SFI/thermal values are end-of-window snapshots.

**Sources**

- [powermetrics command reference (ss64)](https://ss64.com/mac/powermetrics.html)
- [powermetrics(1) man page mirror](https://manp.gs/mac/1/powermetrics)
- [Firefox docs on powermetrics usage patterns](https://firefox-source-docs.mozilla.org/performance/powermetrics.html)
- [Eclectic Light: reading Game Mode via powermetrics clusters/residency/frequency](https://eclecticlight.co/2023/10/18/how-game-mode-manages-cpu-and-gpu/)

### Metal Performance HUD

**Status**

- Built into macOS (Metal framework-level feature; developer-oriented but functional for any user who enables it). Expanded in recent releases: metric presets and a configuration panel (WWDC26-era docs), performance "insights" overlays, and the `metalperftrace` CLI in macOS 27 for look-back recording.

**What it shows**

- Metrics catalogue (`MTL_HUD_ELEMENTS`): device name, Rosetta indicator, layer size/composition and scale/pixel format, memory (process footprint + `MTLDevice.currentAllocatedSize`), thermal state, screen refresh rate, Game Mode state, FPS (rolling average over last 120 frames), FPS graph, frame interval, frame interval graph, frame interval histogram (buckets sized to refresh rate), GPU time (rolling 120-frame average from command-buffer gpuStartTime/gpuEndTime), present delay, Metal CPU encode time, GPU timeline (encoder durations for last ~3 frames), shader compiler activity (pipeline states, cached/compiled shader counts, compile-time graph), disk usage bytes, frame number, top labeled command buffers and encoders. MetalFX-specific metrics appear only when MetalFX is in use.
- Original layout per Apple's Tech Talk: top-right overlay; resolution/scaling line; columns of instantaneous FPS, frame interval (ms), GPU time (ms) plus lowest/highest over the last ~1.5 s; bottom section with process and GPU memory plus a dual-line graph of present interval vs GPU time.
- Insights mode (`MTL_HUD_INSIGHTS_ENABLED=1` or config panel): analyzes Metal API call patterns per frame; if a flagged pattern appears in at least half the frames over an interval (default 5 s), an insight overlay appears naming the issue (e.g. excessive encoders, encoder-splitting blit copies, blocking shader compiles, CPU-bound encoding) with doc links. GPTk-specific insights only in the Game Porting Toolkit evaluation environment.
- Presets: Default, FPS Only, Rich, Full (per Japanese coverage of WWDC26; selectable via Metal HUD menu "Metric Presets", Shift-F10 cycles, Shift-F12 opens the configuration panel; triple-clicking the HUD also opens it).

**How it shows it**

- True overlay drawn on top of the app: small translucent panel, configurable opacity/scale (`MTL_HUD_OPACITY`, `MTL_HUD_SCALE` default 0.2 of drawable width, min 300 px), 9-way alignment (`MTL_HUD_ALIGNMENT`, default topright). A Metal HUD menu appears in the app's menu bar when enabled. Reports: `MTL_HUD_REPORT_URL` writes performance reports including a frame encoding table.
- Enable paths (any Metal app, not just games): Xcode scheme Diagnostics "Show Graphics Overview"/"Log Graphics Overview"; env `MTL_HUD_ENABLED=1` (session-wide via `launchctl setenv MTL_HUD_ENABLED 1`); user default `MetalForceHudEnabled` (per-app or `-g` global); Info.plist `MetalHUDEnabled`; `CAMetalLayer.developerHUDProperties` programmatically. `MTL_HUD_LOGGING_ENABLED=1` logs per-frame stats to the system log (name per Apple's 2023 Tech Talk; the current "Customizing the Metal Performance HUD" doc spells it `MTL_HUD_LOG_ENABLED`). Confirmed working on macOS 26 Tahoe (forum users on 26.0.1).
- Related: Game Overlay (macOS 26+ Tahoe) is a separate panel opened with Cmd-Esc or the Game menu-bar icon: game achievements, friends/chat, brightness, volume, controller settings, and the Game Mode toggle. It is not a metrics HUD.

**Ideas worth taking**

- Proves Apple will ship a proper always-on-top metrics overlay; user-togglable metric list + presets (Default/FPS Only/Rich/Full) is exactly the progressive-disclosure model Coreography wants.
- Histogram of frame intervals bucketed by refresh rate: a good pattern for "how smooth" questions.
- Insights: automated "we noticed X" callouts on top of raw metrics.

**Weaknesses / avoid**

- Hidden by design: no user-facing switch; requires Terminal/defaults/env or Xcode. Triple-click discovery is undiscoverable.
- Metal-only metrics vocabulary: no general CPU/network/thermal system view; per-app, not per-system.
- HUD covers the app it measures; not a standalone monitoring surface.

**Sources**

- [Apple docs: Understanding the Metal Performance HUD metrics (full metric list)](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics)
- [Apple docs: Customizing the Metal Performance HUD (menu, config panel, env vars)](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud)
- [Apple docs: Gaining performance insights with the Metal Performance HUD](https://developer.apple.com/documentation/xcode/gaining-performance-insights-with-metal-performance-hud)
- [Tech Talk: Discover Metal Performance HUD (layout, columns, enable paths)](https://developer.apple.com/videos/play/tech-talks/110339/)
- [WWDC26: Find and fix performance issues in Metal games (HUD insights, presets, metalperftrace)](https://developer.apple.com/videos/play/wwdc2026/388/)
- [MacRumors forum: enabling on Tahoe via launchctl](https://forums.macrumors.com/threads/silly-question-about-the-metal-hud.2468560/)
- [AAPL Ch. (JP): presets Default/FPS Only/Rich/Full, Shift-F10/F12 shortcuts, works on any Metal app](https://applech2.com/archives/20260707-metal-performance-hud-customize.html)
- [MetalHUDmenu (GitHub): third-party wrapper proving settings are env-var driven](https://github.com/Jfishin/MetalHUDmenu)
- [myByways: enabling via env var / launchctl / xbar](https://mybyways.com/blog/enabling-the-macos-metal-performance-hud/)

### metalperftrace

**Status**

- New command-line tool in macOS 27 Golden Gate (per WWDC26). Also covered on Apple's Metal developer tools page alongside the Metal debugger and Metal System Trace.

**What it shows / how it shows it**

- `metalperftrace collect <dir> --last 5h` collects look-back traces covering hours to days with no prior configuration, writing `.atrc` files; `--start`/`--end` for explicit ranges. `metalperftrace overview <file>` prints aggregated per-process performance summaries; JSON output and per-process filtering for automation. Traces include aggregated and per-frame CPU, GPU, FPS, memory, shader compilation, and (with the new StateReporting API) game-defined state markers. Open .atrc in Instruments for the visual timeline; anomalous values are highlighted with recomputed min/max/avg/stddev.
- iOS counterpart: Developer settings > Performance Trace + a Control Center toggle; up to 10 h collection; files shared as .aar that expand to .atrc.
- Sibling Metal CLIs on the same tools page (new, "built for scripts and agentic workflows"): `gpucapture` attaches to a running process to capture a Metal workload on demand; `gpudebug` debugs/profiles captures from the command line.

**Ideas worth taking**

- Always-on low-overhead circular buffer ("look back N hours") is a genuinely new Apple capability worth emulating for system metrics generally: the incident has already happened, so retroactive capture matters.
- Print + machine-readable + GUI-openable artifact (.atrc) is the right triple interface for a power tool.

**Weaknesses / avoid**

- Metal/game-session scoped only; not a general system recorder.

**Sources**

- [WWDC26 session 388](https://developer.apple.com/videos/play/wwdc2026/388/)
- [Metal Developer Tools](https://developer.apple.com/metal/tools/)
- [WWDC26 388 transcript summary](https://wwdc.ai/2026/388)

### Game Mode

**Status**

- macOS Sonoma 14+ on Apple Silicon; still current in macOS 26/27. No cost. Managed automatically; manual override per game.

**What it shows**

- It is a scheduling/latency feature, not a monitor. When a recognized game enters macOS full-screen mode, `gamepolicyd` launches and, with RunningBoard, gives the game exclusive use of the efficiency cores and highest-priority CPU/GPU access; background tasks lose priority (low-QoS threads that must run on E cores are held off entirely until Game Mode exits, measured on M1 Max). Bluetooth sampling rate doubles for controllers and AirPods audio latency. A Game menu-bar icon/menu shows Game Mode on; quitting or leaving full screen disables it; per-game off state persists.
- macOS 26 Tahoe: controlled via Game Overlay (Cmd-Esc, or the Game menu-bar icon) > Settings > Game Mode; the Games app launched with Tahoe hosts the social/overlay features.
- Internals (unverified details beyond Eclectic Light's measured analysis): whitelist of "Game Mode Critical Services"; recognition logic beyond app category is opaque.

**How it shows it**

- A brief notification + menu-bar game controller icon when engaged; overlay panel in Tahoe.

**Ideas worth taking**

- A workload-aware performance mode as a visible, user-toggleable state. Coreography could surface Game Mode as a signal on the CPU/GPU graphs (the Metal HUD already reports it).

**Weaknesses / avoid**

- Opaque activation criteria frustrate users (forum threads: same-category games don't trigger it); Game Overlay reportedly only reachable for games launched through the Games app for some users (Apple Discussions).

**Sources**

- [Apple Support: Use Game Mode (incl. Tahoe Game Overlay steps)](https://support.apple.com/en-us/105118)
- [Eclectic Light: what Game Mode does to CPU/GPU](https://eclecticlight.co/2023/10/18/how-game-mode-manages-cpu-and-gpu/)
- [Eclectic Light: what Game Mode does](https://eclecticlight.co/2023/10/17/what-does-game-mode-do/)
- [MacRumors forums: what triggers Game Mode; gamepolicyd/RunningBoard](https://forums.macrumors.com/threads/sonoma-game-mode-what-triggers-is.2403022/)
- [MacMost: Game Overlay contents (achievements, friends, brightness, controllers, Game Mode)](https://macmost.com/new-small-and-hidden-features-in-macos-tahoe.html)
- [Apple Discussions: Game Overlay not opening outside Games app](https://discussions.apple.com/thread/256157905)

### Console

**Status**

- Built into macOS (`/Applications/Utilities/Console.app`). Actively maintained as the unified log (os_log) viewer. macOS 27 guide current.

**What it shows**

- Live unified-log stream for the Mac plus connected devices (iPhone, iPad, Watch, Apple TV, simulators appear in the sidebar when attached). Log-message types (default, info, debug, error, fault), columns like Time, Type, Process, PID, Thread, Subsystem, Category, message text. Activities view groups messages by activity with child-activity expansion. Reports sidebar: crash reports, spin reports, diagnostic reports, log archives (.logarchive), plus system.log-era files.
- Search with property filters; saved searches pinned to a Favorites bar (built-ins: All Messages, Errors and Faults). Now button pins the view to the latest messages; Clear/Reload; info/debug messages excluded by default in live stream (Action > Include Info/Debug Messages), auto-included in archives.
- Companion CLI: `log stream` (live, with predicates and `--level`), `log show` (archives/time ranges), `log collect` (build a .logarchive), `log stats`, `log config`.

**How it shows it**

- Table-centric: dense monospaced rows, severity color hints, bottom detail pane for the selected message, left sidebar for devices/reports. Effective for forensics, hostile for "health at a glance".

**Ideas worth taking**

- Saved-search favorites bar = reusable filters; activity grouping = cheap causality.
- Per-device log attachment shows the system-level data plumbing Coreography could reuse (os_activity correlation of work across processes).

**Weaknesses / avoid**

- Firehose UI: thousands of rows/s, no aggregation, no charts. The complaint worth noting: it answers "what happened" but never "how busy".

**Sources**

- [Console User Guide](https://support.apple.com/guide/console/welcome/mac)
- [Activities view](https://support.apple.com/guide/console/activities-cnsl6df527d3/1.1/mac/10.14)
- [Customize the log window (Now mode, info/debug toggles, saved searches)](https://support.apple.com/guide/console/customize-the-log-window-cnsl35710/mac)
- [Keyboard shortcuts](https://support.apple.com/guide/console/keyboard-shortcuts-cnsl99a72ebe/mac)

### System Information

**Status**

- Built into macOS (`/Applications/Utilities/System Information.app`, the old System Profiler). Opened via Apple menu > System Settings > General > About > System Report, or Option + Apple menu > System Information. CLI twin: `system_profiler` (the app and tool share data; `system_profiler SPHardwareDataType` etc.).

**What it shows**

- A static system report: Hardware section (Hardware Overview: model, chip, core counts incl. E/P split, memory, serial; subsections for Storage/NVMExpress SMART status, USB, Thunderbolt, Bluetooth incl. per-device details and battery levels, Power with battery health + cycle count, Accessibility, Diagnostics results), Network (interfaces, Wi-Fi details, Firewall, Locations, Volumes), Software (system version, installed apps with versions/obtained-from/signing, extensions, fonts, logs, sync).
- File > Show More/Less Information, Save, Print, Send to Apple.

**How it shows it**

- Classic outline: left source list, right detail table. Zero graphs, zero liveness. Pure inventory.

**Ideas worth taking**

- A "machine identity" header (chip, core topology, memory, GPU cores, display, OS build) is cheap context Coreography should show once and reuse for annotations (e.g. labeling E vs P clusters, GPU core count in graph headers).

**Weaknesses / avoid**

- Snapshot only; some sections (power, sensors) contain the live data monitors want but rendered as text.

**Sources**

- [System Information User Guide](https://support.apple.com/guide/system-information/system-information-user-guide-syspr35536/mac)
- [Eclectic Light: where each system fact lives](https://eclecticlight.co/2019/09/24/more-about-this-mac-where-to-find-that-uuid-mac-address-etc/)

### Command-line tools

**Status**: all built into macOS (no install). `fs_usage`, `powermetrics`, `spindump` need root; `top`, `vm_stat`, `nettop`, `iostat`, `footprint`, `sample`, `memory_pressure` run unprivileged (with reduced visibility for other users' processes).

**What they show and how**

- `top`: full-screen curses process list, ~1 s default refresh per third-party guides (unverified; vs Activity Monitor's 5 s). Global header: Procs by state, LoadAvg 1/5/15, SharedLibs, MemRegions, PhysMem (wired/active/inactive/used/free), VirtMem (pageins/pageouts), Networks (packets in/out), Disks (reads/writes), CPU user/sys/idle, Swap, Purgeable. Per-process sort keys beyond % CPU: csw (context switches), ports (Mach ports), mregion, mem/rprvt/purg/vsize/vprvt/kprvt/kshrd, faults, cow, msgsent/msgrecv, sysbsd, sysmach, pageins, boosts (importance), instrs, cycles, jetpri (jetsam priority), wq. Event-counting modes -a/-d/-e; interactive single-key commands including `S` to send a signal; `-l` logging mode for scripting.
- `vm_stat`: Mach VM stats in page units (header prints the page size; 16384 B on Apple Silicon builds, unverified against current man output but the field exists). Fields: pages free/active/inactive/speculative/throttled/wired/purgeable, translation faults, COW, zero-filled, reactivated, purged, file-backed vs anonymous, pages stored in vs occupied by compressor, compressions/decompressions, pageins/pageouts, swapins/swapouts (compressed-data units, include swapfile maintenance I/O), plus MTE tag stats where supported. Man page now points users at `meminfo(1)` as the modern preferred tool.
- `fs_usage`: root-only, kdebug-traced live stream of filesystem-related syscalls and page faults; per-call rows (call type, path, elapsed time, process.thread). Filters: `-f filesys|network|pathname|exec|diskio|cachehit`; include/exclude process lists; `-w` wide output. Complaint from HN: paths truncate and there is no good aggregated view, unlike Windows' process-monitor story.
- `nettop`: top-style network monitor; modes `-m tcp|udp|route`; interface-type filters `-t wifi|wired|loopback|awdl|expensive|external`; per-process and per-socket bytes in/out; interactive keys (d delta, e expand, c collapse, j column chooser, p process picker); `-L` CSV logging.
- `iostat`: tty/devices/cpu report; per-disk KB/t, tps, MB/s; `-w` interval, `-c` count, `-I` totals.
- `footprint`: Apple's per-process memory accounting. Emphasizes kernel-"dirty" memory; de-duplicates multiply-mapped/shared objects across specified processes and reports a de-duplicated total; categories per region, `-v` for vmmap-style region listing, `--swapped`, `--wired`, accepts memgraph files, `--vmObjectDirty` (pre-10.15 default view). Values intentionally may not match top/Activity Monitor because accounting differs.
- `sample`: per-process profiler, default 10 s at 1 ms intervals; pauses the process, records all thread stacks, emits an indented textual call tree with counts; `-wait`, `-mayDie`, `-fullPaths`, `-file`.
- `spindump`: system-wide sampler (user + kernel stacks, every process), default 10 s at 10 ms; `heavy` (sorted-by-count) vs `timeline` (chronological with thread-state annotations: QoS, darwinbg, importance boost, App Nap suppression, latency-QoS timers, I/O throttling tier, cpu priority); microstackshot reporting (interrupt and I/O microstackshots, battery/AC and idle/active filtering); embeds a binary blob for re-reporting; used by the system for force-quit hang reports into /Library/Logs/DiagnosticReports.
- `memory_pressure`: quick system memory summary including free % and a pressure gauge line (listed in tool comparisons; details unverified).
- `metalperftrace`: see its own section (macOS 27).

**Ideas worth taking**

- These are the data sources for a power-user Coreography layer: per-cluster frequency/residency and energy from powermetrics, per-process footprint categories from footprint, syscall/fault streams from fs_usage, socket-level network from nettop, boosts/jetsam/QoS from top, call-stack sampling from sample/spindump.
- `top`'s sort-key richness shows how much per-process data the kernel already exposes that Activity Monitor never surfaces.

**Weaknesses / avoid**

- Text-first, unscriptable GUIs of their own; several need root; no shared schema; units vary (pages vs bytes, percentages of what).

**Sources**

- [top(1) man page](https://keith.github.io/xcode-man-pages/top.1.html)
- [vm_stat(1) man page](https://keith.github.io/xcode-man-pages/vm_stat.1.html)
- [nettop(1) man page](https://keith.github.io/xcode-man-pages/nettop.1.html)
- [iostat (ss64)](https://ss64.com/mac/iostat.html)
- [fs_usage(1) man page](https://manp.gs/mac/1/fs_usage)
- [footprint(1) man page](https://keith.github.io/xcode-man-pages/footprint.1.html)
- [sample(1) man page](https://keith.github.io/xcode-man-pages/sample.1.html)
- [spindump(8) man page](https://keith.github.io/xcode-man-pages/spindump.8.html)
- [cloudstreet-dev: CLI performance tool comparison](https://cloudstreet-dev.github.io/macOS-and-Unix/part12-performance/cli-performance-tools.html)
- [Apple docs: viewing virtual memory usage (top/vm_stat/vmmap)](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/VMPages.html)

### Battery settings and battery status menu

**Status**

- System Settings > Battery (Mac laptops only); macOS 26 Tahoe shipped a redesigned Battery UI ("learn more about your daily usage patterns and most frequently used apps", per Apple's Tahoe feature list). macOS Tahoe 26.4 added Charge Limit (80-100% ceiling, Apple silicon only) per Apple's charging doc.

**What it shows**

- Last 24 Hours: Battery Level line chart of average charge per 15-minute period with shaded regions marking when the Mac was charging; Screen On Usage bar/line of how long the display was on each hour.
- Last 10 Days: Energy Usage per day and Screen On Usage per day.
- Tahoe redesign adds per-app consumption info (Apple feature list: "most frequently used apps consume battery"; exact layout unverified).
- Top of pane: current level + alerts, Energy Mode (Low Power / Automatic / High Power on supported MacBook Pros), Battery Health (condition, maximum capacity, longevity management), Charging (Optimized Battery Charging, Charge Limit on 26.4+).
- Battery status menu (menu bar): % charge, power source, active power mode, time-until-full, and an "apps using significant energy" list; a Display Brightness warning affordance is reported to appear when brightness is a major drain (unverified).

**How it shows it**

- The canonical Apple "paired time series" layout: one level line (with shading marking a secondary state, charging) + a second aligned series (screen-on) so drain correlates with use. Segmented control switches 24 h / 10 days.

**Ideas worth taking**

- Shaded background regions on a metric to encode a boolean state (charging) without a second chart.
- Correlating "level over time" with "use over time" is exactly the CPU/energy/battery correlation Coreography wants live.
- "Apps using significant energy" in a menu-bar surface: the pattern of blaming named apps, lightweight.

**Weaknesses / avoid**

- Aggregate-only, no watts; 15-minute buckets hide spikes; nothing older than 10 days; no export.

**Sources**

- [Change Battery settings](https://support.apple.com/guide/mac-help/change-battery-settings-mchlfc3b7879/mac)
- [View Battery Usage History](https://support.apple.com/en-ca/guide/mac-help/mchle6eb6928/mac)
- [Battery status menu](https://support.apple.com/guide/mac-help/what-is-the-battery-status-menu-mchl173fcc57/mac)
- [Charge Limit / Optimized Battery Charging](https://support.apple.com/en-us/102338)
- [macOS Tahoe all-new-features PDF (New Battery UI)](https://www.apple.com/os/pdf/All_New_Features_macOS_Tahoe_Sept_2025.pdf)
- [MacMost: reading the battery graphs](https://macmost.com/how-to-diagnose-battery-drain-on-a-macbook.html)

### Storage settings

**Status**

- System Settings > General > Storage; reached maturity around Tahoe (26.2 reviewed positively by Eclectic Light after years of inaccurate About This Mac numbers).

**What it shows / how it shows it**

- A single horizontal segmented stacked bar ("Storage Bar"): color-coded category segments (e.g. Applications, Documents, Photos, Music, iOS Files/backups, Mail, macOS, System Data, Trash), light grey = free space; hover a segment for its size. "All Volumes" expands to per-volume/container bars.
- Below: recommendation cards (Store in iCloud, Optimize Storage, Empty Bin Automatically) and a category list; info buttons per category open detail (Applications sortable by size/last-opened; Documents has largest-files and downloads lists plus a column-view file browser).

**Ideas worth taking**

- Segmented stacked bar + hover-for-values is the accepted macOS idiom for "what makes up this total". Same idiom fits Memory Used composition and disk/network totals in Coreography.
- Pair the summary bar with a management action list; visualization that leads to a fix.

**Weaknesses / avoid**

- Category computation is slow to refresh and historically wrong; fine for storage, unacceptable for live metrics.

**Sources**

- [Change Storage settings](https://support.apple.com/en-gb/guide/mac-help/mchl3d437fbc/mac)
- [See used and available storage (hover for values, light grey = free)](https://support.apple.com/en-gb/guide/mac-help/syspf9b375b9/mac)
- [Eclectic Light: Storage settings explainer (Tahoe 26.2)](https://eclecticlight.co/2025/12/20/explainer-storage-settings/)

## Cross-cutting patterns

- One window, many instruments: every Apple surface splits the same way, a list/table for detail plus a small chart for trend (Activity Monitor bottom strip, Battery settings, Storage bar). None of them make the chart the primary surface, which is Coreography's opportunity.
- Two visual idioms recur: the scrolling monochrome history strip (Activity Monitor, Metal HUD graphs, Instruments tracks) and the segmented/stacked composition bar (Storage, memory breakdown text). Colors carry semantics only in Memory Pressure (green/yellow/red) and Not Responding (red); everywhere else color is decorative.
- Instantaneous + trailing-average pairs: Energy Impact vs 12 hr Power, FPS instant vs 120-frame rolling, top's delta vs accumulative modes. Good UX pattern for jittery metrics.
- Progressive disclosure via presets and column choosers: Metal HUD's Default/FPS Only/Rich/Full, nettop's `j` column menu, Activity Monitor's View > Columns. Power users opt into density.
- Apple's own stack splits by privilege: pretty unprivileged UI (Activity Monitor, 5 s cadence, coarse) vs root-gated firehose (powermetrics, fs_usage, 1 ms). A single app spanning both would need a privileged helper; this is the core architectural decision.
- Metrics are estimates: Apple openly marks powermetrics watts and Power Profiler impact values as model-relative estimates. Honesty about derived metrics is Apple's own precedent.
- Wake-up accounting (idle wake-ups, package idle exits, short timers) is how Apple explains energy, and Activity Monitor surfaces almost none of it visually.
- Everything Apple ships is per-window or per-app; only `metalperftrace` (macOS 27) does always-on look-back recording. Ambient history is unclaimed territory.

## Implications for Coreography

- Make the graphs the product: full-height, interactive (hover crosshair with exact values, range select, click to drill), 250-1000 ms cadence. Activity Monitor's static bottom strip is the thing to outclass, and Instruments' multi-lane timeline is the right reference.
- Per-core CPU graph must split by cluster: two bands (E cluster, P cluster) with frequency alongside residency, because on Apple Silicon "50% of a downclocked E core" is not half of "50% of a boosted P core". This is a documented Activity Monitor weakness.
- Adopt Memory Pressure as a first-class gauge (green/yellow/red) but show its components (free, wired, compressed, cached, swap rate) and optionally graph pressure over time, which Activity Monitor does only as a thin strip.
- Energy panel: show Energy Impact + trailing window average per app, but also real watts where measurable (powermetrics-quality SoC rails: CPU/GPU/ANE power, battery discharge rate). Label estimates as estimates.
- Include what Apple omits: thermal pressure state, SMC fan/temperature sensors, GPU utilization + memory + frequency in the main window, disk IOPS + bytes + (optionally) latency, network per-interface and per-connection detail via nettop-class data.
- Process organization beyond a flat list: hierarchy tree, app coalitions (powermetrics' `--show-process-coalition` model so WebContent bills to its browser), by-GPU, and a user/windowed filter bar replacing the View menu.
- Ambient history: implement a ring buffer (hours) and retroactive "what just spiked?" view, the metalperftrace look-back pattern generalized to all metrics. Activity Monitor has zero recall.
- Power-user shelf: sample process, spindump, open files/ports, send signal, plus sysdiagnose capture, all present in Activity Monitor and expected by its users.
- Performance budget as a feature: publish the monitor's own CPU/energy cost (Activity Monitor's WindowServer spike is a known embarrassment); consider a low-power/idle sampling mode and App Nap-aware throttling when hidden.
- Copy Apple's semantics where legible: red = bad (Not Responding), traffic-light for pressure states, shaded regions for boolean states (charging, Game Mode, Low Power Mode), packets/data toggle.
- Do not copy: 5 s defaults, undocumented unitless scores without a help path, modal dialogs for Quit/Force Quit without showing consequences (children, open files), and per-tab siloed graphs that can't be seen together.

## Sources

- [Activity Monitor User Guide](https://support.apple.com/guide/activity-monitor/welcome/mac)
- [View information about processes](https://support.apple.com/guide/activity-monitor/view-information-about-processes-actmntr1001/10.14/mac/27)
- [View CPU activity](https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/10.14/mac/27)
- [View GPU activity](https://support.apple.com/guide/activity-monitor/view-gpu-activity-actm9329b315/10.14/mac/27)
- [View memory usage](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/10.14/mac/27)
- [View energy consumption](https://support.apple.com/guide/activity-monitor/view-energy-consumption-actmntr43697/10.14/mac/27)
- [View disk activity](https://support.apple.com/guide/activity-monitor/view-disk-activity-actmntr1005/10.14/mac/27)
- [View network activity](https://support.apple.com/guide/activity-monitor/view-network-activity-actmntr1006/10.14/mac/27)
- [View cache activity](https://support.apple.com/guide/activity-monitor/view-cache-activity-actmcdbbd395/10.14/mac/27)
- [Run system diagnostics](https://support.apple.com/guide/activity-monitor/run-system-diagnostics-actmntr2225/10.14/mac/27)
- [Quit an app or process](https://support.apple.com/guide/activity-monitor/quit-a-process-actmntr1002/10.14/mac/27)
- [Update frequency](https://support.apple.com/guide/activity-monitor/change-how-often-information-is-updated-actmntr2224/10.14/mac/27)
- [Check if your Mac needs more RAM](https://support.apple.com/guide/activity-monitor/check-if-your-mac-needs-more-ram-actmntr34865/10.14/mac/27)
- [OWC: Using Activity Monitor part 1](https://eshop.macsales.com/blog/58102-using-activity-monitor-part-1-cpu-and-memory/)
- [cloudstreet-dev: Activity Monitor beyond the GUI](https://cloudstreet-dev.github.io/macOS-and-Unix/part12-performance/activity-monitor.html)
- [AppleInsider: Activity Monitor wrong about Apple Silicon energy](https://appleinsider.com/articles/22/05/03/activity-monitor-in-macos-is-wrong-about-energy-usage-of-apple-silicon)
- [Eclectic Light: Don't trust Activity Monitor on M1 Macs](https://eclecticlight.co/2022/05/02/dont-trust-activity-monitor-on-m1-macs/)
- [HN: observer effect thread](https://news.ycombinator.com/item?id=25401681)
- [HN: energy accuracy thread](https://news.ycombinator.com/item?id=31233157)
- [MacRumors: network data-sent inflation](https://forums.macrumors.com/threads/activity-monitor-network-wrong-data-sent-calculation.2196324/)
- [AppleInsider: Electron/Tahoe GPU slowdown fix](https://appleinsider.com/articles/25/10/10/update-your-slack-discord-clients-the-electron-tahoe-gpu-slowdown-bug-is-fixed)
- [mac-dvd: Activity Monitor on Tahoe](https://mac-dvd.com/blog/mac-activity-monitor/)
- [Apple Energy Efficiency Guide: monitor usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/MonitoringEnergyUsage.html)
- [Instruments Help Topics](https://developer.apple.com/library/archive/documentation/AnalysisTools/Conceptual/instruments_help-collection/Chapter/Chapter.html)
- [WWDC26: Profile, fix, and verify](https://developer.apple.com/videos/play/wwdc2026/268/)
- [Measuring power use with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
- [Addressing CPU bottlenecks](https://developer.apple.com/documentation/xcode/addressing-cpu-bottlenecks)
- [WWDC16: System Trace in depth](https://developer.apple.com/videos/play/wwdc2016/411/)
- [cargo-instruments (template list)](https://github.com/cmyr/cargo-instruments)
- [WWDC25 dev tools overview](https://yaacoub.github.io/articles/swift-tip/get-familiar-with-your-new-development-tools-wwdc25/)
- [powermetrics (ss64)](https://ss64.com/mac/powermetrics.html)
- [powermetrics(1) man page](https://manp.gs/mac/1/powermetrics)
- [Firefox powermetrics guide](https://firefox-source-docs.mozilla.org/performance/powermetrics.html)
- [Metal Performance HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics)
- [Customizing the Metal Performance HUD](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud)
- [Metal HUD performance insights](https://developer.apple.com/documentation/xcode/gaining-performance-insights-with-metal-performance-hud)
- [Tech Talk: Discover Metal Performance HUD](https://developer.apple.com/videos/play/tech-talks/110339/)
- [WWDC26: Find and fix performance issues in Metal games](https://developer.apple.com/videos/play/wwdc2026/388/)
- [WWDC26 session 388 summary](https://wwdc.ai/2026/388)
- [Metal Developer Tools](https://developer.apple.com/metal/tools/)
- [MacRumors: Metal HUD on Tahoe](https://forums.macrumors.com/threads/silly-question-about-the-metal-hud.2468560/)
- [AAPL Ch.: Metal HUD customization](https://applech2.com/archives/20260707-metal-performance-hud-customize.html)
- [MetalHUDmenu](https://github.com/Jfishin/MetalHUDmenu)
- [myByways: enabling the macOS Metal HUD](https://mybyways.com/blog/enabling-the-macos-metal-performance-hud/)
- [Apple Support: Use Game Mode](https://support.apple.com/en-us/105118)
- [Eclectic Light: Game Mode CPU/GPU management](https://eclecticlight.co/2023/10/18/how-game-mode-manages-cpu-and-gpu/)
- [Eclectic Light: what Game Mode does](https://eclecticlight.co/2023/10/17/what-does-game-mode-do/)
- [MacRumors: Game Mode triggers](https://forums.macrumors.com/threads/sonoma-game-mode-what-triggers-is.2403022/)
- [MacMost: Tahoe hidden features incl. Game Overlay](https://macmost.com/new-small-and-hidden-features-in-macos-tahoe.html)
- [Apple Discussions: Game Overlay issue](https://discussions.apple.com/thread/256157905)
- [Console User Guide](https://support.apple.com/guide/console/welcome/mac)
- [Console: activities](https://support.apple.com/guide/console/activities-cnsl6df527d3/1.1/mac/10.14)
- [Console: customize the log window](https://support.apple.com/guide/console/customize-the-log-window-cnsl35710/mac)
- [Console: keyboard shortcuts](https://support.apple.com/guide/console/keyboard-shortcuts-cnsl99a72ebe/mac)
- [System Information User Guide](https://support.apple.com/guide/system-information/system-information-user-guide-syspr35536/mac)
- [Eclectic Light: where system facts live](https://eclecticlight.co/2019/09/24/more-about-this-mac-where-to-find-that-uuid-mac-address-etc/)
- [top(1)](https://keith.github.io/xcode-man-pages/top.1.html)
- [vm_stat(1)](https://keith.github.io/xcode-man-pages/vm_stat.1.html)
- [nettop(1)](https://keith.github.io/xcode-man-pages/nettop.1.html)
- [iostat (ss64)](https://ss64.com/mac/iostat.html)
- [fs_usage(1)](https://manp.gs/mac/1/fs_usage)
- [footprint(1)](https://keith.github.io/xcode-man-pages/footprint.1.html)
- [sample(1)](https://keith.github.io/xcode-man-pages/sample.1.html)
- [spindump(8)](https://keith.github.io/xcode-man-pages/spindump.8.html)
- [cloudstreet-dev: CLI performance tools](https://cloudstreet-dev.github.io/macOS-and-Unix/part12-performance/cli-performance-tools.html)
- [Apple: viewing virtual memory usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/VMPages.html)
- [Change Battery settings](https://support.apple.com/guide/mac-help/change-battery-settings-mchlfc3b7879/mac)
- [View Battery Usage History](https://support.apple.com/en-ca/guide/mac-help/mchle6eb6928/mac)
- [Battery status menu](https://support.apple.com/guide/mac-help/what-is-the-battery-status-menu-mchl173fcc57/mac)
- [Charge Limit / Optimized Battery Charging](https://support.apple.com/en-us/102338)
- [All new features macOS Tahoe (PDF)](https://www.apple.com/os/pdf/All_New_Features_macOS_Tahoe_Sept_2025.pdf)
- [MacMost: diagnose battery drain](https://macmost.com/how-to-diagnose-battery-drain-on-a-macbook.html)
- [Change Storage settings](https://support.apple.com/en-gb/guide/mac-help/mchl3d437fbc/mac)
- [See used and available storage](https://support.apple.com/en-gb/guide/mac-help/syspf9b375b9/mac)
- [Eclectic Light: Storage settings explainer](https://eclecticlight.co/2025/12/20/explainer-storage-settings/)
- [Eclectic Light: Tahoe Launch Angels (GameOverlayUI)](https://eclecticlight.co/2025/10/03/welcome-to-tahoes-launch-angels/)

## Verification log

Verified 2026-10-17 against the cited sources plus Apple primary sources fetched for this pass (Activity Monitor guide pages for macOS 27, Console and System Information guides, Mac User Guide battery/storage pages, Apple Support 102338 and 105118, Apple developer docs and WWDC16/WWDC25/WWDC26 sessions, man-page mirrors). Roughly 90 concrete claims were checked across all tool sections.

Confirmed as written: Activity Monitor's five tabs plus conditional Cache tab, all documented View filters, bottom-panel metrics for CPU/Memory/Energy/Disk/Network, memory-pressure colors and memory terms, Energy column semantics (Energy Impact, 12 hr Power, App Nap, Graphics Card, Preventing Sleep), Sample Process/Spindump/System Diagnostics/Spotlight Diagnostics, Quit/Force Quit/Send Signal, 5 s default refresh; powermetrics samplers, process flags, coalition/DEAD_TASKS accounting, end-of-window thermal/SFI snapshots and the power-estimate disclaimer; Metal Performance HUD metric catalogue, enable paths (env vars, MetalForceHudEnabled, Info.plist, developerHUDProperties), insights, presets; metalperftrace look-back .atrc workflow and the iOS Performance Trace .aar path; Game Mode requirements and Tahoe Game Overlay steps; Console favorites/Now mode/info-debug toggles; Battery Last 24 Hours/Last 10 Days graphs, Tahoe's new Battery UI, and Charge Limit (macOS Tahoe 26.4+, Apple silicon, 80-100%); Storage segmented bar, All Volumes, and per-category info tools; CLI man-page details for top, vm_stat, fs_usage, nettop, iostat, footprint, sample, spindump.

Corrections and clarifications applied:

- "structurally unchanged for over a decade" -> "broadly unchanged in structure for over a decade" (structure confirmed; "structurally identical" was stronger than the evidence).
- "5 s default refresh (1 s minimum)" -> "5 s default refresh (faster menu options of 1 s/2 s per third-party guides; Apple documents only the 5 s default)". Same qualification added to the Update Frequency bullet.
- "has a measurable observer effect" -> "has a reported observer effect (anecdotal forum measurements)". The WindowServer 7-11% to 20-40% figure is one HN report, not a general measurement.
- Cache tab "requires an Activity Monitor relaunch to appear" -> marked unverified; Apple's guide does not mention a relaunch.
- "becomes Afterburner History on a Mac Pro with an Afterburner card" -> "becomes Afterburner History when an Afterburner graphics card is connected" (Apple's wording; not Mac Pro specific).
- Inspect-window Statistics field list -> hedged, exact field list unverified (dropped unconfirmed "hangs").
- Dock icon list "Show Memory Usage" -> moved to an unverified note; confirmed modes are CPU Usage, CPU History, Network Usage, Disk Activity, plus Application Icon.
- Instruments status: "Xcode 26 added ... Swift Concurrency instrument" -> kept but flagged the version attribution as unverified; the new Inspector panel reattributed to Instruments 27 per WWDC26.
- Metal HUD logging env var: added note that the Tech Talk says `MTL_HUD_LOGGING_ENABLED` while current Apple docs spell `MTL_HUD_LOG_ENABLED`.
- metalperftrace section: added sibling CLIs `gpucapture` and `gpudebug` from Apple's Metal developer tools page.
- `top` "1 s default refresh" -> "~1 s per third-party guides (unverified)"; the man page does not state it in the cited excerpt.
- `fs_usage` row fields: dropped "cpu" (not in the documented output format).
- System Information launch path: "Apple menu > About This Mac > System Report" -> "System Settings > General > About > System Report" per the current guide.
- Battery status menu "Display Brightness warning" -> marked unverified.
- Added primary source for the Apple Silicon energy claim: Eclectic Light's "Don't trust Activity Monitor on M1 Macs" (the AppleInsider piece reports on it).

Links: every link was fetched or searched. AppleInsider, MacRumors, Apple Discussions and myByways return HTTP 403 to automated fetchers but all were confirmed to exist via search results with matching titles; none are dead links.

Still unverified (marked in place): Tahoe compact-toolbar claim (single third-party blog), Cache-tab relaunch requirement, exact Update Frequency menu values, Show Memory Usage Dock mode, Inspect Statistics field list, `top` default interval, `vm_stat` 16384-byte page size on current builds, memory_pressure output details, battery-menu Display Brightness warning, Tahoe Battery pane's exact per-app layout, Power Profiler direct-Mac recording, Swift Concurrency instrument's introduction version, and Game Mode internals beyond Eclectic Light's measurements.
