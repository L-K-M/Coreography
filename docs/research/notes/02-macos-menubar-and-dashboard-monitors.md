# Third-party macOS system monitors (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

## Summary

- iStat Menus 7.5 (Bjango) remains the reference implementation: nine core menu bar items (a tenth, Astronomy, added in 7.5), deeply editable dropdown menus, dual-line menu bar modes, per-cluster E/P core colouring, history graphs up to 28 days, a rules engine, weather, and a combined mode. $11.99 single / $14.99 family, plus one-off weather data packs after the included 6 months (from $2.49 for 12 months; explicitly not a subscription). It is the product Coreography's target user already loves; its constraint is physical: everything lives in a 22 pt menu bar and a dropdown the width of a menu.
- Stats (exelban/stats) is the free, open-source rival: 42.6k GitHub stars, 9 modules, 15 widget types in its source (`widget_t`), per-module popups, MIT licence, one developer. Its widget model (mini, line, bar, pie, network chart, speed, tachometer, label, stack, battery, memory, dot, text) is the clearest public vocabulary of menu bar micro-visualizations. New in 2026: an optional "System Stats" remote web dashboard.
- The crowded, nearly solved problem is the menu bar. The open gap is a beautiful graph-first window. Almost every competitor is a menu bar app whose dropdown is a cramped compromise; the actual window-based monitors (XRG, System Dashboard, Activity Monitor itself) look dated or sparse.
- A wave of new indie entrants in 2025-2026 signals where taste is heading: Tempo (notch island, health rings, 30-day local history, top-10 process list), Orcylo (process folding 700 processes to 25 apps, per-app watts, AI-limit widgets), tstats (MLX/GPU monitoring, Apple Silicon only, $7.99/yr), MoniThor (sparklines, click vs option-click panel/dashboard tiers), MacMonitor (free MIT, power rails, standalone WidgetKit widgets).
- Common visual vocabulary worth adopting: rings/gauges for utilization at small sizes, mirrored bidirectional bars for disk and network I/O, per-core bars grouped and coloured by E/P cluster, memory-pressure gauge, icon-identified top-process rows folded by app, per-vital accent colours, optional monochrome/template look.
- Efficiency is now a marketing axis: iStat claims as little as 1/5 the CPU of v6; Tempo advertises ~2% CPU / ~40 MB and pauses process scans when hidden; tstats claims ~0.3%; Stats documents which modules cost most (Sensors, Bluetooth). Coreography must be honest and cheap to run.
- Sensors and fans on Apple Silicon are the hard, fragile domain: SMC keys change per SoC (iStat added "super cores" in 7.3, Stats added M6 in 3.0.21), privileged helpers are required for App Store distribution, and Stats' author openly notes sensor-to-core mapping is guesswork.
- Pricing spread: free open source (Stats, MacMonitor, Hot, MenuMeters, XRG, Übersicht), $5-15 one-time (iStat Menus $11.99, TG Pro $10, App Tamer $14.95, Tempo $14.99 max, Orcylo EUR 9.99, iStatistica Pro $9.99), subscriptions (Sensei $29/yr, tstats $7.99/yr, CleanMyMac). One-time pricing is the norm for monitors; subscriptions are grudgingly tolerated only in "suite" products.
- Dead or dying tools confirm pattern risk: GeekTool (unmaintained since the mid-2010s), Monity (Today-view widget, last update Mojave era), eul (last release 2021), iGlance (explicitly unmaintained), MenuMeters (last release 2021, recommends Stats). Notification-Center-only and single-developer free tools fade; window-anchored, opinionated, paid apps persist.

## Tools

### iStat Menus 7 (Bjango)

- **Status**: macOS menu bar system monitor. v7.5 released 14 September 2026 ("beautiful Liquid Glass menus to macOS 27" plus a new Astronomy item with seeing, transparency and cloud-cover forecasts); requires macOS 13.5+. Paid: $11.99 single licence, $14.99 family (5 users), upgrade from v6 $9.99 single / $12.99 family, all licences include 6 months of weather data. Also on Setapp ($9.99/mo bundle) and the Mac App Store (feature differences: no fan control in the MAS build). 14-day free trial. Actively maintained; major release roughly yearly since 7.0 (31 July 2024).
- **What it shows**: CPU (per-core, load average, uptime, frequency, top apps), GPU (utilization, memory, temperature, frequency, FPS), memory (pressure, compressed, swap, wired/app breakdown, top apps), disks (capacity, read/write activity, S.M.A.R.T., per-app disk usage, purgeable space optional), network (per-interface bandwidth, history, public/private IP, ping, Wi-Fi name, connectivity indicator, link speed, VPN country flag (unverified)), sensors (temperatures, fans, voltages, current, power, CPU/GPU frequency), power/battery (charge, health, cycles, energy mode, AirPods/Bluetooth device levels, history graph), time (clocks, 7/14-day rolling calendars, world clocks with sun/moon altitude graphs, blue/golden hour), weather (hourly forecast, weekly overview, UV, pressure, visibility; one-off data packs after the included 6 months, from $2.49 for 12 months, no subscription), astronomy (7.5: seeing, transparency, cloud cover), plus a Combined item and Rules notifications.
- **How it shows it**: Nine independently toggleable menu bar items, each composed of small add/remove-able sub-items. Menu bar modes added in 7.0 include dual-line label+bar, dual-line label+value, and icon modes; CPU offers pie chart, live graph, history graph, percentage text, and a "CPU" label. E and P cores can be coloured differently in every graph mode, and any mode can show E-only, P-only, or both. Menu bar spacing is standard or compact. Dropdown menus are fully user-editable: hovering the menu preview in settings exposes per-section switches and drag handles to reorder. Per the user's own description of the dropdowns: CPU dropdown shows a stacked user/system bar history, per-core efficiency/performance rings, and a process list with icons; GPU shows rings with FPS; memory shows pressure plus memory rings; disks show a read/write mirrored bar chart and capacity rings. Themes: a carousel sets menu bar theme and dropdown theme separately; the default theme uses the macOS accent colour; light/dark previewable; "Show Background" toggles the dark well behind graphs. History graph ranges: 10 minutes; 1, 3, 6, 12 hours; 1, 3, 7, 14, 28 days. Combined mode merges arbitrary items into one menu bar entry with its own settings and a configurable dropdown with more available sections (per-section sensor/disk/world-clock picking). Rules: notifications on CPU, GPU, memory, disk, network, sensor, battery, power and weather conditions (e.g. CPU > 60% for 10 s, public IP changed, internet down, disk space low, daylight-saving changes), plus rules that switch fan-control modes; hotkeys to open menus live on the rules tab. Fan control (7.0) replaced fan rules with curves that ramp speeds gradually. Sensors menu has "simple" and "detailed" modes. Active GPU shown as a letter (I/D/A/N for Intel-integrated/Discrete/AMD/Nvidia). Per-app figures combine child processes ("Combine Processes" toggle) so Safari's tabs roll up to one number. Optional helper enables admin-free install for basics.
- **Ideas worth taking**: the editable-menu model (every dropdown section is a reorderable, hideable unit) maps directly to a window made of rearrangeable cards; per-cluster core colouring and cluster-only views; dual-line label+value stacking for dense readouts; mirrored disk read/write chart; a rules engine with metric + threshold + duration; history ranges from minutes to weeks with one-minute-ish sampling; efficiency as a headline feature (claimed "as little as 1/5th the CPU usage of iStat Menus 6"); "simple vs detailed" sensor list for novices vs power users.
- **Weaknesses / avoid**: 22-pt menu bar real estate caps everything; dropdowns scroll on smaller screens; upgrade reset user settings from v6 (noted in the heise review); weather costs extra via one-off data packs whose price scales with request frequency (the heise reviewer could not transfer an old weather purchase), which some reviews found confusing; so many options that setup is a real task; closed source. For Coreography: do not copy the "everything in a menu" information architecture, copy its density grammar and let it breathe in a window.
- **Bjango design thinking (Marc Edwards)**: Edwards publishes the reasoning behind this class of UI. "Designing macOS menu bar extras" (Apr 2022) documents the real geometry: menu bar 24 pt on Big Sur+, up to 43 pt on notched MacBooks under display scaling, but a fixed 22 pt working area for extras; 16x16 pt circular icons balance system items; template images tinted by macOS beat colour assets; Apple uses 35% opacity for disabled states. Other relevant articles: "Two decades of Bjango" (iStat began as a 2005 Dashboard widget, moved to a menu bar app because "show all the important stats in a well made app"), "Interaction density" (how much information and control fits per pixel), "Design tool memory usage" (benchmarking ethos applied to app overhead), "Design systems need a colour space" (Mar 2025). Interview quote (TheSweetBits): "Our goal is still to show all the important stats in a well made app."
- **Version arc 7.0-7.5**: 7.0 (Jul 2024) full reboot, the modes listed above, 30+ localizations; 7.0.1-7.0.2 added app launchers in menus, country flags on clock items, link speed, network locations, power history graphs; 7.1 (Feb 2025) moon details, better world-clock search; 7.2 (Nov 2025) Liquid Glass icon with mono support, Tahoe fixes; 7.3 (May 2026) "super cores" support in CPU, network interface-icon mode, cloud-cover forecast graphs, M3/M4 fan control; a build-only 7.2 (2273) shipped 1 April 2026 with an installer security fix; there was no public 7.4; 7.5 (Sep 2026) Liquid Glass menus on macOS 27, Astronomy item.
- **Sources**: https://bjango.com/mac/istatmenus/, https://bjango.com/mac/istatmenus/versionhistory/, https://bjango.com/help/istatmenus7/welcome/, https://bjango.com/help/istatmenus7/global/, https://bjango.com/help/istatmenus7/menus/, https://bjango.com/help/istatmenus7/cpugpu/, https://bjango.com/help/istatmenus7/memory/, https://bjango.com/help/istatmenus7/disks/, https://bjango.com/articles/designingmenubarextras/, https://bjango.com/articles/, https://mjtsai.com/blog/2024/08/01/istat-menus-7/, https://tidbits.com/watchlist/istat-menus-7-0-2/, https://eshop.macsales.com/blog/95542-istat-menus-7-is-the-latest-in-a-long-line-of-delightful-mac-monitoring-apps-from-bjango/, https://thesweetbits.com/inside-istat-menus-from-bjango/, https://www.heise.de/en/news/Mac-Major-update-for-popular-menu-bar-tool-iStat-Menus-9826893.html

### Stats (exelban)

- **Status**: free, open source (MIT) menu bar monitor; v3.0.21 released 11 October 2026; requires macOS 12+; 42.6k GitHub stars, 1.6k forks; site claims 100M+ downloads and 41 languages; built and maintained by one developer ("open source, but not open contribution"); install via DMG, `brew install stats`, or a headless SSH script that registers the machine to the System Stats cloud dashboard.
- **What it shows**: 9 modules: CPU, GPU, RAM, Disk, Sensors, Network, Battery, Bluetooth, Clock. CPU: utilization, frequency, temperature, top processes. GPU: utilization, memory, temperature. RAM: pressure, used/free, swap, top apps. Disk: space, read/write activity, S.M.A.R.T. Sensors: temperature, voltage, power, fan speed. Network: up/down speed, totals, local/public IP. Battery: level, health, cycle count, time remaining. Bluetooth: device battery levels. Clock: multi-timezone clock/calendar. A Remote module (added May 2026) streams metrics to the System Stats web dashboard (app.system-stats.com, freemium: free for 5 machines) and pulls the fleet view back over its REST API, for monitoring the Mac from anywhere.
- **How it shows it**: each module contributes widgets to the menu bar and a popup on click. The site names 13 widget types: Mini, Line chart, Bar chart, Pie chart, Network chart, Speed, Label, Tachometer, Memory, Battery, Stack, Dot, Text; v3.0.21 added an Icon widget, and a "sensors" combined widget plus per-state indicators exist in code. Widgets can be reordered, recoloured, combined into one item. Popups pair a small chart with a top-process list (0, 3, 5, 8, 10 or 15 rows, configurable). Widget settings from the source: colour can follow utilization, memory pressure, or CPU cluster (E vs P), or be system accent, monochrome, one of ~25 named colours, or custom hex; utilization colour zones have configurable orange/red thresholds; chart scale can be none, linear, square, cube, logarithmic, or fixed; line-chart history 1-10 minutes; reader intervals 1-60 s; network speed can render as "interface based" or "process based" with pictograms none/dots/arrows/chars, optionally transparent when idle; RAM pressure maps normal/warning/critical to system green/orange/red; battery widget can embed percentage inside the icon or append time; stack widgets lay out in automatic, one-row or two-row modes. A combined popup shows all modules behind one Stats icon. Optional desktop WidgetKit widgets exist but are off by default due to `chronod` load.
- **Ideas worth taking**: widget-type vocabulary (mini/line/bar/pie/tachometer/label/stack/dot/text) is a sane micro-vis grammar; "colour by meaning" options (utilization, pressure, cluster) instead of only static colour pickers; transparent-when-idle network arrows; threshold-tinted values; process-count configurability; per-module update intervals; honest documentation of per-module cost.
- **Weaknesses / avoid**: utilitarian visuals, widgets feel engineered not designed; fan control is legacy/unmaintained; Sensors+Bluetooth can dominate CPU cost (docs claim up to 50% savings from disabling them); sensor readings are SMC thermal zones that do not map cleanly to cores, and keys change per SoC; macOS 26 requires manually enabling the app under System Settings -> Menu Bar; solo-maintainer bus factor; no long history (line charts max ~10 min in menu bar).
- **Sources**: https://github.com/exelban/stats, https://raw.githubusercontent.com/exelban/stats/master/README.md, https://mac-stats.com/, https://github.com/exelban/stats/releases, https://raw.githubusercontent.com/exelban/stats/master/Kit/types.swift

### MenuMeters

- **Status**: the original menu bar meter (Alex Harper / Raging Menace, early 2000s). The maintained fork is yujitach/MenuMeters (GPL-2.0, 3.1k stars); latest release 2.1.6.1, November 2021. Dormant; its README recommends Stats, iGlance or eul for modern macOS.
- **What it shows**: CPU, memory, disk, network throughput in the menu bar with a dropdown of details.
- **How it shows it**: tiny bitmap-style meters: per-CPU bar/percentage pairs, a small memory pie, disk activity arrows, numeric up/down throughput. Fixed-format, monochrome-plus-two-colour look that predates Big Sur design conventions. Runs as a faceless app putting plain NSStatusItems where the original used NSMenuExtras.
- **Ideas worth taking**: historical baseline; proof that simple text+mini-meter in the menu bar has been the form factor for 20 years.
- **Weaknesses / avoid**: dated visuals, no Apple-Silicon-aware features, unmaintained.
- **Sources**: https://github.com/yujitach/MenuMeters, https://api.github.com/repos/yujitach/MenuMeters/releases/latest, https://raw.githubusercontent.com/yujitach/MenuMeters/main/README.md

### iStatistica Pro (ImageTasks)

- **Status**: commercial monitor in two Mac App Store editions: iStatistica ($5.99 with in-app purchases, so no longer truly free) and iStatistica Pro ($9.99, confirmed on the listing; current major version 7.x). macOS 10.11+ per site; localized in 6 languages (English, French, German, Spanish, Italian, Russian).
- **What it shows**: CPU (total, per-core, per-app), memory (used/free/cache/system, per-app), disk usage with eject, battery (cycles, health, capacity), network (interfaces, external/gateway/local IP, speeds, data chart), sensors/fans/disk-I/O via a separate Sensors plug-in app, storage visualization to find large files, detailed per-app monitoring.
- **How it shows it**: menu bar monitors (CPU, memory, disk, network, battery, GPU, sensors) plus a single-page dashboard window rather than many per-metric pages (TheSweetBits describes it as "all the details on a single page", in contrast to iStat Menus' per-item menus); Notification Center widgets; a web-access dashboard reachable by browser on the LAN, with IP/passkey restriction and a REST API returning JSON; comparison charts and CSV export of key metrics.
- **Ideas worth taking**: built-in HTTP/JSON API for remote checking; one-page dashboard instead of tab-sprawl; separate plug-in process for privileged sensor reads (a clean security boundary).
- **Weaknesses / avoid**: notification rules are fixed presets (no custom triggers per TheSweetBits); single-page layout can feel cramped/confusing; sensors require a second app install.
- **Sources**: https://www.imagetasks.com/istatistica/pro/, https://apps.apple.com/us/app/istatistica-pro/id1447778660?mt=12, https://apps.apple.com/us/app/istatistica/id1025822138?mt=12, https://thesweetbits.com/istat-menus-vs-istatistica-pro/, https://orcylo.app/best-menu-bar-system-monitor-for-mac

### XRG

- **Status**: open source (GPL-2.0) system monitor by Mike Piatek-Jimenez (mikepj/XRG, ~313 stars, Objective-C). Latest release 3.2.1, 31 October 2023 (requires macOS 10.13+); last commit March 2024, so effectively dormant rather than actively maintained.
- **What it shows**: CPU, GPU, memory, battery, temperature sensors (with a dedicated sensors window listing current/min/average/max), network, disk I/O, plus legacy weather and stock-market graphs.
- **How it shows it**: a free-floating, resizable strip/window of stacked scrolling line graphs on the desktop, not a menu bar app. Each graph is a minimal single-line time series with small text readouts; the newer Temperature Graph shows just three selected sensors. Goal stated on the site: "a functional system monitor that has a clean and flexible interface, so it doesn't intrude."
- **Ideas worth taking**: the always-on desktop graph window is the closest existing relative of Coreography's concept; min/avg/max sensor tabulation is worth borrowing.
- **Weaknesses / avoid**: dated AppKit-era rendering (they only just removed manual text anti-aliasing options), sparse typography, legacy weather/stock clutter.
- **Sources**: https://github.com/mikepj/XRG, https://github.com/mikepj/XRG/releases, https://gaucho.software/xrg.html

### eul

- **Status**: free, open source (MIT) SwiftUI status monitor, gao-sun/eul, 10k stars. Last release v1.6.2, August 2021; effectively unmaintained. App Store version outdated and lacks SMC features.
- **What it shows**: CPU, memory, network, battery, fan, Bluetooth battery; menu bar items plus macOS 11-era desktop widgets (separate CpuWidget/MemoryWidget/NetworkWidget/BatteryWidget extension targets in the repo).
- **How it shows it**: minimal text-based menu bar values and simple widget cards; clean but plain SwiftUI lists.
- **Ideas worth taking**: early proof that users want desktop widgets fed by a menu bar app.
- **Weaknesses / avoid**: abandoned; shows the risk of a free solo project without a maintenance story.
- **Sources**: https://github.com/gao-sun/eul, https://api.github.com/repos/gao-sun/eul/releases/latest, https://raw.githubusercontent.com/gao-sun/eul/master/README.md

### iGlance

- **Status**: free open source (GPL-3.0) menu bar monitor, iglance/iGlance, 2.5k stars. README banner: "This project is no longer under active development." Included here for completeness.
- **What/how**: CPU graph, CPU temperature, memory, network, fan speed, battery threshold notifications, light/dark adaptation; conventional menu bar meters.
- **Ideas worth taking**: none beyond confirming the same module set.
- **Weaknesses / avoid**: unmaintained; note their warning about App Store clones showing fake sensor values.
- **Sources**: https://github.com/iglance/iGlance

### TG Pro (Tunabelly Software)

- **Status**: commercial thermal/fan tool; version 2.104 current; $10 one-time, no subscription; macOS 10.14 through macOS 27; Intel and Apple Silicon, including 2026 hardware (M5 Pro/Ultra, MacBook Neo A18 Pro listed).
- **What it shows**: temperatures across CPU (individual cores on Apple Silicon), GPU, drives via S.M.A.R.T., battery (temp, health, cycles), plus memory/power/Thunderbolt sensors; fan speeds; diagnostics (fan/sensor status, battery health, last shutdown); CSV logging, local notifications, email alerts.
- **How it shows it**: a main window listing sensor temperatures with current and highest-recorded values, fan speeds, and diagnostic indicators; a menu bar item whose dropdown repeats individual sensor readings and exposes fan controls. Auto Boost rules map temperature thresholds to fan speeds; manual and "Max" controls sit alongside. Warnings are highlighted with status indicators.
- **Ideas worth taking**: current-vs-highest-recorded dual values per sensor; Auto Boost as a threshold/rule table; diagnostics panel framing (battery health, abnormal shutdowns).
- **Weaknesses / avoid**: dense list UI, functional rather than beautiful; fan control is the product, monitoring is secondary.
- **Sources**: https://www.tunabellysoftware.com/tgpro/

### Macs Fan Control (CrystalIDEA)

- **Status**: freemium fan/temperature tool, free download with a paid Pro version; macOS and Windows (Boot Camp) builds; works on Intel and Apple Silicon.
- **What it shows**: fan speeds and all temperature sensors including third-party HDD/SSD via S.M.A.R.T.
- **How it shows it**: deliberately plain: "two tables layout" with a list of fans and a list of temperature sensors. Menu bar shows fan RPM plus a chosen sensor temperature. Fans run Auto (system) or Custom (constant RPM or sensor-relative); named presets switch modes quickly. On quit it always restores Auto.
- **Ideas worth taking**: presets as the interaction for fan modes; conservative default (restore Auto on exit).
- **Weaknesses / avoid**: a utility table UI, not a monitor; not graph-oriented.
- **Sources**: https://crystalidea.com/macs-fan-control

### Hot (macmade / XS-Labs)

- **Status**: free, open source (MIT) single-purpose menu bar app (~3.1k stars); repo still carries an "active" badge but last push was July 2024, so low activity rather than active development.
- **What it shows**: on Intel: CPU temperature, CPU speed limit (thermal throttle %), scheduler limit, available CPU count; on Apple Silicon: CPU temperature plus system thermal pressure, with an optional all-sensors graph view.
- **How it shows it**: one menu bar text item, colorized orange when the speed limit drops below 60% or pressure is not nominal; dropdown lists the numbers; a graph view plots all sensors on Apple Silicon.
- **Ideas worth taking**: thermal pressure is the honest Apple-Silicon metric (no fake per-core temps); a single colour change is enough for a status item.
- **Weaknesses / avoid**: intentionally narrow scope.
- **Sources**: https://raw.githubusercontent.com/macmade/Hot/main/README.md, https://github.com/macmade/Hot

### coconutBattery (coconut-flavour.com)

- **Status**: commercial battery tool, "the standard for battery reading since 2005"; v4.4 current, macOS 12+; free tier plus coconutBattery Plus (one-time purchase; Standard limited to v4.x updates, Lifetime includes future Plus updates; free trial = 10 Plus-mode launches). Not on the App Store.
- **What it shows**: Mac, iPhone and iPad battery health: current charge, design vs full-charge capacity, cycle count, manufacture date; Wi-Fi-synced iOS device checks; battery lifetime analyzer (max/min/average temperature, voltage, charge/discharge rate ranges, operating time); SSD read/write statistics in the advanced viewer; notifications below set percentages.
- **How it shows it**: a main window with prominent capacity bars (current charge and health as fill bars with numeric labels), a history view charting health over time, and a menu bar view with battery details (Plus). Single-purpose but polished.
- **Ideas worth taking**: longitudinal device-health history (charge cycles and capacity over the device's life) is a dimension CPU-centric monitors ignore.
- **Weaknesses / avoid**: battery-only scope.
- **Sources**: https://www.coconut-flavour.com/coconutbattery/

### AlDente (AppHouseKitchen)

- **Status**: commercial charge limiter; free tier plus Pro (see site pricing page for current tiers); "700,000+ users", 98% rating on Setapp; actively maintained. Notable 2026 context: macOS 26.4 beta added a built-in manual charge limiter, so the team published a "We Got Sherlocked - Or Did We?" post.
- **What it shows**: charge limit (typically hold 20-80%), charging state; Heat Protection (pauses charging when hot), Sailing Mode (lets charge drift inside a range), Calibration Mode; schedule to reach 100% when needed.
- **How it shows it**: menu bar centric; a prominent charge-limit slider/percent readout and a small panel of toggles for the protection modes.
- **Ideas worth taking**: one job done with a single obvious control; per-feature honest docs (blog explains exactly when it disables sleep).
- **Weaknesses / avoid**: adjacent domain (power policy, not monitoring); Apple is absorbing the core feature.
- **Sources**: https://apphousekitchen.com/

### Sensei (Cindori)

- **Status**: commercial "all-in-one" monitor + cleaner; current site leads with Sensei Monitor; pricing: $29/year subscription (up to 3 Macs) or $59 one-time regular licence (updates through v2; v3+ may be paid). Free download trial.
- **What it shows**: real-time CPU, GPU, battery health, storage; temperatures and fan speeds (Thermal Dashboard); S.M.A.R.T. drive health; battery health (cycles, capacity); disk benchmark; SSD trim control; junk/large-file cleaner; app uninstaller.
- **How it shows it**: a status-bar monitor plus a dropdown panel built from user-placed widgets, edited in a dedicated Monitoring Editor ("complete control ... customize widgets for the status bar or dropdown panel"); themes and styling options; the rest of the app is a dashboard-style window of cards per subsystem. MacWorld quoted on-site: "slick-looking ... packs a ton of hardware data inside an attractive, well-organized user interface."
- **Ideas worth taking**: a user-editable widget canvas for the dropdown; consistent card-per-subsystem layout.
- **Weaknesses / avoid**: subscription for a monitor is a hard sell; the app is a suite (cleaner/uninstaller/trim) so the monitor competes for focus; sensor data on modern macOS historically required workarounds (unverified for current release).
- **Sources**: https://cindori.org/sensei/, https://cindori.org/store/sensei

### CleanMyMac Menu (MacPaw)

- **Status**: the menu bar monitor bundled with CleanMyMac (suite; a third-party comparison lists CleanMyMac "from EUR 39.95 a year" (unverified on MacPaw's site, which hides pricing)). Not sold separately.
- **What it shows**: a Health monitor scoring the Mac "Excellent" to "Critical" from disk space, threats, battery health, system load; Protection status; storage/disk; memory (allocation between macOS, apps and available; pressure; swap; top consumers, with apps over 20% RAM highlighted yellow, plus a "Free Up" button); CPU (real-time load chart, uptime, temperature, top apps); battery; network/connected devices.
- **How it shows it**: a menu bar icon opening a menu of named monitor rows; clicking a monitor expands a detail panel. The CPU detail shows a load chart where "red and blue rectangles" mark current load updated every second and curves show history. The memory detail leads with a segmented allocation bar and tooltips.
- **Ideas worth taking**: an overall health score as a top-level summary; expandable monitor rows inside one menu; actionable affordances next to the data (Free Up).
- **Weaknesses / avoid**: monitoring is an accessory to sell a cleanup subscription; "free up RAM" buttons are placebo-adjacent; heavy upsell surface.
- **Sources**: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu, https://macpaw.com/support/cleanmymac/knowledgebase/cpu-load, https://macpaw.com/support/cleanmymac-x/knowledgebase/ram-monitoring

### App Tamer (St. Clair Software)

- **Status**: commercial CPU tamer/monitor hybrid; version 2.8.4 for macOS 10.13-26.5 (older 2.7.6 covers 10.9-10.12); $14.95 single, $12.45 each for 2+; 15-day trial.
- **What it shows**: per-app CPU usage, CPU-hog detection with alerts; on Apple Silicon it can pin background apps to efficiency cores ("more than twice as efficient" claim).
- **How it shows it**: a menu bar item; clicking shows a list of running apps with CPU usage, where clicking an app offers "slow or stop" controls; preconfigured to throttle Safari, Chrome, Spotlight, Time Machine, Photoshop, etc. when they are not in front.
- **Ideas worth taking**: monitoring-to-action in one click (see it, throttle it); E-core pinning is an Apple-Silicon-native power feature that fits Coreography's power-user remit.
- **Weaknesses / avoid**: process list is functional text; no graphs.
- **Sources**: https://www.stclairsoft.com/AppTamer/

### System Toolkit / System Dashboard family (Sascha Simon Software)

- **Status**: Mac App Store utilities; System Toolkit is "all-in-one information and maintenance" (monitors plus disk cleaner, duplicate finder, privacy eraser); System Toolkit Pro is the current line, and sibling apps System Dashboard Pro and System Monitor Panel provide standalone monitor windows (no non-Pro "System Dashboard" was listed on the site at verification time). (Versions/prices not verified beyond listings.)
- **What it shows**: CPU load, memory, network speeds/traffic/open connections, sensor data and fan speeds, Bluetooth device battery levels, battery details; Dashboard shows "the most important parameters".
- **How it shows it**: menu bar extras ("add as many menu bar widgets as you like", each configurable), an overlay window, an info panel, and a dashboard page; System Dashboard/Monitor Panel are explicitly "small and lightweight window" / "customizable window" monitors, i.e. the window-first niche Coreography targets.
- **Ideas worth taking**: market validation that a standalone monitor window sells on the MAS.
- **Weaknesses / avoid**: cleaner-suite bundling; visuals are conventional gauges; sandbox constraints on sensors.
- **Sources**: https://sascha-simon.com/apps/system-toolkit, https://sascha-simon.com/apps/system-toolkit-pro, https://apps.apple.com/us/app/system-toolkit/id1234854699?mt=12, https://sascha-simon.com/apps/system-dashboard-pro

### Monity

- **Status**: commercial Today-view (Notification Center) widget; vendor site monityapp.com did not respond at verification time (unverified). Per the MacUpdate listing: v1.4.5, $4.99, last updated 24 Sep 2018 with "Ready for macOS 10.14 Mojave" notes, OS X 10.10+ (unverified it still works on macOS 27).
- **What it shows**: system (uptime, processes, threads, load average), memory (wired/active/inactive/free), network (WAN/LAN IP, traffic), battery (charge, cycles, Bluetooth accessories), disk usage; reorderable categories plus an "Individual Dashboard".
- **How it shows it**: a Notification Center widget of labelled stats, also usable standalone; praised by Lifehacker for hitting a "Goldilocks zone" of detail without menu bar clutter.
- **Ideas worth taking**: a slide-over panel as an alternative surface to the menu bar.
- **Weaknesses / avoid**: Today-view widgets are a weak, half-hidden surface on modern macOS; unmaintained; Notification Center is not where a live monitor belongs.
- **Sources**: https://monity.macupdate.com/, https://macsources.com/monity/, https://www.chriswrites.com/best-notification-centre-widgets/ (vendor site monityapp.com unreachable at verification time)

### Übersicht and GeekTool (desktop widget engines)

- **Übersicht status**: free, open source (GPL-3.0) by Felix Hageloh; v1.6.82, macOS 12+; maintained.
- **GeekTool status**: the predecessor; a 3.4-11 build still downloadable via the Homebrew cask, but effectively unmaintained since the mid-2010s; Intel-only and reportedly unstable under Rosetta 2 on Apple Silicon (Rosetta claim unverified).
- **What/how**: Übersicht renders HTML5 desktop widgets written in JavaScript/React JSX: each widget declares a shell `command`, a `refreshFrequency` in ms, a `render` function and CSS for absolute positioning. A community widget gallery supplies ready-made CPU/RAM/network/disk widgets. GeekTool did the same via shell/file/image/web "geeklets" with property-panel configuration.
- **Ideas worth taking**: desktop-embedded ambient displays are a real user desire; scriptable data widgets show appetite for customization, but the audience is tinkerers.
- **Weaknesses / avoid**: web-tech rendering is heavyweight for a monitor; positioning is manual pixel work; not a designed product surface.
- **Sources**: https://tracesof.net/uebersicht/, https://www.switchingtomac.com/geektool-mac-alternatives/, https://formulae.brew.sh/cask/geektool

### Usage (WidgetKit system monitor)

- **Status**: commercial monitor by Oleh Stasula (usage.pro); free download with a Pro unlock; macOS, iOS and iPadOS; actively maintained (SwiftUI). It fills the scope's "system stats as real WidgetKit widgets" slot that the dead Today-widget generation (Monity) left behind.
- **What it shows**: CPU activity, memory allocation, storage, network data usage with daily/monthly totals, battery status, device info; menu bar monitors plus a popover.
- **How it shows it**: configurable WidgetKit widgets for the desktop and Notification Center next to the menu bar items; reviewers (ifun.de) describe the look as close to Apple's own design language.
- **Ideas worth taking**: WidgetKit is the durable surface for glanceable stats; per-metric widget configurability.
- **Weaknesses / avoid**: widget-first design splits attention across surfaces; historically iOS-led.
- **Sources**: https://usage.pro/, https://www.ifun.de/usage-plattformuebergreifender-systemmonitor-mit-widgets-230520/

### Newer entrants (2025-2026)

#### Tempo for Mac

- **Status**: indie paid monitor (one-time; launch pricing $4.99 first 20 copies, $9.99 next 100, $14.99 regular); macOS 14+, universal; v1.3 added the "notch island".
- **What it shows**: CPU, memory, storage, network, battery, thermal state; 30 days of private on-device history at one-minute summaries; top-10 process list sorted by CPU, memory or energy with Quit/Force Quit; threshold alerts for CPU, memory pressure, storage, battery. Explicitly no GPU load or exact temperatures (uses the thermal pressure macOS reports).
- **How it shows it**: menu bar shows up to four vitals in chosen order, together in one compact item or as separate items, each as icon, value or both. The window uses "calm, roomy cards": health rings for processor/memory/storage, a live processor line chart, mirrored bars for network and disk, each vital with its own colour, light/dark. The signature feature is the notch island: live CPU and download speed sit either side of the MacBook notch, hovering opens rings for every vital, clicks pass through, it hides in full screen, and notch-less Macs get a drawn island.
- **Ideas worth taking**: rings-per-vital plus per-vital colour as the overview grammar; 30-day local minute history as table stakes; pause expensive scans when the UI is hidden; "tell you once, then wait until things recover" alert policy; honest limits (thermal pressure instead of fake temps).
- **Weaknesses / avoid**: very new and unproven; no sensors/GPU; notch island is a gimmick to borrow carefully.
- **Sources**: https://tempoformac.com/

#### Orcylo

- **Status**: indie monitor in "coming soon" pre-launch (one-time pricing tiered by order of purchase: EUR 5 for the first 20 licences, EUR 7.50 for the next 30, EUR 9.99 after; one Mac per licence, lifetime updates); requires macOS 15+.
- **What it shows**: CPU, memory, disk, network, GPU (utilization split "Renderer"/"Tiler", memory, peak, per-app), power (system watts, adapter watts, per-app watts, energy today), thermals (38 sensors in 7 named groups with averages/max), sound output/mic details, Bluetooth devices with batteries, a Projects tab that detects idle dev servers by port and memory, a website-analytics tab, and AI-tool usage limits (Claude Code, Codex, detected Cursor/Gemini CLI) with reset countdowns and an 80% nudge.
- **How it shows it**: every metric gets its own menu bar item as a number, small graph, both, or a ring, command-drag reorderable. The window is a 13-tab app (Overview, CPU, Memory, Disk, Network, GPU, Power, Thermals, Sound, Bluetooth, Projects, Analytics, AI Tools). Headline interaction: "700 processes, folded into 25 apps": helpers roll into the owning app so each row is an app name, process count, and one figure, versus Activity Monitor's ~700 rows. 30-day history at one point per minute, stored locally.
- **Ideas worth taking**: app-folded process lists are the correct level of abstraction for users; per-app watts/disk-write/GPU columns are power-user gold; tabs-per-domain with consistent stat-card layout; sensor grouping (CPU dies, GPU, SoC, package, storage, battery, other) with max-per-group callouts.
- **Weaknesses / avoid**: feature-broad before proven (analytics/dev-server/AI-limit scope creep); unlaunched at research time.
- **Sources**: https://orcylo.app/, https://orcylo.app/best-menu-bar-system-monitor-for-mac

#### tstats

- **Status**: indie menu bar monitor; $7.99/year subscription after 14-day trial; macOS 13+; Apple Silicon only (M1-M5 listed); claims ~0.3% CPU and <50 MB.
- **What it shows**: CPU (per-core E/P cluster charts, history, clock speeds, thermal), memory (pressure, swap, app breakdown), network (up/down), temperature (CPU/GPU/SSD), disk (throughput, capacity), battery (cycles, wattage, time), GPU (utilization, temperature, FPS, unified-memory allocation, per-process GPU), fans, Bluetooth device batteries, weather included free (conditions + 7-day forecast), and a distinctive MLX tab listing active Apple MLX processes, their GPU memory footprint and unified-memory impact.
- **How it shows it**: one tiny menu bar icon that expands into a tabbed dashboard of charts and per-component breakdowns; customizable menu bar text colours, fonts, sizes, themes, update interval.
- **Ideas worth taking**: MLX/local-AI process monitoring is a genuinely 2026 differentiator; per-cluster charts; GPU detail depth (FPS, unified memory, per-process).
- **Weaknesses / avoid**: yearly subscription for a monitor; Apple-Silicon-only (fine for Coreography but narrows reviews); single vendor, unproven.
- **Sources**: https://tstats.app/

#### MoniThor

- **Status**: free on the Mac App Store (sandboxed), Pro unlock adds a privileged SMC helper for temperatures, fans and power draw (header says $9.99 while the FAQ says $7.99; site inconsistency, both cited); one-time, no subscription; macOS 13+; <30 MB claimed, 1 s refresh.
- **What it shows**: CPU (per-core bars with P-Core/E-Core labels, user vs system, load average, thermal state, uptime), memory (pressure and usage ring gauges, wired/compressed/cached/free, swap, page in/out), network (speeds, peaks since launch, SSID, IPs), GPU (utilization, VRAM, model name), battery (percentage, health, cycles, watts, voltage), disk (usage, purgeable, read/write, top-5 storage categories).
- **How it shows it**: three tiers of surface: menu bar widgets (live sparklines and colour-coded values; per-metric display modes text/graph/graph+text/icon+text; dark pill background with adjustable opacity); click opens a compact draggable floating panel with 7 toggleable sections; option-click opens a full resizable dashboard with 6 metric cards, 8 accent-colour themes, "animated glow graphs", and a session summary (peak CPU/RAM/GPU, total network since launch).
- **Ideas worth taking**: click vs option-click to choose detail tier; sparkline+value menu bar items on a configurable pill; session-peak summary; free-sandboxed vs paid-helper packaging is the clean way to ship sensors alongside the App Store.
- **Weaknesses / avoid**: glow themes risk looking gamer-y rather than Mac-native; pricing inconsistency on its own site.
- **Sources**: https://monithor.dev/

#### MacMonitor (ryyansafar)

- **Status**: free, open source (MIT), Apple Silicon only, macOS 13+; installed via Homebrew tap, curl script or DMG; no Dock icon.
- **What it shows**: menu bar health dot (green/yellow/red) with CPU and memory; a full dashboard: per-core CPU, GPU, memory, battery, network, disk I/O and six power rails; top-8 CPU consumers (name, %, memory); standalone WidgetKit widgets (small and medium) that collect their own data via Mach kernel APIs with no parent app, for desktop or Notification Center.
- **Ideas worth taking**: power rails breakdown is rare and valuable on Apple Silicon; standalone widgets that self-collect data avoid the chronod problem Stats hit; a single health-dot summary.
- **Weaknesses / avoid**: hobbyist-scale (2 s refresh, no App Store); visual design unverified.
- **Sources**: https://macmonitor.ryyansafar.site/

#### Vitals and MacPulse

- **Vitals** (vitalsmac.com, by the maker of Flit): menu bar + window monitor whose pitch is acting from the menu bar: quit or force-quit apps and set fan speeds without leaving it. Folds processes into apps (about 60 app rows instead of ~1,000 processes), adds per-app volume sliders, "Worth a Look" hog alerts, and a Projects/dev-server tab; already shipping (v1.7.3, 16 October 2026). Pricing $9 launch rising to $29 one-time per Orcylo's comparison page (secondhand; vendor page not checked).
- **MacPulse**: menu bar sparklines with history behind them plus a window; EUR 14.99 one-time / EUR 49.99 for 5 Macs (per the same comparison page, secondhand).
- **Sources**: https://vitalsmac.com/, https://orcylo.app/best-menu-bar-system-monitor-for-mac

## Cross-cutting patterns

- **Two-surface architecture is universal**: a tiny always-visible surface (menu bar items, notch island, desktop widget, health dot) plus an on-demand detail surface (dropdown menu, floating panel, tabbed window). Density per surface is the design problem; nobody puts dense detail in the menu bar itself except as micro-charts.
- **The micro-visualization vocabulary has converged**: rings/gauges (utilization, pressure), scrolling or sparkline history, stacked bars (user/system), mirrored bidirectional bars (read/write, up/down), per-core bar strips, text values, dot/health indicators, label+value stacks. iStat Menus and Tempo independently arrived at rings + mirrored bars + per-vital colour.
- **Apple-Silicon-shaped features are now expected**: E/P-core cluster colouring and filtering, cluster-labelled per-core bars, CPU/GPU frequency, thermal pressure (the honest substitute for unavailable temperatures on sandboxed builds), power rails, unified-memory GPU accounting.
- **Process lists are folded into apps**: iStat "Combine Processes", Orcylo's 700-to-25 folding, top-N lists everywhere, always with icons. Raw process tables are an Activity Monitor-ism no modern monitor copies.
- **History sells**: iStat ranges 10 min-28 days; Tempo and Orcylo keep 30 days at 1 pt/min locally; Stats caps at ~10 min in the bar and loses to rivals here. Local-only history is a privacy talking point everywhere.
- **Rules/alerts**: the mature pattern is metric + threshold + duration + state-change triggers (iStat Rules); the lightweight pattern is threshold + notify-once-until-recovery (Tempo). Stats offers flat threshold notifications per module.
- **Fan control is a power-user flag**: iStat ramp curves, TG Pro Auto Boost, Macs Fan Control presets, Vitals. It is also the most fragile and most dangerous feature class.
- **Efficiency claims are marketing now**: iStat's "1/5 of v6", Tempo's "~2% / ~40 MB and pauses scans offscreen", tstats "~0.3%", MoniThor "<30 MB", Stats' per-module cost FAQ. Users audit monitors against themselves; a monitor that costs CPU is a punchline.
- **Pricing**: one-time $5-15 is the indie monitor norm; $25-60 for suite products; subscriptions appear only in suites (CleanMyMac) or ambitious newcomers (tstats, Sensei). Free+helper-Pro split (MoniThor) is an emerging App-Store-compatible model.
- **Platform mechanics matter**: macOS 26 requires explicit per-app enablement under System Settings -> Menu Bar; sandboxed App Store apps cannot read SMC sensors/fans (hence helper-based Pro tiers, iStatistica's plug-in app, MoniThor Pro); Wi-Fi SSID needs Location permission; menu bar extras have a fixed 22 pt working area regardless of notch-driven bar heights.
- **Graveyard pattern**: free solo projects die (eul, iGlance, MenuMeters, GeekTool); Today-view widgets died with Apple's widget transitions (Monity); suites persist on subscription revenue; iStat Menus persists on craft.

## Implications for Coreography

- **Do not compete in the menu bar; anchor in the window.** The menu bar niche is owned by iStat Menus (craft) and Stats (free). The window-first niche is held only by dated tools (XRG, System Dashboard, Activity Monitor). Coreography's pitch, one window where live graphs are the product, is validated by Tempo/Orcylo showing users will pay for a beautiful monitoring window, while neither attempts a full graph-first dashboard at Activity Monitor scale.
- **Adopt the converged visual grammar, at window scale**: per-vital rings for instant state, larger stacked user/system histories for CPU, per-core strips grouped by E/P cluster, mirrored read/write and up/down bars, memory-pressure gauge, capacity rings per volume. At window size these can show axes, legends, and hover crosshairs, the things menu bars cannot.
- **Per-cluster core handling must be structural, not cosmetic.** "Super cores" arrived in iStat 7.3 and M6 in Stats 3.0.21; core topology keeps mutating. Model clusters generically (type, count, colour) instead of hardcoding E/P.
- **Fold processes into apps with icons, and offer power-user columns**: per-app CPU, memory, GPU, energy/watts, disk write; Orcylo's folding is the reference. A plain process table can exist but should not lead.
- **Ship local, honest history**: at least 24 h at fine grain and ~30 days at 1 pt/min, stored on device, with scroll/hover inspection (Tempo's model). This is now a checklist item.
- **Treat thermal/power honestly**: report thermal pressure states (like Hot/Tempo) and power rails/watts (MacMonitor/Orcylo) rather than fabricated per-core temperatures; where real sensors are read (helper tool), label them as thermal zones, not cores (Stats' caveat).
- **Alerts should be quiet by default**: threshold + duration + notify-once-until-recovery; a rules engine (iStat-style) can come later. Nobody does alert UX well; doing it well is differentiating.
- **Price once, be efficient, and say so with numbers**: one-time ~$10-20 matches the category; publish measured CPU/memory cost; pause expensive sampling when the window is occluded (Tempo's process-scan pause is the model).
- **Borrow interaction tiers**: hover-to-peek summary (Tempo notch rings), click for dashboard (MoniThor panel), plus keyboard/shortcut access for power users; a compact mode and a full mode rather than one fixed layout.
- **Differentiate on what no one else does**: correlated multi-metric views (scrub a time cursor across CPU+GPU+power+thermal history), energy-first views (watts, energy impact, Wh today), MLX/local-AI process visibility (tstats is the only precedent), and a menu bar mini-presence that is a summary pointer into the window, not a rival to iStat Menus.
- **Avoid**: subscriptions, cleaner-suite bundling, Notification-Center-first design, fake precision (per-core temps, GPU numbers where APIs do not exist), free-up-RAM buttons, and visual noise (glow effects, 8 accent themes) that reads gamer rather than Mac.

## Sources

- [iStat Menus product page](https://bjango.com/mac/istatmenus/)
- [iStat Menus version history](https://bjango.com/mac/istatmenus/versionhistory/)
- [iStat Menus help: welcome/global layout](https://bjango.com/help/istatmenus7/welcome/)
- [iStat Menus help: global themes](https://bjango.com/help/istatmenus7/global/)
- [iStat Menus help: editable menus](https://bjango.com/help/istatmenus7/menus/)
- [iStat Menus help: CPU & GPU](https://bjango.com/help/istatmenus7/cpugpu/)
- [iStat Menus help: memory](https://bjango.com/help/istatmenus7/memory/)
- [iStat Menus help: disks](https://bjango.com/help/istatmenus7/disks/)
- [Marc Edwards: Designing macOS menu bar extras](https://bjango.com/articles/designingmenubarextras/)
- [Bjango articles index](https://bjango.com/articles/)
- [Michael Tsai: iStat Menus 7 roundup](https://mjtsai.com/blog/2024/08/01/istat-menus-7/)
- [TidBITS: iStat Menus 7.0.2 (pricing)](https://tidbits.com/watchlist/istat-menus-7-0-2/)
- [OWC/Rocket Yard: iStat Menus 7 review](https://eshop.macsales.com/blog/95542-istat-menus-7-is-the-latest-in-a-long-line-of-delightful-mac-monitoring-apps-from-bjango/)
- [TheSweetBits: Marc Edwards interview](https://thesweetbits.com/inside-istat-menus-from-bjango/)
- [heise: iStat Menus 7 launch report](https://www.heise.de/en/news/Mac-Major-update-for-popular-menu-bar-tool-iStat-Menus-9826893.html)
- [Stats repo](https://github.com/exelban/stats)
- [Stats README (raw)](https://raw.githubusercontent.com/exelban/stats/master/README.md)
- [Stats site](https://mac-stats.com/)
- [Stats releases](https://github.com/exelban/stats/releases)
- [Stats types.swift (widget/color/scale internals)](https://raw.githubusercontent.com/exelban/stats/master/Kit/types.swift)
- [MenuMeters fork](https://github.com/yujitach/MenuMeters) and [latest release API](https://api.github.com/repos/yujitach/MenuMeters/releases/latest)
- [iStatistica Pro product page](https://www.imagetasks.com/istatistica/pro/) and [App Store listing](https://apps.apple.com/us/app/istatistica-pro/id1447778660?mt=12)
- [TheSweetBits: iStat Menus vs iStatistica Pro](https://thesweetbits.com/istat-menus-vs-istatistica-pro/)
- [XRG repo](https://github.com/mikepj/XRG), [releases](https://github.com/mikepj/XRG/releases), [site](https://gaucho.software/xrg.html)
- [eul repo](https://github.com/gao-sun/eul) and [latest release API](https://api.github.com/repos/gao-sun/eul/releases/latest)
- [iGlance repo](https://github.com/iglance/iGlance)
- [TG Pro product page](https://www.tunabellysoftware.com/tgpro/)
- [Macs Fan Control product page](https://crystalidea.com/macs-fan-control)
- [Hot README](https://raw.githubusercontent.com/macmade/Hot/main/README.md)
- [coconutBattery](https://www.coconut-flavour.com/coconutbattery/)
- [AlDente / AppHouseKitchen](https://apphousekitchen.com/)
- [Sensei](https://cindori.org/sensei/) and [Sensei store/pricing](https://cindori.org/store/sensei)
- [CleanMyMac Menu docs](https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu), [CPU load](https://macpaw.com/support/cleanmymac/knowledgebase/cpu-load), [RAM monitoring](https://macpaw.com/support/cleanmymac-x/knowledgebase/ram-monitoring)
- [App Tamer](https://www.stclairsoft.com/AppTamer/)
- [System Toolkit](https://sascha-simon.com/apps/system-toolkit), [System Toolkit Pro](https://sascha-simon.com/apps/system-toolkit-pro), [System Dashboard Pro](https://sascha-simon.com/apps/system-dashboard-pro)
- [Monity on MacUpdate](https://monity.macupdate.com/) (vendor site monityapp.com unreachable at verification time)
- [Usage](https://usage.pro/)
- [Übersicht](https://tracesof.net/uebersicht/)
- [GeekTool status via switchingtomac](https://www.switchingtomac.com/geektool-mac-alternatives/) and [brew cask](https://formulae.brew.sh/cask/geektool)
- [Tempo for Mac](https://tempoformac.com/)
- [Orcylo](https://orcylo.app/) and [Orcylo's monitor comparison](https://orcylo.app/best-menu-bar-system-monitor-for-mac)
- [tstats](https://tstats.app/)
- [MoniThor](https://monithor.dev/)
- [MacMonitor](https://macmonitor.ryyansafar.site/)
- [Vitals](https://vitalsmac.com/)
- [System Stats](https://system-stats.com/) (Stats' remote dashboard)

## Verification log

Checked 2026-10-17 against cited sources and vendor/GitHub pages. Roughly 90 concrete claims reviewed.

**Corrections made**

- iStat Menus weather called a "paid subscription" (summary, What-it-shows, Weaknesses) -> one-off data packs after the included 6 months, from $2.49 for 12 months; Bjango's help page explicitly says "No subscriptions".
- iStat Menus "nine menu bar items" -> nine core items; 7.5 added a tenth (Astronomy), per the product page.
- iStat Menus "VPN country flag" -> marked (unverified); not documented (only clock-item country flags, added in 7.02, are).
- Version arc: added the 7.2 build 2273 security release (1 Apr 2026) and noted there is no public 7.4.
- Stats "Remote module streams metrics over MQTT" -> MQTT not evidenced; the module code calls HTTPS REST endpoints (SystemStats.host /v1/...). Reworded; added dashboard pricing (free for 5 machines) from system-stats.com.
- iStatistica "free tier" and "$3.99 upgrade in the free app" -> the non-Pro app is $5.99 with in-app purchases; Pro confirmed $9.99 on the MAS listing (was marked unverified). 6 languages confirmed (EN, FR, DE, ES, IT, RU).
- XRG "31 Oct, year not shown" -> 3.2.1 is 31 October 2023; last commit March 2024, so "still maintained" softened to dormant.
- Hot "active repo" -> repo badge says active, but last push July 2024; softened.
- CleanMyMac "from $39.95 a year" -> EUR 39.95 per the cited comparison (currency fix).
- Sascha Simon "sibling apps System Dashboard, System Dashboard Pro" -> only System Dashboard Pro and System Monitor Panel are listed now; dead link sascha-simon.com/en/desktop.html (404) replaced with /apps/system-dashboard-pro.
- Monity "site still up at monityapp.com" -> site unreachable at verification time; MacUpdate facts retained (v1.4.5, $4.99, updated 24 Sep 2018, Mojave-ready, OS X 10.10+).
- GeekTool "unmaintained since ~2013" -> mid-2010s (brew cask ships a 3.4-11 build); Rosetta instability marked unverified.
- Orcylo "EUR 5/7.50/9.99 by seat count" -> tiers are by order of purchase (first 20 / next 30 / after 50), one Mac per licence.
- Vitals "unverified on a vendor site" -> vendor site exists (vitalsmac.com, v1.7.3 shipped 16 Oct 2026); entry expanded with first-party details.
- Added a Usage (WidgetKit) section, the scope's desktop/Notification-Center-widget entry point the file lacked.

**Confirmed as written** (sample): iStat Menus 7.5 date and Astronomy/Liquid Glass notes, all 7.x dates, pricing via TidBITS, history ranges, GPU letters I/D/A/N, Combine Processes, Show Background, heise settings-reset note; Stats v3.0.21 date, stars/forks, 9 modules, 13 widget names, Icon widget + M6 in 3.0.21, widget internals from types.swift (scales, 1-10 min history, intervals, process counts, pictograms, colour modes, ~25 named colours, pressure colours); MenuMeters 2.1.6.1 Nov 2021 + recommended alternatives; eul v1.6.2 Aug 2021 + widget targets; iGlance unmaintained banner + fake-sensor clone warning; TG Pro 2.104, $10, macOS 10.14-27, M5 Pro/Ultra and MacBook Neo A18 Pro listed; Macs Fan Control details; coconutBattery 4.4/Plus tiers/10-launch trial; AlDente 700k users, 98% Setapp, "We Got Sherlocked" post and macOS 26.4 built-in charge limiter; Sensei $29/yr and $59 one-time (updates through v2); CleanMyMac Menu monitors incl. "red and blue rectangles" and 20%-RAM yellow highlight; App Tamer 2.8.4, $14.95, 10.13-26.5, E-core pinning claim; Tempo pricing tiers, v1.3 notch island, ~2%/~40 MB, no-GPU honesty; Orcylo features incl. 13 tabs and 700-to-25 folding; tstats $7.99/yr, M1-M5, ~0.3%; MoniThor incl. the real $9.99-vs-$7.99 site inconsistency; MacMonitor; Übersicht 1.6.82.

**Still unverified**: iStat VPN country flag; GeekTool Rosetta instability; Monity site status and macOS 27 compatibility; iStatistica "fixed presets" notifications claim (TheSweetBits, site shows broader actions); Sensei sensor workarounds on modern macOS (already marked); Vitals/MacPulse pricing (secondhand); Stats' exact remote-transport protocol; whether Bjango's 7.5 Astronomy is a separate menu item or Time-adjacent.

Coordinator correction (2026-10-17): Stats' `Kit/module/widget.swift` defines 15 widget types: mini, line chart, bar chart, pie chart, network chart, speed, battery, battery details, stack (raw key "sensors"), memory, label, tachometer, state (dot), text and icon. The website lists 13.
