# Specialised visualisers and power-user utilities (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

## Summary

- Every subsystem already has a canonical spatial visual: sunburst for disk hierarchies (DaisyDisk), treemap (GrandPerspective, WinDirStat, SpaceSniffer, WizTree), stacked category bar (macOS Storage), channel-occupancy plot (WiFi Explorer), floor-plan heatmap (NetSpot), geographic map (Little Snitch), nested capacity bars (coconutBattery), editable XY curve (FanControl). Coreography should pick the established metaphor per domain rather than invent new ones.
- The strongest reusable interaction found: chart-as-time-selector. GlassWire and Little Snitch let you click a traffic chart to scope every other view to that moment. Equivalent: selecting a CPU-history region should filter the process list to what ran then.
- The most valued power features are joins between datasets, not new metrics: per-app cumulative bytes (TripMode's killer feature), process -> open files/sockets (Sloth, Process Explorer handle search), background item -> live resource cost, per-app crash counts.
- "Hide signed Apple/Microsoft entries" (Autoruns) and TaskExplorer's `#token` filter grammar are the two filtering patterns worth copying; both reduce hundreds of system rows to the dozen a user can act on.
- Reverse lookup - "which process holds this file or port" - is the highest-value power feature in the category and has no great Mac-native home today (Sloth is the closest, but snapshot-based).
- Monitoring vs control is the key scope line: Little Snitch/LuLu (firewall), TG Pro/Macs Fan Control (fans), AlDente (charging), DaisyDisk (deletion) all mutate the system. Their observation layers belong in Coreography; their control layers do not, and Apple's own features keep absorbing the controls anyway (Storage settings, Login Items & Extensions, charge management, Low Power Mode).
- Retention is a competitive moat: Little Snitch keeps up to twelve months of traffic history; coconutBattery snapshots battery health over time; GlassWire sells "Network Time Machine". Rolling history is table stakes for a monitor claiming to be better than Activity Monitor.
- macOS 27 churn is real: AlDente had to rebuild charge control, TG Pro (2.104, Sep 28) and Macs Fan Control (1.5.22, Sep 2) shipped Golden Gate and new-Mac fixes in Sep 2026, and asitop's upstream has been inactive since ~2023 with community forks extending it to newer chips. Sensor/telemetry parsing is a per-chip maintenance tax; Apple-blessed APIs (Endpoint Security, powermetrics, IOReport) are worth more than clever scraping.
- New entrant to watch: WizTreeMac 1.00 shipped Sep 16, 2026 - the fast-scanner market is moving onto macOS.
- TaskExplorer 3.0 (2026) is the freshest reference for a modern process explorer: Endpoint Security live enumeration, modern UI, `#keyword` filters, signing provenance, JSON export - and its AI assistant shows where the boundary of "too much" lies.

## Tools

### DaisyDisk

- **Status**: macOS 10.13+, Apple Silicon and Intel. Paid, $9.99 one-time lifetime licence (direct via FastSpring, also on the Mac App Store; minor updates included, up to 5 personal Macs). Latest version 4.34.2 (Jul 10, 2026). Actively maintained since 2008; release notes page shows several updates per year. Recent releases added Liquid Glass icons and macOS Tahoe compatibility (4.32-4.33).
- **What it shows**: disk usage per file/folder as physically used space on disk (excludes clones and hard links); capacity and free space for all connected disks in real time before any scan; breakdown of the opaque "Other" / "System Data" categories from About This Mac; APFS/local snapshots that quietly consume space; optional cloud storage scan (Dropbox, Google Drive, OneDrive, Box).
- **How it shows it**: the signature view is an interactive sunburst: concentric rings radiating from a centre circle, each ring band one directory level deeper, arc angle proportional to size; bright saturated hues assigned per top-level folder and carried down its subtree. A file list sits beside the map; hovering a list row highlights the matching arc and vice versa. Clicking a folder arc animates a drill-down rotation so the folder becomes the new centre; a breadcrumb path bar leads back. Space bar gives Quick Look preview. Scan-as-administrator exposes restricted files. Files are dragged onto a "collector" tray at bottom-left which then shows total recoverable space before a confirm-delete step. Marketing claims a full disk scan in ~15 s vs minutes for Finder.
- **Ideas worth taking**: sunburst with animated drill-down is the best-looking spatial metaphor for hierarchies; show free space per volume live, before and without scanning; demystify hidden space (snapshots, restricted files, "System Data") instead of a flat mystery category; deletion as an explicit collect-then-confirm flow, never one click.
- **Weaknesses / avoid**: sunburst arcs are hard to compare for similar sizes (a table beside it is essential); rings waste screen area at depth; deletion is out of scope for a monitor - the interesting part is "what is using space and when did it grow", which DaisyDisk cannot show (no history, no growth-over-time).
- **Sources**: https://daisydiskapp.com/ ; https://daisydiskapp.com/releases/ ; https://daisydiskapp.com/support/pricing/

### GrandPerspective

- **Status**: macOS 14+, GPL open source (Objective-C, on SourceForge). Free download from SourceForge or $2.99 on the Mac App Store (same app; the fee covers distribution/development). Latest 3.8.1 (Sep 13, 2026); continuously maintained by Erwin Bonsma since 2005 (20-year milestone Sep 2025). Recent releases added Liquid Glass compatibility.
- **What it shows**: treemap of disk usage where each file is a rectangle with area proportional to size; files in the same folder are placed adjacently but otherwise arbitrarily.
- **How it shows it**: flat (non-cushioned) treemap; thin folder outlines group children. The notable depth is configurability: colour mapping by name, extension, file type, parent folder, top folder, hierarchy level, size, creation time, modification time, or last access time, with a choice of palettes. Filter system builds tests on name/path/size/type/hard-link/package status and can mask items in the view, remove them from the view, or exclude them from scanning. Multiple views of the same scan can be twinned; scans can be saved, reloaded and compared before/after cleanup; results export as image or text; Quick Look preview; view changes animate.
- **Ideas worth taking**: colour mapping is a dimension channel independent of size - colour by modification time instantly reveals "old junk", colour by top folder shows ownership; saved scans enable before/after comparison; mask vs filter vs exclude is a clean three-level filtering model.
- **Weaknesses / avoid**: purely functional Aqua-era presentation; arbitrary rectangle placement gives no size ordering cue inside a folder; no labels inside small rectangles, so dense regions become noise.
- **Sources**: https://grandperspectiv.sourceforge.net/ ; https://sourceforge.net/projects/grandperspectiv/files/grandperspective/

### OmniDiskSweeper (Omni Group)

- **Status**: macOS, freeware since 2009 (originally 2001 shareware). Latest 1.16 (Sep 12, 2025). Maintained at a low cadence.
- **What it shows**: files and folders on a drive sorted strictly largest to smallest; a drives window lists all mounted volumes with capacity.
- **How it shows it**: a Finder-style column browser: each column shows directory contents sorted by descending size, with the size column tinted by magnitude (small sizes green, escalating through orange to red for the biggest items). Selecting a file offers Trash It or Reveal in Finder. No chart at all: the ranked list is the entire visualisation. Packages (app bundles) are treated as single items.
- **Ideas worth taking**: a descending-size column browser is the fastest possible answer to "what is big"; colour-graded size text does ranking without a chart; bundles-as-files matches the user's mental model.
- **Weaknesses / avoid**: zero visualisation depth, no proportional sense of the whole disk, no history; it is a feature, not an app, from Coreography's perspective.
- **Sources**: https://www.omnigroup.com/more/ ; https://en.wikipedia.org/wiki/OmniDiskSweeper ; https://files.omnigroup.com/software/macOS/11/

### macOS Storage settings

- **Status**: built into macOS (System Settings > General > Storage; the About This Mac > Storage variant predates it). Free, maintained by Apple; on macOS 26/27 it sits in System Settings under General.
- **What it shows**: a categorical breakdown of used space (Apps, Developer, Documents, macOS, System Data, and user/app-specific categories such as Music, Photos, Mail, Messages); per-category detail panels (e.g. Documents shows Large Files, Downloads, Unsupported Apps lists); storage recommendations (Store in iCloud, Optimize Storage, Empty Trash Automatically).
- **How it shows it**: a single horizontal stacked bar segmented by category, with a legend of coloured dots below; category panels below use plain lists with size columns. Categorical, not spatial: it never shows *where* bytes live, which is exactly the gap DaisyDisk/GrandPerspective exploit. The "System Data" bucket is famously opaque and a known user complaint.
- **Ideas worth taking**: the stacked capacity bar is the right "headline" storage visual - one glance shows used vs free and the rough mix; recommendations tie measurement to action.
- **Weaknesses / avoid**: categories hide file system location; "System Data" is a documented catch-all ("files that don't belong to any more specific category") that users cannot manage, and it is a perennial complaint; slow to calculate; nothing live or historical.
- **Sources**: https://support.apple.com/en-us/102624

### WinDirStat

- **Status**: Windows, GPL open source (github.com/windirstat/windirstat, MSVC/MFC). Latest release 2.9.3 (Oct 11, 2026); the project was dormant ~2005-2024, then relaunched with 2.0 in Oct 2024 and has released rapidly since.
- **What it shows**: sortable directory tree with sizes and percentages, a per-extension aggregation list, and an interactive treemap; recent 2.x versions add All Files, Largest Files, Duplicate Files, Search Results and File Watcher views, duplicate detection (optional sparse hashing), search filters (size range, type, owner), and alternative visualisations: flame graph, sunburst, and Hilbert and Moore treemap layouts, with KDirStat or SequoiaView styling presets.
- **How it shows it**: classic three-pane layout - directory list top-left, extension list top-right, treemap filling the bottom half. Treemap rectangles are sized by file size and coloured by file extension; selecting a rectangle outlines it in white and selects the same node in the tree, linking all three views bidirectionally. Free space and unaccounted "unknown" space are shown as distinct regions. The 1.x era had a pac-man progress animation while scanning. Cleanup actions (Open, Delete, Properties, user-defined commands) act on the selection.
- **Ideas worth taking**: the extension list is a second, orthogonal aggregation - "all .dmg files total 40 GB" is a question treemaps alone answer badly; bidirectional selection between tree, extension list and map; offering multiple layout algorithms (squarified, Hilbert, Moore) acknowledges different readability trade-offs; duplicates and largest-files are dedicated views, not buried filters.
- **Weaknesses / avoid**: per-extension random colours produce a garish confetti map; the MFC-era chrome looks dated; three dense panes compete for attention.
- **Sources**: https://github.com/windirstat/windirstat/releases ; https://github.com/windirstat/windirstat/blob/master/CHANGELOG.md ; https://blog.windirstat.net/category/release/

### WizTree

- **Status**: Windows freeware for personal use (commercial use needs a paid Supporter Code, USD 25-500 by staff size; Enterprise licence USD 750). Version 4.33 (Sep 16, 2026). Notably, the same release shipped "WizTreeMac" 1.00 for macOS 12+ (universal binary) - a new direct competitor on Coreography's platform. Developed by Antibody Software.
- **What it shows**: sizes of all files and folders; a largest-files file view/search; duplicate files; handles hard links correctly (no double counting); CSV export and command-line export/MFT dump.
- **How it shows it**: functional split window: a directory tree pane, a treemap, and a largest-files list; the treemap uses strong flat colours by file type. Its real differentiator is speed: on NTFS it reads the Master File Table directly (like Everything Search) rather than walking the filesystem - the site claims 46x faster than WinDirStat, full scans in seconds.
- **Ideas worth taking**: scanning speed is a headline feature users remember - for Coreography, reading APFS metadata efficiently (or indexing once and watching FSEvents) beats walking the tree every launch; a flat "largest files" list is a distinct and heavily used view; CSV export and CLI output for power users.
- **Weaknesses / avoid**: utilitarian enterprise-style UI; treemap is an afterthought to the lists; macOS version is brand new (1.00) and a subset of the Windows feature set.
- **Sources**: https://www.diskanalyzer.com/ ; https://www.diskanalyzer.com/download ; https://www.diskanalyzer.com/whats-new

### SpaceSniffer

- **Status**: Windows freeware (donations accepted), portable single executable by Uderzo Software. Latest 2.2.0.27 (Mar 25, 2026, per Wikipedia). Infrequent releases; closed source.
- **What it shows**: treemap of disk usage; supports NTFS Alternate Data Streams; multiple simultaneous scan windows for different drives/folders.
- **How it shows it**: treemap occupies the whole window with a breadcrumb path bar on top; single-click selects and shows detail, double-click zooms a node to fill the view (zoom is the primary navigation, not a separate level); scanning continues live in subtrees you have not zoomed into. A filter syntax (name, age, size, tag) typed into the view masks matching elements live; colours assigned by file type are user-configurable; selected elements show a size label inside the block.
- **Ideas worth taking**: zoom-to-fill with breadcrumb is a cleaner drill model than DaisyDisk's radial rotation for rectangular layouts; live filter-as-you-type over the visualisation; background scanning that keeps the view explorable mid-scan.
- **Weaknesses / avoid**: cluttered chrome, early-2000s styling; development nearly stalled for years; no delete integration beyond shell commands.
- **Sources**: https://www.uderzo.it/main_products/space_sniffer/index.html ; https://en.wikipedia.org/wiki/SpaceSniffer

### Little Snitch 6 Network Monitor (Objective Development)

- **Status**: macOS, paid. Single licence EUR 59 (valid for both Little Snitch 5 and 6); upgrade licences cheaper. Little Snitch 6's headline additions: DNS encryption, blocklist support, redesigned interactive traffic chart, menu-bar Control Center, new hierarchical grouping options, search tokens, sound notifications. Actively maintained (~20 years on the market).
- **What it shows**: which process connects to which server, where the server is geographically, plus statistics per connection: data transferred over time (history up to twelve months), protocols and ports. Control Center in the menu bar shows recent activity charts and recently blocked connections.
- **How it shows it**: three coordinated views in one window. (1) Connection list: hierarchical table, default grouping Process > Domain > Server; regroupable to Domain > Process or Country > Process > Domain > Server; system processes folded into app groups like "macOS" or "Simulator". (2) Traffic Chart: bar chart of upload/download volume per time unit, zoomable across a year of retained data. (3) Map: geographic map with city/region/cluster marks (GeoIP via local MaxMind/IP2Location/db-ip/Geonames databases, no online lookups); private-network servers are parked at a placeholder spot in the Atlantic Ocean so they cannot be mistaken for a real location. Selecting map marks filters the connection list; a Connection Inspector gives per-connection detail. Search tokens for app, hostname, country, city.
- **Ideas worth taking**: this is the reference design for "who is my Mac talking to": process-to-server hierarchy with regroupable columns, a chart that doubles as a time navigator, and geo context that is decorative but genuinely explanatory. The grouping dimension picker (by app / domain / country) is a small feature with huge payoff. One year of per-connection byte history proves rolling retention is expected by power users.
- **Weaknesses / avoid**: it is a firewall first; the monitor is one pane inside a rules-management app. GeoIP maps are decorative for most connections (CDNs cluster in a few cities). Alert fatigue from connection prompts is the classic complaint.
- **Sources**: https://www.obdev.at/products/littlesnitch/index-en.html ; https://www.obdev.at/products/littlesnitch/whatsnew.html ; https://help.obdev.at/littlesnitch6/lsm-overview ; https://help.obdev.at/littlesnitch6/lsm-map ; https://www.obdev.at/products/littlesnitch/order.html

### LuLu (Objective-See)

- **Status**: macOS 10.15+, free and open source (github.com/objective-see/LuLu). Latest 4.5.1 (Aug 5, 2026); 4.5.0 added "Process + Kids" rules, passive rule creation when no user client is running, better regex/glob/CIDR handling; 4.4.0 (Jun 2026) added compatibility with code-signing changes in macOS 26.6/Golden Gate.
- **What it shows**: no charts at all: it is an outbound firewall. The only views are the alert dialog on a new connection (process icon and path, code-signing info, remote address/port/URL) and a rules window listing per-process rules with allow/block toggles.
- **How it shows it**: the alert is the UX: a modal showing who is connecting, where to, over which protocol, with click-through code-signing details, Allow or Block creating a persistent rule (optionally scoped to the exact host/port, or process-plus-children). Rules window groups rules per app; DNS-aware rules can match domains.
- **Ideas worth taking**: surface identity at the decision moment: signing status, full path, process ancestry are all shown inline in the alert; "Process + Kids" acknowledges helper-process reality; free plus auditable beats Little Snitch for many users.
- **Weaknesses / avoid**: zero monitoring visualization; outbound only; per-connection prompting does not scale (users click Allow reflexively). For Coreography, its value is the alert-layout pattern, not the feature.
- **Sources**: https://objective-see.org/products/lulu ; https://github.com/objective-see/LuLu/releases

### GlassWire

- **Status**: Windows (and Android), freemium. Version 3.11.1164 (Oct 6, 2026), ~monthly releases. Free tier plus paid upgrades unlocking longer history, mini graph, more remote PCs, themes.
- **What it shows**: real-time and historical network activity per app and per host; usage breakdowns by app/host/traffic type; devices on the network ("Who's on your WiFi") with new-device alerts; alerts for new apps going online, network changes, evil twin APs, RDP connections; firewall rules per app (in/out bidirectional, ask-to-connect, block-all lock down, profiles); since 3.x also hardware resource monitoring (GPU, memory).
- **How it shows it**: tabbed window; since 3.3 the tabs are Traffic Monitor (graph plus usage table and a country map view), GlassWire Protect (firewall), Log Analysis (alerts), and Network Scanner (devices on the network, "Things"); 3.8 (Feb 2026) added a Hardware Resources tab. The Traffic Monitor graph is a scrolling area/line chart of throughput; clicking and dragging on the graph selects a time period and re-filters the app/host lists to that slice, so the chart doubles as a time selector ("Network Time Machine" for longer retrospection). Neon accent colours on dark theme, skins available; a desktop "mini graph" gives a persistent widget. Bulk firewall actions added in 3.11.
- **Ideas worth taking**: chart-as-time-selector is the single best interaction to steal: click the graph, the detail lists scope to that moment; alerts as a first-class stream (new app on network, new device joined, app binary changed); a mini always-on-top graph as a reduced presence.
- **Weaknesses / avoid**: consumer-security aesthetic (dark, glowing, alarmist alerts); feature gating pushes users to premium; the graph is a single metric, Coreography needs many.
- **Sources**: https://www.glasswire.com/ ; https://www.glasswire.com/features/ ; https://www.glasswire.com/changes/

### Private Eye (Radio Silence)

- **Status**: macOS, free, DISCONTINUED: the developer's own page says "Private Eye is no longer actively maintained" and points to Radio Silence (v3.4, works with macOS Golden Gate, $9). Homebrew deprecated/disabled the cask (dates unverified); the product page offers downloads for OS X 10.9+ and says it requires OS X Lion through El Capitan (10.7-10.11). Radio Silence itself is a paid outbound firewall whose 3.x versions absorbed the real-time connection monitor.
- **What it showed**: every new network connection in real time, per app, filterable by app and direction.
- **How it showed it**: a single connection list window: rows per app connection appearing live; filter field; closing the window turned monitoring off ("stays out of the way by slacking off whenever you aren't looking").
- **Ideas worth taking**: the zero-config "just show me live connections" mode - a read-only network pane needs no firewall machinery; auto-idle when not visible is a good power behaviour for any monitor pane.
- **Weaknesses / avoid**: abandoned for years; kernel-extension era tech (nke kext visible in the cask uninstall). Its survival lesson: a monitor feature inside a paid product (Radio Silence) outlived the free standalone viewer.
- **Sources**: https://radiosilenceapp.com/private-eye/ ; https://radiosilenceapp.com/ ; https://github.com/Homebrew/homebrew-cask/blob/80121d533f3b5f5410f2bd60f008d615031a9c9c/Casks/p/private-eye.rb

### TripMode

- **Status**: macOS 11+ (Big Sur required for the network-filter design). Launched Nov 2020 at $15 single licence / $20 two-device; today sold via the Mac App Store (subscription; $11.99/yr per Macworld, unverified), via a direct "License version" from the developer's buy page, and via Setapp. Homepage notes compatibility with macOS 27 Golden Gate. Maintained.
- **What it shows**: per-app internet data usage counters (session and historical by day/week/month), live per-app transfer speed ("speedometer for all your apps"), which domains each app connects to (App Inspector), data-plan limits with warnings and hard cutoff; profiles with per-network auto-activation (hotspot/tethering detection).
- **How it shows it**: menu-bar popover listing apps, each row a toggle switch plus cumulative data counter; a detachable Live Monitor window floats above other apps; Reports view aggregates usage per app per period; Scheduler for time-based allow/block.
- **Ideas worth taking**: per-app byte accounting is the feature Apple never built - users on metered connections need "how much did Slack download today", not throughput; auto-activation by network identity (this Wi-Fi = metered) is a model for context-aware profiles; domain-level per-app detail.
- **Weaknesses / avoid**: limits are cutoff not shaping; narrow single-purpose; the metering data lives in its network extension so it cannot seed a general monitor.
- **Sources**: https://tripmode.ch/ ; https://tripmode.ch/buy/ ; https://tripmode-updates.ch/download-press/TripMode_3_Press_Release-2020.11.03.pdf ; https://www.macworld.com/article/344699/tripmode-3-review.html ; https://apps.apple.com/us/app/tripmode/id1513400665?mt=12

### Netiquette (Objective-See)

- **Status**: macOS, free open source (Objective-See). Latest 2.3.0 (Oct 5, 2026, added localization); 2.0.0 (May 25) added sortable columns, per-connection bytes up/down, domain-name resolution.
- **What it shows**: all network connections and all listening sockets; process, PID, protocol, endpoints, state, bytes in/out; filter; CSV-style export; CLI mode for scripting.
- **How it shows it**: one compact table: process name, PID, protocol, local/remote addresses, state, traffic counters; search/filter bar; adjustable row padding via Cmd +/-; expand/collapse all. Essentially a live `netstat`/`lsof -i` with a native UI.
- **Ideas worth taking**: listening sockets as a first-class category ("what is this Mac exposing") is a genuinely security-relevant view most monitors omit; UI density controls are cheap and loved.
- **Weaknesses / avoid**: snapshot-style table, no history, no rates-over-time beyond counters; Coreography's network pane should embed this data inside its richer per-process view.
- **Sources**: https://github.com/objective-see/Netiquette/releases ; https://objective-see.org/tools.html ; https://github.com/objective-see/Netiquette

### WiFi Explorer (Intuitibits)

- **Status**: macOS 13.5+, paid. Consumer WiFi Explorer ($19.99 direct, 3-day trial; Mac App Store version auto-updates, current 3.6.x unverified); WiFi Explorer Pro 3 ($149.99, 7-day trial, requires macOS 13.5+) for WLAN professionals. Actively maintained by Intuitibits (Adrian Granados). A separate WiFi Explorer Pro for Windows exists.
- **What it shows**: every detected network with SSID, BSSID, vendor, RSSI, noise, SNR-derived quality rating, channel/band/width, security, supported rates, advertised information elements; Wi-Fi 4 through 7 on 2.4/5/6 GHz (20-320 MHz widths, unverified). Pro adds more than 550 selectable column fields, passive/directed scan modes (passive Intel-only), remote sensors (e.g. WLAN Pi), capture file import, spectrum-analyser integration, SSID overhead estimation, colouring rules, column profiles with pinning.
- **How it shows it**: two stacked visuals: a sortable/filterable networks table and the signature "channel occupation" chart where each network is a coloured arc/block spanning its channel width on the frequency axis, height encoding signal strength - overlapping networks literally overlap on screen; per-network RSSI history line graphs; custom colouring rules to flag specific BSSIDs or problem types; CSV export.
- **Ideas worth taking**: the channel-occupancy plot is the canonical RF visualisation; colouring rules (user-defined predicates -> colour) generalise beautifully to process highlighting; column profiles for different task modes.
- **Weaknesses / avoid**: single-domain depth; Pro's field count is analyst-grade; RF scanning depends on macOS Wi-Fi scan APIs with band limitations on newer hardware.
- **Sources**: https://apps.apple.com/us/app/wifi-explorer-scanner/id494803304?mt=12 ; https://www.intuitibits.com/products/wifiexplorerpro3/ ; https://formulae.brew.sh/cask/wifi-explorer

### NetSpot (Etwok)

- **Status**: macOS/Windows plus iOS and Android companions, freemium: Free, PRO and Enterprise editions (current site sells per-user commercial licences; older tier tables, e.g. iMore, listed Home ~$49, PRO ~$149, Enterprise ~$499). Over 15 years on the market; actively maintained (the Android app supports surveys and planning and exports projects to the desktop editions).
- **What it shows**: two modes. Inspector = real-time scanner (SSIDs, signal, channels, security). Survey = walk a floor plan, click your position at each data point, collect signal/noise samples; output is a set of interpolated heatmaps (signal level, SNR, signal-to-interference; PRO unlocks further visualisation types, ~23 total, unverified); Planning mode renders predictive heatmaps for hypothetical AP placements.
- **How it shows it**: the heatmap: a floor-plan image overlaid with a colour gradient field (red/orange strong to blue weak) interpolated from sampled points; side legend maps colour to dBm. Zones, snapshots and data points organise multi-floor buildings; survey exports to PDF reports.
- **Ideas worth taking**: spatial interpolation of point samples into a continuous field is the general pattern for "metric over a map" (works for thermals over a motherboard diagram too); calibrating the view against a user-supplied floor plan keeps it concrete.
- **Weaknesses / avoid**: site surveys are a workflow, not a glanceable monitor - out of Coreography's scope beyond inspiring spatial heatmaps; tier limits (data points, AP count) are aggressive.
- **Sources**: https://www.netspotapp.com/ ; https://www.imore.com/netspot ; https://www.netspotapp.com/upgrade-netspot-win.html

### Wireless Diagnostics (Apple, built-in)

- **Status**: built into macOS (open via Option-click on the Wi-Fi status menu, or /System/Library/CoreServices/Applications/Wireless Diagnostics.app). Free, maintained by Apple.
- **What it shows**: guided diagnostics for the current Wi-Fi connection (environment scan, channel recommendations); a live monitor that graphs signal/noise over time and logs drops; report generation for support; and the hidden Wi-Fi Scan utility (Window > Utilities or Cmd+2 in the app) that lists nearby networks with RSSI, noise, channel, band and security, refreshing continuously.
- **How it shows it**: wizard-first tool with utility windows tacked on: the scan window is a compact always-refreshing table, the monitor graphs signal and noise lines over time. Nothing is saved as history beyond the generated diagnostic report.
- **Ideas worth taking**: the channel recommendation ("your best 2.4/5 GHz channels are X and Y") is measurement turned directly into advice - the answer users actually want from an RF pane; Option-click on the status item as a zero-friction entry point.
- **Weaknesses / avoid**: analyst/support workflow, not a live monitor; scan window has no history, no comparison, no per-network drill-down, which is exactly the gap WiFi Explorer/NetSpot fill.
- **Sources**: https://support.apple.com/guide/wireless-diagnostics/welcome/mac

### Speedtest (Ookla) and macOS networkQuality

- **Status**: Speedtest by Ookla: free macOS menu-bar app and speedtest.net, ad/upsell funded. `networkQuality`: built into macOS since Monterey 12, command line, maintained by Apple. `speedtest-cli`-style third-party CLIs exist but the official Ookla CLI is licensed.
- **What it shows**: Speedtest: ping, jitter, download, upload against a picked server. `networkQuality`: upload capacity, download capacity, upload/download flow counts, base RTT, and Responsiveness in RPM (round trips per minute *under load*) rated Low/Medium/High; flags: `-v` verbose, `-s` sequential up/down, `-c` JSON output, `-I` bind to interface, custom server via config URL.
- **How it shows it**: Speedtest's UI is the famous animated speedometer dial with a live needle during the test, then a result card. `networkQuality` prints a `==== SUMMARY ====` block: capacities in Mbps, flows, `Responsiveness: Low (121 RPM)`, base RTT, timestamps.
- **Ideas worth taking**: RPM-under-load is a far better quality metric than idle ping: it captures bufferbloat, and the Low/Medium/High labelling makes it legible; the JSON output makes it trivially embeddable - Coreography can run it on demand or on a timer and chart responsiveness history; the dial is engaging but a live throughput bar works too.
- **Weaknesses / avoid**: a point measurement, not a monitor; RPM still needs the user's line speed as context; tests consume real bandwidth so they must be user-triggered or rare.
- **Sources**: https://keith.github.io/xcode-man-pages/networkQuality.8.html ; https://tidbits.com/2022/04/22/use-apples-networkquality-tool-to-test-internet-responsiveness/ ; https://developer.apple.com/videos/play/wwdc2021/10239/ ; https://support.apple.com/en-us/HT212313

### coconutBattery

- **Status**: macOS 12+, freemium. Free version covers Mac and iPhone/iPad battery diagnostics, health history saving, menu-bar basics; "Plus" (paid upgrade; ~$21.54 per MacUpdate, unverified) adds Lifetime Analyzer, Advanced Viewer (internal SSD read/write stats), custom printing templates, notifications, full menu-bar details, Wi-Fi sync of iOS devices. Latest 4.4 (Sep 9, 2026), with support for macOS/iOS/iPadOS 27. Maintained by coconut-flavour.com since 2005.
- **What it shows**: current charge vs maximum capacity; maximum capacity vs design capacity (battery wear %, can exceed 100% on over-specced packs); cycle count; manufacture date of device and battery (where serial numbers allow decoding); battery temperature; live charge/discharge rate (W); iOS device batteries over USB or Wi-Fi; history of saved health snapshots over time; per-Plus: temperature/voltage/rate ranges and operating time over the battery's lifetime.
- **How it shows it**: compact single window dominated by two capacity bar pairs: "Current charge / maximum capacity" and "Maximum capacity / design capacity", drawn as nested green/blue/gray bars - wear is literally a gap in the bar. Small monospace-ish stats grid for cycles, temperature, power draw, manufacture dates. History viewer lists dated capacity/cycle entries; menu-bar item condenses to percentage + health.
- **Ideas worth taking**: the nested capacity bar (charge inside max inside design) shows three magnitudes in one glyph - the same pattern works for memory (wired inside used inside total); timestamped health snapshots make degradation a chartable series, which Coreography should persist; design-vs-full-charge is the honest denominator for battery %.
- **Weaknesses / avoid**: snapshot UI is utilitarian (2005-era proportions, dense numbers); power-user paywall on the interesting data; no per-process energy correlation.
- **Sources**: https://www.coconut-flavour.com/coconutbattery/ ; https://formulae.brew.sh/cask/coconutbattery ; https://coconutbattery.macupdate.com/ ; https://mac.softpedia.com/get/Utilities/coconutBattery.shtml

### AlDente

- **Status**: macOS 12+, freemium (open core: repo at github.com/AppHouseKitchen; free tier plus Pro licence ~$19.99 per MacUpdate, unverified). Latest 1.39.4 (Sep 23, 2026). Version 1.39 (Sep 8, 2026) completely rebuilt charge control for macOS 27 after Apple changed charge-management internals. Actively maintained.
- **What it shows**: charge limit slider (20-100%); charge percentage; a stats view with hardware battery percentage; "Apps Using Significant Energy" widget with per-app energy scores and Quit buttons; schedule/calibration modes; sailing mode, discharge, heat protection (Pro features).
- **How it shows it**: menu-bar-centric: a popover Dashboard with a big charge-limit slider and a battery glyph; separate windows for stats and settings; the significant-energy widget is a compact ranked list of offending apps. Onboarding uses diagrams explaining why limiting charge preserves battery.
- **Ideas worth taking**: the "Apps Using Significant Energy" ranking is Energy-tab data made actionable (Quit button inline); framing a control as *care* ("your battery lasts longer") rather than tweaking wins mainstream users; watch how much friction macOS 27 charge-control changes caused - Apple's own charge management is absorbing this feature.
- **Weaknesses / avoid**: charge control is firmware/OS territory - fragile against macOS updates, as the 1.39 rebuild shows; mostly a control app, little monitoring.
- **Sources**: https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/releases ; https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/discussions/1814 ; https://aldente.macupdate.com/ ; https://formulae.brew.sh/cask/aldente

### macOS Battery settings and Low Power Mode

- **Status**: built into macOS (System Settings > Battery on laptops; Energy on desktops). Low Power Mode added macOS Monterey 12; High Power Mode on select MacBook Pros; Sequoia 15.1+ exposes Energy Modes in Control Center and Low Power Mode reduces fan noise and supports always-on use.
- **What it shows**: current level and alerts at top; Battery Health (Normal / Service Recommended plus maximum-capacity percentage and longevity toggles: Optimised Battery Charging, "Manage battery longevity" peak-capacity reduction); Energy Mode per power source (Low Power / Automatic / High Power); Options pane (hard-disk sleep, automatic graphics switching, power nap etc.); a battery level graph for the last 24h/10d plus screen-on time exists on the Battery pane.
- **How it shows it**: standard settings list UI: condition text, info buttons revealing detail panels; the status menu shows the active mode via the battery icon. Everything is configuration; the only visualisation is the small level history graph.
- **Ideas worth taking**: per-source mode matrix (battery vs adapter -> different policies) is a good mental model to expose; "Manage battery longevity" and Optimised Charging show Apple silently applies capacity ceilings - a monitor should surface *when charging is being held* so users do not read it as a fault; Low Power Mode's expanding scope (fan noise, always-on) makes it worth a first-class indicator.
- **Weaknesses / avoid**: health surfaced as a single vague verdict; no per-app energy accounting here at all (that lives in Activity Monitor's Energy tab); battery history graph is shallow.
- **Sources**: https://support.apple.com/guide/mac-help/change-battery-settings-mchlfc3b7879/mac ; https://support.apple.com/en-us/101613 ; https://support.apple.com/en-us/108376 ; https://support.apple.com/en-us/102588

### Windows powercfg /batteryreport

- **Status**: built into Windows 10/11, free, command line (`powercfg /batteryreport`, options `/output`, `/xml`, `/duration days`). Also `powercfg /energy` (efficiency problems), `/sleepstudy`, `/srumutil` (per-app energy estimation data from SRUM).
- **What it shows**: an HTML report covering: installed batteries (Design Capacity vs Full Charge Capacity, cycle count), recent usage (per-session battery states over ~3 days with per-entry capacity drain and charge), battery usage history graph, usage history, battery capacity history (design vs full-charge over time), and battery-life estimates (estimated vs actual).
- **How it shows it**: self-contained HTML: sectioned tables plus a battery-level-over-time chart; designed for clipboard-free diagnosis (run, double-click, read). Capacity history table shows the wear curve explicitly as two columns.
- **Ideas worth taking**: generate-and-inspect reports beat GUIs for shipping diagnostics to support; "design vs full charge capacity over time" is the definitive wear chart; `/srumutil`'s per-application energy ledger is the closest thing to per-app battery attribution on any desktop OS - worth copying as an export format.
- **Weaknesses / avoid**: static snapshot, no live view; ugly system-generated HTML; hidden behind cmd.
- **Sources**: https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options ; https://support.microsoft.com/en-us/windows/experience/power-battery/caring-for-your-battery-in-windows ; https://www.tomshardware.com/how-to/battery-health-report-windows

### TG Pro (Tunabelly Software)

- **Status**: macOS 10.14 through 27, Intel and Apple Silicon (M1-M6), paid one-time purchase (promotional $10 vs regular $20 per the Tunabelly blog, unverified; one licence covers up to three personal Macs; 14-day trial; free upgrade path from legacy Temperature Gauge). Latest 2.104 (Sep 28, 2026) adding macOS Golden Gate and M5 Max/Ultra Studio, M5 Pro/M6 mini support plus left/right Thunderbolt-port temperature sensors on M5 Pro/Max MacBook Pros.
- **What it shows**: every temperature sensor macOS exposes (CPU, GPU, SSD, Thunderbolt ports, palm rest, battery, ambient where present); per-fan RPM; diagnostics and logging; notification/email alerts on thresholds; historical sensor logging.
- **How it shows it**: menu-bar-first app: status item shows chosen sensor/fan values; dropdown lists all sensors grouped by region with current/max readings and per-fan controls; main window offers manual and "Auto Boost" fan control - rules binding a sensor threshold to a target fan speed; graph views of sensor history; colour-graded temperature cells.
- **Ideas worth taking**: treat the sensor catalogue as a browsable system inventory, grouped by physical region; rule-based automation (threshold -> fan %) keeps the tool useful unattended; auto-restore of fan state after Siri/dictation shows awareness of OS interactions.
- **Weaknesses / avoid**: fan control belongs to the system; doing it from a monitor risks fighting macOS thermal management - Coreography should chart sensors and fans, maybe warn, but not ship manual fan control in v1; UI is functionally dense.
- **Sources**: https://www.tunabellysoftware.com/tgpro/ ; https://www.tunabellysoftware.com/tgpro/releasenotes/ ; https://www.tunabellysoftware.com/tgupdate/

### Macs Fan Control (CrystalIdea)

- **Status**: macOS 10.13+ and Windows (Boot Camp). Free base version; Pro licence ~€16.95 adds unlimited custom fan presets and priority support (per MacGadget). Latest 1.5.22 (Oct 13, 2026 download page / Sep 2 release tag) with M5 Pro/M6 mini, M5 Max/Ultra Studio support and macOS 27 sensor fixes. Developed since ~2013; GitHub repo hosts releases/issues.
- **What it shows**: all temperature sensors and each fan's RPM; per-fan control: constant RPM or sensor-based (pick a sensor, set lower/upper temperature bounds); custom presets; Boot Camp support for Apple hardware running Windows.
- **How it shows it**: a two-column window - sensors left, fans right - rows of name/value pairs; fan rows have a control pop-up (Auto / constant RPM / sensor-based with temperature range); menu-bar icon can show any sensor or fan; minimal, functional, single window.
- **Ideas worth taking**: sensor-value pairing with the actuator next to it (temp reading beside the fan that cools it) is good spatial design for a thermal pane; sensor-driven fan curve simplified to two bound values is the simplest useful automation.
- **Weaknesses / avoid**: same control-vs-monitor caveat as TG Pro; plain list UI with no history charts; Pro-gated presets.
- **Sources**: https://crystalidea.com/macs-fan-control/download ; https://github.com/crystalidea/macs-fan-control/releases ; https://www.macgadget.de/News/2026/10/14/Macs-Fan-Control-erhaelt-Unterstuetzung-fuer-macOS-27-und-die-neuen-Macs

### FanControl (Windows, Rem0o)

- **Status**: Windows 10/11, free/donationware, closed source (release repo Rem0o/FanControl.Releases; built on LibreHardwareMonitorLib). Latest V283 (Oct 11, 2026); very active cadence (V275 Aug 25, V279 Sep 25, V282 Oct 4, V283 Oct 11). Installer, portable zip, service mode without login session.
- **What it shows**: all sensor sources (CPU, GPU, motherboard, drives via LHM) and every fan/pump as cards with live RPM and percentage; calibration routine measures each fan's real start/stop thresholds.
- **How it shows it**: card-based dashboard: one card per fan (with graph and controls), one per curve, one per sensor; drag to rearrange, hide what you do not need. Curve types: linear, graph (editable XY curve you draw), target, mix (combine two curves via max/sum/min/average), sync, flat. Advanced per-fan tuning: hysteresis, response time (up/down separately), start %, stop %, offset; "avoid points" that skip rattle-inducing speeds. Tray icons show chosen values; profiles save full layouts.
- **Ideas worth taking**: the editable graph curve editor is the gold standard for threshold-type config - any "alert when X > Y" mapping benefits from a drawn-curve editor; mixing sensors/curves with min/max/avg as composable functions is a small DSL worth copying for computed metrics (e.g. chart "max of E-core cluster temps"); calibration discovers real hardware limits rather than assuming.
- **Weaknesses / avoid**: visual complexity grows fast - a wall of cards needs ruthless defaults; Windows-only idiom (tray, service) does not translate directly.
- **Sources**: https://github.com/Rem0o/FanControl.Releases ; https://github.com/Rem0o/FanControl.Releases/releases/ ; https://www.softpedia.com/get/System/System-Info/FanControl-Rem0o.shtml

### macOS Login Items and Extensions settings

- **Status**: built into macOS (System Settings > General > Login Items & Extensions). Apple's consolidated UI for launch agents/daemons, login items, background items, and system extensions.
- **What it shows**: "Open at Login" list of apps; "Allow in the Background" list of helpers/daemons with per-item toggles (shows the owning app/developer name); Extensions section for network/content/system extensions.
- **How it shows it**: plain grouped lists of toggle rows. Information is thin: a name and a vendor, no path, no schedule, no "what does it do", no resource cost. The design answers "may this run" but not "what runs, when, and what does it cost".
- **Ideas worth taking**: users reach this panel asking "what is all this stuff and can I kill it" - Coreography's process view can answer the question the panel raises by joining each background item to live resource usage and its launchd plist details (path, program arguments, run-at-load, keep-alive, interval).
- **Weaknesses / avoid**: toggles are opaque (item names map badly to what users see running); no impact data; disabling is permanent-on/off, not "defer until idle".
- **Sources**: https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web

### KnockKnock and BlockBlock (Objective-See)

- **Status**: macOS 10.15+, free open source. KnockKnock 4.1.0 (current per product page); BlockBlock 2.5.2, built on Apple's Endpoint Security framework + Full Disk Access.
- **What they show**: KnockKnock: a one-shot scan enumerating persistently installed software across all known persistence locations, organised by category, with signing info and VirusTotal lookups; Apple-signed items filtered by default (third-party shown - legitimate but auditable). BlockBlock: continual monitoring that raises an alert whenever a new persistent component lands in a watched location.
- **How they show it**: KnockKnock uses a two-pane category browser: left table lists persistence categories (launch daemons/agents, login items, kernel extensions, cron, browser extensions...) with a short description and item count; right table lists the items of the selected category with signing status. BlockBlock surfaces a single rich alert: what was installed, where it persisted, who installed it (process ancestry), allow/block.
- **Ideas worth taking**: the category-by-category persistence inventory is the right enumeration model - the insight is that "startup items" is not one list but ~dozen distinct mechanisms; provenance ("which installer dropped this") is the question users actually ask; flag-not-block-by-default respects that most persistence is legitimate.
- **Weaknesses / avoid**: security-analyst audience; KnockKnock is a batch scan, not a live view; BlockBlock is an alerting agent. For Coreography, fold persistence metadata into the process/launchd views rather than building a scanner.
- **Sources**: https://objective-see.org/products/knockknock.html ; https://objective-see.org/products/blockblock.html ; https://github.com/objective-see/BlockBlock/

### Lingon / Lingon Pro (Peter Borg Apps)

- **Status**: macOS. Lingon Pro 10 (the new name for Lingon X): $23.99 one-time, macOS 14+, notarized; site licence $99.99; upgrade $16.99. Free sibling "Lingon 10" on the Mac App Store (completely free since 10.6, optional in-app donation; cannot run tasks as root). Active development across ~15 years; Lingon/Pro 10.3 added macOS Golden Gate compatibility.
- **What it shows**: every launchd job on the system, editable: program/arguments, schedule (calendar intervals, intervals, watch paths), keep-alive/restart conditions, environment, working directory, limits, run-as-user including root (Pro); per-job logs; notification on run; hotkey/Siri/Shortcuts triggers.
- **How it shows it**: split view: a table of all jobs (grouped by user/system domain) on the left, a structured editor on the right organised as When / Run / Advanced fields - translating launchd's plist vocabulary into labelled controls. A monitor function watches jobs in the background.
- **Ideas worth taking**: structured plist-as-form editing (When/Run schema) maps cleanly to how Coreography could present "why is this running": show the launchd identity (label, domain, program, trigger condition) directly in the process inspector.
- **Weaknesses / avoid**: it is an editor, not a monitor; exposing all launchd keys invites self-inflicted breakage; Coreography only needs the read side plus "reveal plist".
- **Sources**: https://www.peterborgapps.com/lingon/ ; https://apps.apple.com/us/app/lingon-10/id6742142873?mt=12 ; https://lingon-x.macupdate.com/

### Sysinternals Autoruns

- **Status**: Windows, free (Sysinternals/Microsoft). Autoruns v14.3 (the download page was updated Jun 17, 2026; version number per that release, feature notes unverified); also in the Sysinternals Suite and `autorunsc` CLI with CSV output.
- **What it shows**: the most comprehensive enumeration of auto-start locations on any OS: logon entries, Run/RunOnce keys, startup folders, Explorer shell extensions, BHOs, toolbars, Winlogon notifications, services, drivers, scheduled tasks, WMI subscriptions, codecs, print monitors, LSA providers, image hijacks - dozens of categories, including entries of other user accounts.
- **How it shows it**: tab strip per category over a flat list; rows show entry name, publisher (verified signer), description, image path, timestamp; checkboxes disable entries non-destructively. Killer options: "Hide Microsoft entries" and "Hide Windows entries" collapse the list to third-party only; Verify Signatures and VirusTotal integration flag unsigned/malicious entries; colour coding for missing files and unverified publishers.
- **Ideas worth taking**: "hide signed Microsoft/Apple entries" is the single most useful filter for any startup/process list - instantly reduces hundreds of system rows to the dozen the user can act on; non-destructive disable via checkbox; per-user scoping; CLI+GUI parity.
- **Weaknesses / avoid**: Windows Registry sprawl has no direct macOS analog - macOS's equivalent surface is smaller (launchd, login items, extensions) which means a Coreography "startup" view can be complete where Autoruns is merely encyclopedic.
- **Sources**: https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns ; https://learn.microsoft.com/en-us/sysinternals/downloads/

### Sloth (sveinbjorn)

- **Status**: macOS 11+, free open source (github.com/sveinbjornt/Sloth, universal binary, notarized). Latest 3.6 (Apr 22, 2026). Long-lived hobby project, low-frequency maintenance.
- **What it shows**: all open files, sockets, pipes, character devices and POSIX/Unix domain sockets in use by every running process - i.e. a GUI over `lsof`.
- **How it shows it**: a search field plus a flat/outline list: rows are process -> open item, with columns for name, kind (file/socket/pipe/device), and path/endpoint; filter by kind; Info panel gives file metadata (volume, mount point); contextual actions: reveal in Finder, show package contents, open with chosen app, kill process; refresh on demand; runs entirely off-the-shelf with no helper.
- **Ideas worth taking**: `lsof` data is exactly the "what is this process touching" answer; folding it into a per-process inspector (open files tab) is cheap to implement and beloved by power users; kind-filter chips (files/sockets/pipes) keep a 50k-row list navigable.
- **Weaknesses / avoid**: snapshot model - re-run `lsof` to refresh, nothing live; raw path strings without richer context; huge flat lists need the filter affordances to stay usable.
- **Sources**: https://www.sveinbjorn.org/sloth ; https://github.com/sveinbjornt/Sloth/releases/tag/3.6 ; https://github.com/sveinbjornt/Sloth/blob/master/CHANGES.md

### TaskExplorer (Objective-See)

- **Status**: macOS 14+, free open source. v3.1.0 (current); v3.0 (2026) was a near-complete rewrite on Apple's Endpoint Security framework, adding a built-in AI assistant (on-device via Apple Intelligence on macOS 26, or your own Claude/ChatGPT API key). TaskExplorer 2.1.0 remains for macOS 11-13.
- **What it shows**: every process live (ES-driven: processes appear at exec, vanish at exit, no password prompt); per-process code-signing status (Apple vs third-party vs ad-hoc/unsigned), loaded dylibs including dyld-shared-cache members, open files, network connections, VirusTotal flags (own API key), all exportable as JSON (`-explore`, `-scan` CLI).
- **How it shows it**: modern SwiftUI table: flat or tree process view; filter field with `#keyword` tokens (`#3rdparty`, `#adhoc`, `#listening`, `#root`, `#flagged`, `#everything` to also search dylibs/files/connections); inspector pane with full signing details; flagged/malicious items rendered in red; an assistant sidebar answers natural-language queries like "what's listening on the network?" against live data and can drive the UI.
- **Ideas worth taking**: the hashtag filter-token grammar is a power-user-friendly alternative to filter-builder UIs - `#listening`, `#root`, `#adhoc` reads like a query language users can learn; security-signing provenance in the process list (red-flag rendering) makes suspicious items scannable; ES-based "live" process enumeration is exactly the data source a real monitor should prefer over polling; JSON export + CLI as an API.
- **Weaknesses / avoid**: the AI assistant is a novelty beyond monitoring scope; ES + system extension entitlement is heavyweight to ship; VT lookups are external-dependency bait. Coreography should take the filter tokens and live process data, leave the chatbot.
- **Sources**: https://objective-see.org/products/taskexplorer.html ; https://github.com/objective-see/TaskExplorer ; https://github.com/objective-see/TaskExplorer/releases/

### ProcessMonitor and FileMonitor (Objective-See)

- **Status**: macOS, free open source, Endpoint Security-based event taps maintained by Objective-See (Patrick Wardle). Both are primarily command-line/streaming tools with optional file output; they log every process execution event or every file-system event respectively, in real time.
- **What they show**: ProcessMonitor: each exec/fork event with PID, path, full arguments, signing info, parent chain, user - a structured event stream (JSON-friendly). FileMonitor: each file create/modify/delete/rename event with the responsible process and path.
- **How they show it**: not visualisers: scrolling event logs. Their design lesson is the data model - a normalised, timestamped, provenance-rich event stream is the substrate a monitor's "recent activity" view or per-process timeline should sit on.
- **Ideas worth taking**: an "event timeline" mode (last N process/file events with ancestry) gives forensic power no static table has; capture provenance (parent chain + signing) with each event so rows are self-explanatory.
- **Weaknesses / avoid**: raw event firehoses overwhelm without aggregation; ES entitlements + FDA permissions are heavy for a consumer monitor - offer as an opt-in diagnostic mode, not default.
- **Sources**: https://objective-see.org/tools.html ; https://github.com/objective-see/ (ProcessMonitor, FileMonitor repos)

### Process Explorer handle and DLL search (Sysinternals)

- **Status**: Windows, free (Sysinternals/Microsoft), continuously maintained inside the Sysinternals suite.
- **What it shows**: per-process detail beyond Task Manager: loaded DLLs and their versions/paths, open handles (files, registry keys, mutexes, sections, events), handle counts, per-process threads with stacks, GPU columns, VirusTotal column, signing verification.
- **How it shows it**: split window: process tree top, lower pane switchable between DLL view and Handle view listing every open handle with type + name. The famous killer feature is Find > "Find Handle or DLL..." (Ctrl+F): type a filename and it lists every process holding it - the answer to "why can't I delete this file". Search-highlight colours mark virus-flagged or packed images; replace-taskmanager mode.
- **Ideas worth taking**: reverse lookup - "which process holds this file/port" - is the highest-value power feature in the whole category; Sloth gives it on macOS for files; Coreography should ship it for files AND sockets; lower-pane detail switcher (files vs libraries vs handles) is a compact pattern for the process inspector.
- **Weaknesses / avoid**: handle enumeration is expensive on big systems; modal dialog search is dated - make it a first-class filter instead.
- **Sources**: https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer ; https://learn.microsoft.com/en-us/sysinternals/downloads/

### Geekbench (Primate Labs)

- **Status**: cross-platform (macOS, Windows, Linux, iOS, Android), paid Pro licence plus a free tryout tier. Geekbench 7 is current (launched Jul 23, 2026, with new media workloads, a smarter multi-core benchmark and a refreshed GPU benchmark; current point version 7.1.0, unverified); the 6.x line ended with 6.7/6.7.1 (Apr 2026). Scores calibrate to fixed baselines: CPU baseline 2,500 = Ryzen 7 7700; GPU baseline 100,000 = RTX 4060 (unverified).
- **What it shows**: single-core and multi-core CPU scores plus GPU compute scores (OpenCL/Metal/Vulkan/CUDA), decomposed into workload subscores; the Geekbench Browser publishes percentile charts and per-device averages.
- **How it shows it**: deliberately minimal: a splash screen with one "Run Benchmark" button, a progress list of named workloads (text processing, image compression, machine learning...), then a result card of big numbers with a link to the browser comparison. No charts in-app beyond the workload checklist; the web browser supplies percentile bars.
- **Ideas worth taking**: benchmarks as a *one button, one number* experience - if Coreography ships a "stress/test" mode it should be equally frictionless and produce a comparable score users can quote; labelled workload phases give the run narrative structure; online percentile context is what makes a bare number meaningful.
- **Weaknesses / avoid**: scores without variance/spread invite misinterpretation; synthetic single numbers do not answer "is my Mac healthy *now*" - benchmarks are out of Coreography's monitoring scope, but its own live charts already show what a benchmark would confirm (clock throttling, power draw).
- **Sources**: https://www.geekbench.com/ ; https://www.primatelabs.com/blog/2026/07/geekbench-7/ ; https://www.primatelabs.com/blog/2026/04/geekbench-67/ ; https://browser.geekbench.com/

### Cinebench (Maxon)

- **Status**: Windows/macOS, free. Cinebench 2026 line (latest 2026.1.3, Jun 30, 2026, unverified); the 2026 line launched Dec 29, 2025 with a new Redshift-based scene (scores incomparable with 2024/R23). Supports Apple Silicon including M4 and M5, plus an SMT-vs-single-thread test. Minimum-runtime stress option for sustained-load testing (unverified).
- **What it shows**: CPU multi-core, CPU single-core, and GPU render scores; an arbitrary minimum-runtime mode turns it into a thermal stress test - reviewers use multi-run loops to expose throttling.
- **How it shows it**: a render view that fills tile-by-tile during the run (the workload is a real 3D render), plus a simple ranked score table comparing your result against a reference list of CPUs. Watching tiles appear is the visualisation: progress is spatial.
- **Ideas worth taking**: a real workload is more persuasive than synthetic gauges: for Coreography, "run the render, watch the power/temperature/frequency traces sag as it heats up" is the stress-test story - Coreography supplies the traces, the benchmark supplies the load; a minimum-runtime option exists precisely because single runs hide throttling.
- **Weaknesses / avoid**: single score, opaque conditions; its niche is silicon evaluation, not monitoring.
- **Sources**: https://www.maxon.net/en/cinebench ; https://support.maxon.net/hc/en-us/sections/10379181139484-Cinebench ; https://www.maxon.net/en/article/maxon-introduces-cinebench-2026 ; https://www.maxon.net/en/tech-info-cinebench

### Blackmagic Disk Speed Test

- **Status**: macOS, free on the Mac App Store (and bundled with Blackmagic software). Infrequently updated; still the default "how fast is this drive" check in the Mac world.
- **What it shows**: sequential write and read throughput in MB/s - one number each, meant to judge whether storage sustains video capture/playback rates.
- **How it shows it**: two large analogue-style speedometer dials (WRITE left, READ right) with sweeping needles and live numeric readouts that flutter during the test; below them a reference table ("Will it Work?" / "How Fast?") mapping measured rates to video formats/resolutions with checkmarks. Single window, one Start button, loops until stopped.
- **Ideas worth taking**: the format table is the smart part: translating MB/s into "will this capture ProRes 4K60" is unit translation into user meaning - the analogue dial is charming but leaves the true rate ambiguous (a documented complaint); a monitor's job is the "how fast" chart over time, not a capture certification.
- **Weaknesses / avoid**: fluttering needle gives no stable reading (subjective); sequential-only; writes real files so it cannot run on read-only volumes. Eclectic Light's critique applies to the whole category: single numbers without spread mislead.
- **Sources**: https://apps.apple.com/us/app/blackmagic-disk-speed-test/id425264550 ; https://eclecticlight.co/2022/05/06/interpreting-and-using-disk-performance-data/

### AmorphousDiskMark (Katsura Shareware)

- **Status**: macOS 10.9.5+, free open source. Version 4.0 (Jan 7, 2022); stable and essentially unchanged since (a CrystalDiskMark port to Mac).
- **What it shows**: sequential 1 MiB and random 4 KiB read/write at queue depths 1-1024, in MB/s and IOPS; configurable measurement size (16 MiB-64 GiB), iterations, interval; data pattern random or zero (to expose SSD compression tricks).
- **How it shows it**: a grid of eight result cells mirroring CrystalDiskMark: four test rows (SEQ1M QD8, SEQ1M QD1, RND4K QD64, RND4K QD1) x read/write, each filling with the median of 5 runs; plain form UI, zero chrome.
- **Ideas worth taking**: queue depth is the variable casual tools hide: QD1 vs QD64 random 4K is the difference between "feels snappy" and "spec sheet"; reporting median-of-5 is standard but hides variance - Coreography's live throughput graphs already answer the honest version of this question.
- **Weaknesses / avoid**: pure benchmark, no monitoring; dated modal UI; median-only reporting (documented pitfall - identical medians can hide wildly different result sequences).
- **Sources**: https://katsurashareware.com/amorphousdiskmark/ ; https://eclecticlight.co/2022/05/06/interpreting-and-using-disk-performance-data/ ; https://forums.macrumors.com/threads/disk-speed-testing-on-apple-silicon-amorphousdiskmark-blackmagic-etc-merged.2378298/

### asitop and stress utilities

- **Status**: `asitop` (github.com/tlkh/asitop): free open source, Python CLI; upstream inactive since ~2023 (exact date unverified) and the README still targets macOS Monterey, so newer chips are untested - community forks extend it (specific M5 patches unverified); `neoasitop` (github.com/op06072/neoasitop) is a Swift rewrite that needs no sudo, reading IOReport via SocPowerBuddy-style logic. Related: `mactop`, `powermetrics` itself, `stress`/`stress-ng` style load generators (e.g. `yes > /dev/null` loops, `stress-ng` via brew).
- **What it shows**: per-cluster CPU utilization and frequency (E-cluster vs P-cluster gauges), GPU utilization/frequency, ANE utilization (inferred from power), RAM/swap usage, CPU/GPU/package power draw in watts with peak and rolling-average readouts, memory bandwidth where powermetrics still exposes it, throttle status.
- **How it shows it**: `nvtop`-style terminal dashboard: ASCII/Unicode gauges per cluster, a braille-line chart of CPU and GPU power over time, watt numbers with colour; updates ~1s. `powermetrics` underneath requires root - the entire value is presentation of counters Apple already collects.
- **Ideas worth taking**: this is the closest existing thing to Coreography's core view: E/P cluster split, watts, and frequency are the Apple-Silicon-specific metrics Activity Monitor hides; power charts prove utilization numbers lie under thermal throttle - chart watts next to %, always; the fork scene shows maintenance risk when a tool depends on per-chip field parsing.
- **Weaknesses / avoid**: sudo requirement and per-chip brittle parsing; terminal UI ceiling. Coreography can take the metrics and leave the plumbing pain (Apple's powermetrics needs root; alternatives like neoasitop's IOReport path do not).
- **Sources**: https://github.com/tlkh/asitop ; https://tlkh.github.io/asitop/ ; https://github.com/op06072/neoasitop

### Console (Apple)

- **Status**: built into macOS (/System/Applications/Utilities/Console.app), free, maintained. Apple's front-end to the unified logging system (`os_log`, `log` command) and on-device diagnostic reports.
- **What it shows**: live streamed log messages (errors/faults by default; info and debug messages opt-in via the Action menu); Activities; a reports sidebar collecting Crash Reports, Spin Reports, Hang Reports, Diagnostics Usage, Log Reports (`.logarchive`), Mac Analytics Data; saved searches as Favorites.
- **How it shows it**: dense table of log lines (time, process, type, message) with a search bar supporting text, multiple tokens and Insert Pattern (email/URL/whitespace patterns); a Now mode auto-scrolls to tail; expandable rows plus an Info pane for full message detail; left sidebar for report categories. Keyboard shortcuts: Cmd-K clear, Shift-Cmd-R reload, Shift-Cmd-N jump to latest, Option-Cmd-F search.
- **Ideas worth taking**: saved-search Favorites (All Messages, Errors and Faults) prove pre-cooked filters are how normal users survive log volume; "Now" tail mode is the correct default for live views; per-process filtering is the real want - Coreography should let you jump from a process row to its logs.
- **Weaknesses / avoid**: firehose density makes it an analyst tool; reports list is passive (no grouping, no trend, no "this app crashed 4x this week"); crash `.ips` JSON is opaque to non-developers.
- **Sources**: https://support.apple.com/guide/console/welcome/mac ; https://support.apple.com/guide/console/customize-the-log-window-cnsl35710/mac ; https://support.apple.com/guide/console/keyboard-shortcuts-cnsl99a72ebe/mac

### EtreCheck

- **Status**: macOS, freemium by Etresoft. EtreCheckPro 6.8.x (Jul 2026; supports macOS 26/27; exact build 6.8.16 unverified); EtreCheckPro 7 announced for later this year with a new UI, requiring macOS 13+ (unverified). Free download; Power User package $19.99 IAP unlocks deeper detail links and extras.
- **What it shows**: a structured system audit: detects 70+ specific problems (adware, orphaned launch agents, failing drives, unsigned system modifications, low RAM, kernel panics history...), grouped findings with severity, hardware info, software inventory, configuration dumps - all exportable as an anonymized text report designed to be pasted into Apple Support Communities without leaking personal data.
- **How it shows it**: a run produces a long sectioned report (top-level severity banner, then sections: Problem List, Hardware Information, System Software, Startup/Background items, Security, Processes...); major problems link to the relevant report location; the anonymized plain-text format is its signature feature - designed for forum triage.
- **Ideas worth taking**: "health audit as shareable artifact" - the anonymized copy-paste report is a UX triumph for support workflows; severity-tiered findings (major/minor) beats flat lists; the notion that a monitor should also *assess* (this is wrong, fix it here) rather than only display.
- **Weaknesses / avoid**: batch-audit model, not live monitoring; report walls are long reads; problem detection heuristics drift as macOS changes (hence its own v7 rewrite).
- **Sources**: https://etrecheck.com/en/details.html ; https://www.etrecheck.com/en/features.html ; https://formulae.brew.sh/cask/etrecheckpro

### Crash report viewers

- **Status**: crash/spin/hang reports are stored as `.ips` JSON bundles in `~/Library/Logs/DiagnosticReports` (user) and `/Library/Logs/DiagnosticReports` (system); macOS purges oldest automatically. Viewers: Console.app (Crash Reports sidebar), Xcode's "Devices and Simulators" for device logs, and the `.ips` files can be opened as JSON in any text editor.
- **What they show**: per-crash: exception type/codes, crashed thread, backtrace with symbolication state, binary images list, termination reason, plus registration metadata (uptime, hardware model, OS build); "Full Report" section is the raw JSON with code-signing and CPU details.
- **How they show it**: Console renders the report in a readable pane and links "Reveal in Finder"; the crash-alert dialog after a crash offers Report/Reopen. Third-party wrappers exist but nothing has displaced Console - the .ips JSON format is machine-readable by design.
- **Ideas worth taking**: crash *frequency over time* is a signal no built-in tool charts: "Safari Web Content crashed 9 times this week" belongs in a process detail timeline; grouping reports by process + termination reason converts a pile of JSON into a health signal; keep raw reports one click away (Reveal in Finder) for filing bugs.
- **Weaknesses / avoid**: raw JSON reading is a developer skill; auto-purging silently erases history; symbolication of third-party frames needs dSYMs, so a monitor can only ever aggregate, not fully explain.
- **Sources**: https://support.apple.com/guide/console/welcome/mac ; https://appleinsider.com/inside/macos/tips/how-to-understand-macos-finder-crash-report-alerts

## Cross-cutting patterns

- Linked views beat lone views: WinDirStat's tree/extension/treemap, Little Snitch's list/chart/map, NetSpot's floor plan/data points all share one selection state. Selecting in one surface filters the others - this is the difference between "several charts" and "a monitor".
- The ranked list is the workhorse: OmniDiskSweeper's descending column browser, WizTree's top-1000 files, AlDente's "Apps Using Significant Energy", Autoruns' third-party-only view. For every "what is eating X" question, the honest UI is a sorted table; the chart is decoration on top of it.
- One spatial metaphor per domain: sunburst or treemap for disk trees, occupancy plot for RF spectrum, floor-plan heatmap for Wi-Fi, geo map for Internet endpoints, nested bars for capacity-versus-capacity (battery wear). The metaphor is what makes each tool memorable; the table is what makes it useful.
- Colour as a second data channel: GrandPerspective colours treemap cells by mtime/type/depth independently of size; WiFi Explorer's colouring rules flag chosen networks; TaskExplorer renders flagged items red; WinDirStat's per-extension palette shows how *not* to do it (confetti noise). Colour should encode provenance, age, or flag state - not a random category.
- Identity at the decision moment: LuLu and BlockBlock alerts show signing status, path and ancestry inline when they ask for a verdict. In a monitor, the same data belongs in the inspector: provenance is what turns "a process" into "a process I trust".
- Two presences: every serious tool ships a dense main window plus a reduced presence - menu-bar item (TG Pro, coconutBattery, TripMode), floating mini graph (GlassWire), detachable monitor window (TripMode). The small presence is a pointer back into the rich view, never a summary replacement.
- Context-aware automation: TripMode activates profiles per Wi-Fi network, FanControl maps sensors to curves, TG Pro binds thresholds to fans. Users want the machine to switch modes by context; a monitor can adopt this as per-context layouts or alert profiles.
- CLI and export parity: autorunsc CSV, WizTree CSV, networkQuality `-c` JSON, TaskExplorer JSON export, powercfg HTML reports - power users script and paste. Any data Coreography can show should be exportable in a documented format.
- Apple absorption pressure: Storage pane vs DaisyDisk, Login Items & Extensions vs KnockKnock/Lingon, built-in charge management vs AlDente, Battery Health vs coconutBattery, networkQuality vs speed-test apps. Features Apple ships are always the shallow version: the durable gap is history, cross-joins, and power depth.
- Permission gravity: Endpoint Security, Full Disk Access, system extensions, sudo-for-powermetrics - the deeper the telemetry, the heavier the entitlement story. The tools that won (TaskExplorer on ES, neoasitop's IOReport path) found the Apple-blessed route rather than kexts.

## Implications for Coreography

Concrete, opinionated recommendations:

- **Disk pane**: headline = macOS-Storage-style stacked capacity bar (one glance) + ranked largest-files/largest-folders list (OmniDiskSweeper's answer to "what is big") + a treemap or sunburst drill-down for exploration (GrandPerspective's colour-by-mtime as an option). Add a "hidden space" breakdown: APFS snapshots, purgeable space, System Data - the thing Apple's pane cannot explain. Read-only: no deletion in v1.
- **Network pane**: per-process connection list with regroupable hierarchy (Process > Domain > Server like Little Snitch), a traffic chart that acts as a time selector for the whole pane (GlassWire's interaction), per-app cumulative byte counters per day/week (TripMode's gap-filling feature), listening sockets as a first-class tab (Netiquette), and an on-demand `networkQuality` run to surface RPM/responsiveness history. Geo map: nice-to-have, not v1.
- **Power pane**: coconutBattery's nested capacity bars (charge / max / design) + persisted wear history (capacity snapshots over months) + live watts chart next to CPU/GPU utilization (asitop's lesson: % lies under throttle, watts do not) + Energy Mode / Low Power Mode / charge-held-by-Apple as visible state. Per-app energy leaderboard with a Quit affordance (AlDente's widget pattern).
- **Thermal pane**: sensor inventory grouped by physical region (TG Pro), each fan beside the sensors it cools (Macs Fan Control's pairing), threshold *alerts* only - no fan control. Fight Apple's thermal manager and you lose; chart it and you win.
- **Process inspector**: tabs for Open Files and Open Sockets (Sloth's lsof data, live where possible), launchd identity panel (label, plist path, run conditions - Lingon's read side), signing provenance, and an event/crash timeline (ProcessMonitor-style stream aggregated per process). Global reverse lookup: "which process holds this path or port" (Process Explorer's Ctrl+F, done as a first-class filter).
- **Startup/background view**: KnockKnock's category inventory (launchd domains, login items, extensions) joined to live resource cost - the join is the product; Apple's toggles list cannot show it. Include "Hide Apple-signed" (Autoruns' best feature).
- **Filtering**: adopt TaskExplorer's `#token` grammar (`#listening`, `#root`, `#3rdparty`, `#adhoc`) plus saved searches (Console's Favorites). Skip the AI assistant - scope, not lack of ability.
- **History architecture**: budget retention from day one: rolling per-second data for hours, downsampled for days, monthly snapshots for wear metrics (Little Snitch's one-year bar is the bar to beat).
- **Deliberately out of scope**: firewall rules, connection blocking, fan speed control, charge limits, file deletion, benchmark scores, VirusTotal lookups, geo-IP licensing. These are the control/enforcement layers that make the other tools heavyweight - observing them (e.g. showing that a connection was blocked by the system) is fine; enforcing is not.
- **Benchmarks**: do not build a benchmark. Offer an exportable "stress session" marker on the live charts (start/stop annotation like GlassWire's time-scoped view) so users can correlate a Cinebench run with their traces.

## Sources

- [DaisyDisk home](https://daisydiskapp.com/) · [DaisyDisk release notes](https://daisydiskapp.com/releases/) · [DaisyDisk pricing](https://daisydiskapp.com/support/pricing/)
- [GrandPerspective](https://grandperspectiv.sourceforge.net/) · [GrandPerspective files](https://sourceforge.net/projects/grandperspectiv/files/grandperspective/)
- [OmniDiskSweeper (Omni Labs)](https://www.omnigroup.com/more/) · [OmniDiskSweeper Wikipedia](https://en.wikipedia.org/wiki/OmniDiskSweeper) · [Omni file index](https://files.omnigroup.com/software/macOS/11/)
- [Apple: Free up storage space on Mac](https://support.apple.com/en-us/102624)
- [WinDirStat releases](https://github.com/windirstat/windirstat/releases) · [WinDirStat changelog](https://github.com/windirstat/windirstat/blob/master/CHANGELOG.md) · [WinDirStat blog](https://blog.windirstat.net/category/release/)
- [WizTree](https://www.diskanalyzer.com/) · [WizTree download](https://www.diskanalyzer.com/download) · [WizTree what's new](https://www.diskanalyzer.com/whats-new)
- [SpaceSniffer](https://www.uderzo.it/main_products/space_sniffer/index.html) · [SpaceSniffer Wikipedia](https://en.wikipedia.org/wiki/SpaceSniffer)
- [Little Snitch](https://www.obdev.at/products/littlesnitch/index-en.html) · [What's new in LS6](https://www.obdev.at/products/littlesnitch/whatsnew.html) · [Network Monitor help](https://help.obdev.at/littlesnitch6/lsm-overview) · [Map help](https://help.obdev.at/littlesnitch6/lsm-map) · [Order page](https://www.obdev.at/products/littlesnitch/order.html)
- [LuLu product page](https://objective-see.org/products/lulu) · [LuLu releases](https://github.com/objective-see/LuLu/releases)
- [GlassWire](https://www.glasswire.com/) · [GlassWire features](https://www.glasswire.com/features/) · [GlassWire changelog](https://www.glasswire.com/changes/)
- [Private Eye](https://radiosilenceapp.com/private-eye/) · [Radio Silence](https://radiosilenceapp.com/) · [private-eye cask](https://github.com/Homebrew/homebrew-cask/blob/80121d533f3b5f5410f2bd60f008d615031a9c9c/Casks/p/private-eye.rb)
- [TripMode](https://tripmode.ch/) · [TripMode buy](https://tripmode.ch/buy/) · [TripMode 3 press release (PDF)](https://tripmode-updates.ch/download-press/TripMode_3_Press_Release-2020.11.03.pdf) · [Macworld TripMode 3 review](https://www.macworld.com/article/344699/tripmode-3-review.html) · [TripMode on the App Store](https://apps.apple.com/us/app/tripmode/id1513400665?mt=12)
- [Netiquette releases](https://github.com/objective-see/Netiquette/releases) · [Netiquette repo](https://github.com/objective-see/Netiquette) · [Objective-See tools](https://objective-see.org/tools.html)
- [WiFi Explorer on the App Store](https://apps.apple.com/us/app/wifi-explorer-scanner/id494803304?mt=12) · [WiFi Explorer Pro 3](https://www.intuitibits.com/products/wifiexplorerpro3/) · [wifi-explorer cask](https://formulae.brew.sh/cask/wifi-explorer)
- [NetSpot](https://www.netspotapp.com/) · [NetSpot iMore review](https://www.imore.com/netspot) · [NetSpot upgrade matrix](https://www.netspotapp.com/upgrade-netspot-win.html) · [Apple: Wireless Diagnostics guide](https://support.apple.com/guide/wireless-diagnostics/welcome/mac)
- [networkQuality man page](https://keith.github.io/xcode-man-pages/networkQuality.8.html) · [TidBITS on networkQuality](https://tidbits.com/2022/04/22/use-apples-networkquality-tool-to-test-internet-responsiveness/) · [WWDC21: Reduce network delays](https://developer.apple.com/videos/play/wwdc2021/10239/) · [Apple: test responsiveness (HT212313)](https://support.apple.com/en-us/HT212313)
- [coconutBattery](https://www.coconut-flavour.com/coconutbattery/) · [coconutbattery cask](https://formulae.brew.sh/cask/coconutbattery) · [coconutBattery on MacUpdate](https://coconutbattery.macupdate.com/) · [Softpedia listing](https://mac.softpedia.com/get/Utilities/coconutBattery.shtml)
- [AlDente releases](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/releases) · [AlDente 1.39 discussion](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/discussions/1814) · [AlDente on MacUpdate](https://aldente.macupdate.com/) · [aldente cask](https://formulae.brew.sh/cask/aldente)
- [Apple: Battery settings](https://support.apple.com/guide/mac-help/change-battery-settings-mchlfc3b7879/mac) · [Apple: Power Modes](https://support.apple.com/en-us/101613) · [Apple: Service Recommended](https://support.apple.com/en-us/108376) · [Apple: battery health management](https://support.apple.com/en-us/102588)
- [powercfg options](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options) · [Microsoft: caring for your battery](https://support.microsoft.com/en-us/windows/experience/power-battery/caring-for-your-battery-in-windows) · [Tom's Hardware battery report guide](https://www.tomshardware.com/how-to/battery-health-report-windows)
- [TG Pro](https://www.tunabellysoftware.com/tgpro/) · [TG Pro release notes](https://www.tunabellysoftware.com/tgpro/releasenotes/) · [Temperature Gauge upgrade](https://www.tunabellysoftware.com/tgupdate/) · [Tunabelly blog (M2 Ultra, $10 pricing)](https://www.tunabellysoftware.com/blog/files/macpro-m2-ultra-plus-new-macs-temperatures-and-fan-control.html)
- [Macs Fan Control download](https://crystalidea.com/macs-fan-control/download) · [Macs Fan Control releases](https://github.com/crystalidea/macs-fan-control/releases) · [MacGadget on 1.5.22](https://www.macgadget.de/News/2026/10/14/Macs-Fan-Control-erhaelt-Unterstuetzung-fuer-macOS-27-und-die-neuen-Macs)
- [FanControl releases repo](https://github.com/Rem0o/FanControl.Releases) · [FanControl releases](https://github.com/Rem0o/FanControl.Releases/releases/) · [FanControl on Softpedia](https://www.softpedia.com/get/System/System-Info/FanControl-Rem0o.shtml)
- [Apple: manage login items (deployment)](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)
- [KnockKnock](https://objective-see.org/products/knockknock.html) · [BlockBlock](https://objective-see.org/products/blockblock.html) · [BlockBlock repo](https://github.com/objective-see/BlockBlock/)
- [Lingon](https://www.peterborgapps.com/lingon/) · [Lingon 10 on the App Store](https://apps.apple.com/us/app/lingon-10/id6742142873?mt=12) · [Lingon Pro on MacUpdate](https://lingon-x.macupdate.com/)
- [Autoruns](https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns) · [Sysinternals downloads](https://learn.microsoft.com/en-us/sysinternals/downloads/) · [Process Explorer](https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer)
- [Sloth](https://www.sveinbjorn.org/sloth) · [Sloth 3.6](https://github.com/sveinbjornt/Sloth/releases/tag/3.6) · [Sloth changes](https://github.com/sveinbjornt/Sloth/blob/master/CHANGES.md)
- [TaskExplorer](https://objective-see.org/products/taskexplorer.html) · [TaskExplorer repo](https://github.com/objective-see/TaskExplorer) · [TaskExplorer releases](https://github.com/objective-see/TaskExplorer/releases/)
- [Geekbench home](https://www.geekbench.com/) · [Geekbench 7 announcement](https://www.primatelabs.com/blog/2026/07/geekbench-7/) · [Geekbench 6.7 announcement](https://www.primatelabs.com/blog/2026/04/geekbench-67/) · [Geekbench Browser](https://browser.geekbench.com/)
- [Cinebench](https://www.maxon.net/en/cinebench) · [Cinebench release notes](https://support.maxon.net/hc/en-us/sections/10379181139484-Cinebench) · [Cinebench 2026 announcement](https://www.maxon.net/en/article/maxon-introduces-cinebench-2026) · [Cinebench tech info](https://www.maxon.net/en/tech-info-cinebench)
- [Blackmagic Disk Speed Test](https://apps.apple.com/us/app/blackmagic-disk-speed-test/id425264550) · [Eclectic Light on disk benchmarks](https://eclecticlight.co/2022/05/06/interpreting-and-using-disk-performance-data/)
- [AmorphousDiskMark](https://katsurashareware.com/amorphousdiskmark/) · [MacRumors disk speed thread](https://forums.macrumors.com/threads/disk-speed-testing-on-apple-silicon-amorphousdiskmark-blackmagic-etc-merged.2378298/)
- [asitop](https://github.com/tlkh/asitop) · [asitop docs](https://tlkh.github.io/asitop/) · [neoasitop](https://github.com/op06072/neoasitop)
- [Console User Guide](https://support.apple.com/guide/console/welcome/mac) · [Customize the log window](https://support.apple.com/guide/console/customize-the-log-window-cnsl35710/mac) · [Console shortcuts](https://support.apple.com/guide/console/keyboard-shortcuts-cnsl99a72ebe/mac)
- [EtreCheck details](https://etrecheck.com/en/details.html) · [EtreCheck features](https://www.etrecheck.com/en/features.html) · [etrecheckpro cask](https://formulae.brew.sh/cask/etrecheckpro)
- [AppleInsider on crash reports](https://appleinsider.com/inside/macos/tips/how-to-understand-macos-finder-crash-report-alerts)

## Verification log

Fact-checked 2026-10-17 by fetching ~40 cited or official pages (vendor release notes, order pages, GitHub releases, Apple and Microsoft docs) and checking every concrete version, date, price, platform, feature and API claim (~150 individual claims across all tool sections).

Verified correct as written (selected): DaisyDisk 4.34.2 (Jul 10, 2026), $9.99 lifetime, 10.13+, 5 Macs; GrandPerspective 3.8.1 (Sep 13, 2026), macOS 14+ deployment target, $2.99 MAS, GPL, Erwin Bonsma, 20-year milestone; OmniDiskSweeper 1.16 (Sep 12, 2025), freeware since 2009, first released 2001 as shareware; WinDirStat 2.9.3 (Oct 11, 2026); WizTree 4.33 + WizTreeMac 1.00 (Sep 16, 2026, macOS 12+ universal), 46x claim, MFT reading; SpaceSniffer 2.2.0.27 (Mar 25, 2026); Little Snitch 6 feature set, ~20 years, 12-month chart; LuLu 4.5.1 (Aug 5, 2026) and 4.5.0/4.4.0 notes; GlassWire 3.11.1164 (Oct 6, 2026) incl. bulk actions in 3.11; Private Eye discontinued notice and Radio Silence pointer; TripMode feature set incl. Live Monitor, reports, scheduler, Golden Gate compatibility; Netiquette 2.3.0 (Oct 5, 2026) and 2.0.0 (May 25) notes; WiFi Explorer Pro 3 requirements/trial; networkQuality flags and JSON fields per man page; coconutBattery 4.4 (Sep 9, 2026) with macOS/iOS 27 support, Plus feature matrix; AlDente 1.39 (Sep 8, 2026) macOS 27 charge-control rebuild and energy-widget redesign; Apple Power Modes article (Sequoia 15.1 Control Center Energy Modes, LPM fan-noise/always-on scope, High Power Mode models); Apple storage article incl. System Data wording; TG Pro 2.104 content (Golden Gate, M5/M6 models, TB-port sensors) and 10.14-27 span; Macs Fan Control 1.5.22 (GitHub tag Sep 2, download page updated Oct 13, 2026), macOS 10.13+; FanControl V283 (Oct 11, 2026), V275/V279/V282 dates, LibreHardwareMonitorLib base; KnockKnock 4.1.0 (10.15+, Apple-signed filtered by default, VT lookups); BlockBlock 2.5.2 on Endpoint Security + Full Disk Access; Lingon Pro 10 pricing ($23.99/$16.99/$99.99, macOS 14+); Sloth 3.6 (Apr 22, 2026), macOS 11+, notarized; TaskExplorer 3.1.0 features (ES live enumeration, #keyword tokens incl. #everything, JSON/-explore/-scan, 2.1.0 for macOS 11-13); Geekbench 7 exists and is current; Cinebench 2026 Redshift basis, Dec 29, 2025 launch, score break with 2024, SMT test, M4/M5 support; AmorphousDiskMark 4.0 (Jan 7, 2022, macOS 10.9.5+, open source, QD/size/pattern options); asitop sudo/powermetrics mechanics; EtreCheck 70+ problems, anonymised report, $19.99 Power User IAP.

Corrections made (old -> new):

- Summary: TG Pro/Macs Fan Control Golden Gate fixes "Oct 2026" -> Sep 2026 (2.104 on Sep 28, 1.5.22 tagged Sep 2); "one year" Little Snitch history -> "up to twelve months" (obdev wording); coconutBattery "monthly" snapshots -> "over time"; TaskExplorer "SwiftUI" -> "modern UI" (not stated by vendor).
- DaisyDisk: "site claims Apple Silicon, Retina and macOS Golden Gate support" -> verified Tahoe/Liquid Glass release notes only; Golden Gate support claim removed.
- WizTree: "top 1000 largest files" -> file view/search; donationware wording -> free for personal use with Supporter Code USD 25-500 / Enterprise USD 750; dead/wrong link https://wiztree.world/whats-new/ -> https://www.diskanalyzer.com/whats-new ; download link normalised (trailing-slash 404).
- Little Snitch: "$59" -> EUR 59 (order page); wrong order URL geolocation.obdev.at -> www.obdev.at/products/littlesnitch/order.html; whatsnew URL given www prefix.
- LuLu: removed unverified "GPLv3" licence label and "~12.8k stars" figure; added verified 4.4.0 Golden Gate compatibility note.
- GlassWire: outdated tab names (Graph/Firewall/Usage/Things/Alerts) -> current Traffic Monitor / GlassWire Protect / Log Analysis / Network Scanner, Hardware Resources added in 3.8 (Feb 2026); chart interaction described as click-drag range select.
- Private Eye: "last supported 10.7-10.9 era" -> 10.7-10.11 per product page; Homebrew deprecation/disable dates marked unverified; Radio Silence price $9 added.
- TripMode: removed false "direct licence sales were sunset" (developer still sells a License version); Setapp "$5.99/mo app-only tier" removed (unverified); MAS $11.99/yr marked unverified.
- WiFi Explorer: "Pro adds 850+ selectable fields" -> more than 550 fields (vendor page); consumer "3.6.10" and Pro "3.10 (Jun 2026)" version numbers marked unverified; "macOS 13+" -> macOS 13.5+; passive scan Intel-only added; consumer price $19.99 added.
- NetSpot: current-edition tiers (Free/PRO/Enterprise) replace the dated Home/PRO/Enterprise price table, which is now attributed to iMore; "NetSpot 4 line on Android" -> the Android app (version claim dropped); "~23 visualisation types" marked unverified.
- coconutBattery: "4.4.0 build 265 (Sep 9-16) / 4.4.1 beta" -> 4.4 (Sep 9, 2026); Plus price marked unverified; "monthly entries" dropped; manufacture-date caveat added (randomised serials).
- AlDente: 1.39.4 "Sep 24" -> Sep 23, 2026; 1.39 date Sep 8 added; Pro price marked unverified.
- TG Pro: 2.104 "Oct 1" -> Sep 28, 2026; $10 promotional pricing marked unverified; Thunderbolt sensor support scoped to M5 Pro/Max MacBook Pros.
- Autoruns: unverifiable "aligns autorunsc CLI with GUI incl. packaged apps; v14.2 added packaged-app support" feature notes dropped, page update date Jun 17, 2026 kept; "Sysinternals Suite MSIX bundle" wording simplified.
- Lingon X -> retitled "Lingon / Lingon Pro"; MAS Lingon 10 "donationware: optional $19.99 Super Supporter IAP" -> completely free since 10.6 with optional donation ($19.99 figure unverifiable); 10.3 Golden Gate compatibility noted.
- Sloth: unverified "~1.3 MB" size dropped.
- TaskExplorer: "local Ollama" assistant option removed (only Apple Intelligence, Claude, ChatGPT per product page); v3.0 "Sep 2026" and v3.1.0 "Oct 3, 2026" dates -> 2026/current (unverified).
- Process Explorer: unverifiable "Suite build Oct 15, 2026" dropped.
- Geekbench: 7.1.0-as-current and "6.7.1 (Apr 28, 2026)" -> Geekbench 7 launched Jul 23, 2026 (verified), 6.x ended at 6.7 (Apr 2026), point versions unverified; baseline calibrations marked unverified; dead/unverifiable links (primatelabs.com/release/geekbench6/, browser mac-benchmarks path) -> verified blog and browser URLs.
- Cinebench: "M1-M5 incl. Metal RT ray tracing on M3+" -> Apple Silicon incl. M4 and M5 (per Maxon announcement; Metal RT detail unverified); 2026.1.3 and minimum-runtime option marked unverified.
- asitop: "inactive since ~Jan 2023" -> since ~2023 (exact date unverified); "does not handle M5's renamed clusters, forks patch M5" -> README still targets Monterey, forks extend to newer chips (specific M5 patches unverified); unverified ProducerGuy/asitop fork link removed from section and Sources.
- EtreCheck: "6.8.16" and Pro 7 details marked unverified; "~$19.9x" -> $19.99 (verified).
- Crash viewers: ".ips format (since macOS 12)" version claim removed (unverified).
- ProcessMonitor: "Endpoint Security-based" en dash normalised to hyphen (writing rules).
- Added missing scope item: Wireless Diagnostics (built-in) section, with the Apple Wireless Diagnostics guide as source.

Remains unverified (flagged in text or listed here): Autoruns v14.2/v14.3 feature notes; Little Snitch GeoIP database vendors and Atlantic-Ocean placeholder detail (help pages cited but not re-fetched); Speedtest macOS menu-bar app specifics; WiFi Explorer consumer/Pro point versions and 320 MHz channel-width claim; NetSpot visualisation-type count and current licence prices; coconutBattery Plus price; AlDente Pro price; TG Pro $10 promo price and trial length; Macs Fan Control Pro EUR 16.95 (per MacGadget) and ~2013 origin; Geekbench 7.1.0/6.7.1 point versions and score baselines; Cinebench 2026.1.3 and minimum-runtime option; TaskExplorer 3.1.0 release date; EtreCheckPro 6.8.16 and Pro 7 announcement; asitop last-commit date and fork activity; Homebrew private-eye deprecation dates; Apple support articles 108376 and 102588 (not re-fetched); Console keyboard shortcuts; WinDirStat "dormant 2005-2024, relaunched with 2.0 in Oct 2024" history framing (release list confirms 2.x cadence, not the 2005-2024 gap); powercfg flag details (standard Microsoft documentation, page not re-fetched).
