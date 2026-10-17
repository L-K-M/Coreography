# Visual system monitors: research for Coreography

> Survey of system monitoring tools that present live system state
> visually, across macOS, Windows, Linux and PC gaming, with what each one
> teaches a Mac-native, graph-first replacement for Activity Monitor.
> Sources accessed 2026-10-17. The product plan built on this research is
> in [`../plan.md`](../plan.md).

## Contents

- [How this was researched](#how-this-was-researched)
- [Key findings](#key-findings)
- [The baseline: Activity Monitor](#the-baseline-activity-monitor)
- [Landscape at a glance](#landscape-at-a-glance)
- [macOS monitors](#macos-monitors)
- [Windows: Task Manager and the power tools](#windows-task-manager-and-the-power-tools)
- [Gaming and enthusiast tools](#gaming-and-enthusiast-tools)
- [TMOG: right ideas, wrong skin](#tmog-right-ideas-wrong-skin)
- [Linux and terminal monitors](#linux-and-terminal-monitors)
- [Specialised tools worth absorbing](#specialised-tools-worth-absorbing)
- [Visualisation and Mac design principles](#visualisation-and-mac-design-principles)
- [What macOS lets a monitor measure](#what-macos-lets-a-monitor-measure)
- [Pattern catalogue](#pattern-catalogue)
- [Where Coreography can win](#where-coreography-can-win)
- [Open questions to settle on hardware](#open-questions-to-settle-on-hardware)
- [Notes index](#notes-index)

## How this was researched

Eleven topic surveys plus an analysis of the owner's reference screenshots.
Each survey was written by one model with web access and then fact-checked
by a second model on a different provider, which corrected the file in place
and logged every change in a "Verification log" at its end (the check of
notes 10 timed out; its claims were covered by the pass described next). About forty claims
the plan depends on were then re-checked against primary sources (source
code, man pages, issue threads, vendor pages). That pass corrected several
overstated or misattributed details, and it also reversed one of the
coordinator's own corrections: Apple's WWDC session shows only two
`metalperftrace` subcommands, but the macOS 27 man page documents the live
`listen` mode too. Anything still marked "(unverified)" in the notes should
be treated as a lead, not a fact.

The full, sourced notes are in [`notes/`](notes/). This document is the
synthesis: read it first, then go to a notes file for detail and links.

## Key findings

1. **No Mac monitor combines a graph-first window with history and
   attribution.** Most of the market is menu bar apps (iStat Menus, Stats,
   a 2025-2026 wave of indie entrants) whose detail views are popovers the
   width of a menu. Window dashboards exist (Vitals, Sensei, iStatistica
   Pro, System Dashboard Pro, Tempo, TMOG, Activity Monitor itself), but
   they are card grids of current values, list-first, or visually poor.
   None aligns all subsystems on one scrubbable time axis that says who
   caused a past spike. That is the open space.
2. **Every good tool puts the cause next to the symptom.** iStat Menus
   lists the top five processes under each graph; Process Explorer names the
   top process when you hover a point on its CPU graph; Game Bar's Resources
   widget lists what is hurting the game. Activity Monitor separates the
   graph (bottom strip) from the cause (table) and only for one subsystem at
   a time.
3. **History is the most common gap.** Almost every tool keeps about 60
   seconds. The ones that keep more (Little Snitch: a year of traffic;
   iStat Menus: 28 days; atop and below: record and replay; TMOG Pro: Flight
   Recorder; macOS 27 `metalperftrace`: look-back game traces) are loved for
   it. Scrubbing back to "what happened at 14:02" with attribution is
   offered by almost no one.
4. **The gaming world solved compact, legible overlays.** Corner-anchored
   panels of big numbers with small labels, one frame-time graph, density
   levels on one control (Steam Deck's 0-4 slider), opacity, text outline,
   click-through, pin to keep visible. Apple's own Game Overlay (macOS 26)
   shows no performance data at all, which leaves a gap on the Mac, and
   macOS 27's `metalperftrace listen` now streams live per-process Metal
   frame statistics that a third-party HUD can show without injection.
5. **Frame time, percentiles and sessions beat averages.** Enthusiast tools
   moved from FPS to frame-time graphs, 1% and 0.1% lows, named capture
   sessions and post-capture analysis (CapFrameX, PresentMon). The same
   discipline applies to any spiky metric: show the tail, not just the
   mean.
6. **Honest measurement is a design feature.** TMOG's best idea is its
   measurement contract: a zero means measured zero, unavailable data is
   labelled unavailable, missing samples leave gaps. On macOS this matters
   more than elsewhere, because many readings are private, per-chip or
   privilege-gated.
7. **Apple Silicon needs cluster-aware views.** Per-core percentages lie
   when cores run at different frequencies: 50% of a slowed efficiency core
   is not 50% of a boosted performance core. Good tools group cores by
   cluster (efficiency, performance, and from M5 "super" cores), show
   frequency next to residency, and report watts.
8. **macOS 27 broke unprivileged power counters, and the community found
   workarounds.** IOReport energy channels stopped updating for normal
   processes; macmon restored readings without root in its 0.9.0 release
   (2026-10-07) by reading other counters. Sensor and power telemetry is a
   per-chip, per-OS maintenance commitment.
9. **A full-featured monitor does not fit the Mac App Store.** The App
   Sandbox denies listing processes, reading most data about other
   processes and opening the SMC sensor interface. iStat Menus sells a Mac
   App Store edition that needs a separately downloaded helper for sensors
   and cannot control fans; Stats and TMOG ship directly. Developer ID with
   notarization plus an optional privileged helper is the proven path.
10. **Liquid Glass belongs on chrome, not on charts.** Apple's guidance is
    to keep glass to the navigation layer (toolbar, sidebar, inspector) and
    never in the content layer. macOS 27 adds a user glass-opacity slider,
    so the app must look right at both extremes.
11. **Self-cost is part of the product.** Users audit monitors against
    themselves: iStat advertises one fifth of its previous CPU use, TMOG was
    criticised for 3-4% CPU, NVIDIA's overlay was caught costing games up to
    15%. A monitor must be cheap and show its own cost.
12. **Restraint is what separates designed from "vibecoded".** The
    best-received tools (iStat Menus, Little Snitch, DaisyDisk, Instruments)
    use system typography, few colours with fixed meanings, one established
    visual metaphor per domain and generous spacing. The worst-received
    (TMOG's neon phosphor meters, gamer skins, Rainmeter clutter) decorate.

## The baseline: Activity Monitor

Activity Monitor has kept the same structure for over a decade: one window,
five tabs (CPU, Memory, Energy, Disk, Network), a process table, and a
fixed strip of summary panels at the bottom. Details:
[notes 00](notes/00-reference-screenshots.md),
[notes 01](notes/01-activity-monitor-and-apple-tools.md).

```text
+----------------------------------------------------------------------+
| toolbar: stop, info, actions   [CPU|Memory|Energy|Disk|Network] find |
+----------------------------------------------------------------------+
|                                                                      |
|  process table (about 95% of the window)                             |
|                                                                      |
+----------------------------------------------------------------------+
|           [ numbers | tiny graph | numbers ]   (about 2%)            |
+----------------------------------------------------------------------+
```

What it gets right, and Coreography should keep:

- **Memory Pressure**: one green, yellow or red signal combining free
  memory, swap rate, wired and cached pages. Its best single idea.
- **Energy Impact with "12 hr Power"**: an instant value paired with a
  trailing average, a good pattern for jittery metrics.
- **Process tools**: Inspect (memory, statistics, open files and ports),
  Sample Process, spindump, System Diagnostics, Send Signal.
- **Apps over time**: the Energy tab lists applications from the last 12
  hours, greying out those that have quit.

What it gets wrong:

- Graphs are about 220 x 80 pt and have no axes, scales or hover values.
- One subsystem at a time; seeing CPU and memory together needs tab
  switching or extra windows.
- A 5-second default refresh and no history beyond the visible strip.
- Nothing about temperatures, fans, frequencies or watts; GPU only as a
  separate history window.
- Documented Apple Silicon inaccuracies: Energy Impact does not price
  efficiency and performance core work correctly, and per-core load ignores
  frequency.
- Silent gaps: the reference screenshot shows an empty per-process Disk list
  while the summary reports 83 MB/s of reads.

Apple's real time-series design lives elsewhere: in Instruments (aligned
multi-track timelines, range selection, zoom), in System Settings' Battery
pane (24-hour level line with charging shading, 10-day bars) and Storage
pane (hoverable stacked bar). Coreography should borrow from these, not from
Activity Monitor's strip.

## Landscape at a glance

| Tool | Platform | Kind | Visual signature | Take | Avoid |
| --- | --- | --- | --- | --- | --- |
| Activity Monitor | macOS | Built-in | Process table, tiny summary strip | Memory pressure, energy averages, process tools | Graphs as afterthought, tab silos |
| iStat Menus 7.5 | macOS | Menu bar | Card dropdowns, rings, mirrored bars, E/P core colours | Metric with top processes, typography, rules, 28-day history | Fixed popover, rings for everything |
| Stats | macOS | Menu bar, open source | 13 menu bar widget types | Micro-chart vocabulary, honest cost FAQ | About 10 minutes of history |
| 2025-2026 indie entrants | macOS | Menu bar, notch, window | App folding, per-app watts, 30-day history | Folding processes into apps | Unproven longevity |
| Vitals, Sensei, iStatistica Pro, System Dashboard Pro | macOS | Window dashboards | Card grids of current values | App-level rows, one-window overview | No shared time axis or attribution in time |
| Instruments | macOS | Developer | Multi-track timeline | Shared time axis, range selection | Developer complexity |
| Windows Task Manager | Windows | Built-in | Sparkline rail plus large graph, heat-shaded cells | Rail as picker, heat cells, per-core grid, compact view | List-first, 60-second memory |
| Resource Monitor | Windows | Built-in | Collapsible tables, graph rail | Per-file disk, connections and ports | Density |
| Process Explorer | Windows | Sysinternals | Coloured tree, toolbar and tray graphs | Hover attribution on graphs, change colours, handle search | Win32 density |
| System Informer | Windows | Open source | Columns for everything | The ceiling of power-user depth | Kernel driver, clutter |
| MSI Afterburner + RTSS | Windows | Gaming | Graph strip, on-screen display | Per-metric surface toggles, value-range colours, benchmarks | Skins, tiny targets |
| HWiNFO64 | Windows | Sensors | Current, Min, Max, Average table | Session statistics, alerts, logging | Wall of numbers |
| Game Bar | Windows | Overlay | Pinnable widgets | Pin to keep, Resources widget | Overhead, admin step for FPS |
| NVIDIA App (formerly GeForce Experience) | Windows | Overlay | Stacked stat block | Toggle and cycle hotkeys, latency breakdown | No frame-time graph, overhead |
| Steam overlay and Steam Deck | Windows, SteamOS | Overlay | Density levels | Level slider with live preview, real vs generated FPS, battery hours | Small fixed text |
| PresentMon, CapFrameX, FrameView | Windows | Frame-time analysis | Frame-time graphs, percentile curves | Tail statistics, bottleneck verdicts | Expert-only |
| MangoHud | Linux | Overlay | Coloured cells, frame-time line | Colour as metric identity, layout presets | Text configuration |
| Metal Performance HUD | macOS | Overlay, developer | Corner panel, frame-interval histogram | Histogram bucketed by refresh, hide zero metrics | Opt-in at launch, Metal only |
| TMOG | macOS, Windows, Linux | Window | Neon segmented meters, phosphor themes | Availability states, gaps, flight recorder, PID identity | The whole skin |
| btop++ | Cross-platform TUI | Terminal | Braille graphs, two-band CPU graph | Two metrics in one graph, presets | Terminal limits |
| atop, below | Linux | Recorders | Record and replay | Time travel through history | Terminal only |
| Mission Center, Resources | Linux | GUI | Task Manager-style rail | Apps vs processes split | Imitation |
| KDE Plasma System Monitor | Linux | GUI | Pages of sensor "faces" | Compact and full renderings of one card | Configuration sprawl |
| Netdata | Cross-platform | Web | Per-second charts, anomaly ribbon | Legend as stats table, highlight to correlate | Density |
| asitop, macmon, mactop | macOS | Terminal | Apple Silicon power and frequency | Rootless IOReport data | Fragile per chip |
| Little Snitch 6 | macOS | Network | Linked list, traffic chart, map | Linked selection, chart as time selector, year of history | Firewall scope |
| DaisyDisk, GrandPerspective | macOS | Disk space | Sunburst, treemap | Drill-down by size | Deletion scope |
| coconutBattery | macOS | Battery | Nested capacity bars, history | Wear over months | Narrow |
| TG Pro, Macs Fan Control | macOS | Thermal | Sensor lists, fan pairing | Grouping sensors by region | Fan control |

## macOS monitors

Details: [notes 02](notes/02-macos-menubar-and-dashboard-monitors.md).

**iStat Menus 7.5** (Bjango, 2026-09-14) is the craft benchmark and the
owner's reference. Ten menu bar items (CPU and GPU, memory, disks, network,
sensors, battery and power, time, weather, astronomy and a combined mode),
editable dropdowns, history from 10 minutes to 28 days, a rules engine for
notifications, and cluster-coloured cores. Version 7 claims about one fifth
of version 6's CPU use. Its dropdowns show the visual grammar worth
adopting: an accent label, one or two big values with smaller units, a
history graph in two colours, then the top five processes. Its limit is
physical: a menu-width popover cannot show axes, long history or several
subsystems side by side.

**Stats** (exelban, MIT, about 42,600 GitHub stars) is the free alternative
and the clearest public vocabulary of menu bar micro-charts: mini, line,
bar, pie, network, speed, tachometer, label, stack, battery, memory, dot,
text. It documents which modules cost the most CPU and keeps only about ten
minutes of history.

**New entrants (2025-2026)** show where taste is going: notch-anchored
rings, folding hundreds of processes into a few dozen apps, per-app watts,
30 days of local history, published resource budgets. Their details rest
on single sources; treat them as signals, not references.

**Window dashboards** exist but stop short of the brief. Vitals
(window plus menu bar, about 60 app rows instead of 1,000 processes, 1.7.3
on 2026-10-16), Sensei's dashboard, iStatistica Pro, System Dashboard Pro
and System Monitor Panel, and Tempo's card window show current values and
short histories; none found in this survey aligns subsystems on a shared,
scrubbable time axis with attribution. A head-to-head comparison is being
added as notes 15.

**The graveyard** (GeekTool, Monity, eul, iGlance, MenuMeters) shows that
free solo projects and Notification Center-only tools fade, while
window-anchored or deeply crafted paid tools persist.

What the category agrees on: two surfaces (a tiny always-visible one and an
on-demand detail one), rings for bounded values, mirrored bars for paired
flows, cores grouped by cluster, icon-led process rows folded into apps,
local history as a privacy point, and one-time pricing around US$10-20.

## Windows: Task Manager and the power tools

Details: [notes 03](notes/03-windows-task-manager-and-sysinternals.md).

**Task Manager** (Windows 11) is list-first, but its Performance page holds
the best built-in layout on any OS: a left rail of live sparklines (CPU,
memory, each disk, each network adapter, GPU, NPU) that is both overview
and navigation, with a large graph for the selected device and a
per-logical-processor grid on demand. The Processes page shades each cell
by intensity (heat map), now tinted by the system accent colour. Dave
Plummer's original 1996 principles still hold: tiny footprint, flicker-free
resizing, repaint only cells that changed, and let the OS enforce
permissions.

**Process Explorer** (Sysinternals, 17.2 released 2026-10-15) contributes
the rarest interaction in the survey: hover a point on its CPU history
graph and it names the process that contributed most at that instant. It
also popularised change highlighting (new rows green, exiting rows red),
tray mini-graphs and "which process holds this handle" search.

**Resource Monitor** shows file-level disk activity, TCP connections and
listening ports per process, with checkbox filtering across panes.
**System Informer** (formerly Process Hacker, 4.0 in August 2026) shows the
ceiling of columns-for-everything depth, at the cost of a kernel driver and
antivirus false positives.

Ambient surfaces are a proven second product: Process Explorer tray graphs,
TrafficMonitor's taskbar band, Rainmeter skins. Microsoft's own Dev Home
system widgets were retired in 2025, a reminder that shallow cards in a
separate dashboard do not stick.

## Gaming and enthusiast tools

Details: [notes 04](notes/04-gaming-afterburner-hwinfo-frametime.md),
[notes 05](notes/05-gaming-overlays-game-bar-nvidia-steam-metal.md).

### MSI Afterburner and RivaTuner Statistics Server

Afterburner 4.6.6 went final in October 2025 after years of betas (4.6.7
betas continue in 2026). Its monitoring window is a vertical strip of
per-sensor graphs; its Monitoring tab established a useful pattern: pick a
sensor from a long catalogue, then set separately whether it appears in the
on-screen display, the tray, a graph, and at which thresholds it changes
colour. RTSS draws the on-screen display into games and offers the most
capable overlay composer (layers, embedded graphs, value-range colours,
conditional badges such as "GPU limited"), a frame limiter, and benchmark
statistics with 1% and 0.1% lows.

### HWiNFO64

The widest sensor coverage on Windows and the table everyone copies:
Sensor, Current, Minimum, Maximum, Average, with a reset. Adds per-sensor
graphs, tray icons, alerts (popup, sound, program, email), CSV logging and a
shared-memory interface other tools build on (its free tier limits that
interface to 12 hours, which silently breaks downstream overlays). Power
users love its completeness; everyone else sees a wall of numbers.

### Windows Game Bar

Win+G opens floating widgets over a game. The Performance widget shows FPS,
CPU, GPU, VRAM and RAM, each with a history graph on click, with per-metric
toggles and an opacity slider inside the widget. Pinning keeps a widget on
screen after the bar closes: the editing surface is transient, the readout
persists. The Resources widget lists the processes affecting the game, with
close buttons. Weak points: FPS needs an admin grant and a restart, and the
bar itself costs measurable GPU time.

### NVIDIA GeForce Experience and the NVIDIA App

GeForce Experience is legacy (no new features or fixes) and the NVIDIA App
(first release 11.0.1, November 2024) replaced it. Alt+R toggles the statistics overlay and
Alt+Shift+R cycles its density: two shortcuts that make progressive
disclosure discoverable. It breaks latency down into render, PC and display,
and total system latency. Reviewers note it has no frame-time graph (NVIDIA
documents only numeric statistics), and its Game Filters pipeline cost games 2-12% in
Tom's Hardware's tests (up to 15% in user reports) until disabled.

### Steam, Steam Deck, AMD, MangoHud, PresentMon

- **Steam Deck** has the best density control in the survey: one slider,
  levels 0-4, previewed live. Level 1 is a single FPS number, level 2 a
  strip across the top, level 3 a corner box, level 4 everything. Battery
  percentage and estimated hours remaining sit next to the power figures.
- **Steam's desktop overlay** (2025) separates generated frames from real
  ones, the honest answer to frame generation, and exposes text size,
  saturation and background opacity as separate sliders.
- **AMD Adrenalin** splits configuration into what to measure, how to draw
  it and when to log it: clean information architecture for a configurable
  monitor.
- **MangoHud** gives each metric a fixed hue across value, label and graph,
  outlines text by default for legibility over game content, and uses
  presets that change layout (strip vs box), not just item count.
- **PresentMon, CapFrameX and FrameView** turned frame timing into a
  discipline: CPU busy vs GPU busy to tell which side limits, display
  latency, percentile curves, stutter counts, named captures compared side
  by side.

### Apple: Metal Performance HUD, Game Mode, Game Overlay

The Metal Performance HUD draws a corner panel inside Metal apps that opt
in at launch (environment variable, Info.plist, Xcode, or a global
developer default). It shows FPS, GPU time, frame interval with a 120-frame
chart, memory, thermal state, and a frame-interval histogram whose buckets
match the display refresh interval, an elegant way to show pacing. It hides
zero-valued metrics. macOS 27 records frame timing for all Metal layers continuously and adds
`metalperftrace` to read it: `collect` saves hours of look-back traces,
`overview` summarises them per process, `listen --pid` streams live
per-process statistics at 1-second or slower intervals, and `setup --enable
hud --pid` switches the HUD on inside a running game. Apple's WWDC session
demonstrates only the first two; the man page documents all four.
Apple's consumer Game Overlay (macOS 26, Cmd-Esc) shows achievements,
friends and energy mode but no performance numbers.

### What the gaming world teaches

```text
 Steam Deck density levels           Coreography equivalent
 -------------------------           ----------------------
 1  [ 60 ]                           menu bar value
 2  [ 60 | ~~frame~~ | CPU GPU W ]   compact strip window
 3  +--------------+                 HUD panel (always on top)
    | FPS  frames  |
    | CPU  GPU  W  |
    +--------------+
 4  everything, quarter screen        the main window
```

- One density control, previewed live, with layout changing per level.
- The frame-time graph is the "real" signal; FPS alone hides stutter.
- Legibility kit over arbitrary content: background opacity, text scale,
  outline or scrim, corner presets, click-through.
- Colour is metric identity, consistent across value, label and graph.
- Overlay cost must be near zero and visible.
- Battery hours at the current draw is the energy metric players use.

## TMOG: right ideas, wrong skin

Details: [notes 06](notes/06-tmog-task-manager-og.md).

TMOG (Task Manager OG, by Dave Plummer, original author of Windows Task
Manager) reached 1.0 in 2026 on macOS (Swift and AppKit, macOS 14+),
Windows and Linux from one C++20 measuring core. It has twelve destinations
(Summary, Performance, Processes, System Info, Startup apps, Users,
Services, Power & Freq, Connections, Installed Apps, Disk Space,
Benchmarks), five of them in a US$39.95 Pro tier with Flight Recorder.
Its author has described building it largely with an AI coding agent from a
long written specification.

Ideas worth adopting:

- **Measurement contract**: "measured, never invented". Zero means a
  measured zero; unavailable readings say "Unavailable"; stopped sampling
  leaves a gap in the graph instead of an interpolated line.
- **Flight Recorder**: record, save, scrub and replay the telemetry panels
  (`.tmogtrace`).
- **Compressed timelines**: dense recent seconds, coarser older history in
  one scrolling graph.
- **PID identity**: pair each PID with its creation identity so an action
  cannot hit a recycled PID.
- **Self-monitoring** and a strict no-telemetry privacy stance.
- **Why is my computer slow** framing: the summary answers a question.

What to avoid, concretely: segmented "phosphor" meters with bloom and glow,
a wide sci-fi display face, a different saturated neon per subsystem on
near-black, glowing branding inside the sidebar, dense grids of tiny
graphs, phosphor theme variants, and Pro destinations shown as locked items
in the navigation. Reviewers called it "ugly" and like a "fake antivirus
interface", and noted it uses more resources than Windows Task Manager.
The lesson: the information architecture is sound; the skin decorates
instead of informing, and none of it uses the platform's own vocabulary.

## Linux and terminal monitors

Details: [notes 07](notes/07-linux-and-cross-platform-monitors.md).

- **btop++** draws two metrics in one graph (upper and lower halves,
  optionally mirrored), switches graph glyphs by available resolution, and
  ships named layout presets.
- **htop** colours CPU bar segments by meaning (user, system, nice, IRQ)
  and explains the colours in its help.
- **atop** and **below** record compressed history and replay it
  (`below replay -t "3m ago"`); **bottom** and **zenith** zoom and scroll
  charts back in time.
- **asitop, macmon, mactop** show Apple Silicon cluster frequencies,
  residency, GPU, Neural Engine and watts; macmon and mactop do it without
  root.
- **Mission Center** and **Resources** bring the Task Manager rail to GNOME
  and split apps from processes. **KDE Plasma System Monitor** builds pages
  from reusable sensor "faces" that render both full-size and compact,
  so the same card works in a window and in a panel.
- **Netdata** has the densest chart chrome worth studying: each chart's
  legend is a sortable table of min, average and max for the visible
  window, an anomaly ribbon runs above the chart, and highlighting a time
  range correlates it across all metrics.

The structural lesson: the serious tools separate collection from display
(one engine feeding a UI, a CLI, exports). Coreography should keep its
sampling engine independent of its views for the same reason.

## Specialised tools worth absorbing

Details: [notes 11](notes/11-specialized-subsystem-and-power-tools.md).

Each subsystem already has a canonical visual, and Coreography should use
it rather than invent one:

| Domain | Established visual | Reference tools |
| --- | --- | --- |
| Disk space | Sunburst or treemap, plus a ranked list | DaisyDisk, GrandPerspective, OmniDiskSweeper |
| Storage categories | Stacked capacity bar | macOS Storage settings |
| Network endpoints | Map, linked to list and traffic chart | Little Snitch 6 |
| Network over time | Chart that selects a time window for the rest of the view | GlassWire, Little Snitch |
| Battery wear | Nested bars: charge, full charge capacity, design capacity | coconutBattery |
| Thermal sensors | Sensors grouped by physical region, fans beside them | TG Pro, Macs Fan Control |
| Startup items | Category inventory with "hide Apple-signed" | KnockKnock, Autoruns |
| Open files and ports | Per-process lists plus reverse lookup | Sloth, Process Explorer |

The most valuable power features are joins between datasets, not new
metrics: per-app cumulative bytes per day (TripMode's main feature), which
process holds this file or port, a startup item joined to its live
resource cost. The scope line is observation versus control: firewalls, fan
control, charge limits and file deletion make tools heavyweight and Apple
keeps absorbing them. Coreography should observe these systems, not
control them.

## Visualisation and Mac design principles

Details: [notes 08](notes/08-dataviz-and-mac-design-principles.md).

Visualisation:

- Maximise data ink; prefer sparklines, small multiples and bullet-style
  bars over dials (Tufte, Few). Encode by position and length first.
- Percent metrics keep a fixed 0-100 scale; rates may autoscale but must
  label the axis; bars start at zero.
- Decimate for display with min/max or LTTB so peaks survive; never smooth
  the data the user is reading. Keep raw samples for hover readouts.
- Colour carries status, never alone: avoid red against green, vary
  lightness as well as hue (Okabe-Ito is the reference set), label series
  directly, add a second cue (dashes, position).
- Units follow macOS: decimal GB as Disk Utility shows them, bits or bytes
  stated explicitly for network rates, tabular digits for live numbers.

Mac platform:

- **Swift Charts** is the right default for interactive and historical
  charts: vectorised plots since 2024, accessibility (VoiceOver summaries,
  Audio Graphs) built in. It has no virtualisation: downsample to about one
  point per pixel and keep always-ticking surfaces on a lighter custom
  renderer, measured before reaching for Metal.
- **Liquid Glass** (macOS 26) is for controls and navigation. Do not put it
  in the content layer; reserve the clear variant for floating over rich
  media. macOS 27 adds a user opacity slider from clear to tinted.
- **Chrome vocabulary**: unified toolbar, sidebar, inspector for the
  selection, `MenuBarExtra` for ambient status, Control Center controls and
  desktop widgets as satellites, a Settings window behind Cmd-comma.
- **Energy-aware rendering**: ProMotion adapts refresh to content, so tie
  redraws to the sample rate, hint frame rates, and honour Reduce Motion,
  Reduce Transparency and Increase Contrast.
- **Accessibility as architecture**: `AXChartDescriptor` gives every chart
  an audio graph and a VoiceOver summary. No third-party monitor found in
  this survey ships it.

What makes Mac apps feel native rather than ported: system fonts and
semantic colours, standard window chrome and controls, keyboard navigation,
restrained motion, one selection model driving every view (Little Snitch,
Instruments), and features that disappear into convention rather than
announcing themselves.

## What macOS lets a monitor measure

Details: [notes 09](notes/09-macos-data-sources-cpu-gpu-power-thermal.md),
[notes 10](notes/10-macos-data-sources-processes-memory-io-privileges.md).

| Metric | Source | Without root | Stability |
| --- | --- | --- | --- |
| CPU total and per core | `host_statistics`, `host_processor_info` | Yes | Stable |
| Core clusters (efficiency, performance, super) | `hw.perflevel*` sysctls, IORegistry `cluster-type` | Yes | Letters remapped on M5 |
| Cluster frequency and residency | IOReport (private) plus DVFS tables in IORegistry | Yes | Channel names change per chip |
| CPU, GPU, DRAM, Neural Engine watts | IOReport energy model; on macOS 27 fallbacks via CLPC counters or SMC rails | Partly, via fallbacks | Broke in macOS 27 |
| System and battery power | SMC keys, battery registry | Yes | Model-dependent |
| GPU utilisation and memory | `IOAccelerator` performance statistics | Yes | Fairly stable |
| GPU time per process | AGX user client registry entries (as macmon and mactop read them) | Yes | Stable so far |
| Temperatures | SMC keys or `IOHIDEventSystemClient` | Yes | Sensor names unofficial |
| Fan speed / fan control | SMC | Read yes / write no | Per model |
| Thermal pressure | `ProcessInfo.thermalState` | Yes | Stable, public |
| Memory composition and pressure | `host_statistics64`, `kern.memorystatus_vm_pressure_level` | Yes | Stable |
| Process list, names, paths | `sysctl`, `proc_pidpath`, short BSD info | Yes, all processes | Stable |
| Per-process CPU, memory, energy, disk bytes, wakeups | `proc_pidinfo`, `proc_pid_rusage` (own energy is `ri_energy_nj`, not `ri_billed_energy`) | Own user only; root for others | Stable |
| Per-process network | Private NetworkStatistics framework (as `nettop` uses) | Yes | Private API |
| Interface network and disk totals | `NET_RT_IFLIST2`, `IOBlockStorageDriver` | Yes | Stable |
| Battery health, cycles, adapter | IOPowerSources, `AppleSmartBattery` | Yes | Stable |
| Sleep assertions | `IOPMCopyAssertionsByProcess` | Yes | Public |
| FPS of another Metal app | `metalperftrace listen --pid` (macOS 27, 1 s resolution); display swap counters for the whole display | Yes | New in macOS 27 |

Consequences for the product:

- A rich dashboard needs no privileges. Root is needed for other users'
  processes (including `WindowServer` and `kernel_task` detail), fan
  control and some inventories: an optional `SMAppService` daemon with a
  narrow XPC protocol covers those, and declining it must cost little.
- Several key readings are private or undocumented and change per chip and
  OS release. They belong behind one data-driven abstraction with per-chip
  tables, capability probes, explicit "unavailable" states and a diagnostic
  mode, so breakage degrades a card instead of the app.
- Code or child processes that touch other apps' containers can trigger
  the "access data from other apps" privacy prompt (reported against Stats
  on macOS 15). In-process APIs are more predictable than shelling out to
  `ps`, `top` or `nettop`.
- Distribution is Developer ID with notarization, outside the Mac App
  Store.

## Pattern catalogue

Named patterns found across the survey, with where they appear. The plan
refers to these by number.

| # | Pattern | Seen in | What it means for Coreography |
| --- | --- | --- | --- |
| P1 | Graph-first, list second | Task Manager Performance page, TMOG, iStat dropdowns | Graphs own the window; the process list is a secondary pane |
| P2 | Cause beside symptom | iStat top-5 lists, Game Bar Resources | Every subsystem card lists its top processes |
| P3 | Attribution in time | Process Explorer graph hover | Hovering any past point names who caused it |
| P4 | Shared time axis | Instruments, Netdata | All graphs align on one time axis with one cursor |
| P5 | Sparkline rail as navigator | Task Manager, Mission Center | Overview cards double as navigation |
| P6 | Look-back and replay | atop, below, TMOG Flight Recorder, Little Snitch, `metalperftrace` | Continuous local history, scrubbable, exportable |
| P7 | Chart as time selector | GlassWire, Windows battery page, Little Snitch | Selecting a range filters every other view |
| P8 | Linked selection | Little Snitch, WinDirStat | One selection model across chart, list and inspector |
| P9 | Mirrored flows | iStat disk and network, Activity Monitor packets | Read/write and in/out above and below one baseline |
| P10 | Cluster-aware CPU | iStat, macmon, asitop | Cores grouped by cluster, frequency beside load, watts |
| P11 | Composition bars | Storage settings, iStat memory ring | Memory and storage as segmented totals |
| P12 | Context bands | Few's bullet graphs, Battery charging shading | Thresholds and states drawn behind values |
| P13 | Heat-shaded cells | Task Manager | Table cells tinted by intensity |
| P14 | Change highlighting | Process Explorer, TCPView | New rows briefly tinted, exiting rows fade |
| P15 | Session statistics | HWiNFO, Afterburner | Current, Min, Max, Average with reset |
| P16 | Density levels | Steam Deck, Metal HUD, MangoHud, NVIDIA | One control from minimal to full, previewed live |
| P17 | Pinned compact surfaces | Game Bar pins, Task Manager compact view, menu bar extras | Small always-on-top views fed by the same engine |
| P18 | Honest availability | TMOG, Metal HUD hiding zeros | Measured, unavailable, restricted and estimated are visibly different |
| P19 | Capture sessions and percentiles | CapFrameX, PresentMon, Afterburner | Named recordings with tail statistics |
| P20 | Apps over processes | iStat combine, Activity Monitor energy, new entrants | Helpers fold into their app by default |
| P21 | Self-cost disclosure | iStat, TMOG self-monitoring | The app shows what it costs |
| P22 | Filter grammar and noise filters | TaskExplorer `#tokens`, Autoruns | Tokens such as `#root` and "hide Apple" |
| P23 | Reverse lookup | Process Explorer, Sloth | Which process holds this file or port |
| P24 | Instant plus trailing average | Activity Monitor 12 hr Power, Metal HUD | Jittery metrics shown with their average |

## Where Coreography can win

1. **The window nobody built**: a Mac-native, graph-first, single window at
   Activity Monitor scale (P1, P4, P5).
2. **Attribution in time**: point at any moment in the last hours and see
   which processes were responsible (P3, P6, P7). No tool on any platform
   combines graph-hover attribution with long scrubbable history.
3. **Honest Apple Silicon telemetry**: clusters with frequency and watts,
   thermal pressure, explicit availability and estimate labels (P10, P18).
4. **Energy as a first-class story**: watts, battery hours at current
   draw, per-app energy over the day.
5. **A Mac performance HUD**: Apple's Game Overlay shows no numbers; a
   native always-on-top panel with density levels fills that gap (P16,
   P17).
6. **Joins power users want**: process to files, sockets, launch item,
   signing and energy in one inspector (P23).
7. **Craft**: system typography and colour, Liquid Glass only on chrome,
   audio graphs, locale-correct numbers, a published self-cost budget.

## Open questions to settle on hardware

These need a macOS 27 Mac to answer and should be early prototype spikes:

1. **FPS of other apps.** What fields does `metalperftrace listen --json`
   emit, what does it cost, does it prompt, and how does it behave with
   games running through CrossOver or Game Porting Toolkit? Can a HUD built
   on it stay legible at 1-second updates, and what does the display swap
   counter add for frame pacing?
2. **Power on macOS 27.** Which fallback (CLPC counters as in macmon 0.9,
   SMC rails) is accurate on each chip family, and how far do the readings
   drift from `powermetrics`?
3. **Per-process network.** Is the private NetworkStatistics framework
   usable from a Developer ID app on macOS 27 without prompts?
4. **Helper value.** How much of the process list is blank for root-owned
   processes without the helper, and is that acceptable as the default?
5. **Rendering budget.** Can a window of about eight live charts at 1 Hz,
   with a 60 Hz scrolling option, stay under 1% CPU on an M1 with Swift
   Charts, or does the live layer need Core Animation or Metal?
6. **Privacy prompts.** Which data paths trigger TCC prompts on macOS 26
   and 27 (subprocesses, Wi-Fi SSID, screen capture)?

## Notes index

| File | Topic |
| --- | --- |
| [00](notes/00-reference-screenshots.md) | Owner's Activity Monitor and iStat Menus screenshots |
| [01](notes/01-activity-monitor-and-apple-tools.md) | Activity Monitor, Instruments, powermetrics, Metal HUD, Apple CLI tools |
| [02](notes/02-macos-menubar-and-dashboard-monitors.md) | iStat Menus, Stats and other Mac monitors |
| [03](notes/03-windows-task-manager-and-sysinternals.md) | Windows Task Manager, Resource Monitor, Sysinternals, System Informer |
| [04](notes/04-gaming-afterburner-hwinfo-frametime.md) | MSI Afterburner, RTSS, HWiNFO64, frame-time analysis tools |
| [05](notes/05-gaming-overlays-game-bar-nvidia-steam-metal.md) | Game Bar, NVIDIA App, AMD, Steam, MangoHud, Metal Performance HUD |
| [06](notes/06-tmog-task-manager-og.md) | TMOG |
| [07](notes/07-linux-and-cross-platform-monitors.md) | Terminal monitors, Linux GUIs, Netdata, Apple Silicon TUIs |
| [08](notes/08-dataviz-and-mac-design-principles.md) | Visualisation theory, Swift Charts, Liquid Glass, Mac design |
| [09](notes/09-macos-data-sources-cpu-gpu-power-thermal.md) | macOS data sources: CPU, GPU, power, thermals, frame rate |
| [10](notes/10-macos-data-sources-processes-memory-io-privileges.md) | macOS data sources: processes, memory, disk, network, privileges |
| [11](notes/11-specialized-subsystem-and-power-tools.md) | Disk, network, battery, thermal, startup and inspection tools |
