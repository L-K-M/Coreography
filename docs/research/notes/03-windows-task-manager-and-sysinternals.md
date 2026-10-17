# Windows system monitoring tools (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

## Summary

- The Windows monitoring landscape is a stack: Task Manager for everyone (list-first, graphs second), Resource Monitor for file/connection-level drill-down, Sysinternals Process Explorer + System Informer for power users, perfmon/RAMMap/Autoruns for specialists, and ambient surfaces (tray graphs, taskbar readouts, Rainmeter skins) for always-on glanceability. Coreography's "graphs first, process list second" inverts Task Manager's hierarchy, which no built-in Windows tool does.
- Task Manager's strongest visual ideas: heat-map shading of each cell by intensity (now tinted by the system accent color), the Performance page's left rail of mini sparklines that acts as a device picker, per-logical-processor grid view, dynamic y-axis autoscaling, and a double-click "graph summary view" compact mode. Recent 24H2/25H2 updates added NPU columns and an AppContainer Isolation column, and standardized CPU accounting.
- Dave Plummer's original Task Manager (Windows NT 4.0, 1996, ~85 KB) was built on principles worth copying directly: tiny footprint, flicker-free live resizing, per-cell invalidation so only changed cells repaint, let the OS enforce permissions instead of building guardrails into the tool, and a self-healing launch path (Ctrl+Shift+Esc) that works even when the shell is dead.
- Process Explorer's best idea is attribution on graphs: hovering its System Information CPU graph shows which process contributed most at that instant. Its other transferable ideas: delta highlighting (green = new, red = exited, ~1 s), tray-icon mini-graphs, a toolbar strip of tiny graphs, and per-process GPU columns. v17.2 (October 15, 2026) adds efficiency-mode support, persistent process activity history, NPU monitoring, and a Devices page.
- System Informer (formerly Process Hacker) shipped a major 4.0 release on August 29, 2026 with a driver-backed Process Monitor, Hybrid Analysis reputation columns, and rewritten settings/installer. It shows the ceiling of "columns for everything plus graphs" power-user design, at the cost of density, kernel-driver dependence, and recurring AV false positives.
- Ambient monitoring is a proven distinct surface: TrafficMonitor's taskbar band (numbers with an optional sparkline painted behind them), Process Explorer's tray graphs, and Rainmeter skins (millions of downloads) all live outside a main window. Microsoft killed its own attempt: Dev Home's CPU/GPU/memory/network widgets were retired May 2025 and the repo archived June 5, 2025.
- Diff highlighting is a common vocabulary across tools: green for new, red for exited/closed, yellow for state-changed (Process Explorer, TCPView, System Informer). Windows Settings' battery page contributes a different pattern: click a region of the usage graph to filter the per-app list to that window, and split each app's cost into foreground vs background.
- Almost every tool's rolling history is ~60 seconds. Persistence is rare (App history totals, Reliability Monitor's daily index, GlassWire's bandwidth history, PE 17.2 activity history). A monitor with deep, queryable history plus click-back attribution would beat every Windows option on that axis alone.

## Tools

### Windows 11 Task Manager

- **Status**: Built into Windows 11. Current OS versions are 24H2 (build 26100) and 25H2 (build 26200). The WinUI/Fluent redesign (Mica backdrop, sidebar navigation, command bar, dark mode, settings page) shipped with 22H2 in 2022, previewed from build 22557. Still actively updated via cumulative updates; no separate versioning or price.
- **What it shows**: Processes page groups rows under Apps, Background processes, and Windows processes. Default and optional columns include Status, CPU, Memory, Disk, Network, GPU, GPU engine, Power usage, Power usage trend, Type, Publisher, PID, Process name, Command line; the June 9, 2026 cumulative update (KB5094126, builds 26100.8655/26200.8655) added optional NPU and NPU Engine columns on the Processes, Users, and Details pages, NPU Dedicated Memory and NPU Shared Memory columns on Details, and an Isolation column on Processes and Details showing AppContainer processes; neural engines inside a GPU now also appear on the Performance page. Performance page has a left rail of per-device mini graphs (CPU, Memory, one per disk, Ethernet, Wi-Fi, one per GPU, NPU engines where present) feeding a large right-hand graph plus hardware details (CPU name/speed/cores, memory composition, adapter stats). Other pages: App history (cumulative CPU time and network for Store apps), Startup apps (Startup impact rated High/Medium/Low/Not measured from CPU and disk at boot), Users (per-session resources, expandable to per-app), Details (the classic flat process list), Services (start/stop/restart). Memory page breaks memory into In use (with Compressed amount), Committed, Cached, Paged pool, Non-paged pool, Hardware reserved, plus a segmented composition bar.
- **How it shows it**: The Processes grid shades each numeric cell on a heat scale by usage intensity; since build 22610 (2022) the palette follows the system accent color, falling back to blue for readability. Status column overlays meaning: a leaf icon marks Efficiency mode (EcoQoS, apply per-process via right-click), a pause icon marks suspended processes, "Not responding" marks hung apps. On the Performance page, right-click the CPU graph for "Change graph to" overall usage, a per-logical-processor grid, or NUMA nodes; "Show kernel times" overlays kernel time. Axes autoscale to current utilization (Microsoft's own example: network graph rescaling from 100 Kbps to 500 Mbps mid-transfer). Double-clicking a graph, or right-click > "Graph summary view", collapses the whole app to a small floating always-on-top graph; double-click the left rail instead for an all-devices mini-gadget. Selecting rows and pressing Ctrl+C copies them as text. Settings offers Real time update speed (High = 0.5 s, Normal = 1 s, Low = 4 s, Paused), app theme (Light/Dark/Use system), default start page, Always on top, Minimize on use, Hide when minimized. Launch: Ctrl+Shift+Esc, right-click taskbar or Start, Ctrl+Alt+Del, taskmgr. A hidden developer setting (Settings > System > Advanced in 25H2, formerly "For developers") adds "End task"/"End all tasks" to taskbar icon right-click menus.
- **Ideas worth taking**: Heat-map cells beat sorted columns for spotting hogs at a glance. The sparkline rail doubles as overview and navigation. Per-logical-CPU grid. Autoscaling axes. Paused update mode for inspecting a frozen snapshot. Compact floating summary view. Power usage vs Power usage trend (instant vs averaged) as two separate signals.
- **Weaknesses / avoid**: ~60 s history with no scrollback and no attribution on graphs (you see that CPU spiked, not who did it). Tab-to-sidebar move costs a click per switch. Hidden affordances (double-click summary view, Ctrl+C copy, kernel times) are undiscoverable. No export or logging. Heat map tint following accent color can hurt legibility (hence Microsoft's blue fallback). Early redesign shipped "old elements pasted into the new shell" inconsistency on secondary pages.
- **Sources**: https://www.windowslatest.com/2022/07/03/windows-11-22h2-hands-with-new-task-manager-features-and-more/ , https://thewincentral.com/microsoft-updates-windows-11-file-explorer-task-manager-battery-tooltip-more-in-the-latest-build-22610/ , https://www.elevenforum.com/t/add-or-remove-columns-in-task-manager-in-windows-11.7173/ , https://blogs.windows.com/windows-insider/2025/02/28/announcing-windows-11-insider-preview-build-26120-3360-dev-and-beta-channels/ , https://www.techrepublic.com/article/news-windows-11-npu-monitoring/ , https://blogs.windows.com/windowsexperience/2013/06/06/windows-8-task-manager-in-depth/ , https://www.howtogeek.com/685379/how-to-show-windows-10s-hidden-floating-performance-panels/ , https://winaero.com/customize-windows-11-task-manager-columns-and-settings/ , https://helpdeskgeek.com/windows-11-task-manager-in-depth-guide-and-overview/ , https://www.techradar.com/computing/windows/what-is-task-manager-in-windows-11 , https://www.bleepingcomputer.com/news/microsoft/windows-11-taskbar-has-a-hidden-end-task-feature-how-to-turn-it-on/ , https://www.makeuseof.com/change-task-manager-real-time-update-speed-windows-11/

### Task Manager history and Dave Plummer's design principles

- **Status**: Historical background. Task Manager shipped first in Windows NT 4.0 (1996); turned 30 in November 2025.
- **What it shows**: n/a (history).
- **How it shows it**: Plummer wrote Task Manager as shareware in his den; Dave Cutler tried it, liked it, and let him check it into Windows. The NT 4.0 binary was about 85 KB and still runs today. His stated goals: small size, robustness, and above all flicker-free painting while resizing in all directions, achieved by exploiting the system listview control fully and invalidating only the rectangle of the single cell that changed. He deliberately put in no "rubber baby buggy bumpers": the OS, not the tool, arbitrated what you were allowed to do, so an admin could kill winlogon or set real-time priority; after journalists demonstrated one-click bluescreens, later versions added a few "kid gloves". Ctrl+Shift+Esc asks the running instance for a secret code and launches a fresh instance if none answers, so it works even when the shell or Task Manager itself is hung. He hunted a CPU-total-over-100% bug by planting an assert containing his own phone number; it turned out to be a kernel accounting bug. Today's Task Manager is roughly 50x the original size.
- **Ideas worth taking**: Flicker-free resize and per-cell invalidation are table stakes for a "fast" monitor. Single-instance self-healing launch. No artificial guardrails beyond OS permissions (with sensible exceptions learned the hard way). Tiny binary discipline (85 KB vs ~50x today is a polemical but useful bar).
- **Weaknesses / avoid**: "Let the OS decide" produced bad PR and had to be walked back; destructive actions do need friction.
- **Sources**: https://www.theregister.com/2020/05/26/task_manager_confession , https://www.theregister.com/software/2025/11/12/microsofts-task-manager-turns-30-original-coder-celebrates/1887243 , https://www.youtube.com/watch?v=Ve95Nh690l0 , https://lexfridman.com/dave-plummer-transcript/

### Resource Monitor

- **Status**: Built into Windows since Vista (resmon.exe; perfmon /res). Still present in Windows 11, effectively in maintenance mode: the MMC-era UI is essentially unchanged for years.
- **What it shows**: Tabs: Overview, CPU, Memory, Disk, Network. CPU tab lists Processes, Services, Associated handles, Associated modules. Memory tab adds per-process hard faults/sec and a physical memory bar. Disk tab splits "Processes with disk activity" from "Disk activity", which shows the actual file path being read/written, plus read B/sec, write B/sec, queue length, and response time; a Storage panel shows per-disk free space. Network tab lists processes with network activity, per-endpoint Network Activity (address, send/receive/total B/sec), a TCP Connections table (local/remote address and port, packet loss, latency), and a Listening Ports table (port, protocol, firewall status).
- **How it shows it**: Each tab pairs left-side sortable tables with a right rail of live graphs (CPU usage per core, disk KB/sec plus queue length, network per adapter, memory hard faults). Ticking a checkbox on any process filters every table and graph on that tab to it ("Filtered by ..." banner). A Search Handles box on the CPU tab finds which process holds a given file or object. All graphs are ~60 s rolling area charts.
- **Ideas worth taking**: Checkbox-driven cross-panel filtering is an underrated pattern for "show me everything this process touches". Per-file disk activity (which file, which direction) answers questions a throughput graph cannot. Listening ports as a first-class table. Queue length displayed next to throughput.
- **Weaknesses / avoid**: Dated look, no dark mode, cramped splitter-heavy layout, graphs too short-lived and too small, discoverability near zero (it is buried behind a Task Manager link).
- **Sources**: https://docs.rackspace.com/docs/guide-to-windows-resource-monitoring , https://en.wikipedia.org/wiki/Resource_Monitor , https://www.pctips.com/resource-monitor/ , https://techcommunity.microsoft.com/blog/askperf/using-resource-monitor-to-troubleshoot-windows-performance-issues-part-1/375008

### Sysinternals Process Explorer

- **Status**: Free Microsoft Sysinternals tool (procexp.exe, 3.5 MB, portable; also Sysinternals Live). Latest version 17.2, published October 15, 2026: adds process efficiency-mode support, persistent process activity history, live kernel memory dump creation, a process memory map explorer, a Devices page in System Information, and NPU monitoring. v17.0 (October 26, 2022) added the dark theme and a multipane main window with a threads pane; v17.08 (November 20, 2025) and v17.11 (April 9, 2026) shipped interim fixes. Runs on Windows 11+ / Server 2019+.
- **What it shows**: Process tree with parent-child indentation and dozens of selectable columns (CPU, private bytes, working set, I/O delta reads/writes, GPU usage since v15, company name, VirusTotal score). Lower pane toggles between DLL mode (loaded DLLs and memory-mapped files) and handle mode (open handles). Per-process properties include threads with stacks, TCP/IP endpoints, environment, GPU and memory graphs. Find > Find Handle or DLL locates lock owners. VirusTotal integration submits hashes and reports detection ratios inline, with optional submission of unknown executables.
- **How it shows it**: One dense window: process tree on top, configurable lower pane, and a toolbar strip of mini graphs for CPU, system commit, physical memory, I/O, disk, network, and GPU; clicking a mini graph opens the System Information dialog (Ctrl+I) with full-size history. Default color legend (Options > Configure Highlighting): green = new processes, red = exited (delta highlight, default 1 s duration), light blue = running in the same security context, pink = hosting services, violet = packed images, dark grey = suspended, yellow = .NET, brown = jobs. In System Information, the CPU graph paints kernel time in red under a green total line; the commit graph and I/O graph (blue total, pink write) behave similarly; hovering any history graph shows which process contributed most at that instant; "Show one graph per CPU" splits into a per-processor view with SMT/NUMA grouping. Tray icons can carry live CPU/I/O/GPU/network/disk history mini-graphs; hover tooltip names the current top process. Other flourishes: space bar pauses refresh, F5 refreshes, crosshair "window finder" identifies a window's process, "Replace Task Manager" option hooks Ctrl+Shift+Esc-era expectations.
- **Ideas worth taking**: Attribution tooltip on history graphs is the single best idea in this whole document: hover a spike, learn who caused it. Delta highlighting for arrivals/exits. Toolbar sparkline strip. One window with a drill-down lower pane rather than more windows. Tray icon mini-graphs as an ambient surface. Color-as-category legend that is user-configurable.
- **Weaknesses / avoid**: Visually spartan and column-overloaded; graph fidelity is coarse. Full functionality needs elevation. Color coding is effective but the legend is buried. The lower pane's DLL/handle duality confuses first-time users.
- **Sources**: https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer , https://learn.microsoft.com/en-us/sysinternals/ , https://techcommunity.microsoft.com/blog/sysinternals-blog/process-explorer-v17-0-handle-v5-0-process-monitor-v3-92-and-sysmon-v14-11/3663465 , https://documentation.help/Process-Explorer/System_Information.htm , https://geek-university.com/process-highlighting/ , https://www.threatdown.com/blog/process-explorer-part-two/ , https://untrustednetwork.net/files/russinovich-malware-hunting-with-the-sysinternals-tools.pdf , https://www.computerworld.com/article/1346034/installing-and-tweaking-process-explorer-part-2.html , https://en.wikipedia.org/wiki/Process_Explorer

### Sysinternals Process Monitor

- **Status**: Free Sysinternals tool. Latest v4.1 (August 19, 2026) adds an IPC event class for named pipes and mailslots. Actively maintained.
- **What it shows**: Real-time event stream of file system, Registry, process and thread, network, and (new) IPC activity. Columns include Time of Day, Process, PID, Operation, Path, Result, Detail; each event's properties include the call stack. Summary tools (File > Tools): Process Activity Summary, Registry Summary, Stack Summary, Network Summary, Cross Reference Summary, Count Occurrences. Boot logging option captures early-start activity.
- **How it shows it**: A dense auto-scrolling event table where the real interface is the filter model: powerful include/exclude rules on any field, plus row highlighting. It is instrumentation, not a dashboard: nothing is charted, everything is itemized.
- **Ideas worth taking**: One unified chronological feed across subsystems; structured filtering that composes include/exclude; per-event stack traces. For Coreography this suggests an optional "activity log" view behind the graphs, not a primary surface.
- **Weaknesses / avoid**: Firehose volume (millions of events) defeats casual use; capture only runs while it runs; no persistence design; purely tabular.
- **Sources**: https://learn.microsoft.com/en-us/sysinternals/ , https://learn.microsoft.com/en-us/sysinternals/downloads/system-information

### TCPView

- **Status**: Free Sysinternals tool, v4.x published April 11, 2023; ships with Tcpvcon, a command-line equivalent. Rarely updated because it does one thing.
- **What it shows**: Every TCP and UDP endpoint on the system with owning process name (and service name), protocol, local address/port, remote address/port, and connection state (LISTENING, ESTABLISHED, TIME_WAIT, etc.). A toolbar toggle switches between resolved names and raw addresses. Established connections can be closed from the File menu or context menu.
- **How it shows it**: A single sortable table refreshing once per second by default (Options > Refresh Rate). State changes are color-coded between refreshes: green rows are new endpoints, yellow rows changed state, red rows closed.
- **Ideas worth taking**: Same diff-highlight vocabulary as Process Explorer applied to connections; per-row destructive action (close connection) in a table of live endpoints.
- **Weaknesses / avoid**: Pure table, no rates or graphs; close-connection feature is a footgun next to browsing.
- **Sources**: https://learn.microsoft.com/en-us/sysinternals/downloads/tcpview

### RAMMap

- **Status**: Free Sysinternals tool for Windows Vista and later; infrequently updated, still distributed.
- **What it shows**: Physical memory decomposition across tabs: Use Counts (by type and by paging list), Processes (working set sizes), Priority Summary (standby list sizes per priority), Physical Pages (per-page use), Physical Ranges (physical address layout), File Summary (file data cached in RAM, by file), File Details (individual pages of a file). Snapshots can be saved and reloaded; an Empty menu can purge standby and other lists.
- **How it shows it**: Tabbed tables with a small summary strip; Use Counts mixes a table with a legend-style breakdown of Active, Standby, Modified, Transition, Zeroed, Free, Bad lists.
- **Ideas worth taking**: Memory presented as a taxonomy (type x paging-list state) rather than one "used" number; file-level cache visibility; snapshot compare workflow.
- **Weaknesses / avoid**: No history, no graphs worth the name; empty-list purging is expert-only.
- **Sources**: https://learn.microsoft.com/en-us/sysinternals/downloads/rammap , https://learn.microsoft.com/en-us/sysinternals/downloads/system-information

### Autoruns

- **Status**: Free Sysinternals tool, actively updated: v14.2 (May 7, 2026) added Windows packaged-app support; v14.3 (June 17, 2026) aligned the autorunsc command line with the GUI. The most comprehensive autostart enumeration tool on Windows.
- **What it shows**: Every autostart location grouped into tabs: Everything, Logon, Explorer, Internet Explorer, Scheduled Tasks, Services, Drivers, Codecs, Boot Execute, Image Hijacks, AppInit, KnownDLLs, Winlogon, Winsock Providers, Print Monitors, LSA Providers, Network Providers, WMI, Office, and more. Each entry shows publisher, image path, timestamp, and (optionally) signature verification and VirusTotal results.
- **How it shows it**: A flat sortable list under many tabs. The killer feature is a filter, not a view: "Hide Microsoft entries" / "Hide Windows entries" strips OS noise so third-party startup items pop out; signature and VirusTotal columns flag the suspicious remainder. Entries jump to their Registry/file location.
- **Ideas worth taking**: Exhaustiveness plus a one-click noise filter beats clever grouping; for Coreography, a "login items" surface gains trust by covering all launch mechanisms, not the friendly few.
- **Weaknesses / avoid**: Dozens of tabs of flat lists; intimidating and purely utilitarian.
- **Sources**: https://learn.microsoft.com/en-us/sysinternals/ , https://learn.microsoft.com/en-us/sysinternals/downloads/system-information

### System Informer (formerly Process Hacker)

- **Status**: Free, open source (MIT). Process Hacker was renamed when the project moved to the winsiderss organization in 2022. Stable 3.2.25011 released May 14, 2025; major release 4.0.26241.138 ("System Informer 4.0") released August 29, 2026 after a year of work; rolling canary builds continue (e.g. 4.0.26255, September 12, 2026). Distributed as portable zip, setup.exe, or Microsoft Store package; requires admin and its signed kernel driver for full data.
- **What it shows**: Process tree with a very large column set (CPU, memory, I/O, GPU, handles, cycles delta, start times, digital signature, packed status, service hosting), Services management that exceeds services.msc (create, edit, delete, control), Network connections per process, Disk and GPU per-process data via the ExtendedTools plugin (admin required), System Information window with CPU/memory/I/O/GPU graphs (F11 fullscreen), handle/DLL search, kernel-mode/WOW64/.NET stack traces, Users tab for logon sessions, WMI tab, environment editor. New in 4.0: a driver-backed Process Monitor (live log of process, thread, image, registry, file, handle, and silo events with filtering, access-mask decoding, configurable look-back); Hybrid Analysis integration adding a reputation column to process and module lists; ring-buffer kernel transport; rewritten installer and updater; experimental low-latency mode on Windows 11.
- **How it shows it**: Main window with Processes/Services/Network tabs, a toolbar, and status bar; extensive row highlighting with user-editable colors; I/O and CPU graphs mark the maximum data point with a label; tray icons provide mini graphs and a click pop-up. The 4.0 cycle brought per-monitor DPI, dark theme across app and plugins, Windows 11 window borders, and much-reduced resize flicker. Plugins (DotNetTools, ExtendedTools, HardwareDevices, OnlineChecks, ToolStatus, UserNotes, WindowExplorer) add panes and data rather than new apps.
- **Ideas worth taking**: "Everything is a column" extensibility; peak labels on graphs; plugins that extend the same list/graph vocabulary; inline service management; fullscreen System Information mode.
- **Weaknesses / avoid**: Depends on a kernel driver and elevation for headline features; installer and binaries periodically flagged by AV engines (dozens of VirusTotal engines have flagged shipped files; tracked in project issues #1668 and #1715); UI density is for experts; canary train is noisy.
- **Sources**: https://systeminformer.com/readme , https://github.com/winsiderss/systeminformer/releases/ , https://github.com/winsiderss/systeminformer/blob/master/CHANGELOG.txt , https://systeminformer.com/canary , https://sourceforge.net/projects/systeminformer/files/ , https://www.xda-developers.com/system-informer-task-manager-alternative/ , https://www.wilderssecurity.com/threads/system-informer-formerly-process-hacker.447068/ , https://github.com/SigmaHQ/sigma/issues/4224

### Performance Monitor (perfmon)

- **Status**: MMC snap-in shipping since Windows NT; still present. Launch modes: perfmon /sys (line monitor), /res (Resource Monitor view), /rel (Reliability Monitor), /report (diagnostics report). Stable, legacy-grade UI.
- **What it shows**: Arbitrary Windows performance counters (PDH) overlaid as line graphs, a histogram (bar) view, or a numeric report view; counters from remote machines too. Data Collector Sets schedule and record logs, replayable in the same graph; alert rules fire on thresholds.
- **How it shows it**: Classic MMC: left tree (Monitoring Tools, Data Collector Sets, Reports), right pane a multi-series line chart with a counter list below where each series gets its own color and a manual scale multiplier; individual counters can be highlighted. Counters are chosen from a modal dialog of object/counter/instance triples.
- **Ideas worth taking**: User-composable multi-metric overlays; per-series scale normalization; record-then-replay with the same visualization.
- **Weaknesses / avoid**: Cryptic counter naming and an expert-only selection dialog; the line chart is static-grid, non-interactive; no one composes counters casually.
- **Sources**: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/perfmon , https://techcommunity.microsoft.com/blog/askperf/prf-reliability--performance-monitor-windows-vista-/373762

### Reliability Monitor

- **Status**: Built in since Windows Vista (perfmon /rel, or Control Panel > Security and Maintenance > Reliability history). Unchanged concept since.
- **What it shows**: A System Stability Index from 1 (least stable) to 10 (most stable), a weighted measure of specified failures over a rolling period where recent failures count more; days powered off or asleep are excluded; the line renders dotted until enough data exists.
- **How it shows it**: A timeline (by day or week): the index line runs across the top third while icon columns per day below mark critical events (red circle-x: Windows failures, application failures, miscellaneous failures), warnings (yellow triangle), and informational events (blue i: software installs/updates, Windows update). Selecting a day or event opens technical details; options include viewing all problem reports and checking for solutions.
- **Ideas worth taking**: A single composite health score over time is a genuinely different visualization from resource charts; event markers on a timeline connect "when did it break" to "what changed".
- **Weaknesses / avoid**: The index math is opaque; buried UI almost nobody finds; backward-looking only.
- **Sources**: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/racwmiprov/win32-reliabilitystabilitymetrics , https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc749032(v=ws.10) , https://techcommunity.microsoft.com/blog/askperf/prf-reliability--performance-monitor-windows-vista-/373762

### Windows Settings battery usage

- **Status**: Built into Windows 11 (Settings > System > Power & battery > Battery usage). On 24H2+, Battery saver was replaced by Energy saver: Quick Settings toggle, auto-enable at a configurable battery threshold, can run even when plugged in, reduces display brightness by 30% (OEM-configurable via the ESBRIGHTNESS powercfg setting), disables transparency effects, and blocks background activity, sync, and most telemetry.
- **What it shows**: A battery-level area graph over "Last 24 hours" or "Last 7 days" with screen-on stats, then a "Battery usage per app" list showing each app's share with a foreground vs background split. Selecting a portion of the graph filters the app list to that period; sort options include overall, in use, and background; a per-app action opens "Manage background activity".
- **How it shows it**: Standard Settings layout: single column, one area chart, ranked app rows with percentages, drop-down period picker.
- **Ideas worth taking**: Brushing a region of the usage chart to filter the ranked app list is a cheap, powerful interaction. Foreground/background split per app is more actionable than one percentage. Putting the remediation control (background policy) on the same row as the measurement closes the loop.
- **Weaknesses / avoid**: Coarse percentage buckets, no absolute energy units; desktop PCs see reduced value (unverified how the page degrades without a battery).
- **Sources**: https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/energy-saver , https://support.microsoft.com/en-us/windows/experience/power-battery/battery-saving-tips-for-windows , https://www.windowscentral.com/software-apps/windows-11/how-to-check-apps-draining-the-most-battery-on-windows-11 , https://www.edtittel.com/blog/24h2-adopts-energy-saver.html , https://www.howtogeek.com/how-to-check-which-apps-are-draining-your-battery-on-windows-11/

### Dev Home widgets (retired)

- **Status**: Discontinued. Microsoft announced Dev Home would go away in May 2025; the GitHub repository was archived June 5, 2025; the app was removed from Windows builds (e.g. 26200.5600) and uninstalled on devices. A subset of developer features moved into Settings (the 25H2 "Advanced" page).
- **What it shows**: A dashboard of Adaptive Card widgets on the Windows Widgets platform: CPU, GPU, Memory, and Network system widgets plus GitHub/Azure DevOps/SSH keychain developer widgets.
- **How it shows it**: Customizable dashboard grid; each system widget was a card showing a utilization figure plus a few key stats (e.g. memory committed/cached/pool, GPU temperature), customizable which devices to show.
- **Ideas worth taking**: Mostly a cautionary tale: a separate dashboard for the same metrics the taskbar/terminal world already had did not survive. Widgets are a secondary surface, never the product.
- **Weaknesses / avoid**: Dead product; required sign-in-adjacent setup for marginal value; widget cards were shallow (a figure and a few stats, no history).
- **Sources**: https://learn.microsoft.com/en-us/previous-versions/windows/dev-home/ , https://github.com/microsoft/devhome , https://github.com/microsoft/devhome/releases , https://learn.microsoft.com/en-us/answers/questions/2350783/dev-home-has-been-removed-in-26200-5600

### Rainmeter

- **Status**: Free, open source (GPLv2), in continuous development since 2001. Latest stable 4.5.28 (October 12, 2026); 5.0.0 Release Candidate 1 also published October 12, 2026. Very large user base: individual releases record millions of downloads on GitHub alone (4.5.23 installer 18.7 M, 4.5.20 8.5 M, 4.5.21 4.4 M, 4.5.26 8.6 M).
- **What it shows**: Desktop "skins": composable meters for CPU, memory, network up/down, disk activity, GPU, plus non-system content (weather, now playing). Popular system skins like SYSMonitor show up-to-16-core CPU bars, RAM, network rates, disk read/write, and via HWiNFO shared-memory integration, temperatures and fan speeds; skins can also read Windows performance counters via the UsageMonitor plugin.
- **How it shows it**: INI-configured meter primitives: text, bar, histogram, line, Roundline gauges, images; arbitrary layout, fonts, colors, transparency, click-through and always-on-top behavior. Skins are mini dashboards on the desktop; many make elements interactive (click a SYSMonitor element to open the matching Task Manager page or drive folder).
- **Ideas worth taking**: Proves demand for ambient always-visible monitoring; click-to-deep-link from a widget into the full tool is exactly right; update interval per skin keeps cost proportional.
- **Weaknesses / avoid**: Hand-edited INI files, inconsistent visual quality across skins, sensor plumbing (HWiNFO, plugins) is user labor; it is a rendering engine, not a monitoring product.
- **Sources**: https://www.rainmeter.net/ , https://github.com/rainmeter/rainmeter/releases , https://forum.rainmeter.net/viewtopic.php?t=45365 , https://www.xda-developers.com/new-cool-rainmeter-skins/

### GlassWire

- **Status**: Commercial freemium for Windows and Android; actively developed. Free tier plus paid plans from $2.99/month equivalent (Personal plan, billed annually) per the pricing page; free tier limits bandwidth history to 1 day and excludes firewall features.
- **What it shows**: Network-centric monitoring: real-time traffic graph per app/host, bandwidth usage by app/host/traffic type (usage table with CSV export), alerts for first network activity, suspicious hosts, new devices, ARP spoofing, evil twins, DNS/proxy/RDP/system-file changes, remote server monitoring, plus hardware monitors for CPU, memory, GPU, and disk. Premium adds click-to-block firewall, lockdown mode, ask-to-connect, longer histories.
- **How it shows it**: Dark, skinned UI. The Traffic Monitor tab has a Graph view and a Usage (table) view; a separate interactive world map shows where connections go by country. Signature interaction is "Network Time Machine": click a point on the traffic graph to see which apps and hosts were active at that moment. A detachable Mini graph widget floats always-on-top; alerts arrive as tray popups then accumulate in an alert log.
- **Ideas worth taking**: Click-back attribution on a history graph (what was happening *then*), the event/alert log as a first-class peer to the graph, graph + ranked-table dual views of the same data.
- **Weaknesses / avoid**: Paywalling the basics (1-day history free) generates resentment; alert-first UX risks noise; it is network-only despite nominal hardware monitors.
- **Sources**: https://www.glasswire.com/pricing/ , https://www.glasswire.com/features/ , https://www.glasswire.com/faq/ , https://forum.glasswire.com/t/does-the-free-version-have-any-sort-of-firewall/21095

### TrafficMonitor

- **Status**: Free, open source (github.com/zhongyang219/TrafficMonitor). Latest release V1.86 (March 29, 2026; the x64 zip has ~565K downloads); previous V1.85.1 (February 10, 2025; ~822K x64-zip downloads). Historically two editions: Standard (requires admin; adds CPU/GPU/disk/motherboard temperature plus GPU and disk utilization via LibreHardwareMonitor since 1.80) and Lite (no admin, no hardware monitoring). Since 1.86, Lite also shows GPU and disk utilization; temperature monitoring moved to a separate Hardware Monitor plugin and the Standard edition is being discontinued.
- **What it shows**: Current upload/download speed, CPU%, memory (percentage, used, or available per setting), CPU frequency, GPU and disk utilization, and (Standard edition / Hardware Monitor plugin) temperatures; a connection-details dialog; historical traffic statistics; plugin-provided items.
- **How it shows it**: Two surfaces: a small floating window (skinnable, right-click menu) and a taskbar-embedded strip docked on the right of the taskbar. The taskbar strip renders chosen metrics as compact text (e.g. up/down arrows + rate, CPU%) and can paint a resource-usage sparkline graph behind the numbers; per-item font, color, width, and unit settings (B vs b, short mode, fixed widths).
- **Ideas worth taking**: The menu-bar-class ambient readout: tiny text metrics with an optional sparkline behind them, configurable per item. Splitting feature sets by privilege (Lite vs Standard) is an honest way to degrade.
- **Weaknesses / avoid**: Taskbar embedding is fragile against OS updates (1.85 release notes mention adapting to the latest Windows 11 taskbar style); text-first presentation; Chinese-first documentation.
- **Sources**: https://github.com/zhongyang219/trafficmonitor , https://github.com/zhongyang219/trafficmonitor/blob/master/README_en-us.md , https://github.com/zhongyang219/TrafficMonitor/releases/tag/V1.85.1 , https://github.com/zhongyang219/TrafficMonitor/wiki/Taskbar-Window , https://www.trafficmonitor.cn/download.html

### PowerToys

- **Status**: Free, open source, Microsoft-maintained; ~30 utilities; latest stable v0.101.2362.0 (August 25, 2026), v0.102 in preview. Includes ZoomIt (integrated since v0.88).
- **What it shows**: No system-monitoring utility exists in the suite. The adjacent tools are File Locksmith (right-click a file to see which processes lock it, a Resource Monitor "associated handles" idea in a context menu) and ZoomIt (screen zoom/annotate, now also on macOS). A community issue requests Process Explorer integration as a PowerToy (open, unimplemented).
- **How it shows it**: Each utility is an independent module behind a shared Settings app; not a monitoring surface.
- **Ideas worth taking**: File Locksmith's placement of "which process holds this file" in the file's own context menu is a better home than a separate tab.
- **Weaknesses / avoid**: Nothing to copy for a monitor's core UI.
- **Sources**: https://learn.microsoft.com/en-us/windows/powertoys/ , https://github.com/microsoft/PowerToys , https://microsoft.github.io/PowerToys/modules/ , https://github.com/microsoft/PowerToys/issues/45806 , https://powertoy.net/changelogs/

## Cross-cutting patterns

- **Color encodes change and category, not decoration**: Task Manager's heat-map cells (intensity), Process Explorer's type+state colors (services pink, packed violet, suspended grey, new green, exited red), TCPView's state-change colors (new green, changed yellow, closed red), System Informer's configurable highlighting. Two distinct uses recur: category highlighting and delta highlighting.
- **Sparkline rail as device picker**: Task Manager's Performance sidebar, Process Explorer's toolbar mini-graphs, Resource Monitor's right rail. Small multiples double as navigation.
- **Attribution on graphs is the rarest and most valuable interaction**: Process Explorer's "top contributor at this instant" hover, GlassWire's "click a point in history" time machine, Resource Monitor's checkbox filtering, Windows battery page's graph-region filtering. Most tools show *that* load happened; almost none show *who* caused it.
- **Compact/ambient modes**: Task Manager's double-click graph summary view and always-on-top; Process Explorer tray history icons; TrafficMonitor's taskbar band; Rainmeter's desktop skins. Glanceable micro-surfaces are a proven second product surface; Microsoft's Dev Home widgets show the failure mode (shallow cards, separate dashboard, abandoned 2025).
- **~60-second memory**: rolling windows are short almost everywhere. Persistence exists only as cumulative counters (App history, Reliability Monitor index), paid retention (GlassWire), or new features (PE 17.2 process activity history). Deep queryable history is unclaimed territory.
- **Update throttling is a first-class setting**: Task Manager High/Normal/Low/Paused (0.5/1/4 s/frozen), Process Explorer update speed + space-to-pause, TCPView refresh rate, Rainmeter per-skin intervals. Pause matters for screenshotting a fault.
- **Privilege-tiered features**: TrafficMonitor Lite vs Standard, System Informer's driver, Process Explorer elevation, resmon admin data. Capability visibly degrades without admin; the honest tools say so.
- **Per-device decomposition**: per-logical-CPU grids (Task Manager, PE's per-CPU checkbox), per-disk/per-adapter graphs (resmon), per-GPU engine columns. Users on modern silicon expect E-core/P-core and engine-level views.
- **Process list is a grid; monitoring is a graph**: the Windows tools all pick one as primary. Task Manager, PE, System Informer, Autoruns, TCPView, procmon are list-first; only Rainmeter/GlassWire/TrafficMonitor surfaces are graph-first. None of the inbox tools treat graphs as the main event: the gap Coreography targets.
- **Emerging metric: NPU/AI engines** (Task Manager 2025-2026 NPU columns and Performance engines, PE 17.2 NPU monitoring, System Informer). Hardware monitoring expands per accelerator class.

## Implications for Coreography

- Adopt the Performance-page information architecture as a baseline but promote it: persistent left rail of sparklines (CPU, memory, disk, network, GPU, battery/thermals) that is both overview and selector, with the main pane devoted to large graphs. That is already graph-first; the process list becomes a secondary pane below or behind it, not the default page.
- Steal attribution-on-graph as a headline feature: hovering any point on any history chart should name the top contributing process(es). Combine with GlassWire's time machine so scrubbing backward replays attribution. No mainstream tool on either OS does both; this alone differentiates from Activity Monitor.
- Use heat-map cell shading in the process table (intensity per column, theme-aware like the accent-color version, but keep a fixed accessible fallback palette). Add delta highlighting: new rows briefly tinted, exiting rows tinted then removed; it is a three-color vocabulary every Windows power tool shares and Activity Monitor lacks.
- Ship a compact mode deliberately (do not hide it behind a double-click): a small always-on-top floating window showing one selected graph, plus an optional all-devices mini view. Add a menu bar extra as the macOS analogue of TrafficMonitor's taskbar band: configurable tiny metrics with an optional sparkline behind the numbers.
- Give the update-speed control (normal/high/low/paused) visible UI, not a buried menu. Paused is a debugging feature, not a preference.
- Go past the 60-second ceiling: keep a longer rolling history (minutes to hours) and make every graph scrub-able; persistence is the unclaimed axis. Per-app cumulative usage (App history, battery page) belongs in a dedicated "over time" view with foreground/background split and the remediation control on the same row.
- Do per-device decomposition properly on Apple Silicon: per-core cluster (E/P) CPU view, per-disk and per-interface graphs, GPU utilization, and unified-memory composition rendered like Task Manager's memory page (in use, compressed, cached, swap) but as a proper segmented bar.
- Power-user tools worth absorbing later, not shipping first: per-file disk activity and "which process holds this file" (resmon/File Locksmith), listening ports and TCP connections table, login-item/launch-agent coverage with a "hide Apple entries" filter (Autoruns' noise filter idea), services/agents management.
- Guard against the failure modes seen here: no paywalled history, no kernel extension dependence for core features, no alert feed that can flood, no INI-style skin system. Keep Plummer's constraints: flicker-free resize and per-cell invalidation in the list, a self-healing single instance, and no guardrails beyond what the OS already enforces (with explicit confirmation for destructive actions, which Task Manager eventually needed).
- Do not copy perfmon's counter-composer or Resource Monitor's density; curate the metric set and let power users opt into columns. Avoid Dev Home's mistake: widgets/menubar are ambient surfaces fed by the app, never a replacement dashboard.

## Sources

- [Windows 11 22H2 Task Manager redesign hands-on (Windows Latest)](https://www.windowslatest.com/2022/07/03/windows-11-22h2-hands-with-new-task-manager-features-and-more/)
- [Redesigned Task Manager with dark mode (Windows Latest)](https://www.windowslatest.com/2022/02/17/hands-on-with-windows-11s-redesigned-task-manager-with-dark-mode/)
- [Build 22610: accent-color heat map (WinCentral)](https://thewincentral.com/microsoft-updates-windows-11-file-explorer-task-manager-battery-tooltip-more-in-the-latest-build-22610/)
- [Windows 11 new Task Manager design (The Verge)](https://www.theverge.com/2022/1/20/22892879/microsoft-windows-11-new-task-manager-design)
- [Task Manager color picker (MakeUseOf)](https://www.makeuseof.com/windows-11-task-manager-color-picker/)
- [Add or remove Task Manager columns; NPU columns, CPU Utility (ElevenForum)](https://www.elevenforum.com/t/add-or-remove-columns-in-task-manager-in-windows-11.7173/)
- [Build 26120.3360: standard CPU metrics (Windows Insider Blog)](https://blogs.windows.com/windows-insider/2025/02/28/announcing-windows-11-insider-preview-build-26120-3360-dev-and-beta-channels/)
- [24H2/25H2 Release Preview: NPU columns, Isolation column (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-insider/release-notes/release-preview-24h2-25h2/build-26100-8514-26200-8514)
- [June update adds NPU monitoring (TechRepublic)](https://www.techrepublic.com/article/news-windows-11-npu-monitoring/)
- [25H2 update coverage (Neowin)](https://www.neowin.net/news/windows-11-25h2-gets-shared-audio-improved-task-manager-better-performance-and-more/)
- [Task Manager AI workload features (Windows IT Pro Blog)](https://techcommunity.microsoft.com/blog/windows-itpro-blog/task-manager-features-for-visibility-into-ai-workloads/4545150)
- [Windows 8 Task Manager in-depth (Windows Experience Blog)](https://blogs.windows.com/windowsexperience/2013/06/06/windows-8-task-manager-in-depth/)
- [Floating performance panels / summary view (How-To Geek)](https://www.howtogeek.com/685379/how-to-show-windows-10s-hidden-floating-performance-panels/)
- [Performance graph summary view (Windows Central)](https://www.windowscentral.com/how-use-windows-10-task-manager-monitor-system-performance)
- [Task Manager tiny footprint mode (Matt Refghi)](https://mattrefghi.com/2016/12/how-to-use-task-managers-hidden-tiny-footprint-mode/)
- [Summary view instructions (EightForums)](https://www.eightforums.com/threads/task-manager-show-in-summary-view-compact-mode-in-windows-8.2472/)
- [Task Manager columns and settings (Winaero)](https://winaero.com/customize-windows-11-task-manager-columns-and-settings/)
- [Windows 11 Task Manager in-depth (HelpDeskGeek)](https://helpdeskgeek.com/windows-11-task-manager-in-depth-guide-and-overview/)
- [Task Manager tabs explained (TechRadar)](https://www.techradar.com/computing/windows/what-is-task-manager-in-windows-11)
- [Task Manager complete guide (How-To Geek)](https://www.howtogeek.com/405806/windows-task-manager-the-complete-guide/)
- [Task Manager processes columns (Daves Computer Tips)](https://davescomputertips.com/understanding-task-manager-processes-part-2/)
- [Task Manager guide (Serverman)](https://www.serverman.co.uk/software/microsoft/windows-11/win11-task-manager/)
- [Open Task Manager, end tasks, shortcuts (Windows 11 Field Guide)](https://windows11.io/task-manager-windows-11/)
- [Hidden End Task taskbar feature (BleepingComputer)](https://www.bleepingcomputer.com/news/microsoft/windows-11-taskbar-has-a-hidden-end-task-feature-how-to-turn-it-on/)
- [End Task taskbar option (Tom's Hardware)](https://www.tomshardware.com/software/windows/kill-windows-tasks-with-impunity-windows-11-has-a-hidden-end-task-taskbar-option-but-it-is-quick-and-easy-to-toggle)
- [End Task feature (TechSpot)](https://www.techspot.com/news/104016-how-enable-windows-11-hidden-end-task-feature.html)
- [End Task on 25H2 Advanced page (BetaNews)](https://betanews.com/commentary/how-to-add-an-end-task-option-to-the-taskbar-in-windows-11/)
- [Real-time update speed (MakeUseOf)](https://www.makeuseof.com/change-task-manager-real-time-update-speed-windows-11/)
- [Real-time update speed values (AllThingsHow)](https://allthings.how/how-to-change-real-time-performance-updates-in-task-manager-on-windows-11/)
- [Task Manager theme (Geek Rewind)](https://geekrewind.com/how-to-change-task-manager-app-theme-in-windows-11/)
- [Memory values explanation (Tom's Hardware forum)](https://forums.tomshardware.com/threads/task-manager-performance-memory-values-explanation.3338281/)
- [Task Manager memory terms mapped to counters (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/win32/memory/memory-performance-information)
- [Dave Plummer confession (The Register)](https://www.theregister.com/2020/05/26/task_manager_confession)
- [Task Manager turns 30 (The Register)](https://www.theregister.com/software/2025/11/12/microsofts-task-manager-turns-30-original-coder-celebrates/1887243)
- [Inside Task Manager with Dave Plummer (YouTube)](https://www.youtube.com/watch?v=Ve95Nh690l0)
- [Dave Plummer transcript (Lex Fridman)](https://lexfridman.com/dave-plummer-transcript/)
- [University of Regina: Secret History of Task Manager](https://uregina.scholaris.ca/server/api/core/bitstreams/3d332314-b89f-4f75-931d-344f263ad335/content)
- [Resource Monitor guide (Rackspace)](https://docs.rackspace.com/docs/guide-to-windows-resource-monitoring)
- [Resource Monitor (Wikipedia)](https://en.wikipedia.org/wiki/Resource_Monitor)
- [Resource Monitor beginner's guide (PCTips)](https://www.pctips.com/resource-monitor/)
- [Resource Monitor troubleshooting (Microsoft Community Hub)](https://techcommunity.microsoft.com/blog/askperf/using-resource-monitor-to-troubleshoot-windows-performance-issues-part-1/375008)
- [Process Explorer (Microsoft Learn)](https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer)
- [Sysinternals index, latest releases (Microsoft Learn)](https://learn.microsoft.com/en-us/sysinternals/)
- [Process Explorer v17.0 announcement (Sysinternals Blog)](https://techcommunity.microsoft.com/blog/sysinternals-blog/process-explorer-v17-0-handle-v5-0-process-monitor-v3-92-and-sysmon-v14-11/3663465)
- [Process Explorer v17.08 (Sysinternals Blog)](https://techcommunity.microsoft.com/blog/sysinternals-blog/process-explorer-v17-08/4471908)
- [Process Explorer v17.11 (Sysinternals Blog)](https://techcommunity.microsoft.com/blog/sysinternals-blog/process-explorer-v17-11/4510019)
- [Process Explorer dark mode coverage (Neowin)](https://www.neowin.net/news/microsoft-updates-process-explorer-with-dark-mode-support/)
- [Process Explorer System Information docs](https://documentation.help/Process-Explorer/System_Information.htm)
- [Process Explorer highlighting (Geek University)](https://geek-university.com/process-highlighting/)
- [Process Explorer System Information window (Geek University)](https://geek-university.com/process-explorer/system-information-window/)
- [Process Explorer colors (ThreatDown)](https://www.threatdown.com/blog/process-explorer-part-two/)
- [Russinovich: Malware hunting with Sysinternals tools (PDF)](https://untrustednetwork.net/files/russinovich-malware-hunting-with-the-sysinternals-tools.pdf)
- [Process Explorer tweak guide (Computerworld)](https://www.computerworld.com/article/1346034/installing-and-tweaking-process-explorer-part-2.html)
- [Process Explorer features (OPCUG PDF)](https://opcug.ca/qa_recordings/20221116_UnderTheHood_Part1.pdf)
- [Process Explorer (Wikipedia)](https://en.wikipedia.org/wiki/Process_Explorer)
- [TCPView (Microsoft Learn)](https://learn.microsoft.com/en-us/sysinternals/downloads/tcpview)
- [RAMMap (Microsoft Learn)](https://learn.microsoft.com/en-us/sysinternals/downloads/rammap)
- [Sysinternals system information utilities](https://learn.microsoft.com/en-us/sysinternals/downloads/system-information)
- [Sysinternals process utilities](https://learn.microsoft.com/en-us/sysinternals/downloads/process-utilities)
- [System Informer readme](https://systeminformer.com/readme)
- [System Informer releases (GitHub)](https://github.com/winsiderss/systeminformer/releases/)
- [System Informer changelog](https://github.com/winsiderss/systeminformer/blob/master/CHANGELOG.txt)
- [System Informer canary builds](https://systeminformer.com/canary)
- [System Informer files (SourceForge)](https://sourceforge.net/projects/systeminformer/files/)
- [System Informer 3.2.25011 release](https://github.com/winsiderss/systeminformer/releases/tag/v3.2.25011.2103)
- [System Informer review (XDA)](https://www.xda-developers.com/system-informer-task-manager-alternative/)
- [Process Hacker rename discussion (Wilders)](https://www.wilderssecurity.com/threads/system-informer-formerly-process-hacker.447068/)
- [System Informer rename/migration (GitHub issue)](https://github.com/winsiderss/systeminformer/issues/1286)
- [System Informer classification discussion (Sigma issue)](https://github.com/SigmaHQ/sigma/issues/4224)
- [System Informer 4.0 coverage (Deskmodder)](https://www.deskmodder.de/blog/2026/08/30/system-informer-4-0-prozessmonitor-zur-ueberwachung-des-systems/)
- [perfmon command reference (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/perfmon)
- [Reliability/Performance Monitor PRF (Microsoft Community Hub)](https://techcommunity.microsoft.com/blog/askperf/prf-reliability--performance-monitor-windows-vista-/373762)
- [Reliability Monitor troubleshooting (Microsoft Community Hub)](https://techcommunity.microsoft.com/blog/askperf/using-reliability-monitor-for-troubleshooting/372962)
- [Win32_ReliabilityStabilityMetrics (Microsoft Learn)](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/racwmiprov/win32-reliabilitystabilitymetrics)
- [System Stability Index (Microsoft Learn)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc749032(v=ws.10))
- [Energy saver (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/energy-saver)
- [Battery saving tips (Microsoft Support)](https://support.microsoft.com/en-us/windows/experience/power-battery/battery-saving-tips-for-windows)
- [Battery usage per app (Windows Central)](https://www.windowscentral.com/software-apps/windows-11/how-to-check-apps-draining-the-most-battery-on-windows-11)
- [24H2 adopts Energy Saver (Ed Tittel)](https://www.edtittel.com/blog/24h2-adopts-energy-saver.html)
- [Battery drain per app (How-To Geek)](https://www.howtogeek.com/how-to-check-which-apps-are-draining-your-battery-on-windows-11/)
- [Dev Home (Microsoft Learn, previous versions)](https://learn.microsoft.com/en-us/previous-versions/windows/dev-home/)
- [Dev Home repository, archived (GitHub)](https://github.com/microsoft/devhome)
- [Dev Home releases](https://github.com/microsoft/devhome/releases)
- [Dev Home removed (Microsoft Q&A)](https://learn.microsoft.com/en-us/answers/questions/2350783/dev-home-has-been-removed-in-26200-5600)
- [Dev Home utilities (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/dev-home/utilities)
- [Rainmeter official site](https://www.rainmeter.net/)
- [Rainmeter releases (GitHub)](https://github.com/rainmeter/rainmeter/releases)
- [Rainmeter 4.5.23 release](https://github.com/rainmeter/rainmeter/releases/tag/v4.5.23.3836)
- [Rainmeter statistics (forum)](https://forum.rainmeter.net/viewtopic.php?t=45365)
- [Rainmeter system monitor skins (XDA)](https://www.xda-developers.com/new-cool-rainmeter-skins/)
- [Rainmeter minimal system monitor skin (forum)](https://forum.rainmeter.net/viewtopic.php?t=45478)
- [GlassWire pricing](https://www.glasswire.com/pricing/)
- [GlassWire features](https://www.glasswire.com/features/)
- [GlassWire FAQ](https://www.glasswire.com/faq/)
- [GlassWire free vs premium firewall (forum)](https://forum.glasswire.com/t/does-the-free-version-have-any-sort-of-firewall/21095)
- [GlassWire pricing summary (GetApp)](https://www.getapp.com/security-software/a/glasswire/pricing/)
- [TrafficMonitor repository](https://github.com/zhongyang219/trafficmonitor)
- [TrafficMonitor English README](https://github.com/zhongyang219/trafficmonitor/blob/master/README_en-us.md)
- [TrafficMonitor V1.85.1 release](https://github.com/zhongyang219/TrafficMonitor/releases/tag/V1.85.1)
- [TrafficMonitor taskbar window wiki](https://github.com/zhongyang219/TrafficMonitor/wiki/Taskbar-Window)
- [TrafficMonitor option settings wiki](https://github.com/zhongyang219/TrafficMonitor/wiki/Option-Settings)
- [TrafficMonitor official download page](https://www.trafficmonitor.cn/download.html)
- [PowerToys (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/powertoys/)
- [PowerToys repository](https://github.com/microsoft/PowerToys)
- [PowerToys modules list](https://microsoft.github.io/PowerToys/modules/)
- [PowerToys Process Explorer request (GitHub issue)](https://github.com/microsoft/PowerToys/issues/45806)
- [PowerToys changelog summary](https://powertoy.net/changelogs/)

## Verification log

Checked 2026-10-17 against primary sources (Microsoft Learn product pages and release notes, GitHub release APIs, official sites, cited articles).

Verified as written: Task Manager 24H2/25H2 builds, 22H2 redesign previewed in build 22557, accent-color heat map from 22610, update-speed values, End task/End all tasks taskbar toggle (BleepingComputer), graph summary view, column set, and memory-page breakdown. Plummer history: NT 4.0 1996 ship, 85 KB binary, ~50x size growth, Cutler approval, phone-number assert, Ctrl+Shift+Esc self-healing, code-stamped November 10, 1995 birthday (Register, Nov 12, 2025). Process Explorer: v17.2 October 15, 2026 with all listed features verbatim from Sysinternals What's New; v17.0 (Oct 26, 2022) dark theme + multipane threads pane; v17.08 (Nov 20, 2025) and v17.11 (Apr 9, 2026); 3.5 MB; runs on Windows 11+/Server 2019+; GPU columns since v15.0 (2011). Process Monitor v4.1 (Aug 19, 2026, IPC class). TCPView publish date April 11, 2023. RAMMap tab list and Vista+ support. Autoruns v14.2 (May 7, 2026) and v14.3 (June 17, 2026). System Informer 3.2.25011 (May 14, 2025), 4.0.26241.138 (Aug 29, 2026) with all listed 4.0 features, canary 4.0.26255.346 (Sep 12, 2026), MIT license, 2022 rename. perfmon /sys /res /rel /report switches. Reliability Monitor index mechanics. Battery page graph-region filtering and foreground/background split. Energy saver mechanics. Dev Home retirement (May 2025), repo archive (June 5, 2025), widget list. Rainmeter 4.5.28 + 5.0.0 RC1 (Oct 12, 2026), GPLv2. GlassWire free-tier 1-day limit, hardware monitors (CPU/memory/GPU/disk), interactive world map, Network Time Machine, alert types. TrafficMonitor V1.85.1 (Feb 10, 2025), LibreHardwareMonitor use, Standard/Lite split. PowerToys v0.101.2362.0 (Aug 25, 2026), v0.102 previews, ZoomIt module (integrated since v0.88), ZoomIt for macOS, File Locksmith, issue #45806.

Corrections made:

- Task Manager: vague "2025-2026 updates added NPU columns" -> pinned to the June 9, 2026 cumulative update (KB5094126, builds 26100.8655/26200.8655) with exact per-page column placement.
- TrafficMonitor: "Latest tagged release V1.85.1" -> V1.86 (March 29, 2026) is the latest release; "~820K" -> 822K for the V1.85.1 x64 zip; "Lite (no admin, no hardware monitoring)" -> Lite gained GPU/disk utilization in 1.86, temperature moved to a Hardware Monitor plugin, and the Standard edition is being discontinued.
- Rainmeter: "skins can also bind to Task Manager data" -> removed; skins read performance counters via the UsageMonitor plugin (plus HWiNFO shared memory). "forum stats show 4-10 M per release" -> replaced with verified GitHub download counts (4.5.23: 18.7 M, 4.5.20: 8.5 M, 4.5.21: 4.4 M, 4.5.26: 8.6 M).
- System Informer: "driver-backed event monitor" -> "driver-backed Process Monitor" (official feature name). "WithSecure and Zillya reports in 2026" -> not confirmed; replaced with verified statement that shipped files draw VirusTotal false positives tracked in project issues #1668/#1715.
- Energy saver: "auto-enable at a battery threshold (default 30%)" -> Microsoft's doc confirms a configurable threshold but states no default; claim changed to "configurable battery threshold". Brightness reduction is exactly 30%, OEM-configurable (ESBRIGHTNESS).
- GlassWire: "paid plans from $2.99/month (Personal)" -> the pricing page shows EUR 2.99/mo billed annually; reworded accordingly. "three views: Graph, Usage, and Map (an interactive world map with animated live connections)" -> reworded to Graph and Usage views plus a separate interactive world map, matching the features page.
- Dev Home: "a utilization bar and percentage" -> cards showed a figure plus several stats (committed/cached memory, GPU temperature) per Microsoft docs.
- Dead links: geek-university.com/process-explorer/process-highlighting/ (404) -> https://geek-university.com/process-highlighting/ ; ourtechroom.com committed-memory article (404) -> https://learn.microsoft.com/en-us/windows/win32/memory/memory-performance-information .

Remains unverified: the exact attribution wording on Process Explorer's history-graph hover and its full tray/toolbar mini-graph set (mirrors of the PE help file were bot-blocked); TCPView's exact minor version ("v4.x" left as written); whether System Informer's installer saw WithSecure/Zillya flags specifically in 2026; Rainmeter forum per-release stats thread (403 to bots; GitHub counts substituted); claim that SYSMonitor skins deep-link into Task Manager pages (secondary source only).
