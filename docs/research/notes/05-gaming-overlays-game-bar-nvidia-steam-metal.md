# Enthusiast and gaming monitoring tools, part 2: overlays and platform tools (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

## Summary

- Every serious overlay converges on the same grammar: corner-anchored, translucent, color-coded cells showing a big number with a small label, plus one line graph that is almost always frametime or frame interval. The frame graph, not the FPS number, is the "pro" signal.
- Progressive disclosure is universal: Steam desktop offers 4 detail levels, Steam Deck a 0-4 slider, NVIDIA Alt+Shift+R view cycling with a Custom per-metric checklist, Armoury Crate Minimal/Row/Square layouts, Metal HUD named layouts FPS/Lite/Default/Rich/Full, MangoHud switchable presets. Users want "one FPS number" for playing and "the panel" for debugging.
- Legibility over arbitrary game content is a solved problem with a fixed toolkit: background opacity slider, text outline (MangoHud ships it on by default), text size scaling, saturation control (Steam), click-through, and corner presets.
- macOS has no system-level overlay injection API like Windows' RTSS/GPU-driver hooks. Apple's own Metal Performance HUD only draws inside Metal apps that opt in at launch (env var, Info.plist, Xcode scheme) (a `metalperftrace setup --enable hud --pid` route for running processes was claimed but is not in Apple's WWDC26 material: unverified).
- New in macOS 27 Golden Gate: `metalperftrace` collects hours-to-days of look-back Metal performance traces with no prior setup (`collect --last 5h`, `.atrc` files) and summarises them per process (`overview --json`). Apple's WWDC26 session shows only `collect` and `overview`; a live `listen --pid` stream was claimed by the first research pass but is unverified. If it exists, a third-party app could show another app's real FPS inside its own window. Confirm on a macOS 27 machine (`metalperftrace --help`) before designing around it.
- Apple's consumer Game Overlay (macOS 26 Tahoe, Cmd-Esc) deliberately shows zero performance data: achievements, friends/chat, volume, brightness, Game Mode, energy mode. Reviewers noted the missing FPS as a gap, which is precisely Coreography's opportunity.
- NVIDIA replaced GeForce Experience with the NVIDIA App (1.0 Nov 2024; latest listed release 11.0.9.565). GFE is legacy: no new features or bug fixes, web servers being shut down. The App's Game Filters/Photo Mode pipeline cost games performance even when no filter was used (user reports up to 15%, Tom's Hardware measured 2-12% on its own bench); disabling Game Filters removed the penalty.
- Handheld overlays are the closest design analog for a compact Coreography panel: Armoury Crate SE's 2026 editor (per-metric text vs text+graph modes, per-metric colors, three independent layouts) and Steam Deck's slider are the two best references.
- No console (PS5, Xbox Series) ships a live FPS counter; Xbox shows only a static FPS Boost/Auto HDR indicator chip in the Guide overlay. Overlay depth is a PC-handheld phenomenon.

## Tools

### Xbox Game Bar (Performance and Resources widgets)

**Status**: Built into Windows 10/11, free, updated through the Microsoft Store as an app. Opened with Win+G or the Xbox button on a controller. Renamed from "Xbox Game Bar" to "Game Bar" in Windows 11 24H2-era builds. Visually overhauled in 2025 with a Compact Mode aimed at handhelds, and a Gaming Copilot widget was added (it cannot be removed entirely; its settings include a model-training opt-out).

**What it shows**: The Performance widget reports FPS, CPU %, GPU %, VRAM and RAM usage. FPS requires a one-time UAC permission grant that adds the user to the Performance Log Users group, plus a restart. The Resources widget is a task-manager-lite listing top tasks/processes with their impact on the game, with close buttons. Other built-in widgets: Capture, Audio (per-app volume), Gallery, Xbox Social, Spotify, Clock and Battery status icons, Edge Game Assist, and third-party widgets from the Widget Store.

**How it shows it**: Widgets are floating panels over the game; each can be moved, resized, and pinned. Pinning keeps a widget visible and always-on-top after Game Bar closes (unpinned widgets vanish with the overlay). The Performance widget shows each metric as a labeled readout; clicking a metric reveals a small history graph. Its options gear exposes per-metric on/off toggles, graph placement, an "Override default transparency" checkbox with an opacity slider, and a compact display mode (a Game Bar setting aimed at small screens and handhelds). A click-through toggle on the bar decides whether mouse input passes to the game. Controller Bar is a minimal, controller-navigable alternate view of the home bar.

**Ideas worth taking**: Pin-to-keep-visible is the key interaction: the full editor surface is transient, the pinned readout persists. Metric toggles and transparency live in the widget itself, not a distant settings page. Resources widget pattern ("which process is hurting my game right now", with a kill action) is exactly the power-user feature a monitor can own.

**Weaknesses / avoid**: FPS telemetry needs elevated permission and a reboot on first use. Game Bar itself costs measurable GPU/CPU while resident (reported around 1-3% GPU idle, more when recording; unverified), which undermines the credibility of a tool whose job is measuring overhead. The Copilot widget bloat illustrates what happens when an overlay becomes a platform team's billboard.

**Sources**: [TechRadar Game Bar guide](https://www.techradar.com/how-to/how-to-use-xbox-game-bar-in-windows-10), [ASUS Game Bar FAQ](https://www.asus.com/support/faq/1053128/), [Thurrott Windows 11 Field Guide: Game Bar](https://www.thurrott.com/books/windows-11-field-guide/archived-22h2/313981/game-bar-24h2), [Tech How Win11 guide](https://www.techy.how/tutorials/win11-show-cpu-gpu-vram-ram-usage), [Microsoft Edge Game Assist FAQ](https://support.microsoft.com/en-us/edge/microsoft-edge-game-assist-faq), [EliteGear Game Bar FPS guide](https://www.elitegear.io/games/windows-fps-anzeigen/)

### Xbox PC app and full-screen experience (2025-2026)

**Status**: Shipped October 16, 2025 with the Asus ROG Xbox Ally / Ally X, and is rolling out as a "home app" option in Windows 11 gaming settings. Free, part of Windows/Xbox app.

**What it shows**: Not a metrics overlay but a launcher: the Xbox app's compact mode runs full-screen, aggregating installed games from all stores (Steam titles included) into one controller-first library. The Game Bar inside it exposes device settings (Wi-Fi, Bluetooth), the vendor Command Center, and the usual widgets including Performance.

**How it shows it**: Boots straight into the full-screen Xbox UI without loading desktop wallpaper, taskbar, or productivity processes, freeing resources for games. All apps run full-screen; window controls are removed. A long-press on the Xbox button (or a swipe up from the bottom) opens a Task Switcher to jump between games or to the real Windows desktop; once the desktop is loaded it stays resident until reboot, so returning to full optimization requires a restart.

**Ideas worth taking**: The "shell swaps into a reduced environment" model: Apple already does a weak version with Game Mode + Game Overlay. For Coreography, an analog is a deliberately minimal always-on-top state for the window, not a second UI.

**Weaknesses / avoid**: Hidden state transitions with real costs (desktop stays loaded once entered) create user confusion. The design is locked to Microsoft account / Xbox branding.

**Sources**: [The Verge on Windows+Xbox handheld combination](https://www.theverge.com/news/682011/microsoft-windows-xbox-pc-combination-features-rog-xbox-ally-devices), [Windows Central hands-on](https://www.windowscentral.com/gaming/xbox/i-tried-windows-11s-new-handheld-gaming-mode-on-the-xbox-ally-will-this-save-gaming-on-windows-handhelds), [Asus ROG guide to reaching the desktop](https://rog.asus.com/articles/guides/how-to-get-to-the-windows-desktop-on-the-rog-xbox-ally-and-rog-xbox-ally-x/), [Notebookcheck on the restart requirement](https://www.notebookcheck.net/Potentially-annoying-ROG-Xbox-Ally-full-screen-experience-requires-restart-for-optimizations-after-switching-from-Windows-desktop.1093126.0.html)

### NVIDIA App (GeForce Experience successor)

**Status**: Windows, free, closed-source, requires GeForce GTX 600-series or newer for the performance overlay. NVIDIA App left beta at 1.0 in November 2024 as NVIDIA's stated replacement for GeForce Experience and Control Panel (both remain available in a legacy state); GFE is explicitly legacy (no new features, no bug fixes, web servers being switched off, and driver 566.36 dropped it from the driver package per Tom's Hardware). Latest listed release at access time: 11.0.9.565, which adds CPU clock/power/temperature to the overlay, an MCP server for AI agents, RTX Spark support, and a beta Performance Mode for DLSS Frame Generation.

**What it shows**: Statistics overlay toggled with Alt+R, cycled through metric sets with Alt+Shift+R, configured via Alt+Z > Statistics > Configure heads-up display. The Custom view exposes per-metric toggles via the "View All" button (older coverage also names Basic and Advanced views; unverified). Metrics include FPS, 1% low FPS (added 2024, App beta 10.0.2), render latency, mouse latency, PC + display latency, total system latency, GPU utilization, GPU and memory clocks, GPU temperature, fan speed, VRAM, CPU utilization, and (11.0.9) CPU clock/power/temperature. In-game statistics report which DLSS Override models and modes are active. With a Reflex Analyzer-capable G-SYNC monitor and a supported game's latency flash indicator, each mouse click's click-to-display latency is measured in-monitor and shown in the overlay. The desktop app's System page hosts a Performance Panel with live GPU stats and one-click automatic GPU tuning (an OC scanning algorithm that manages the tuning profile).

**How it shows it**: A compact, vertically stacked stats block, default position top-right. Configurable position (corner presets), opacity, text size (Standard/Large only; users complain the choice is too coarse), and custom font color (added in beta release 10.0.3, October 2024). Views trade detail for footprint; the "minimize HUD footprint" framing in NVIDIA's own beta notes is the design goal.

**Ideas worth taking**: Latency as a first-class metric block (render vs PC+display vs total system) is a genuinely useful decomposition. A single hotkey to toggle, a second to cycle density: that pair of shortcuts is the cheapest discoverable progressive-disclosure UX in this roundup. Per-view metric checklists (the Custom view's "View All") keep the editor simple.

**Weaknesses / avoid**: No frametime graph at all, which reviewers single out as its biggest analytical gap. The Game Filters/Photo Mode feature cost up to 15% performance in some games even when no filter was used (15% is the peak user report; Tom's Hardware measured 2-12% on its own test bench, and verified that disabling Game Filters and Photo Mode in settings removes the penalty; with filters off, the App and overlay themselves measured clean): an overlay that slows the thing it measures destroys trust. Vendor-locked to NVIDIA GPUs.

**Sources**: [NVIDIA App in-game performance and latency overlay KB](https://nvidia.custhelp.com/app/answers/detail/a_id/5084/~/nvidia-app-in-game-performance-and-latency-overlay), [NVIDIA App release highlights](https://www.nvidia.com/en-us/software/nvidia-app/release-highlights/), [Tom's Hardware: NVIDIA App 1.0 exits beta, GFE deprecated](https://www.tomshardware.com/pc-components/gpus/nvidia-app-version-1-0-exits-beta), [Tom's Hardware: up to 15% slower](https://www.tomshardware.com/pc-components/gpus/we-tested-nvidia-app-performance-problems-games-run-up-to-15-percent-slower-with-the-app), [NVIDIA: Reflex Analyzer](https://www.nvidia.com/en-us/geforce/news/reflex-latency-analyzer-360hz-g-sync-monitors/), [NVIDIA upgrade notice](https://www.nvidia.com/en-us/geforce/news/gfecnt/20265/upgrade-to-nvidia-app/), [HowToGeek monitoring tools review](https://www.howtogeek.com/3-in-game-performance-monitoring-tools-i-recommend-to-every-pc-gamer/)

### AMD Software: Adrenalin Edition (Metrics Overlay)

**Status**: Windows, free, ships with Radeon drivers. Actively maintained; the tracking/overlay UI described here is the current Adrenalin "Performance > Metrics" surface (older docs call it Radeon Overlay, same lineage).

**What it shows**: FPS, frametime, 99th-percentile FPS, GPU utilization %, GPU engine clock (MHz), GPU memory clock, GPU current and junction temperature (C), total board power (W), GPU fan speed (RPM), GPU memory utilization (MB), CPU utilization %, CPU frequency (GHz), CPU temperature, CPU power (W), and system RAM (GB). Logging writes CSV files to `%LOCALAPPDATA%\AMD\CN` (per docs) at an adjustable sampling interval of 0.25-5 s in the current UI (1-10 s in the old Radeon Overlay). An in-game overlay popup on game launch can announce driver features such as whether AFMF frame generation is active.

**How it shows it**: Metrics render as gauges/graphs over time on-screen; toggle the whole metrics overlay with Ctrl+Shift+O, the full in-game overlay with Alt+R. The Performance > Metrics page keeps per-metric toggles (overlay gauge/graph, visibility, and logging) in its tracking panel, plus two named tabs: Overlay (location: top-left/top-right/bottom-left/bottom-right/custom XY in px; size %; column count; transparency %; text color presets white/blue/green/magenta/custom hex) and Settings (sample interval and logging options). Per-metric graphs and gauges can be individually enabled.

**Ideas worth taking**: The three-way split "what to measure (Tracking), how to paint it (Overlay), when to record (Logging)" is clean information architecture for a configurable monitor. Column count + size % + transparency gives one slider per dimension of footprint. Custom XY position in px as an escape hatch beyond corner presets.

**Weaknesses / avoid**: Community reports of metrics logging producing only a FrameTime file and no CSV (unverified whether fixed). AFMF-generated frames make vendor overlays disagree about FPS; ASUS's FAQ tells AFMF users to prefer AMD's own overlay for accurate numbers, and third-party monitors needed a driver update (at least V32.0.12011.7001) to report correctly. Sampling up to 5 s is too coarse for stutter analysis.

**Sources**: [AMD support: Monitor Performance Metrics with Adrenalin](https://www.amd.com/en/resources/support-articles/faqs/DH3-038.html), [AMD support: Radeon Overlay monitoring](https://www.amd.com/en/resources/support-articles/faqs/DH-026.html), [Adrenalin performance page](https://www.amd.com/en/products/software/adrenalin/software-performance.html), [AMD forum: CSV logging bug](https://pcforum.amd.com/s/question/0D5KZ000010HjgD0AS/adrenalin-metrics-logging-not-producing-csv-file), [Progressive Robot logging tutorial](https://blog.progressiverobot.com/how-to-use-radeons-built-in-radeon-performance-logging), [ASUS ROG Ally FAQ on AFMF/monitor interplay](https://www.asus.com/global/support/faq/1050046/)

### Steam In-Game Performance Monitor (desktop client)

**Status**: Free, built into the Steam client. Entered beta June 17, 2025 and shipped in the June 30, 2025 stable update. Windows-first: Valve states the first version targets Windows and the most common GPUs, with non-Windows platforms possibly missing data. A September 9, 2025 update added CPU temperature (needs an optional kernel-mode driver on Windows), DPI scaling, DLSS-vs-game-FPS correctness fixes, macOS rendering fixes, and faster Vulkan/OpenGL/D3D12 overlay chart rendering.

**What it shows**: Frame rate values with DLSS/FSR generated frames broken out separately from real game FPS; min/max single-frame values; FPS-over-time graph; CPU performance info (clock speed; per-core utilization graph optional); GPU performance info (utilization, temperature); system RAM and VRAM usage. Configured at Settings > In Game > Performance Overlay: enable/position/hotkey, detail level, UI scaling for text size, color saturation, background opacity.

**How it shows it**: Four detail levels selectable live in-game: "Single FPS Value"; "FPS Details"; "FPS Details, CPU & GPU Utilization"; "FPS, CPU, GPU & RAM Full Details". Each metric row can carry a small history graph; the overlay grows downward/sideways in the chosen corner as detail increases. Saturation, text-size, and background-opacity sliders make it either prominent or near-invisible against the game. Valve frames it as step one; planned additions include detection of common bad-hardware scenarios and a performance summary in the Shift+Tab overlay.

**Ideas worth taking**: Generated-vs-real FPS split is the most honest handling of frame generation in any mainstream overlay and maps directly to Apple's MetalFX frame interpolation story. Adjustability of text scale + saturation + background opacity as three separate sliders. Explicit "levels" named by content rather than numbers.

**Weaknesses / avoid**: Windows-first telemetry means the feature degrades silently on other platforms; the CPU-temp kernel driver requirement on Windows shows the cost of deep metrics. Early beta complaints: default text too small to read, no CPU temp, no wattage, no vertical side layout like the Deck.

**Sources**: [Steam news: In-Game Performance Monitor, June 30 2025](https://store.steampowered.com/news/posts/?enddate=1752684106), [Tom's Hardware coverage](https://www.tomshardware.com/video-games/pc-gaming/steam-just-got-a-new-performance-overlay-you-can-now-view-real-fps-alongside-dlss-frs-generated-frames), [Tom's Hardware how-to](https://www.tomshardware.com/pc-components/gpus/how-to-use-steams-in-game-performance-monitor-to-display-real-fps-with-dlss-or-fsr-frame-generation-active), [PC Gamer on the Sept 2025 update](https://www.pcgamer.com/software/platforms/steam-mega-update-ends-our-long-national-game-sorting-nightmare-adds-cpu-temp-measuring-and-a-gajillion-other-bullet-points/), [9to5Linux on Linux overlay improvements](https://9to5linux.com/steam-client-adds-advanced-options-to-the-in-game-overlay-for-amd-nvidia-gpus), [Steam community beta thread](https://steamcommunity.com/groups/SteamClientBeta/discussions/3/591774445091167328/)

### Steam Deck performance overlay (SteamOS)

**Status**: Free, built into SteamOS on Steam Deck (and Legion Go S running SteamOS). Reached from the Quick Access Menu (the three-dot button) > Performance (lightning-bolt icon) > overlay level slider, positions 0-4 (0 = off). It is Valve's own SteamOS overlay, not MangoHud underneath; SteamOS desktop-mode users install MangoHud separately when they want a configurable overlay.

**What it shows**: Level 1: FPS counter only, top-left. Level 2: single horizontal strip along the top with FPS plus a frametime/FPS graph, CPU and GPU utilization %, CPU and GPU power draw (W), RAM and VRAM, gamescope frame-rate, and battery charge % plus estimated remaining playtime. Level 3: switches to a box anchored top-left, adds CPU and GPU speeds and temperatures, shows frametime min/max/avg ms, drops some battery detail. Level 4: everything plus per-core CPU usage and clocks, fan RPM, FSR status, frame count, and restored battery detail; it covers roughly a quarter of the 1280x800 screen.

**How it shows it**: One slider in a side panel cycles all levels and each level previews live as you move it. The design trades vertical real estate for information: line strip for playing, box for tuning. Battery (percent + hours remaining) is treated as a first-class perf metric, which is correct for a handheld.

**Ideas worth taking**: The level slider with live preview is the best possible UX for progressive disclosure: one control, immediate feedback, no menu spelunking. Estimated battery-remaining-next-to-consumption is the right model for energy UX on a MacBook. Dedicated level geometry (strip vs box) shows layout, not just item count, should change with density.

**Weaknesses / avoid**: Level 4's quarter-screen footprint is only acceptable for tuning sessions. Numbers are small enough that low-vision users are poorly served (text size is not adjustable on the Deck itself; desktop Steam added text scaling later, which suggests Valve learned this).

**Sources**: [Rock Paper Shotgun Steam Deck overlay guide](https://www.rockpapershotgun.com/how-to-use-performance-overlay-on-steam-deck), [Beebom level breakdown](https://beebom.com/how-enable-performance-overlay-fps-counter-steam-deck/), [Tom's Guide](https://www.tomsguide.com/how-to/how-to-enable-the-performance-overlay-on-the-steam-deck), [arvrtips overlay notes](https://arvrtips.com/steam-deck-performance-overlay/)

### MangoHud

**Status**: Free, open source (MIT), C++, Vulkan and OpenGL overlay for Linux; works natively and under Proton (SteamOS ships its own separate built-in overlay). Latest release v0.8.4 (May 27, 2026); actively maintained. Configured by text config files with layered precedence (`MangoHud.conf`, per-app `<name>.conf`, `wine-<name>.conf`, `./MangoHud.conf`, `$MANGOHUD_CONFIGFILE`, `$MANGOHUD_PRESETSFILE`) or the `MANGOHUD_CONFIG` comma-separated env var.

**What it shows**: Defaults on: FPS, frametime + frametime line graph (`frame_timing`), CPU load, GPU load. Optional: RAM, VRAM, CPU/GPU temperature, clocks, power draw, per-core load, per-app disk I/O (`io_read`/`io_write`), battery, frame count, FPS percentiles via `fps_metrics`, custom text and the output of a shell command as its own column. `fps_color_change` shifts FPS text color at configurable thresholds (e.g. red below 30, yellow, green above 60).

**How it shows it**: A corner-anchored strip (default `top-left`) of color-coded cells: large colored value with a small label beneath. `position` takes corner/edge presets plus `offset_x`/`offset_y` px; `width`, `height`, and `table_columns` control density; `horizontal` / `horizontal_stretch` flattens it into a single row; `hud_compact` minimizes. Typography: `font_size`, `font_scale`, `font_file` (TTF/OTF), `font_glyph_ranges` for CJK/Cyrillic, and text outline (`text_outline` default on, configurable color and thickness). Per-metric hex colors with defaults (CPU `2e97cb` blue, GPU `2e9762` green, VRAM `ad64c1` purple, RAM `c26693`, engine `eb5b5b`, frametime `00ff00` on `020202` background). Optional `graphs=` overlay charts for gpu_load, cpu_load, gpu_core_clock, gpu_mem_clock, vram, ram, cpu_temp, gpu_temp. Presets `-1` (default) and `0-4` (0 no HUD, 1 FPS only, 2 horizontal, 3 extended, 4 detailed) are switchable at runtime. Keybinds: Shift_R+F12 toggle HUD, Shift_R+F11 cycle position, Shift_R+F10 cycle preset, Shift_L+F1 FPS limit, Shift_L+F2 logging, Shift_L+F4 reload config, Shift_L+F3 upload log, Shift_R+F9 reset FPS metrics.

**Logging**: `toggle_logging`, `autostart_log`, `log_duration`, `log_interval`; logs uploadable to flightlessmango.com for web visualization (`permit_upload`, `upload_logs`) or rendered locally with `mangoplot`.

**Ideas worth taking**: Presets that reshape layout (vertical box vs horizontal strip) bound to a cycle hotkey. Color-as-metric-identity: each metric owns a hue everywhere (value, graph, label). Text outline as default for legibility on arbitrary content. Per-app config files as a power feature. Threshold-based FPS recoloring for at-a-glance health.

**Weaknesses / avoid**: Config is flat text keys; without GOverlay it is expert-only. No alarm/notification layer. Linux-only. The aesthetic (brightly colored monospace text) reads as tool, not platform: good for credibility with enthusiasts, bad for mainstream taste.

**Sources**: [MangoHud README](https://github.com/flightlessmango/MangoHud/blob/master/README.md), [MangoHud.conf annotated reference](https://github.com/flightlessmango/MangoHud/blob/master/data/MangoHud.conf), [DeepWiki configuration page](https://deepwiki.com/flightlessmango/MangoHud/2.2-configuration), [ArchWiki MangoHud](https://wiki.archlinux.org/title/MangoHud), [GitHub releases](https://github.com/flightlessmango/MangoHud/releases)

### GOverlay

**Status**: Free, open source (GPL-3.0), Qt6 GUI written in Free Pascal/Lazarus for Linux; distributed as a Flatpak on Flathub. Latest stable 1.9.4 (October 10, 2026); nightly builds publish daily. Requires MangoHud (mandatory since GOverlay 0.6.4); also configures vkBasalt, vkSumi, OptiScaler, and Proton environment tweaks.

**What it shows**: It is a configurator, not a monitor: card-based toggles for every MangoHud metric and vkBasalt effect, plus launch-command generation for Steam/Lutris. Ships PasCube, a bundled Vulkan demo, that renders the user's exact overlay config in real time so edits are previewed against live 3D content.

**How it shows it**: Sidebar navigation with Nerd Font icons; cards of checkboxes, sliders, and color pickers per tool. Per-game mode: selecting a game creates an XDG-compliant config directory (`MangoHud.conf`, `vkBasalt.conf`, `vkSumi.conf`, `OptiScaler.ini`, `fakenvapi.ini`, `bgmod.conf` + wrapper). 1.7.x added "Save as" for config export, global-enable context menu for MangoHud, and full XDG path compliance for configs and logs.

**Ideas worth taking**: The live preview panel is the big one: editing overlay settings blind against a real rendered scene is strictly better than editing and relaunching a game. Card-per-domain layout scales to many options without a giant form. Generating the launch command (env vars) as the output artifact respects that the user still owns their game config.

**Weaknesses / avoid**: Qt6 + Lazarus + Nerd Fonts looks alien next to native toolkits; it is unambiguously a power tool. Conceptual load remains high: it organizes MangoHud's options but does not simplify them.

**Sources**: [GOverlay repo and README](https://github.com/benjamimgois/goverlay), [GOverlay 1.7.2 release notes](https://github.com/benjamimgois/goverlay/releases/tag/1.7.2), [GOverlay releases](https://github.com/benjamimgois/goverlay/releases), [Flathub listing](https://flathub.org/en/apps/io.github.benjamimgois.goverlay)

### Apple Metal Performance HUD

**Status**: Built into macOS (and iOS/tvOS for own-built apps), free, Apple. Only draws inside Metal-based applications. Current documented form per the `MetalPerformanceHUD(1)` man page dated May 26, 2026 (macOS 26), which lists substantially more metrics than the original Xcode 14-era HUD; WWDC25 noted a visual refresh with better organization and selectable metrics. WWDC26 added `metalperftrace` (new CLI in macOS 27) plus an Instruments "Game Performance Overview" template, and MetricKit began including Metal frame-rate data in reports.

**What it shows**: Default top section: Metal device name, layer resolution, direct-vs-composited present indicator, memory allocated by the app and by Metal, Game Mode on/off. Default bottom: average FPS, GPU time, frame interval, plus a chart of frame interval for the past 120 frames. Full metric vocabulary (`MTL_HUD_ELEMENTS`): `device`, `rosetta` (x86_64 under translation), `layersize`, `layerscale` (content scale + pixel format), `memory`, `thermal` (`ProcessInfo.thermalState`), `fps`, `fpsgraph`, `framenumber`, `gputime` (from `MTLCommandBuffer` gpuStartTime/gpuEndTime), `presentdelay` (present-to-glass interval), `frameinterval`, `frameintervalgraph`, `frameintervalhistogram` (buckets equal to display refresh interval), `metalcpu` (scheduled command buffers/encoders + CPU encoding time), `shaders` (pipeline states, cached and compiled shaders + compile-time graph), `disk` (rusage bytes read/written/logical writes), `gputimeline` (per-encoder GPU time + timeline of past 3 frames each second), `toplabeledcommandbuffers`, `toplabeledencoders`. Apps using MetalFX get extra transient metrics: scaling method, input/target resolution, exposure, frame interpolator state.

**How it shows it**: Corner-anchored panel (default top-right) over the drawable. Named layouts via `MTL_HUD_ELEMENTS`: `FPS`, `Lite`, `Default`, `Rich`, `Full`, or an explicit comma-separated metric list. Placement: `MTL_HUD_ALIGNMENT` (9-way grid, e.g. `topleft`) or `MTL_HUD_POSITION_X/Y` in px. `MTL_HUD_SCALE` sets width as a fraction of drawable (default 0.2, minimum 300 px), `MTL_HUD_OPACITY` sets translucency. Zero-valued metrics auto-hide (`MTL_HUD_SHOW_ZERO_METRICS`), transient metrics auto-hide when the feature stops (`MTL_HUD_METRIC_TIMEOUT`), `MTL_HUD_SHOW_METRICS_RANGE` adds min/max of last 1200 frames beside the 120-frame average. An insights mode (`MTL_HUD_INSIGHTS_ENABLED`) highlights API-usage bottlenecks with per-insight timeout and report interval. On macOS a "Metal HUD" menu-bar item appears; triple-clicking the overlay opens a three-section configuration panel (HUD / Metrics / Insights) that can export the setup as a plist (`MTL_HUD_CONFIG_FILE`) or copy it as env vars. Enabling paths: Xcode scheme diagnostics, `MTL_HUD_ENABLED=1` env var, `MetalHudEnabled` Info.plist key, `MetalHUDForceEnabled` user default, `developerHUDProperties` on CAMetalLayer, or `metalperftrace setup --enable hud --pid` on a running process.

**Ideas worth taking**: `frameintervalhistogram` with buckets sized to the refresh interval is a brilliant, low-noise way to show pacing vs vsync. Auto-hiding zero metrics keeps the panel honest. `metalperftrace` look-back traces (`collect`, then `overview --json`) give per-process frame statistics after the fact without injection; a live `listen --pid` mode is unverified (check `metalperftrace --help` on macOS 27). Export-config-as-env-vars is a clean "share your setup" pattern.

**Weaknesses / avoid**: Cannot be enabled for arbitrary apps by end users without launch-time control or SIP-unsafe tricks; Metal-only; nothing about system-wide CPU/GPU/power. Console logging deprecated in favor of metalperftrace. The HUD is a developer tool cosmetically: functional but plain.

**Sources**: [MetalPerformanceHUD(1) man page](https://keith.github.io/xcode-man-pages/MetalPerformanceHUD.1.html), [Apple Tech Talk: Discover Metal Performance HUD](https://developer.apple.com/videos/play/tech-talks/110339/), [Customizing the Metal Performance HUD](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud), [Monitoring your Metal app's graphics performance](https://apple-docs.everest.mt/docs/xcode/monitoring-your-metal-apps-graphics-performance/), [WWDC26: Find and fix performance issues in Metal games](https://apple-docs.everest.mt/docs/wwdc/wwdc2026-388/), [WWDC26 Games guide](https://developer.apple.com/wwdc26/guides/games/)

### Apple Game Mode and Game Overlay (macOS)

**Status**: Game Mode since macOS Sonoma 14 (Apple silicon only); Game Overlay and the preinstalled Apple Games app (a launcher whose library lists App Store and non-App-Store games, e.g. from Steam, with Game Center achievements and challenges) are new in macOS 26 Tahoe; all current in macOS 27 Golden Gate. Free, system features.

**What it shows**: Game Mode gives a running fullscreen game highest-priority CPU/GPU access, lowers background task usage, and doubles Bluetooth sampling rate for lower controller/AirPods input+audio latency. It auto-enables on native fullscreen (games opt in via `LSSupportsGameMode`), shows a "Game Mode: on" banner, and its per-game toggle persists across launches. Game Overlay (Cmd-Esc, the Xbox or PlayStation controller button, or the Game menu-bar icon) contains: the running game with its achievements and leaderboards via Game Center; a friends voice/text chat button; system controls (volume, display brightness, connected controller settings, Now Playing widget, Gaming focus toggle); and settings incl. the Game Mode toggle. In macOS 26 the system can notify when a game is using significant energy on battery and offers Low Power Mode, tuned for gaming, switchable inside Game Overlay. macOS 27 gaming additions are developer-facing (metalperftrace, Metal 4.1 Neural-Engine temporal upscaler on M5 Pro/Max, GPTK 4 with agentic porting skills); no new consumer overlay metrics were announced.

**How it shows it**: Game Overlay slides in as a compact panel in the corner of the screen over the fullscreen game (Apple documents it while a game runs in full screen; a notification reminds players of the Cmd-Esc shortcut when a game starts). It is a settings/social surface, not a telemetry surface: it deliberately contains no FPS or resource numbers, and reviewers called that absence out as the missing piece.

**Ideas worth taking**: The energy notification + in-overlay energy-mode switch couples power state to play context: the same pattern belongs in a monitor ("this game is burning 40W on battery: switch to Low Power?"). Banner-on-enter-fullscreen is a cheap, non-modal way to announce a mode change.

**Weaknesses / avoid**: Discoverability is poor: overlay availability depends on the game path and confused even Apple community power users. The total absence of perf data is the documented gap (MacStories review explicitly wanted FPS there). Game Mode itself is an opaque on/off with no telemetry feedback on what it changed.

**Sources**: [Apple Support: Use Game Mode](https://support.apple.com/en-us/105118), [WWDC25: Level up your games](https://developer.apple.com/videos/play/wwdc2025/209/), [MacStories macOS Tahoe review, Games section](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/5/), [MacMost Tahoe hidden features](https://macmost.com/new-small-and-hidden-features-in-macos-tahoe.html), [Apple Community thread on Game Overlay access](https://discussions.apple.com/thread/256157905), [WWDC26 macOS guide](https://developer.apple.com/wwdc26/guides/macos/), [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)

### Third-party FPS overlays on macOS

**Status**: Sparse and fragile. "Count It" (abandoned; last version 1.5.0, macOS 10.11-10.13) was, per its own README, the only native general FPS counter; it instrumented apps via Frida (user-level, crashes some games) or DTrace (requires partially disabling SIP). MetalHUDEnabler (github.com/Trsvsr) enables Apple's own HUD per app: it writes `MTL_HUD_ENABLED` into a CrossOver bottle's config or `MetalForceHudEnabled` into an app's defaults (macOS Ventura and later). The Steam client overlay's performance monitor renders on macOS since the Sept 9, 2025 fixes, but only for Steam games and with less data than on Windows. HardwareMon-style tools use a plain always-on-top, click-through window fed by a local collector and explicitly avoid renderer hooks; they note exclusive fullscreen can still cover normal windows.

**What it shows**: Count It showed a frame-rate counter (plus session recording) for OpenGL/Metal apps. MetalHUDEnabler surfaces Apple's own HUD. Independent windows can show system telemetry plus FPS only when a data provider exists (PresentMon on Windows and MangoHud on Linux are documented providers; HardwareMon leaves the macOS collector unspecified, and metalperftrace on macOS 27 could fill that role).

**How it shows it**: Two honest patterns exist on macOS: (a) ask the OS to draw inside the target (Metal HUD env var / launchctl global), or (b) draw a separate always-on-top click-through window beside/over the game, which only survives in borderless/windowed modes. There is no pattern (c): nothing lets a third party hook present calls of a running arbitrary app the way RTSS does on Windows.

**Ideas worth taking**: For Coreography the viable design is pattern (b) done natively: a small always-on-top panel with click-through and opacity control, fed by system telemetry plus, if a live mode is confirmed, `metalperftrace` per-Metal-app frame statistics (macOS 27+; only `collect`/`overview` are documented). That yields an honest "gaming HUD" without injection, SIP changes, or private APIs.

**Weaknesses / avoid**: Injection-based designs are dead ends on modern macOS: SIP blocks DTrace-style instrumentation, and Frida-style hooking crashes titles and needs per-app surgery. Exclusive fullscreen will still occlude an external window; document borderless as the supported mode.

**Sources**: [Count It repo](https://github.com/mlarandeau/Count-It), [MacRumors thread: no general FPS overlay on macOS](https://forums.macrumors.com/threads/is-there-really-no-software-for-mac-that-shows-the-fps-of-any-application-game.2400401/), [myByways: enabling the Metal HUD](https://mybyways.com/blog/enabling-the-macos-metal-performance-hud/), [HardwareMon gaming overlay doc](https://raw.githubusercontent.com/louisboii747/HardwareMon/main/docs/GAMING_OVERLAY.md), [MetalPerformanceHUD man page, metalperftrace section](https://keith.github.io/xcode-man-pages/MetalPerformanceHUD.1.html)

### Console and handheld overlays (Armoury Crate SE, Legion Space, PlayStation, Xbox)

**Status**: Armoury Crate SE ships on all Asus ROG Ally variants (Windows handhelds), free; Real-time Monitor editor added in version 2.2.17.0 (August 2026). Lenovo Legion Space ships on Legion Go; its real-time monitor exists but the FPS counter repeatedly broke across driver updates in 2024 (community-tracked, unverified; treated as unreliable). Consoles: PS5 and Xbox Series X|S have no live FPS overlay; Xbox shows only a static FPS Boost / Auto HDR status chip in the upper-right of the Guide overlay when you press the Xbox button; a Title Performance Overlay exists but only for devkits (unverified).

**What it shows (Armoury Crate SE)**: Command Center button > Real-Time Monitor. Small transparent box, default top-right, drag-anywhere via touchscreen; repeated taps cycle views from a small set (CPU usage, GPU usage, FPS, temperature, battery level) to fully detailed (CPU and GPU usage, power draw, and a graph of your framerate). Per ASUS's FAQ: "APU WATT" is SoC (CPU+iGPU) package power; "BATT Power" is total system draw including screen and motors. Since 2.2.17.0 the editor exposes three independent layouts (Minimal, Row, Square), each with its own item list chosen from six stats (APU, Battery, FPS, CPU, GPU, VRAM); every item gets a checkbox, a display dropdown (Text Only vs Text & Graph, the latter adding a live line graph under the number), a color swatch (default all green), and a drag handle for ordering. Fully controller-navigable.

**How it shows it**: Three distinct densities correspond to contexts (Minimal for couch play, Square for docked debugging). The editor separates layout selection from item selection; ordering on screen follows list order.

**Ideas worth taking**: Per-metric "Text vs Text+Graph" is a more granular density control than global levels, and worth copying: let each metric decide if it earns a graph. Splitting package power vs system power is exactly the right energy model for a Mac (SoC package W vs battery W). Layout-name + per-layout item lists keep presets orthogonal to metric selection.

**Weaknesses / avoid**: Vendor-overlay FPS frequently disagrees with driver-level frame generation (ASUS's own FAQ admits it and tells AFMF users to use AMD's overlay): a monitor must say which number it reports. Legion Space's broken-counter saga shows users will abandon a built-in monitor over one unreliable metric, and the fix latency of a platform vendor is slow.

**Sources**: [Asus ROG guide: FPS and stats on ROG Ally](https://rog.asus.com/articles/guides/how-to-boost-gaming-performance-on-the-rog-ally/), [rogallylife: ACSE 2.2.17.0 Real-time Monitor editor](https://rogallylife.com/2026/08/21/armoury-crate-se-2-2-17-0-real-time/), [Asus ROG Ally FAQ](https://www.asus.com/global/support/faq/1050046/), [Asus ACSE introduction](https://www.asus.com/support/faq/1050220/), [Legion Go forum: broken FPS counter](https://gaming.lenovo.com/legion-go/post/legion-space-update-Gk7pjd4aLnbXxiR), [Tom's Guide: FPS on PS5](https://www.tomsguide.com/how-to-see-frames-per-second-fps-on-ps5), [Tom's Guide: FPS on Xbox Series](https://www.tomsguide.com/how-to-see-frames-per-second-fps-on-xbox-series-xors), [Xbox Wire: FPS Boost indicator](https://news.xbox.com/en-us/2021/03/15/five-legendary-bethesda-titles-get-fps-boost/)

## Cross-cutting patterns

- Density levels are the dominant UX: Steam desktop (4 named levels), Steam Deck (0-4 slider), NVIDIA (Basic/Advanced/Custom), Metal HUD (FPS/Lite/Default/Rich/Full), ACSE (Minimal/Row/Square), MangoHud presets (-1..4). Two orthogonal knobs recur: how much detail, and which metrics; the good designs keep presets independent of the metric checklist.
- The frame-time graph is the universal "real" signal: Steam FPS-over-time, Deck frametime strip, MangoHud frametime line, Metal HUD frameinterval chart + histogram. NVIDIA notably lacks one and reviewers complain.
- Legibility kit: background opacity slider (everyone), text outline (MangoHud default on), text size / UI scale (Steam, NVIDIA, Deck via scale), saturation (Steam), corner presets + pixel offsets (everyone), click-through (Game Bar, independent-window tools), drag-to-reposition (ACSE, Game Bar widgets).
- Color is metric identity, not decoration: MangoHud's per-metric palette, Steam's saturation slider, ACSE's per-item swatches. Consistent hue per metric across value/graph/label is the common thread.
- Shortcuts split toggle vs cycle: Alt+R / Alt+Shift+R (NVIDIA), Ctrl+Shift+O (AMD), Shift_R+F12 / Shift_R+F11 / Shift_R+F10 (MangoHud HUD/position/preset). Cycling position is as valuable as cycling content.
- Frame generation breaks everyone's FPS number: Steam splits generated vs real frames; ACSE admits divergence from AFMF and defers to AMD's overlay; Metal HUD tracks MetalFX interpolator state as a metric. Honest handling is now table stakes.
- Power storytelling differs by platform: handhelds foreground watts and hours-remaining (Deck L2, ACSE APU vs BATT); desktop overlays show W but no budget; Apple's Game Overlay shows energy mode but no number. Nobody yet presents "energy per frame" or "time remaining" on desktop-class Macs.
- Overlay cost matters: NVIDIA App cost up to 15% (reported) until Game Filters were disabled; Game Bar reportedly eats 1-3% GPU idle (unverified). A monitor that perturbs its own measurement loses credibility; lightweight sampling and GPU-cheap rendering are features.
- Progressive ownership of the overlay surface: pinned widgets (Game Bar), persistent HUD across launches (Metal HUD env vars / config file), hot-reloadable configs (MangoHud Shift_L+F4): the overlay is a long-lived companion, not a dialog.

## Implications for Coreography

1. Build "HUD mode" as a property of the Coreography window, not a separate overlay engine. An always-on-top, click-through, opacity/scale-adjustable compact panel is the only honest overlay a third party can do on macOS; document borderless-mode gaming as the supported scenario. Do not attempt injection: SIP and the lack of a public present-hook make it a dead end (Count It's fate).
2. Investigate metalperftrace (macOS 27) as the FPS/frametime source. Documented: look-back `collect` and per-process `overview --json`, usable for "what happened in the last 10 minutes of play". Unverified: live `listen --pid` streaming and `setup --enable hud`. Prototype on a macOS 27 Mac before committing; label the FPS source in the UI either way.
3. Ship named density presets plus per-metric detail: e.g. "FPS only" / "Strip" / "Panel" mirroring Deck L1/L2/L3 geometry (single number, top strip, corner box). Let each metric toggle Text vs Text+Graph individually (ACSE's editor is the best reference). One hotkey toggles HUD mode, a second cycles density.
4. Realistic metric set for a Mac gaming HUD: per-frontmost-Metal-app FPS, frame interval + interval graph (120-frame window like Apple's HUD) and optionally a refresh-rate-bucketed interval histogram; GPU %, GPU W, SoC package W vs system/battery W, hours-remaining on battery (Deck model); CPU % (per-cluster if possible), RAM, VRAM-equivalent (unified memory pressure + swap), network, thermal pressure (`ProcessInfo.thermalState`), MetalFX upscaler/interpolator state when detectable, and Game Mode on/off.
5. Legibility defaults: vibrancy/material background with user opacity, SF tabular figures, optional text outline or scrim, text scale slider, 4-corner presets + drag, click-through. Test against bright/noisy game footage; Steam's saturation+opacity+size triad is the checklist.
6. Energy is Coreography's differentiator on Apple silicon laptops: nobody on desktop OSes connects watts to play time. Surface battery-hours-at-current-draw next to FPS, and consider a Low Power Mode toggle shortcut (mirroring Game Overlay's energy integration).
7. Don't resurrect NVIDIA's mistake: keep the monitor's own CPU/GPU cost visible and tiny; publish its overhead. Sample lazily when hidden.
8. Treat frame generation honestly: if MetalFX frame interpolation is active, show rendered vs interpolated frame rates separately (Steam's split), or at minimum label the displayed FPS source.
9. Non-goals learned from others: no widget store, no social features, no in-overlay process killing unless it stays a one-click "top offender" hint (Game Bar's Resources widget is the right scope).

## Sources

- [TechRadar: How to use Xbox Game Bar](https://www.techradar.com/how-to/how-to-use-xbox-game-bar-in-windows-10)
- [Tech How: Show CPU/GPU/RAM/VRAM/FPS in Windows 11](https://www.techy.how/tutorials/win11-show-cpu-gpu-vram-ram-usage)
- [Microsoft Q&A: removing Game Bar performance metrics and compact mode](https://learn.microsoft.com/en-us/answers/questions/3862234/how-to-remove-widget-in-xbox-game-bar-performance)
- [GamerHardware: How to use Game Bar in Windows 11](https://gamerhardware.org/how-to-use-game-bar-windows-11/)
- [ASUS support: Game Bar features incl. Resources and Widget Store](https://www.asus.com/support/faq/1053128/)
- [Thurrott Windows 11 Field Guide: Game Bar (24H2)](https://www.thurrott.com/books/windows-11-field-guide/archived-22h2/313981/game-bar-24h2)
- [Microsoft Support: Edge Game Assist FAQ](https://support.microsoft.com/en-us/edge/microsoft-edge-game-assist-faq)
- [EliteGear: Game Bar FPS counter (incl. 2025 redesign and Copilot notes)](https://www.elitegear.io/games/windows-fps-anzeigen/)
- [The Verge: Windows + Xbox handheld full-screen experience](https://www.theverge.com/news/682011/microsoft-windows-xbox-pc-combination-features-rog-xbox-ally-devices)
- [Windows Central: hands-on with handheld gaming mode](https://www.windowscentral.com/gaming/xbox/i-tried-windows-11s-new-handheld-gaming-mode-on-the-xbox-ally-will-this-save-gaming-on-windows-handhelds)
- [Asus ROG: getting to the Windows desktop on Xbox Ally](https://rog.asus.com/articles/guides/how-to-get-to-the-windows-desktop-on-the-rog-xbox-ally-and-rog-xbox-ally-x/)
- [Notebookcheck: restart needed after desktop mode](https://www.notebookcheck.net/Potentially-annoying-ROG-Xbox-Ally-full-screen-experience-requires-restart-for-optimizations-after-switching-from-Windows-desktop.1093126.0.html)
- [NVIDIA KB: in-game performance and latency overlay](https://nvidia.custhelp.com/app/answers/detail/a_id/5084/~/nvidia-app-in-game-performance-and-latency-overlay)
- [NVIDIA: App release highlights](https://www.nvidia.com/en-us/software/nvidia-app/release-highlights/)
- [NVIDIA: upgrade to NVIDIA App (GFE sunset notice)](https://www.nvidia.com/en-us/geforce/news/gfecnt/20265/upgrade-to-nvidia-app/)
- [NVIDIA: App beta adds VSR/HDR sliders; 1% lows note](https://www.nvidia.com/en-in/geforce/news/nvidia-app-beta-update-rtx-vsr-hdr-controls-and-more/)
- [Tom's Hardware: NVIDIA App 1.0 exits beta, GFE deprecated](https://www.tomshardware.com/pc-components/gpus/nvidia-app-version-1-0-exits-beta)
- [Tom's Hardware: NVIDIA App performance penalty](https://www.tomshardware.com/pc-components/gpus/we-tested-nvidia-app-performance-problems-games-run-up-to-15-percent-slower-with-the-app)
- [NVIDIA: Reflex Latency Analyzer](https://www.nvidia.com/en-us/geforce/news/reflex-latency-analyzer-360hz-g-sync-monitors/)
- [HowToGeek: in-game monitoring tools comparison](https://www.howtogeek.com/3-in-game-performance-monitoring-tools-i-recommend-to-every-pc-gamer/)
- [LinusTechTips forum: NVIDIA overlay text size limited to Standard/Large](https://linustechtips.com/topic/1599311-nvidia-app-stats-overlay-text-size/)
- [AMD: monitor performance metrics with Adrenalin](https://www.amd.com/en/resources/support-articles/faqs/DH3-038.html)
- [AMD: Radeon Overlay performance monitoring](https://www.amd.com/en/resources/support-articles/faqs/DH-026.html)
- [AMD: Adrenalin performance page](https://www.amd.com/en/products/software/adrenalin/software-performance.html)
- [AMD forum: metrics logging missing CSV](https://pcforum.amd.com/s/question/0D5KZ000010HjgD0AS/adrenalin-metrics-logging-not-producing-csv-file)
- [Progressive Robot: Radeon performance logging](https://blog.progressiverobot.com/how-to-use-radeons-built-in-radeon-performance-logging)
- [Steam news: In-Game Performance Monitor (June 30, 2025)](https://store.steampowered.com/news/posts/?enddate=1752684106)
- [Tom's Hardware: Steam performance overlay with DLSS/FSR split](https://www.tomshardware.com/video-games/pc-gaming/steam-just-got-a-new-performance-overlay-you-can-now-view-real-fps-alongside-dlss-frs-generated-frames)
- [Tom's Hardware: how to use the Steam monitor](https://www.tomshardware.com/pc-components/gpus/how-to-use-steams-in-game-performance-monitor-to-display-real-fps-with-dlss-or-fsr-frame-generation-active)
- [PC Gamer: September 2025 Steam update (CPU temp, DPI scaling, macOS fixes)](https://www.pcgamer.com/software/platforms/steam-mega-update-ends-our-long-national-game-sorting-nightmare-adds-cpu-temp-measuring-and-a-gajillion-other-bullet-points/)
- [9to5Linux: Steam overlay advanced options for AMD/NVIDIA](https://9to5linux.com/steam-client-adds-advanced-options-to-the-in-game-overlay-for-amd-nvidia-gpus)
- [Steam community beta discussion](https://steamcommunity.com/groups/SteamClientBeta/discussions/3/591774445091167328/)
- [Rock Paper Shotgun: Steam Deck performance overlay levels](https://www.rockpapershotgun.com/how-to-use-performance-overlay-on-steam-deck)
- [Beebom: Steam Deck FPS counter levels](https://beebom.com/how-enable-performance-overlay-fps-counter-steam-deck/)
- [Tom's Guide: Steam Deck performance overlay](https://www.tomsguide.com/how-to/how-to-enable-the-performance-overlay-on-the-steam-deck)
- [arvrtips: Steam Deck overlay 0-4](https://arvrtips.com/steam-deck-performance-overlay/)
- [MangoHud README](https://github.com/flightlessmango/MangoHud/blob/master/README.md)
- [MangoHud.conf annotated config](https://github.com/flightlessmango/MangoHud/blob/master/data/MangoHud.conf)
- [DeepWiki: MangoHud configuration](https://deepwiki.com/flightlessmango/MangoHud/2.2-configuration)
- [ArchWiki: MangoHud](https://wiki.archlinux.org/title/MangoHud)
- [MangoHud releases](https://github.com/flightlessmango/MangoHud/releases)
- [GOverlay repository](https://github.com/benjamimgois/goverlay)
- [GOverlay 1.7.2 release notes](https://github.com/benjamimgois/goverlay/releases/tag/1.7.2)
- [GOverlay releases](https://github.com/benjamimgois/goverlay/releases)
- [GOverlay on Flathub](https://flathub.org/en/apps/io.github.benjamimgois.goverlay)
- [MetalPerformanceHUD(1) man page (macOS 26, May 2026)](https://keith.github.io/xcode-man-pages/MetalPerformanceHUD.1.html)
- [Apple Tech Talk: Discover Metal Performance HUD](https://developer.apple.com/videos/play/tech-talks/110339/)
- [Apple docs: Customizing the Metal Performance HUD](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud)
- [Apple docs: Monitoring your Metal app's graphics performance](https://apple-docs.everest.mt/docs/xcode/monitoring-your-metal-apps-graphics-performance/)
- [WWDC26 session: Find and fix performance issues in your Metal games (metalperftrace on macOS 27)](https://apple-docs.everest.mt/docs/wwdc/wwdc2026-388/)
- [Apple Support: Use Game Mode](https://support.apple.com/en-us/105118)
- [WWDC25: Level up your games](https://developer.apple.com/videos/play/wwdc2025/209/)
- [WWDC26 Games guide (Metal 4.1, GPTK 4, MetricKit)](https://developer.apple.com/wwdc26/guides/games/)
- [WWDC26 macOS guide](https://developer.apple.com/wwdc26/guides/macos/)
- [macOS 27 Golden Gate release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- [MacStories: macOS 26 Tahoe review (Games app and Game Overlay)](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/5/)
- [MacMost: Tahoe hidden features (Game Overlay)](https://macmost.com/new-small-and-hidden-features-in-macos-tahoe.html)
- [Apple Community: Tahoe Game Overlay not working](https://discussions.apple.com/thread/256157905)
- [Hypercritic: WWDC25 Games launcher and GPTK 3.0 (Metal HUD refresh)](https://hypercritic.org/wwdc-2025-apple-games-launcher-gptk-3-0)
- [Count It repository (abandoned macOS FPS counter)](https://github.com/mlarandeau/Count-It)
- [MacRumors forum: no general FPS counter on macOS; MetalHUDEnabler](https://forums.macrumors.com/threads/is-there-really-no-software-for-mac-that-shows-the-fps-of-any-application-game.2400401/)
- [myByways: enabling the macOS Metal Performance HUD](https://mybyways.com/blog/enabling-the-macos-metal-performance-hud/)
- [HardwareMon gaming overlay doc (no-injection pattern)](https://raw.githubusercontent.com/louisboii747/HardwareMon/main/docs/GAMING_OVERLAY.md)
- [Asus ROG: boost gaming performance on ROG Ally (Real-Time Monitor)](https://rog.asus.com/articles/guides/how-to-boost-gaming-performance-on-the-rog-ally/)
- [rogallylife: Armoury Crate SE 2.2.17.0 Real-time Monitor editor](https://rogallylife.com/2026/08/21/armoury-crate-se-2-2-17-0-real-time/)
- [Asus ROG Ally FAQ (APU WATT vs BATT, AFMF interplay)](https://www.asus.com/global/support/faq/1050046/)
- [Asus ACSE introduction](https://www.asus.com/support/faq/1050220/)
- [Lenovo forum: Legion Space FPS counter breakage](https://gaming.lenovo.com/legion-go/post/legion-space-update-Gk7pjd4aLnbXxiR)
- [LegionGoLife: AFMF2 setup (turn off other monitors)](https://legiongolife.com/amd-fluid-motion-frames-afmf-2-legion-go/)
- [Tom's Guide: how to see FPS on PS5](https://www.tomsguide.com/how-to-see-frames-per-second-fps-on-ps5)
- [Tom's Guide: how to see FPS on Xbox Series X|S](https://www.tomsguide.com/how-to-see-frames-per-second-fps-on-xbox-series-xors)
- [Xbox Wire: FPS Boost and Guide indicator](https://news.xbox.com/en-us/2021/03/15/five-legendary-bethesda-titles-get-fps-boost/)
- [GameSpot: FPS Boost games and the indicator](https://www.gamespot.com/articles/fps-boost-all-games-supported-series-x-s/1100-6495975/)

## Verification log

Fact-checked 2026-10-17 by fetching the cited sources plus official pages (NVIDIA release highlights and KB, AMD FAQs, Valve Steam news and beta thread, Apple man pages, WWDC25 and WWDC26 sessions and guides, Apple Support, GitHub repos and releases, ASUS/ROG FAQs, The Verge, Notebookcheck, Tom's Hardware/Guide, MacStories, RPS, Beebom, arvrtips, HowToGeek, EliteGear, Thurrott). Roughly 90 concrete claims checked across about 45 sources; most held up.

Corrections made (old -> new):

1. NVIDIA summary and weaknesses: "caused up to 15% slowdowns until Game Filters were defaulted to off" -> 15% was the peak user report; Tom's Hardware measured 2-12% itself and verified that disabling Game Filters and Photo Mode removes the penalty; no shipped default-off fix was documented in the cited article. Overlay itself measured clean.
2. NVIDIA status: "fully replaced GeForce Experience and Control Panel" -> NVIDIA's stated replacement; both remain available in a legacy state (Tom's Hardware, Nov 12 2024). "removed from driver packages at 566.36" kept but reworded and attributed to Tom's Hardware.
3. NVIDIA views: "Views: Basic / Advanced / Custom" -> only Alt+Shift+R cycling plus the Custom view with "View All" is documented (NVIDIA KB, HowToGeek); Basic/Advanced view names marked unverified.
4. NVIDIA overlay font color: "added in 11.0.3" -> added in beta release 10.0.3, October 2024 (release highlights).
5. NVIDIA 1% low FPS: now pinned to beta 10.0.2 (2024), matching the existing "added 2024".
6. AMD metrics list: replaced with the documented set (frametime, 99th-percentile FPS, junction temp, TBP, GPU memory in MB, CPU frequency/power); VRAM is reported in MB, not GB.
7. AMD layout: "three tabs: Tracking / Overlay / Settings" -> tracking panel with per-metric toggles plus named Overlay and Settings tabs (AMD DH3-038).
8. AMD AFMF advice attribution: "AMD itself tells users to prefer its own overlay" -> ASUS's FAQ gives that advice (AMD doc says nothing).
9. Steam Deck: "Underneath is MangoHud" -> it is Valve's own SteamOS overlay; MangoHud is a separate install used in desktop mode (no cited source supports MangoHud underneath).
10. MangoHud: language "C" -> "C++"; "used under Proton and is the basis of the SteamOS overlay" -> works natively and under Proton (SteamOS ships its own overlay).
11. MangoHud presets: "-1/0/1/2 (2 = horizontal)" -> presets -1 (default) and 0-4 (0 no HUD, 1 FPS only, 2 horizontal, 3 extended, 4 detailed); also fixed in Cross-cutting patterns.
12. GOverlay: "Requires MangoHud (since 0.6.4)" -> "mandatory since GOverlay 0.6.4" (README wording).
13. Game Overlay contents: "friends and GameChat voice/text" -> friends voice/text chat (GameChat is not Apple terminology); "also usable in windowed mode" -> documented for fullscreen games only.
14. Controller button: "controller home button" -> Xbox or PlayStation controller button (MacStories, Apple Support).
15. Added the Apple Games app (macOS 26) to the Game Mode section; scope named it and the file omitted it (MacStories, WWDC25 session 209).
16. Count It: "frame-rate counter + chart" -> counter plus session recording (README documents sessions, not a chart); "was the only native general FPS counter" -> attributed to its own README.
17. MetalHUDEnabler: "applies the Metal HUD env-var trick" -> precisely: writes MTL_HUD_ENABLED into CrossOver bottle configs or MetalForceHudEnabled into app defaults, macOS Ventura+ (repo README).
18. Steam on macOS: "with a reduced metric set" -> "with less data than on Windows" (Valve's Windows-first statement).
19. HardwareMon providers: metalperftrace listed as an existing macOS provider -> HardwareMon leaves the macOS collector unspecified; metalperftrace noted as a candidate.
20. Console sources: replaced two dead Tom's Guide links (doubled /how-to/how-to-see-... slugs, 404) with the working URLs; dropped the unofficial mangohud.com FAQ from sources (not affiliated with the project; the README and MangoHud.conf cover the same ground).
21. Armoury Crate SE overlay cycle: minimal view items corrected to "CPU usage, GPU usage, FPS, temperature, battery level" (ASUS ROG guide) instead of "battery, temperature, FPS, clock".
22. Game Bar: "(per user reports) a compact display mode" -> compact mode is a documented Game Bar setting (Microsoft Q&A answer).
23. Added "(unverified)" to: Game Bar 1-3% idle GPU cost, NVIDIA Basic/Advanced view names, Legion Space 2024 FPS-counter breakage, Xbox Title Performance Overlay being devkit-only.

Verified as correct (highlights): NVIDIA App 1.0 Nov 2024 and latest 11.0.9.565 with CPU stats, MCP server, RTX Spark support, Performance Mode beta; GTX 600+ requirement; Alt+R/Alt+Shift+R; GFE web-server shutdown notice. Steam overlay beta June 17, stable June 30, 2025; Sept 9, 2025 update with CPU temp via optional kernel-mode driver, DPI scaling, DLSS-vs-game FPS fix, macOS font fix, Vulkan/OpenGL/D3D12 chart speedups; four level names; Windows-first caveat. AMD Ctrl+Shift+O, legacy Alt+R and 1-10 s interval, %LOCALAPPDATA%\AMD\CN, 0.25-5 s interval, overlay location/size/columns/transparency/text colors; driver V32.0.12011.7001 for AFMF monitoring. Steam Deck levels 1-4 incl. level 2 strip with graph and gamescope framerate, level 3 box with min/max/avg frametime, level 4 fan/FSR/frame count and quarter-screen cost; Legion Go S on SteamOS. MangoHud v0.8.4 May 27 2026, MIT, defaults, hex colors (cpu 2E97CB etc., frametime 00FF00 on 020202), text_outline default on, all keybinds, graphs list, config precedence, flightlessmango.com uploads, mangoplot. GOverlay Qt6/Lazarus, GPL-3.0, 1.9.4 Oct 10 2026, nightlies, PasCube live preview, per-game config file list, 1.7.2 Save-as/XDG/global-enable. Metal Performance HUD: every metric and env var in the man page (May 26 2026, macOS 26), named layouts FPS/Lite/Default/Rich/Full, 9-way alignment, 300 px minimum, zero-metric hiding, insights, menu bar + triple-click panel, plist/env export; metalperftrace collect/overview/listen/setup confirmed by the man page and WWDC26 session 388, which calls it new in macOS 27; MetricKit Metal frame-rate data, Metal 4.1 upscaler on M5 Pro/Max, GPTK 4 agent skills confirmed by the WWDC26 Games guide. Game Mode Sonoma/Apple-silicon-only, doubled Bluetooth sampling, LSSupportsGameMode, persistent per-game toggle, Cmd-Esc and menu-bar Game icon, Low Power Mode in overlay; MacStories wanting frame rates in the overlay. Xbox full screen shipped Oct 16 2025, long-press task switcher and swipe-up desktop, desktop stays resident until restart, home-app option, ~2 GB RAM saved. Game Bar rename, Win+G/Xbox button, Performance Log Users + restart for FPS, pinning, widgets incl. Resources and Widget Store, Copilot widget 2025 with model-training opt-out, Controller Bar. ACSE 2.2.17.0 editor (layouts, six stats, Text/Text+Graph, green swatches, drag order); APU WATT vs BATT Power; Xbox Guide FPS Boost/Auto HDR chip.

Remains unverified (flagged inline where relevant): NVIDIA "Basic/Advanced" overlay view names; Game Bar idle GPU cost figure; Legion Space FPS-counter breakage history and Xbox devkit Title Performance Overlay; NVIDIA App performance-panel auto-tuning details (kept, consistent with public docs but not re-checked); AMD metrics-logging CSV bug status (forum report); Steam Deck level 3 frametime min/max/avg is from Beebom only. Lenovo forum link returns 403 to automated fetchers; Tech How link rate-limits (429) but is not dead.

Coordinator correction (2026-10-17): Apple's WWDC26 session 388 page and its transcript show only the `collect` and `overview` subcommands of `metalperftrace`, with no live streaming, `listen`, `setup` or `--pid`. The claims built on `listen --pid` were rewritten as unverified, pending a check on a macOS 27 machine.
