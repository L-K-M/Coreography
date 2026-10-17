# macOS data sources: processes, memory, disk, network, battery, privileges (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

## Summary

- The kernel divides per-process introspection by uid. From `xnu/bsd/kern/proc_info.c`: `proc_pidinfo` flavors `PROC_PIDT_SHORTBSDINFO`, `PROC_PIDUNIQIDENTIFIERINFO`, `PROC_PIDPATHINFO`, `PROC_PIDCOALITIONINFO` and `PROC_PIDPLATFORMINFO` need no same-user check; `PROC_PIDTASKALLINFO`, `PROC_PIDTASKINFO`, `PROC_PIDLISTFDS`, `PROC_PIDVNODEPATHINFO` and `proc_pid_rusage` (all flavors) return `EPERM` for processes owned by other users unless the caller is root.
- `proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, ...)` is the single most valuable per-process call: V6 carries physical footprint, the process's own energy in nanojoules (`ri_energy_nj`, `ri_penergy_nj` for P-cores; filled only on kernels built with pervasive energy accounting) and billed/serviced energy (work done on its behalf by others, or by it for others), disk bytes read/written, logical writes, package-idle and interrupt wakeups, instructions, cycles, per-QoS CPU times, and lifetime/interval max footprint. All are cumulative counters; rates come from differencing.
- `task_for_pid` is not a viable data path for a shipping app: it is gated by `taskgated`, needs root, the procmod group, or Apple-private entitlements (`com.apple.system-task-ports.read` is what lets Apple's `top` use `processor_set_tasks_with_flavor`). Third parties should design around it. `kqueue` `NOTE_EXIT` is friendlier: watching any pid's exit needs no privilege; only the `NOTE_EXITSTATUS`/`NOTE_EXIT_DETAIL` variants are gated by "can send SIGKILL" (same uid, parent, or root).
- Activity Monitor's memory categories are derived, not raw kernel counters. Stats' formula is the practical reference: `used = active + inactive + speculative + wired + compressed - purgeable - external`, `app = used - wired - compressed`, `cached = purgeable + external`. Pressure comes from `kern.memorystatus_vm_pressure_level` (2 = warning, 4 = critical) or `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`.
- Per-process network has no public counter API. Every third-party app either parses `nettop` (Stats: `nettop -P -L 1 -n`), or speaks to the private `NetworkStatistics.framework` / `PF_SYSTEM` `com.apple.network.statistics` socket that `nettop` uses (Activity Monitor loaded it historically; its current path is via `sysmond` and unverified).
- A full-featured monitor does not fit the Mac App Store: the App Sandbox denies listing pids and reading rusage or file descriptors of other processes (it still allows `proc_pidinfo` on them), denies IOKit user clients such as the SMC without a temporary exception, and blocks force-quitting other apps. iStat Menus does sell a Mac App Store edition, which needs a separately downloaded helper for temperatures and fans and cannot control fan speed. TMOG publicly cites this as its reason for leaving the MAS. Developer ID + notarization is the proven channel (Stats, iStat Menus, TMOG).
- Privileged work belongs in an optional `SMAppService.daemon` + XPC helper with audit-token code-sign validation. Stats and iStat Menus both follow this pattern; iStat Menus' helper history (two privilege-escalation CVEs) shows the cost of skipping it.
- macOS 26 changed the environment around monitors: a new System Settings > Menu Bar allow-list hides menu bar items by default, the "would like to access data from other apps" prompt (macOS 15+) can fire when the app or a child process touches other apps' containers, as reported against Stats in 2024, and `task_for_pid` enforcement via AMFI reportedly tightened. macOS 27 already forced a battery-temperature fix in Stats v3.0.21.
- Expect partial data and design for it: other users' and protected processes will yield pid/name/uid/state/path but no memory, CPU time, disk I/O or energy. Apple's `top` shows what full coverage looks like only because it ships with Apple-only entitlements.

## Tools

### xnu process APIs: sysctl KERN_PROC, libproc, rusage

- **Status**: Public syscall surface, stable since OS X 10.5-10.9 (`libproc.h`: "private interfaces... subject to change" but unchanged for years in practice). `RUSAGE_INFO_CURRENT` is `RUSAGE_INFO_V6` on current xnu. Source: `bsd/sys/proc_info.h`, `bsd/sys/resource.h`, `libsyscall/wrappers/libproc/libproc.h`, `bsd/kern/proc_info.c`.
- **What it shows**: `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)` returns `kinfo_proc` for every process on the system regardless of uid: pid, ppid, uid/gid sets, stat, comm, start time, nice. `proc_pidinfo` adds per-flavor detail: `PROC_PIDTASKINFO` gives virtual/resident size, total user/system time, thread counts, faults, pageins; `PROC_PIDTBSDINFO` adds full bsdinfo (uids, nfiles, nice, start tvsec). `proc_pid_rusage` V6 adds `ri_phys_footprint`, billed/serviced energy plus `ri_energy_nj` (nanojoules), `ri_diskio_bytesread/written`, `ri_logical_writes`, `ri_pkg_idle_wkups`, `ri_interrupt_wkups`, `ri_instructions`, `ri_cycles`, `ri_cpu_time_qos_*`, `ri_lifetime_max_phys_footprint`, `ri_interval_max_phys_footprint`, and child-process aggregates. `sysctl(KERN_PROCARGS2, pid)` returns argc+argv.
- **How it shows it**: All three reference implementations do the same loop: enumerate once with `sysctl KERN_PROC_ALL` (htop, btop) or `proc_listallpids`, then enrich per pid with `proc_pidpath`/`proc_pidinfo`/`proc_pid_rusage`, differencing cumulative counters across each poll interval (Stats uses a 1 s tick for disk).
- **Ideas worth taking**: One full `KERN_PROC` read plus targeted `proc_pidinfo` per row is cheap; treat `rusage` fields as counters and keep per-pid history keyed by pid+start-time so pid reuse doesn't corrupt deltas. `PROC_PIDPATHINFO`, `PROC_PIDCOALITIONINFO` and `PROC_PIDT_SHORTBSDINFO` are explicitly exempt from the same-user check, so path, coalition id and short info can be shown for every process without root.
- **Weaknesses / avoid**: Everything under `CHECK_SAME_USER` fails `EPERM` for other users' processes: taskinfo (memory, CPU times, threads), rusage (energy, disk I/O, footprint), fd lists, vnode paths, workqueue info. btop's fallback (zero memory, reuse last CPU) and htop's reduced-detail mode show the degraded path; a full-system monitor needs root or a helper for complete columns.
- **Sources**: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/proc_info.h, https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/resource.h, https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/proc_info.c, https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/libsyscall/wrappers/libproc/libproc.h, https://github.com/giampaolo/psutil/issues/2885, https://github.com/shirou/gopsutil/pull/1229

### task_for_pid, task ports and Apple's top/libtop

- **Status**: `task_for_pid` requires authorization by `taskgated`; in practice root, procmod group membership, or `com.apple.security.cs.debugger` for eligible targets. `com.apple.system-task-ports*` are Apple-private managed entitlements. Apple's `top` ships `com.apple.system-task-ports.read`, which gates `processor_set_tasks_with_flavor(TASK_FLAVOR_READ)`.
- **What it shows**: With a read task port, `task_info` flavors expose what libproc hides: `TASK_BASIC_INFO_64`, `TASK_EVENTS_INFO` (faults, syscalls, context switches), `TASK_KERNELMEMORY_INFO`, `TASK_POWER_INFO`, `TASK_VM_INFO_PURGEABLE`, plus `mach_vm_region` traversal for real memory maps. libtop also calls `memorystatus_control` for jetsam priority.
- **How it shows it**: `top`'s columns map to these flavors; its VM-region "purgeable" detail and complete cross-user memory numbers exist only because of the entitlement.
- **Ideas worth taking**: Read Apple's `libtop.c` as the catalog of "what a system monitor could show with perfect privilege" and mark every field that needs a task port. Design Coreography's data model so task-port-only fields are optional columns, not core state.
- **Weaknesses / avoid**: Do not call `task_for_pid` opportunistically on foreign processes: it can block on `taskgated` in non-interactive environments and is denied for anything hardened/SIP-protected even with `cs.debugger`. Reporters describe macOS 26 as tightening AMFI enforcement for binaries without Apple-issued entitlements (community claim, unverified).
- **Sources**: https://github.com/apple-oss-distributions/top, https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger, https://newosxbook.com/ent.php?exec=spindump&osVer=MacOS15, https://joe.nyland.io/blog/htop_on_osx/, https://ziraph.com/docs/concepts/per-process-attribution

### Process grouping, icons and coalitions

- **Status**: `NSRunningApplication` (AppKit, macOS 10.6+) is public. `responsibility_get_pid_responsible_for_pid` is a private libproc SPI that Stats resolves with `dlsym`. Coalition ids via `PROC_PIDCOALITIONINFO` need no privilege.
- **What it shows**: `NSRunningApplication` provides localizedName, icon, bundleIdentifier, executableURL, launchDate, activation state, and `terminate()`/`forceTerminate()` for same-uid app processes. Responsible-pid grouping replicates Activity Monitor's "app" rollups (helpers attribute to their app); coalition ids are the kernel's own grouping mechanism (`proc_listcoalitions` exists in xnu alongside the per-pid flavor).
- **How it shows it**: Stats renders rows with the app icon, name, optional pid, optional mini bar chart, alternating backgrounds in detailed mode, and a hover-revealed kill button; compact rows are ~22 pt. Non-LS daemons get a generic icon via `NSWorkspace.icon(forFile:)` on the `proc_pidpath` result.
- **Ideas worth taking**: Group by responsible pid for the app-level view, show coalition id when available for a power-user "ungrouped" view, and cache `NSRunningApplication` lookups since properties are runloop-synchronized.
- **Weaknesses / avoid**: `responsibility_*` is private SPI resolved at runtime: it can disappear and would be flagged in MAS review anyway. `NSRunningApplication` only exists for processes registered with LaunchServices, so daemons, helpers and kernel-space agents need the path/icon fallback. App Nap state is not exposed through any of these public paths (private `pbi_flags` exist but are not public).
- **Sources**: https://developer.apple.com/documentation/appkit/nsrunningapplication, https://raw.githubusercontent.com/exelban/stats/master/Modules/CPU/readers.swift, https://raw.githubusercontent.com/exelban/stats/master/Kit/process.swift, https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/proc_info.h

### Lifecycle notifications, Endpoint Security, fds, sampling, signals

- **Status**: `kqueue` `EVFILT_PROC`/`NOTE_EXIT` is public and works on any pid (only `NOTE_EXITSTATUS`/`NOTE_EXIT_DETAIL` detail is rights-gated); Endpoint Security needs a managed entitlement; `sample`/`spindump` ride on task-port restrictions; `kill`/`setpriority` follow standard uid rules.
- **What it shows**: `filt_procattach` in `kern_event.c` attaches plain `NOTE_EXIT` on any pid; the privilege check (parent, parent-in-waiting debugger, or `cansignal` SIGKILL: same uid or root) applies only when `NOTE_EXITSTATUS` is also requested. `NOTE_EXIT_DETAIL` surfaces jetsam exit reasons (memory pressure, codesigning, fc/vnode thrashing), but `proc_pidnoteexit`-style detail is parent/debugger only. ES `es_new_client` yields exec/fork/exit stream for the whole system. `PROC_PIDLISTFDS` + `proc_pidfdinfo` enumerate a process's fds with vnode paths and socket addresses (lsof's mechanism). `IOPMCopyAssertionsByProcess` (public since 10.7, used by `pmset -g assertions`) returns per-pid sleep/display assertions.
- **How it shows it**: A monitor typically polls `KERN_PROC` each tick and diffs the pid set for birth/death; `NOTE_EXIT` on any pid is the zero-cost upgrade (no privilege needed for plain exit), while exit-status detail needs the same rights as signaling. Open-files and connection panels in Activity Monitor correspond to fdinfo and the nstat paths.
- **Ideas worth taking**: Poll-diff plus `NOTE_EXIT` on all listed pids covers a visual monitor without any privilege; offer "sample process" for same-uid targets and degrade the button elsewhere. Use `IOPMCopyAssertionsByProcess` for a "what's preventing sleep" list: public API, no privilege.
- **Weaknesses / avoid**: No global exec/exit events without ES (`com.apple.developer.endpoint-security.client` is a managed entitlement Apple approves case-by-case, typically for security vendors, and ES clients run as root daemons). `spindump` carries `task_for_pid-allow`; third parties can't sample foreign processes. `proc_pidfdinfo` flavors are same-uid-only, so a full-system open-files view needs the privileged helper.
- **Sources**: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_event.c, https://developer.apple.com/videos/play/wwdc2020/10159/, https://apple-docs.everest.mt/docs/bundleresources/entitlements/com.apple.developer.endpoint-security.client/, https://developer.apple.com/documentation/iokit/1557130-iopmcopyassertionsbyprocess, https://keith.github.io/xcode-man-pages/spindump.8.html, https://stackoverflow.com/questions/68175143/

### Memory: vm_statistics64, pressure, swap

- **Status**: `host_statistics64(HOST_VM_INFO64)` is fully public and unprivileged; same for `kern.memorystatus_vm_pressure_level`, `vm.swapusage` and `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`.
- **What it shows**: `vm_statistics64` counters: free, active, inactive, wired, speculative, pageins/pageouts, `compressor_page_count`, `external_page_count` (file-backed), `internal_page_count`, `purgeable_count`, swapins/swapouts, `total_uncompressed_pages_in_compressor`. Stats' Activity-Monitor mapping: `used = active + inactive + speculative + wired + compressed - purgeable - external`, `app = used - wired - compressed`, `cached_files = purgeable + external`, `free = total - used`. Pressure sysctl levels observed in Stats: 2 = warning, 4 = critical.
- **How it shows it**: Stats renders a donut/bar in the menu bar and a popup list of top-memory apps; the pressure value drives a colored dot/label. btop shows used/cached/buffers-style bars plus a memory graph over time.
- **Ideas worth taking**: Publish the formula in the UI ("App Memory + Wired + Compressed") rather than a single "used" number; show `total_uncompressed_pages_in_compressor / compressor_page_count` as a compression-ratio stat; use the dispatch source (not polling) for pressure changes; plot swap usage and pageins/outs rate as separate small-multiples.
- **Weaknesses / avoid**: Category arithmetic is an approximation; kernel adds counters over time (neural-footprint fields landed in V6 rusage). `kern.memorystatus_vm_pressure_level` is an undocumented sysctl (works today, wrapped by Stats' `sysctlbyname` helper); treat the dispatch source as the primary path.
- **Sources**: https://raw.githubusercontent.com/exelban/stats/master/Modules/RAM/readers.swift, https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/mach/vm_statistics.h, https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/kern_memorystatus.h, https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure, https://newosxbook.com/code/xnu-11215.1.10/doc/vm/memorystatus_notify.md, https://developer.apple.com/forums/thread/802656

### Disk: I/O counters, volumes, APFS, SMART

- **Status**: IOKit `IOBlockStorageDriver` statistics and `proc_pid_rusage` disk counters are unprivileged (rusage still same-uid). Volume capacity keys are public Foundation API. NVMe SMART uses a documented IOCFPlugIn interface (Stats ships it without root).
- **What it shows**: `IOBlockStorageDriver` `Statistics` dict gives cumulative bytes read/written, read/write ops, latency, errors per disk. `ri_diskio_bytesread/written` and `ri_logical_writes` give per-process lifetime disk bytes. `volumeAvailableCapacityForImportantUsageKey` returns the CacheDelete-adjusted figure (free + purgeable that would be reclaimed); `volumeAvailableCapacityForOpportunisticUsageKey` and plain `volumeAvailableCapacityKey` are the other two tiers. Stats additionally calls private `CSDiskSpaceGetRecoveryEstimate` for purgeable space.
- **How it shows it**: Stats enumerates mounted volumes via `FileManager.mountedVolumeURLs`, binds each to a `DADisk` (Disk Arbitration) for BSD name/media properties, walks the IORegistry to the `IOBlockStorageDriver` parent for byte counters, and parses `SMART` attributes through `IOCFPlugInInterface`/`SMARTReadData` with hand-defined NVMe/ATA structs in `Modules/Disk/header.h`.
- **Ideas worth taking**: Show the three capacity numbers honestly (physical free vs available-for-important-usage); label APFS snapshot space separately since it isn't accounted in the capacity keys; per-process disk read/write columns are cheap deltas of rusage; SMART attributes (percentage used, spare, unsafe shutdowns, media errors) belong in a drive-health detail view.
- **Weaknesses / avoid**: `DADisk`/`IOKit` enumeration is verbose and change-prone across media types; `CSDiskSpaceGetRecoveryEstimate` is private (Developer-ID shipping only); SMART via user clients fails for some external/enclosure drives; there is no public snapshot-size API so TM local snapshots can only be listed via `diskutil`/`fs_snapshot_*` private calls.
- **Sources**: https://raw.githubusercontent.com/exelban/stats/master/Modules/Disk/readers.swift, https://raw.githubusercontent.com/exelban/stats/master/Modules/Disk/header.h, https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey, https://developer.apple.com/forums/thread/826582, https://eclecticlight.co/2023/04/27/where-does-macos-get-its-volume-free-space-figures-from/

### Network: interfaces, per-process, Wi-Fi, connectivity

- **Status**: `getifaddrs` and `sysctl(NET_RT_IFLIST2)` are public and unprivileged. Per-process bytes have no public API: `nettop` (a system binary) or the private `NetworkStatistics.framework`/`PF_SYSTEM` `com.apple.network.statistics` socket are the only paths. CoreWLAN SSID/BSSID requires Location Services.
- **What it shows**: `RTM_IFINFO2`/`if_msghdr2` gives cumulative `ifi_ibytes`/`ifi_obytes` per interface; `getifaddrs` gives flags (`IFF_RUNNING`), IPv4/IPv6 addresses; `if_data` reports baud rate. `nettop` rows include per-connection/per-process rx/tx, `rtt_avg`, `rcvsize`, `tx_win`, `cc_algo`, connection state. CoreWLAN exposes ssid, bssid, rssi, noise, transmitRate, channel/band, security.
- **How it shows it**: Stats spawns `/usr/bin/nettop -P -L 1 -n`, parses per-process totals, differences them per interval, and resolves names via `NSRunningApplication`; interface detection filters VPN prefixes (`utun`, `ipsec`, `ppp`, `tun`, `tap`, `gif`, `stf`, `wg`); primary interface via `SCDynamicStore`; public IP via its own `api.mac-stats.com` endpoint; latency via ICMP (`1.1.1.1`) or HTTP check toggle. btop does `getifaddrs` + `NET_RT_IFLIST2` only (no per-process).
- **Ideas worth taking**: The three-layer model (interface counters free, per-process via nettop subprocess or private nstat, Wi-Fi detail via CoreWLAN + Location Services) is the realistic ceiling; VPN-prefix filtering and an explicit connectivity target setting are good UX details; `rtt_avg` from nstat is a free latency-per-flow metric most monitors ignore.
- **Weaknesses / avoid**: Subprocess parsing is fragile and now risks TCC prompts on macOS 26 (see changes section); the private framework avoids subprocesses but is unstable ("keeps breaking" per netbottom.c) and unusable on MAS; SSID returns nil/redacted without Location Services authorization; public-IP lookup requires a trusted endpoint, so Stats runs its own.
- **Sources**: https://raw.githubusercontent.com/exelban/stats/master/Modules/Net/readers.swift, https://raw.githubusercontent.com/aristocratos/btop/main/src/osx/btop_collect.cpp, https://taomm.org/vol2/pdfs/CH%204%20Network%20State%20and%20Statistics.pdf, https://taomm.org/vol2/pdfs/CH%207%20Network%20Monitoring.pdf, https://newosxbook.com/src.jl?tree=listings&file=/netbottom.c, https://stackoverflow.com/questions/19540445/, https://developer.apple.com/forums/thread/732431, https://developer.apple.com/forums/thread/833749

### Battery and power assertions

- **Status**: `IOPSCopyPowerSourcesInfo`/`IOPSGetPowerSourceDescription` are public IOKit APIs (`IOPowerSources.h`); `AppleSmartBattery` IORegistry properties are read unprivileged; `IOPMCopyAssertionsByProcess` is public since 10.7. No public charge-history API exists.
- **What it shows**: IOPS descriptions give power source (AC/Battery/UPS), charge level, charging flags, time-to-empty. `AppleSmartBattery` properties cover `IsCharging`, `Voltage`, `Temperature`, `ChargerData` (adapter watts/voltage), `BatteryData` (cycle count, design vs max capacity). Stats falls back to SMC keys (`TB1T`, `TB2T`, `PPBR`, `PDTR`) when properties are missing.
- **How it shows it**: Stats registers an IOPS notification runloop source and re-reads on change; shows health as max/design capacity, cycle count, temperature, watts in/out, and a menu-bar icon that reflects state.
- **Ideas worth taking**: Event-driven refresh via IOPS runloop source instead of polling; the SMC fallback chain matters because Stats had to adjust battery temperature reads for macOS 27 (v3.0.21 notes); a "power assertions" panel via `IOPMCopyAssertionsByProcess` is a differentiator Activity Monitor doesn't surface.
- **Weaknesses / avoid**: Charge history is not exposed: macOS keeps battery analytics in protected powerd data, so long-term graphs require the app to log its own samples; property names and units vary by SoC (Stats fixes land regularly); UPS support exists but is untested on desktops without one.
- **Sources**: https://raw.githubusercontent.com/exelban/stats/master/Modules/Battery/readers.swift, https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.h, https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h, https://api.github.com/repos/exelban/stats/releases/latest

### System inventory: uptime, users, launchd, login items, apps

- **Status**: All unprivileged reads except the BTM database. `kern.boottime`/`uptime` sysctls are free; login sessions come from `utmpx`; `SMAppService` reports your own registrations; enumerating everyone's background items needs root + Full Disk Access.
- **What it shows**: Boot time and uptime; logged-in users/sessions via `getutxent`; `SMAppService` status for the app's own login item/agent/daemon (enabled, requiresApproval, notRegistered, notFound); `sfltool dumpbtm` or the `BackgroundItems-v7.btm` plist for the full persistence inventory (developer, team id, disposition: enabled/allowed/visible/notified); installed apps via LaunchServices/`NSWorkspace`/Spotlight.
- **How it shows it**: Activity Monitor surfaces none of this; it's the space where a power tool can add a "Startup" tab. Stats registers its login item through `SMAppService.mainApp` on macOS 13+ and falls back to `SMLoginItemSetEnabled`.
- **Ideas worth taking**: A startup/background-items list is genuinely useful and mostly unbuilt in monitors; display SMAppService status transitions to catch the macOS 13+ "requires approval" state; show uptime/load average as a small header stat.
- **Weaknesses / avoid**: Reading `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm` needs root+FDA, so a live BTM panel is only feasible through the privileged helper or by shelling to `sudo sfltool dumpbtm` (bad UX); `ES_EVENT_TYPE_NOTIFY_BTM_LAUNCH_ITEM_ADD` is reported broken by Objective-See; `launchctl print` system domain needs root.
- **Sources**: https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web, https://github.com/objective-see/DumpBTM/, https://www.macforensics.app/en/artifacts/login-items-btm, https://theevilbit.github.io/posts/smappservice/, https://raw.githubusercontent.com/exelban/stats/master/Kit/helpers.swift

### exelban/stats (menu bar monitor, reference implementation)

- **Status**: Free, MIT, solo-maintained "open source but not open contribution". v3.0.21 released 2026-10-11; requires macOS 12+. Distributed as `Stats.dmg` on GitHub releases, `brew install stats`, and a headless curl installer; DMG ships a bundled SMC helper daemon (`eu.exelban.Stats.SMC.Helper` under `/Library/PrivilegedHelperTools` + LaunchDaemons) for fan control only.
- **What it shows**: Menu-bar modules for CPU, GPU, RAM, disk, network, battery, sensors, fans, Bluetooth; popups carry top-process tables (CPU%, memory, disk, net) and per-module detail; remote-monitoring streaming to a hosted account.
- **How it shows it**: AppKit; tiny widget primitives in `Kit/Widgets/` (line, bar, pie, stack, tachometer, network charts); process rows with icon + name + optional pid + inline bar, ~22 pt compact/28 pt detailed rows, alternating backgrounds, hover kill button issuing `kill -9`; `Stats.entitlements` notably has no `com.apple.security.app-sandbox`: only `disable-library-validation`, `personal-information.location`, and a widgets app group.
- **Ideas worth taking**: The reader architecture is a clean per-module "collector" pattern; formulas for memory categories, nettop parsing, NVMe SMART via CFPlugin, dlsym'd `responsibility_*`, and the SMC helper's audit-token certificate check are all directly reusable patterns; documented cost awareness ("Sensors and Bluetooth are the most expensive modules") is a good product stance.
- **Weaknesses / avoid**: Heavy subprocess use (`/bin/ps -Aceo pid,pcpu,comm -r` for the CPU top list, `nettop -P -L 1 -n` for per-process network) creates TCC friction on macOS 26 and per-second process spawn cost; fan control is in "legacy mode, not maintained"; every sensors release is a SoC chase (new keys per chip).
- **Sources**: https://raw.githubusercontent.com/exelban/stats/master/README.md, https://raw.githubusercontent.com/exelban/stats/master/Modules/RAM/readers.swift, https://raw.githubusercontent.com/exelban/stats/master/Modules/CPU/readers.swift, https://raw.githubusercontent.com/exelban/stats/master/Modules/Net/readers.swift, https://raw.githubusercontent.com/exelban/stats/master/Modules/Disk/readers.swift, https://raw.githubusercontent.com/exelban/stats/master/Modules/Battery/readers.swift, https://raw.githubusercontent.com/exelban/stats/master/SMC/Helper/main.swift, https://raw.githubusercontent.com/exelban/stats/master/Kit/process.swift, https://raw.githubusercontent.com/exelban/stats/master/Stats/Supporting%20Files/Stats.entitlements, https://api.github.com/repos/exelban/stats/releases/latest, https://github.com/Homebrew/homebrew-cask/blob/master/Casks/s/stats.rb

### aristocratos/btop (src/osx)

- **Status**: Free open source terminal monitor; latest release v1.4.7 (2026-05-01), actively maintained; Homebrew `btop` formula.
- **What it shows**: Per-core CPU, memory, disks, network, processes, GPU and sensors on Apple Silicon.
- **How it shows it**: `src/osx/btop_collect.cpp`: `sysctl(KERN_PROC_ALL)` for the pid set, `proc_pidpath` for names, `KERN_PROCARGS2` for argv, `proc_pidinfo(PROC_PIDTASKINFO)` for threads/mem/cpu times, `proc_pid_rusage(RUSAGE_INFO_CURRENT)` for per-process disk bytes (comment in source: "this fails for processes we don't own"), `host_processor_info` for per-core load, `getifaddrs` + `NET_RT_IFLIST2`/`if_msghdr2` for network, and dynamically-resolved private `IOReport`/`IOHIDEventSystemClient` APIs for GPU residency, energy and sensors.
- **Ideas worth taking**: The defensive pattern when a foreign process denies `proc_pidinfo` (zero the fields, keep last CPU) is exactly how a graceful monitor should behave; gpu frequency is reverse-engineered from the `pmgr` `voltage-states9` IORegistry property when IOReport channels are absent.
- **Weaknesses / avoid**: TUI, not a windowed app; no per-process network at all; sensors rely on private frameworks.
- **Sources**: https://raw.githubusercontent.com/aristocratos/btop/main/src/osx/btop_collect.cpp, https://raw.githubusercontent.com/aristocratos/btop/main/src/osx/sensors.cpp, https://raw.githubusercontent.com/aristocratos/btop/main/src/osx/smc.cpp, https://api.github.com/repos/aristocratos/btop/releases/latest

### htop (darwin)

- **Status**: Free open source; 3.5.3 released 2026-08-16; Darwin backend lives under `darwin/`.
- **What it shows**: Process table with pid, user, priority/nice, cpu%, mem%, time, command, disk read/write bytes and rates, translated state; per-thread view when accessible.
- **How it shows it**: `DarwinProcessTable.c` enumerates with `sysctl(KERN_PROC_ALL)` into `kinfo_proc` with `ENOMEM` retry growth; `DarwinProcess_setFromLibprocPidinfo` calls `proc_pidinfo(PROC_PIDTASKINFO)` for resident size, thread counts, user/system time; per-process disk via `proc_pid_rusage` (V2) differenced across scans; optionally tries `task_for_pid` + `task_threads`/`thread_info` for real thread enumeration, which fails for foreign processes, so htop runs reduced-detail unprivileged and needs root/procmod for full view.
- **Ideas worth taking**: The explicit `taskAccess` flag pattern (attempt privileged enrichment once, remember the result) keeps the UI honest; zombie handling via `proc_find_zombref` equivalents avoids ghost rows.
- **Weaknesses / avoid**: Without elevation, htop shows degraded columns; guidance blogs explicitly recommend running under sudo or MacPorts' procmod group, neither acceptable for a consumer app.
- **Sources**: https://raw.githubusercontent.com/htop-dev/htop/main/darwin/DarwinProcessTable.c, https://raw.githubusercontent.com/htop-dev/htop/main/darwin/DarwinProcess.c, https://raw.githubusercontent.com/htop-dev/htop/main/darwin/DarwinMachine.c, https://api.github.com/repos/htop-dev/htop/releases/latest, https://joe.nyland.io/blog/htop_on_osx/

### iStat Menus

- **Status**: Commercial menu-bar monitor from Bjango. Site lists "iStat Menus 7.5" (version history: 7.5 on 2026-09-14 with Liquid Glass menus for macOS 27); Homebrew cask tracks 7.30. Requires macOS 13.5+. Licenses: single, family (5 seats), upgrade pricing, 14-day trial, plus Setapp ($9.99/mo bundle). Optional privileged daemon since 7.0 ("install without an admin password: the helper is optional").
- **What it shows**: CPU/GPU/mem/disk/network/sensors/battery/weather/time plus rules-based notifications, fan control ramping, per-app disk and bandwidth, SMART status, energy mode switching, world clocks, astronomy.
- **How it shows it**: Dense menu-bar items and dropdown menus with many modes (dual-line label+bar, icon, iOS-style battery, ping); E/P cores can be styled differently; menus carry history graphs with selectable ranges (10 min to 28 days).
- **Ideas worth taking**: Optional-helper design (full function minus privileged features without admin) and the breadth of notification rules; helper split: `com.bjango.istatmenus.daemon` for sensors/fans/smart data plus a separate installer helper under `/Library/PrivilegedHelperTools`.
- **Weaknesses / avoid**: Two privilege-escalation CVEs against the helper stack (insecure XPC auth + command injection in `processCommand:`; world-writable helper directory): the exact failure modes to design against with audit-token checks and minimal helper surface. Closed source.
- **Sources**: https://bjango.com/mac/istatmenus/, https://bjango.com/mac/istatmenus/versionhistory/, https://github.com/Homebrew/homebrew-cask/blob/master/Casks/i/istat-menus.rb, https://markuta.com/istat-menus-local-privilege-escalation/, https://fluidattacks.com/advisories/muse

### TMOG (Task Manager OG)

- **Status**: Proprietary beta from Dave Plummer (Windows Task Manager author); site lists "macOS 1.0.0 RTM" targeting macOS 14+, Swift+AppKit, universal binary, Developer-ID signed and notarized DMG direct download; press coverage notes beta 0.1.1 requiring macOS 13+ and a planned paid Pro tier. Closed source.
- **What it shows**: Task-manager-style process/performance views at up to 60 Hz refresh, shared metric core across macOS/Windows/Linux.
- **How it shows it**: Native AppKit windows and tables; deliberately outside the Mac App Store because sandboxed apps "cannot retrieve a system-wide process list or force-quit other applications" (Plummer's account of the store constraint).
- **Ideas worth taking**: Validation of the thesis: high-refresh native UI plus Developer-ID distribution is the only way to ship a real monitor; its existence (built largely via Claude Code) is also the "vibecoded" perception risk Coreography must visibly exceed.
- **Weaknesses / avoid**: Closed source, no public metrics detail to verify; community criticism of the project's AI-built provenance.
- **Sources**: https://www.tmog.org/, https://www.blogspan.net/tmog-task-manager-macos-beta/, https://xenospectrum.com/en/dave-plummer-tmog-macos/, https://www.purepc.pl/dave-plummer-tmog-task-manager-claude-code-windows-macos-linux

### Distribution and privilege model

- **Status**: Three shipping channels in practice: MAS (sandboxed), Developer ID + notarization (direct), and Developer ID + optional privileged daemon. Every serious monitor researched ships outside MAS.
- **What it shows**: Stats' entitlements contain no `app-sandbox` key at all; TMOG is a Developer-ID/notarized direct download; iStat Menus ships both direct and as a Mac App Store edition that needs a separate helper for sensors; all three rely on optional or on-demand privilege.
- **How it shows it**: Privileged helpers are `SMAppService.daemon` (macOS 13+) registrations: a LaunchDaemons plist in the app bundle, user approval surfaced in System Settings > Login Items, XPC between app and daemon; Stats' helper validates the client's code-signing certificate chain from the connection audit token before serving requests.
- **Ideas worth taking**: Gate tiers explicitly: Tier 1 unprivileged dashboard (everything public), Tier 2 entitlements that are grantable (Location Services for SSID), Tier 3 optional daemon for foreign-process rusage/fd/sampling, fan control, BTM inventory. That mirrors iStat Menus' "helper optional" and Stats' "helper only for fans".
- **Weaknesses / avoid**: MAS is a dead end: sandbox blocks foreign-process introspection beyond the no-check flavors, IOKit user clients (SMC, NVMe SMART), subprocess tools (`nettop`), ES (root-daemon managed entitlement), and other-app termination. Private frameworks (NetworkStatistics, IOReport, `responsibility_*`, `CSDiskSpaceGetRecoveryEstimate`) are safe under Developer ID but fragile and MAS-rejected. FDA is only needed for niche reads (BTM db); don't require it by default.
- **Sources**: https://raw.githubusercontent.com/exelban/stats/master/Stats/Supporting%20Files/Stats.entitlements, https://raw.githubusercontent.com/exelban/stats/master/SMC/Helper/main.swift, https://raw.githubusercontent.com/exelban/stats/master/SMC/Helper/protocol.swift, https://theevilbit.github.io/posts/smappservice/, https://www.blogspan.net/tmog-task-manager-macos-beta/, https://developer.apple.com/forums/thread/735356

### macOS 26 and 27 changes observed

- **Status**: Mixed official/community evidence; macOS 26 Tahoe (Liquid Glass) and macOS 27 Golden Gate are both current as of 2026-10-17.
- **What it shows**: macOS 26 added a System Settings > Menu Bar allow-list that hides menu-bar items until enabled (Stats FAQ/issue #3120). On macOS 15 and later, the "would like to access data from other apps" prompt can fire when an app or its child processes read other apps' containers (reported against Stats; one codebase migrated `ps`/`lsof` scans to in-process libproc. `airport` CLI was reported removed in macOS 26.3 (unverified). Stats v3.0.21 adjusted battery temperature reading "on macOS 27 for some SoC". iStat Menus 7.2 release notes mention Tahoe fixes: menu-bar vertical offset, missing frequency sensors. `kern.osproductversion` correctly reports 26.0 while SDK-linked version APIs returned 16.0 to a fastfetch CI build.
- **How it shows it**: N/A (this section is a changelog of environment changes).
- **Ideas worth taking**: Prefer in-process libproc/sysctl calls over helper CLIs (avoids the new TCC prompts and subprocess cost); treat menu-bar visibility as onboarding friction for any menu-bar surface; version-gate sensor/battery property readers per SoC and macOS version.
- **Weaknesses / avoid**: Beta-period reports are noisy; mark `airport` removal and the AMFI `task_for_pid` tightening as unverified until confirmed on a 26.3+ machine; keep `sysctl kern.osproductversion` rather than bundled-version APIs for OS detection.
- **Sources**: https://raw.githubusercontent.com/exelban/stats/master/README.md, https://api.github.com/repos/exelban/stats/releases/latest, https://github.com/steipete/CodexBar/pull/2599, https://gist.github.com/ruseel/b1e3568c237c823260c6781bbebd0875, https://bjango.com/mac/istatmenus/versionhistory/, https://github.com/fastfetch-cli/fastfetch/issues/1809, https://ziraph.com/docs/concepts/per-process-attribution

## Cross-cutting patterns

- Same-uid wall: `proc_pidinfo` (except SHORTBSDINFO/UNIQIDENTIFIER/PATHINFO/COALITIONINFO/PLATFORMINFO), `proc_pid_rusage`, fd info, `NOTE_EXIT`, `task_for_pid`, signals and renice all degrade to own-uid processes without root. Everything else (pid lists, bsdinfo basics, executable path, coalition id, system-wide counters) is world-readable.
- Counters, not rates: nearly every API returns cumulative numbers; every implementation keeps previous samples and computes deltas keyed by pid (+ start time to survive reuse).
- Event sources exist and are cheap: IOPS power-source runloop source, `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`, `kqueue NOTE_EXIT` for owned pids, `DASession` disk callbacks; prefer them over timers.
- Subprocess wrappers are being squeezed: Stats' `ps`/`top`/`nettop` pattern now collides with macOS 26 TCC prompts; in-process libproc/sysctl is the direction.
- Private APIs fill real gaps (per-process network via NStat, responsible-pid via `responsibility_*`, purgeable estimate via `CSDiskSpaceGetRecoveryEstimate`, GPU/sensor via IOReport/IOHIDEventSystemClient, SMART via CFPlugin). Safe under Developer ID, fatal for MAS.
- Privileged features are all optional: fan control, foreign-process detail, BTM inventory. Every successful product treats the helper as an add-on.
- Security surface is the helper: both iStat Menus CVEs were helper/XPC problems; audit-token signature validation and a narrow protocol are mandatory.

## Implications for Coreography

- Build the main engine on public APIs: `sysctl(KERN_PROC_ALL)` enumeration, `proc_pidpath`/`PROC_PIDTSHORTBSDINFO`/`PROC_PIDCOALITIONINFO` for all-process rows, `proc_pidinfo(PROC_PIDTASKALLINFO)` and `proc_pid_rusage(RUSAGE_INFO_CURRENT)` for same-uid enrichment, `host_statistics64` memory, `NET_RT_IFLIST2` interfaces, `IOBlockStorageDriver` disk counters, IOPS + AppleSmartBattery battery. That alone fills a rich dashboard with zero privilege.
- Model every per-process field as optional data with a provenance tag (universal vs same-uid vs root). Dim or collapse denied columns instead of zeroing them, and surface a single "show all processes' details" affordance that installs the helper.
- Ship Developer ID + notarized; do not plan a MAS build. Keep private-API usage isolated behind capability checks (`dlsym`, runtime feature probes) so nothing hard-fails when Apple removes a symbol.
- Avoid subprocess monitors entirely (no `ps`/`top`/`nettop` shells) because of the macOS 26 TCC prompts; if per-process network is a must-have, link `NetworkStatistics.framework` dynamically behind a feature flag and keep `nettop` parsing as the documented fallback, not the primary path.
- Memory view should publish the honest decomposition (App/Wired/Compressed/Cached/Free + pressure level + swap) rather than a single bar; the Stats formula is a proven baseline to match Activity Monitor's vocabulary.
- Process list: icon-led rows via `NSRunningApplication` + `responsibility_get_pid_responsible_for_pid` grouping, coalition ids for a power grouping mode, `NOTE_EXIT` watchers for timely row removal (any pid, plain exit only), hover kill via `kill()`/`NSRunningApplication.forceTerminate`, renice only offered on same-uid rows.
- Optional `SMAppService.daemon` + XPC helper with audit-token cert validation for: foreign-process rusage/fd info, process sampling, SMART on more hardware, BTM inventory. Make refusal to install cost nothing feature-wise.
- Add the differentiators competitors can't or don't: a sleep-assertions panel (`IOPMCopyAssertionsByProcess`), per-QoS CPU time columns from rusage V6, energy column from `ri_energy_nj` (not `ri_billed_energy`, which is energy billed to the process by others), connection RTT from nstat data, compression ratio, and a startup-items view.
- Version-gate everything platform-dependent (battery property names, sensor keys, CoreWLAN behavior, menu-bar entitlement prompts) and read the OS version from `sysctl kern.osproductversion`, not the SDK-linked compatibility value.

## Sources

- https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/proc_info.h
- https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/resource.h
- https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/mach/vm_statistics.h
- https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/kern_memorystatus.h
- https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/proc_info.c
- https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_event.c
- https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/libsyscall/wrappers/libproc/libproc.h
- https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/mach/task_info.h
- https://github.com/apple-oss-distributions/top
- https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.h
- https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h
- https://raw.githubusercontent.com/exelban/stats/master/README.md
- https://raw.githubusercontent.com/exelban/stats/master/Modules/RAM/readers.swift
- https://raw.githubusercontent.com/exelban/stats/master/Modules/CPU/readers.swift
- https://raw.githubusercontent.com/exelban/stats/master/Modules/Net/readers.swift
- https://raw.githubusercontent.com/exelban/stats/master/Modules/Disk/readers.swift
- https://raw.githubusercontent.com/exelban/stats/master/Modules/Disk/header.h
- https://raw.githubusercontent.com/exelban/stats/master/Modules/Battery/readers.swift
- https://raw.githubusercontent.com/exelban/stats/master/Kit/process.swift
- https://raw.githubusercontent.com/exelban/stats/master/Kit/helpers.swift
- https://raw.githubusercontent.com/exelban/stats/master/SMC/Helper/main.swift
- https://raw.githubusercontent.com/exelban/stats/master/SMC/Helper/protocol.swift
- https://raw.githubusercontent.com/exelban/stats/master/Stats/Supporting%20Files/Stats.entitlements
- https://api.github.com/repos/exelban/stats/releases/latest
- https://github.com/Homebrew/homebrew-cask/blob/master/Casks/s/stats.rb
- https://raw.githubusercontent.com/aristocratos/btop/main/src/osx/btop_collect.cpp
- https://raw.githubusercontent.com/aristocratos/btop/main/src/osx/sensors.cpp
- https://raw.githubusercontent.com/aristocratos/btop/main/src/osx/smc.cpp
- https://api.github.com/repos/aristocratos/btop/releases/latest
- https://raw.githubusercontent.com/htop-dev/htop/main/darwin/DarwinProcessTable.c
- https://raw.githubusercontent.com/htop-dev/htop/main/darwin/DarwinProcess.c
- https://raw.githubusercontent.com/htop-dev/htop/main/darwin/DarwinMachine.c
- https://raw.githubusercontent.com/htop-dev/htop/main/darwin/Platform.c
- https://api.github.com/repos/htop-dev/htop/releases/latest
- https://developer.apple.com/documentation/appkit/nsrunningapplication
- https://developer.apple.com/documentation/iokit/1557130-iopmcopyassertionsbyprocess
- https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure
- https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger
- https://developer.apple.com/videos/play/wwdc2020/10159/
- https://developer.apple.com/forums/thread/732431
- https://developer.apple.com/forums/thread/833749
- https://developer.apple.com/forums/thread/826582
- https://developer.apple.com/forums/thread/802656
- https://developer.apple.com/forums/thread/824751
- https://developer.apple.com/forums/thread/735356
- https://apple-docs.everest.mt/docs/bundleresources/entitlements/com.apple.developer.endpoint-security.client/
- https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web
- https://github.com/objective-see/DumpBTM/
- https://www.macforensics.app/en/artifacts/login-items-btm
- https://theevilbit.github.io/posts/smappservice/
- https://bjango.com/mac/istatmenus/
- https://bjango.com/mac/istatmenus/versionhistory/
- https://github.com/Homebrew/homebrew-cask/blob/master/Casks/i/istat-menus.rb
- https://markuta.com/istat-menus-local-privilege-escalation/
- https://fluidattacks.com/advisories/muse
- https://www.tmog.org/
- https://www.blogspan.net/tmog-task-manager-macos-beta/
- https://xenospectrum.com/en/dave-plummer-tmog-macos/
- https://www.purepc.pl/dave-plummer-tmog-task-manager-claude-code-windows-macos-linux
- https://taomm.org/vol2/pdfs/CH%204%20Network%20State%20and%20Statistics.pdf
- https://taomm.org/vol2/pdfs/CH%207%20Network%20Monitoring.pdf
- https://newosxbook.com/src.jl?tree=listings&file=/netbottom.c
- https://newosxbook.com/ent.php?exec=spindump&osVer=MacOS15
- https://newosxbook.com/code/xnu-11215.1.10/doc/vm/memorystatus_notify.md
- https://stackoverflow.com/questions/19540445/
- https://superuser.com/questions/933817/
- https://stackoverflow.com/questions/68175143/
- https://keith.github.io/xcode-man-pages/spindump.8.html
- https://github.com/giampaolo/psutil/issues/2885
- https://github.com/shirou/gopsutil/pull/1229
- https://github.com/shirou/gopsutil/pull/2117
- https://joe.nyland.io/blog/htop_on_osx/
- https://ziraph.com/docs/concepts/per-process-attribution
- https://github.com/steipete/CodexBar/pull/2599
- https://gist.github.com/ruseel/b1e3568c237c823260c6781bbebd0875
- https://github.com/fastfetch-cli/fastfetch/issues/1809
- https://eclecticlight.co/2023/04/27/where-does-macos-get-its-volume-free-space-figures-from/

Coordinator corrections (2026-10-17), from a second primary-source check: `ri_billed_energy` is energy billed to a task through vouchers, not its own energy (`ri_energy_nj`); Activity Monitor's current network path is unverified; the "access data from other apps" prompt was reported on macOS 15 and is tied to touching other apps' containers, with no report of `ps` or `lsof` alone triggering it; iStat Menus has a Mac App Store edition that relies on a separate helper; the sandbox still allows `proc_pidinfo` on other processes but denies pid listing and rusage.
