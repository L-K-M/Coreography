# Platform mechanics: HUD overlays, sleep/wake history, local AI load, automation, history-store privacy (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

Scope: macOS 26 Tahoe / 27 Golden Gate platform mechanics a graph-first
monitor needs beyond sampling. Five areas: (A) drawing a click-through HUD
over full-screen apps and games; (B) reading sleep, wake and overnight
battery-drain history; (C) observing local AI workloads (MLX, llama.cpp,
Ollama, LM Studio, Apple Intelligence); (D) exposing the app to automation
(App Intents, Shortcuts, Control Center, widgets, CLI, MCP); (E) keeping a
local history store private. Notes 05 and 09 cover the Metal Performance
HUD itself, IOReport/SMC data sources, and the FPS measurement options;
this file is about the windowing, OS-event, and integration mechanics.

## Summary

- **A fullscreen-capable HUD is a proven recipe with known limits**: borderless
  `NSPanel` with `.nonactivatingPanel`, `NSApp.setActivationPolicy(.accessory)`,
  `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces,
  .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `ignoresMouseEvents`
  toggled for click-through. This is exactly what zzoko/PerformanceHUD ships
  (verified in `HUDPanel.swift`, `HUDWindowController.swift` and
  `HUDStyle.swift`, which defines `windowLevel = .screenSaver`); mactop's
  overlay uses `NSStatusWindowLevel + 1` with the same collectionBehavior and
  stays interactive instead.
- **Windowed and borderless games "just work"; native and compatibility-layer
  fullscreen are conditional.** PerformanceHUD documents: native fullscreen
  generally works but macOS UI-scaling changes can shrink the HUD; CrossOver
  fullscreen only shows the HUD when the game's fullscreen resolution equals
  the desktop "looks like" resolution or its 2x Retina equivalent. Treat
  fullscreen HUD as best-effort with an escape hatch (density/scale control).
- **`metalperftrace listen --json` (macOS 27) streams NDJSON per process at
  >= 1 s intervals** with `PID`, `Layers[].Configuration` (`Width (pixels)`,
  `Height (pixels)`) and `Layers[]."Performance Stats"` (`"Time Active (sec)"`,
  `"Presented Frame Stats"` containing `FPS` and `"On-GPU Walltime
  Stats"."Total (ms)"`), the exact schema PerformanceHUD parses for FPS,
  app GPU busy %, and Metal output resolution. Each update is an
  interval summary, not raw frame times: 1% lows / frame-time
  percentiles need `collect` + `overview --json-include-timeline` (full
  per-frame timeline) or `setup --enable per-frame-metrics` signposts.
  `metalperftrace setup --enable hud --pid` can turn Apple's own HUD on
  in a running process.
- **`sharingType = .none` no longer hides a window from capture.** It can
  still exclude a window from legacy CGWindowList capture paths, with
  coverage varying by tool (verified against ScreenCaptureKit only), but
  ScreenCaptureKit on macOS 15+ ignores it; Apple DTS answered "there are
  no public APIs for preventing screen capture" (dev forums, Tauri
  #14200). A privacy feature built on it must be labelled accordingly.
- **Sleep/wake history is largely readable without root**: `pmset -g log` (about
  14 days of Sleep/Wake/DarkWake/Assertion lines with charge levels),
  `pmset -g assertions`/`assertionslog`/`stats`/`uuidlog`, the public
  `IOPMCopyAssertionsByProcess` API, `IORegisterForSystemPower`/`NSWorkspace`
  notifications, and unified log under `subsystem == "com.apple.powerd"`.
  Caveats: dark wakes suppress notification delivery, log `<private>`
  redaction hides details for normal readers (unredaction is gated on an
  Apple-signed profile, not on privilege: root alone does not lift it,
  and root does not bypass TCC/SIP generally), log access, redaction and
  retention vary by version and configuration (unprivileged reading is
  common but not guaranteed complete or zero-permission), and assertion
  data has real parsing traps (`AssertionTrueType` vs `AssertType`,
  `OnBehalfOfPID`, renewed `TimeoutSeconds`). The logs name wake reasons
  and assertion holders; certain per-app attribution of overnight drain
  is not available. Sleep Aid (Ohanaware) proves the product shape:
  a calendar of sleep/wake/wake-reason/insomnia events plus "DID NOT SLEEP".
- **Local AI load is observable through three layers**: the OS level
  (phys_footprint may include IOAccelerator GPU allocations but is not a
  GPU-only figure; there is no public
  per-process Metal memory query equivalent to `nvidia-smi
  --query-compute-apps`; `MTLDevice.currentAllocatedSize` is own-process
  only), the runtime level (Ollama `/api/ps` exposes `size_vram`,
  `context_length`, `expires_at`; `lms ps --json`; `llama-server
  --metrics`/`--slots`), and the system level (device-specific GPU memory
  budgets and Metal working-set recommendations; ANE power/state via
  the IOReport/SMC fallbacks in notes 09). StatBar and tstats already sell
  the "LLM telemetry in a monitor" idea; Apple Intelligence runs as named
  daemons (`generativeexperiencesd`, `siriinferenced`,
  `intelligenceplatformd`, `HostInferenceProviderService`), reportedly on
  ANE (single teardown source; ANE-only execution unverified).
- **Automation surfaces on macOS 26 are unusually rich**: App Intents run
  directly from Spotlight (menu items are surfaced automatically;
  `IndexedEntity` + `indexingKey` drive parameter completion), personal
  automations came to Shortcuts on Mac (folder/file, app open/close, Stage
  Manager, battery level, charger, focus triggers), `ControlWidget` puts
  controls in Control Center and the menu bar, desktop widgets are
  WidgetKit-timeline-throttled, and local MCP servers in Mac apps are a real
  2026 trend (DEVONthink 4.3 ships a ~60-command built-in MCP server).
- **A history store is a forensic record.** Little Snitch sets the bar:
  encrypted store (key in System keychain), explicit retention limits (1
  year / 50,000-200,000 connections), "Rules to Hide Connections" that
  collapse chosen flows into an anonymous row, and exports that exclude
  traffic history. `isExcludedFromBackup` keeps the store out of Time
  Machine backups but not local snapshots; Data Protection classes on Apple
  Silicon gate files at log-out, not lock. iStat Menus leaves visible gaps
  in history rather than sampling through sleep; PerformanceHUD logs CSV
  only on demand with no PIDs.

## Floating HUD over full-screen apps and games

### The working recipe, as shipped in the wild

The Apple Developer Forums thread on overlaying fullscreen apps and two
shipping implementations agree on the same set of knobs:

| Knob | Value | Why |
| --- | --- | --- |
| Activation policy | `NSApplicationActivationPolicyAccessory` (`.accessory`) | Regular foreground apps are not layered above other apps' fullscreen Spaces; accessory apps (LSUIElement) are. Verified in Apple dev forums thread 826308. |
| Window class | `NSPanel` with `.nonactivatingPanel` (or borderless `NSWindow` that can't become key/main) | Ordering a normal window front activates its app, which can pop the user out of the fullscreen Space. `canBecomeKey`/`canBecomeMain` = NO. |
| Style | `.borderless` (+ `.nonactivatingPanel`), `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false` | Transparent corner panel. One SO answer notes `.borderless` was the fix that made programmatic fullscreen floating work at all. |
| Level | `.screenSaver` (kCGScreenSaverWindowLevel) for maximum coverage; `NSStatusWindowLevel + 1` works in practice | `.floating` (3) and `.statusBar` (25) sit below fullscreen content per the DTS answer; `.screenSaver` is what drops above a fullscreen Space. mactop ships level 26 and its overlay rides fullscreen Spaces because `.fullScreenAuxiliary` lets it join the space; the level only has to beat the app's own windows inside it. |
| collectionBehavior | `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, `.ignoresCycle`; optionally `.canJoinAllApplications` | Joins every Space including fullscreen app Spaces, doesn't move with space switches, stays out of Cmd-backtick window cycling. `.canJoinAllApplications` additionally spans other apps' Spaces (DropOver-style). |
| Input | `ignoresMouseEvents = true` for a read-only HUD | Click-through. Toggling it off transiently (e.g., while Option is held) gives drag-to-reposition without Accessibility permission. |
| Ordering | `orderFrontRegardless()` | Panels in accessory apps won't front on their own. |

zzoko/PerformanceHUD (Swift, macOS 27+, ~13 stars but the most complete
shipping reference) implements the recipe exactly: `HUDPanel` is an
`NSPanel` with `[.borderless, .nonactivatingPanel]`; `level =
.screenSaver`; `collectionBehavior = [.canJoinAllSpaces,
.fullScreenAuxiliary, .stationary, .ignoresCycle]`; `ignoresMouseEvents =
true` normally, flipped off only while a held Option-drag is in progress
(it polls `NSEvent.modifierFlags` on an 80 ms timer, so no Accessibility
permission is needed); `canBecomeKey`/`canBecomeMain` return false; and it
overrides `constrainFrameRect` so the panel can sit flush against the top
screen edge despite its transparent shadow margin. It also anchors position
by top-left so scale changes don't drift the panel.

mactop's overlay (`internal/app/overlay.m`, ObjC) uses a plain borderless
`NSWindow` subclass (`canBecomeKeyWindow`/`canBecomeMainWindow` = NO),
`level = NSStatusWindowLevel + 1`, the same four collectionBehavior flags,
`ignoresMouseEvents = NO` (it's interactive: gear icon opens a checkbox
settings panel, drag anywhere to move), a solid rounded-corner NSView, and
an opacity config. Two workable answers for input: fully click-through with
a modifier-drag affordance, or interactive; pick per density level.

### Click-through and screen-capture exclusion

- `ignoresMouseEvents` makes the whole window transparent to hit-testing;
  it's a per-window property that can be toggled live, which is how
  PerformanceHUD implements "hold Option to drag".
- `NSWindow.sharingType = .none` hides a window from **legacy** CoreGraphics
  window-list capture and from some `SCWindow` listings, but on macOS 15+
  ScreenCaptureKit composites and captures it anyway. Apple DTS's answer in
  dev forums thread 792152: "At this time there are no public APIs for
  preventing screen capture." Tauri issue #14200 documents the same for
  `setContentProtection`. A "hide HUD from recordings" toggle can still
  claim Cmd-Tab/task-switcher and partial screenshot-tool exclusion, but
  coverage varies by tool and it must not promise invisibility to
  ScreenCaptureKit or screenshots generally.

### Fullscreen Spaces, Stage Manager, multiple displays

- Native macOS fullscreen creates a Space; `.canJoinAllSpaces` +
  `.fullScreenAuxiliary` lets the HUD live inside it. Vendor-confirmed
  working in fullscreen exclusive in Stray and Minecraft (Vulkan
  rendering, per PerformanceHUD's README), with the caveat that games
  changing macOS UI scaling make the HUD render larger or smaller (it
  offers a 0.5x-2x size override).
- Games under CrossOver (and, inferred, Whisky/GPTK; same mechanism):
  fullscreen only composites the HUD when the game's fullscreen resolution
  matches the display's current "looks like" resolution or its exact 2x
  Retina equivalent, e.g., 1470x956 or 2940x1912 on a 13" Air default.
  Vendor-confirmed in RDR2 and Resident Evil Requiem via CrossOver at
  matching resolutions; windowed/borderless is universal. The resolution-matching
  constraint is about which scanout/surface the WindowServer treats as the
  fullscreen Space's content; a HUD pinned at a logical position only joins
  the Space when the geometry lines up.
- Stage Manager: floating panels ride across app sets (the same mechanism
  that keeps a "Keep On Top" Notes window visible everywhere). Known
  wrinkles from the BTT forum and Eclectic Light: pinned/floating windows
  can confuse Stage Manager's set-switching (BTT's pin mode switches to the
  pinned app's stage; an Apple-Silicon-specific WindowServer bug retired
  windows to the "cast" when an always-on-top window is minimized). Nothing
  found suggests Stage Manager blocks `.canJoinAllSpaces` HUDs, but test it.
- Multiple displays: collectionBehavior is per-Space; a `.canJoinAllSpaces`
  window on each display's active space stays visible while the user games
  on one screen. Positioning should key off `NSScreen.visibleFrame` of the
  target display (mactop anchors top-left of `mainScreen` + 16 pt). A
  fullscreen game on display B does not disturb the HUD on display A.

### Game Mode detection

macOS 27's `gamepolicyd` publishes Game Mode state through the Darwin
notification `com.apple.system.game_mode_status_changed`: 0 = off, 1 = on,
2 = paused (paused means the performance mode is inactive). Read with
`notify_register_dispatch`/`notify_get_state`. Undocumented; PerformanceHUD
treats it as a read-only experiment and shows unknown/failure states as
unavailable. Useful for "the HUD auto-shows when a game is actually in Game
Mode" behavior.

### Apple's own HUD and its toggle tools

Notes 05 and 09 cover Apple's Metal Performance HUD (opt-in at launch via
`MTL_HUD_ENABLED`, Info.plist, or the global `MetalForceHudEnabled`
default). Two small tools exist just to drive it: oliwonders/MetalHUDHelper
(menu bar toggle for the global default; notes 09 documents the macOS
26.2 breakage where the toggle stopped being honored while the
`defaults write` kept working) and Jfishin/MetalHUDmenu (macOS 26 menu bar
app that configures HUD elements, opacity, scale and alignment via
environment variables; changes apply to newly launched processes only).
On macOS 27 the dynamic equivalent is `metalperftrace setup --enable hud
--pid <pid>`, which turns Apple's HUD on inside a running Metal process
without relaunching it.

### metalperftrace listen output (macOS 27)

The man page (macOS 27.0, May 2026) documents four subcommands: `collect`
(look-back `.atrc` trace files for a duration `--last` or `--start`/`--end`),
`overview` (per-process/per-layer summary of a trace, `--json`,
`--json-include-timeline`, `--aggregate` with `--domain`/`--state-label`,
`--predicate` over `processName`/`pid`/`layerName`), `listen` (live stream),
and `setup --enable/--disable` (`per-frame-metrics`,
`shader-compiler-metrics`, `hud`) targeting running processes by `--pid`.

`listen` specifics from the man page: `--json` emits each update as a
compact single-line JSON object (NDJSON); on SIGINT/SIGTERM/SIGHUP an
`--output` file is rewritten as a pretty-printed array; `--interval`
minimum and default are both 1.0 s; `--process`/`--pid`/`--predicate`
filter; `--output` tees to a file that must not already exist.

The observed JSON schema (from PerformanceHUD's `MetalMetricsParser`,
which consumes it in production): root keys `PID` (number) and `Layers`
(array). Each layer: `Configuration` with `Width (pixels)`, `Height
(pixels)`; `Performance Stats` with `Time Active (sec)` and `Presented
Frame Stats`; the latter carries `FPS` and `On-GPU Walltime Stats` with
`Total (ms)`. PerformanceHUD derives app GPU busy % as
`100 * Total(ms)/(TimeActive*1000)` for positive active time, clamped to
0-100, and picks the largest-area
layer as "the" game surface. Practical notes from its monitor: set
`NSUnbufferedIO=YES` in the child's environment or output arrives in
multi-second batches; treat samples stale after ~3 s; drain stderr so the
child can't block; the same stream provides the Metal output resolution
(which can differ from the game's internal render resolution).

Two limits that matter for the product: each `listen` update is an
interval summary (aggregate FPS and walltime totals over the interval),
so frame-time percentiles and 1% lows are not computable from it. The
man page puts "the full per-frame timeline data" behind `overview
--json-include-timeline` on a `collect`ed trace, and per-drawable
signposting behind `setup --enable per-frame-metrics` (requires `--pid`,
targets running processes). PerformanceHUD's own comparison doc says the
same of its sampled readings ("they do not replace per-frame timing").
Separately, focused-app readings "may exclude the app's helper
processes" (privacy doc), so the derived GPU busy is a per-process
figure, not a whole-app one, and is not guaranteed to match Activity
Monitor.

Also noteworthy: PerformanceHUD's privacy doc mentions a "display-refresh
listener" added after an observed game FPS cap with native glass (the
doc does not scope it to fullscreen); the
listener receives change notifications only while the HUD is visible and
exists to work around the cap. It uses "an older macOS interface that
Apple no longer supports" (per the doc); treat HUD-over-game compositing
cost as a real thing to measure, not assume.

## Sleep, wake and overnight battery drain

### What exists and what it costs to read

| Source | Content | Privilege |
| --- | --- | --- |
| `pmset -g log` | Timeline of Sleep, Wake, DarkWake, Assertions, WakeDetails, UUID, charge level and power source per event; observed retention varies | Read-only `-g` queries normally need no root; setting power policy is separate and privileged |
| `pmset -g assertions` | Current power assertions by type and process | None |
| `pmset -g assertionslog` | Create/release history of assertions | None |
| `pmset -g stats` | Sleep/wake counts since boot | None |
| `pmset -g uuid` / `-g uuidlog` | Sleep/wake UUID correlating one sleep cycle's events | None |
| `pmset -g pslog` / `-g rawlog` / `-g thermlog` | Power source, battery, thermal event streams | None |
| `IOPMCopyAssertionsByProcess` | The same assertion table as `pmset -g assertions`, as a pid→assertions dict | Public IOKit API, none |
| `IORegisterForSystemPower` / `NSWorkspace.willSleep/didWakeNotification` | In-process will-sleep/has-powered-on delivery | None |
| Unified log `subsystem == "com.apple.powerd"` | powerd's narrative log; categories include `sleepWake`, `assertions`, `battery`, `systemLoad`, `pmSettings`, `wakeRequests`, `displayState`, `lowPowerMode`, `sleepWakeResource` (PowerManagement `PrivateLib.h`) | `log show` needs no root; `<private>` fields stay redacted without an Apple-signed profile |

The `pmset -g log` event vocabulary (from real logs): `Sleep` lines give the
reason (`'Clamshell Sleep'`, `'Maintenance Sleep'`, `'Software Sleep
pid=N'`), `TCPKeepAlive` state, `Using AC/BATT (Charge:N%)` and a duration
in seconds; `DarkWake`/`Wake` lines give the wake type (`Normal Sleep`,
`Deep Idle`, `Standby`, `Hibernate`) and a driver-reported reason
(`EC.LidOpen/Lid Open`, `EC.ACAttach/Maintenance`, `RTC/Maintenance`,
`ARPT/Network`, `SMC.OutboxNotEmpty`, `HID Activity`, `EC.SleepTimer`),
expanded in `WakeDetails`/`DriverReason` lines. Assertions create/timeout
lines name the holding pid and the assertion string
(`com.apple.powermanagement.darkwakelinger`, `.acwakelinger`, "Holding in
darkwake for up to 30 seconds to update inactivity prediction", etc.).

### Reading the assertion table correctly

`IOPMCopyAssertionsByProcess` is public and needs no helper, but the dict
has four documented traps (from a shipping implementation write-up,
mTinker 1.7.0):

1. **`AssertionTrueType` is the effective type**, not `AssertType`; legacy
   names are normalised into it. Match against both the modern constants
   (`PreventUserIdleSystemSleep`, `PreventSystemSleep`,
   `PreventUserIdleDisplaySleep`, `NoIdleSleep`, `NoDisplaySleep`) and
   `InternalPreventDisplaySleep`, an internal powerd proxy type with no
   public constant. Skip `UserIsActive` or you report a phantom blocker
   whenever the user touches a key.
2. **The holder is not the responsible party.** Audio keeps the machine
   awake via an assertion filed under `coreaudiod`; the entry's
   `AssertionOnBehalfOfPID` names the real culprit. Attribute to it when
   it's positive, != holder, and still alive; show "held via coreaudiod".
3. **Daemons can't be told from user processes by name** (`sharingd` runs
   as the user). Classify by executable path prefixes (`/System/`,
   `/usr/libexec/`, `/usr/sbin/`, `/sbin/`, `/Library/Apple/`); keep
   `/usr/bin` user-side so `caffeinate`/`rsync`/`ffmpeg` get a Quit button.
4. **Timeout semantics**: an assertion only expires if `TimeoutSeconds` >
   0, computed from `AssertionTimeoutUpdateTime` (renewable), not creation
   time. Aggregate per process worst-case: one indefinite assertion means
   the process never expires.

Two more details from the same source: `pmset -g assertions` renders
non-ASCII assertion names as empty strings (name yours in ASCII; it shows
up in other people's debugging). `PreventUserIdleSystemSleep` keeps the
system awake while allowing display sleep; additionally preventing
display sleep requires `PreventUserIdleDisplaySleep`. These are separate
assertions with different effects, not interchangeable names.

### Dark wakes and notification delivery

`IORegisterForSystemPower` delivers `kIOMessageSystemWillSleep` (must be
acknowledged via `IOAllowPowerChange` within ~30 s or sleep proceeds
anyway), `kIOMessageSystemWillPowerOn` and `kIOMessageSystemHasPoweredOn`
(never acknowledged), `kIOMessageCanSystemSleep` (vetoable; `IOCancelPowerChange`
delays/cancels idle sleep) and `kIOMessageSystemWillNotSleep` (QA1340,
IOPMLib.h). The caveat that matters for a monitor: **macOS suppresses
delivery of many notifications during DarkWake, including sleep/wake
notifications** (Apple dev forums thread 15736; also why daemons can't
easily observe their own dark-wake windows). So an in-app sleep timeline
must be reconstructed from `pmset -g log` / powerd unified log after wake,
not from live notifications alone. `kIOPMAssertionTypePreventSystemSleep`
has an interesting documented side effect: asserted at `kIOPMAssertionLevelOn`,
"the system will prefer to enter the Dark Wake state, or remain in Dark
Wake if already there, rather than go to sleep"; i.e., the assertion type
that keeps a lid-closed Mac semi-awake.

### What an app can ship on top of this

Sleep Aid (Ohanaware; v1.5, April 2025; requires an admin user account;
paid with 14-day trial) is the reference implementation. Its Sleep History
Viewer is a calendar-style timeline showing: when the Mac didn't sleep,
when it pretended to sleep (screen off, never slept; "insomnia" events
graded Unusual/Excessive/Long), apps that prevented sleep or kept it in
insomnia, "insta-wakes", wake sources (notifications, Bluetooth, Siri),
OS updates, restarts, and settings changes. `DID NOT SLEEP` events are
highlighted with the screen-wake reason; short events under 10 minutes get
flagged. Sleep Check lists which settings and apps currently prevent sleep,
including which apps are playing audio and Internet Sharing state. It can
run user shell scripts before sleep and after wake, and exports history as
a zip. That is essentially "Activity Monitor for the night", a strong
validation of the battery-drain story as a feature, and a demonstration
that the data needed (sleep/wake timeline + assertions + charge deltas)
is reachable without root in the common case.

Overnight-drain framing a monitor can compute directly: join `pmset -g
log`'s per-event `Using BATT (Charge:N%)` deltas against Sleep/DarkWake
segments and attribute wake reasons + the assertions logged between them.
These reads are unprivileged in the common case, but the result attributes
wake reasons and assertion holders; a certain per-app energy split is not
available.

## Local AI workloads on Macs

### Memory: the metrics that actually describe LLM load

- `phys_footprint` (`proc_pid_rusage` RUSAGE_INFO_V4 `ri_phys_footprint`)
  is the kernel's per-process ledger (what Activity Monitor's Memory
  column and jetsam use); it **may include IOAccelerator (GPU/Metal)
  allocations as dirty, non-reclaimable pages**, but the total is not a
  GPU-only figure and the IOAccelerator share is not an independently
  queryable number. Splitting it out takes `footprint`/`vmmap`-class
  diagnostics or runtime cooperation (an MLX issue shows a
  110 GB footprint being ~109 GB "IOAccelerator (graphics) [all DIRTY]"),
  and because unified memory is shared, per-process figures are not
  additive across processes.
- There is **no public per-process Metal allocation query** comparable to
  `nvidia-smi --query-compute-apps`. `MTLDevice.currentAllocatedSize` is
  real but only reports the calling process's own Metal allocator; external
  tools that want it inject a DYLD shim (Liquid's methodology doc says this
  outright). Practical consequence: a monitor's per-process "VRAM" is the
  footprint IOAccelerator share where a footprint/vmmap-class breakdown
  is available (otherwise the footprint total, labelled as such), or the
  runtime's own API.
- MLX allocator caveat: `mx.get_peak_memory()` tracks only *active*
  buffers; freed buffers stay in the Metal pool and keep counting toward
  phys_footprint. MLX's own limit check uses `active + cache`. Report
  footprint, not the framework's counter (mlx issue #3896).
- `iogpu.wired_limit_mb` is an undocumented GPU-wired-memory budget
  setting; reported defaults vary by device, RAM and OS. Read the actual
  value rather than deriving it from a fixed RAM percentage. Metal's
  `recommendedMaxWorkingSetSize` (MLX's
  `max_recommended_working_set_size`) is a working-set recommendation,
  not a universal hard allocation ceiling. Do not assume it equals the
  private wired-memory limit. Runtimes use these readings to choose their
  budgets; preserve source and byte units when presenting them.
- Pressure signals during model loads: `kern.memorystatus_vm_pressure_level`
  (what mactop/iStat show), `sysctl vm.swapusage`, wired growth from Metal
  allocations. A big model load is largely a wired/resident memory event:
  not every model buffer is guaranteed wired or unswappable, but the
  wired growth pushes everything else toward compression/swap.

### Where each runtime exposes its state

- **Ollama**: `GET /api/ps` on localhost:11434 lists loaded models with
  `name`, `size`, `size_vram` (bytes resident in "VRAM", i.e., GPU memory),
  `context_length`, `expires_at` (when the model unloads), plus nested
  `details.family` and `details.quantization_level`.
- **llama.cpp `llama-server`**: `--metrics` enables a Prometheus endpoint,
  `--slots` exposes per-slot context state; this is what StatBar polls on
  127.0.0.1:8080 for tokens/sec, prompt/generate speed, context usage, KV
  cache, model name.
- **LM Studio**: `lms` CLI ships with the app (`~/.lmstudio/bin/lms
  bootstrap`): `lms ps`/`--json` lists loaded models, `lms load
  --estimate-only` previews memory cost, `--ttl` auto-unloads,
  `lms server start|stop`, `lms daemon`, `lms log stream`. Plus its
  documented HTTP server. A monitor can poll `lms ps --json` without
  touching internals.
- **MLX**: framework-level; `mlx.core.device_info()` exposes
  `max_recommended_working_set_size` and `memory_size`;
  `set_wired_limit`/`get_active_memory`/`get_cache_memory` are the
  in-process counters.
- **Apple Intelligence**: a ~3B base model plus task LoRA adapters, loaded
  via MobileAsset `com.apple.MobileAsset.UAF.FM.GenerativeModels` under
  `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels/...`,
  reportedly executed on ANE through `aned` (single teardown source;
  ANE-only execution unverified) by named daemons: `siriinferenced`,
  `generativeexperiencesd`, `intelligenceplatformd`,
  `IntelligencePlatformComputeService`, `HostInferenceProviderService`
  (`_modelmanagerd`), `intelligencecontextd`, `siriknowledged`
  (caiovicentino/apple-silicon-internals mapping). Idle footprint is small
  (one report: generativeexperiencesd ~11.5 MB idle); the load spikes show
  as ANE bursts when Siri/Writing Tools/Foundation Models run. Observable as
  ANE power/duty (notes 09 fallbacks) plus these processes' CPU/memory,
  labelled "Apple Intelligence" rather than a user model. Daemon presence
  or CPU is circumstantial evidence only: it can show the subsystem ran,
  not which app or model triggered inference.

### How tools present it

- **StatBar** (coderhd/system-stats-menubar-app, macOS 15+, brew): menubar
  stacked segments for E-core/P-core CPU, GPU util + memory, RAM
  breakdown (active/wired/compressed/available) and an auto-hidden LLM
  segment; the popover shows live tokens/sec, prompt-eval rate, context
  usage (e.g., 2,227/12,032), KV cache and model name for llama-server,
  Ollama and LM Studio; `--once` headless snapshot mode. This is the
  clearest existing "system monitor + LLM telemetry" product.
- **tstats.app**: menu bar monitor advertising "Apple MLX process
  monitoring": active MLX processes with PIDs, per-process GPU memory
  footprint, and a breakdown of MLX vs other GPU vs free unified memory.
- **asitop/macmon/mactop**: ANE shown as watts/bandwidth/duty (mactop's
  H11ANEIn power-state duty sampling; AMC `ANE* RD/WR` bytes; see notes 09),
  the only practical "is the Neural Engine busy" signal, which fires for
  CoreML and Apple Intelligence alike and can't name the model.
- **Vitals** (notes 15) advertises per-app Neural Engine attribution
  ("How hard each is working, and for whom", plus an ANE memory-traffic
  figure in MB/s); the mechanism is unpublished; treat as an unverified
  vendor claim, and note it does not name models either.
- Token-usage trackers (Tallyburn, toki-monitor) are a neighbouring
  category: they aggregate CLI-agent token spend, not inference load.

## Automation and integration surfaces

| Surface | State on macOS 26/27 | Fit for a monitor |
| --- | --- | --- |
| App Intents (entities, queries, actions) | Actions run directly from Spotlight on Mac; any app menu item is surfaced automatically; `IndexedEntity` + `indexingKey` make entity properties searchable in Spotlight's parameter UI; interactive snippets new in 26 | Queries for live readings ("current CPU"), actions (start/stop recording, toggle HUD, export), entities (metric, process, time-range): the verbs of an automation story |
| Shortcuts | Personal automations arrived on Mac in Tahoe: triggers for time, alarm, email/message, folder/file changes, external drive, Wi-Fi, Bluetooth, display connect, Stage Manager on/off, app open/close, battery level, charger, focus; "Allow Running When Locked" + optional notify-when-run; "Use Model" action passes app entities into Apple Intelligence models | "When battery < 20% -> ask Coreography for top energy apps"; folder trigger into "drop a CSV -> chart it"; entity outputs feed Use Model |
| Control Center controls | `ControlWidget` (WidgetKit) on macOS 26: small/medium/large, in Control Center **and pinned on the menu bar**, from macOS/Catalyst/iOS-sourced apps | Toggle HUD, pause sampling, one-tap recording; menu-bar control doubles as a compact always-visible surface |
| Desktop widgets | WidgetKit widgets on desktop/NC, Tahoe adds accented/tinted rendering and iPhone Live Activities in the menu bar; **system controls refresh cadence: periodic timelines, not per-second** | Good for slow metrics (battery health, uptime, daily energy); wrong surface for live graphs. MacPulse says it plainly: "macOS controls WidgetKit refresh timing, so desktop widgets update periodically rather than every second" |
| CLI companion | Convention: `lms` (LM Studio, bootstraps from `~/.lmstudio/bin`), macmon `pipe`/`serve` JSON+Prometheus, StatBar `--once` snapshot | A `coreography` CLI that streams the same engine's samples as JSON is both a power feature and the cheapest MCP backend |
| URL scheme | Convention: Things `things:///json` writes gated by an opt-in auth token in settings; reads unauthenticated | `coreography://` for open-pane/deep-link + scripted capture; auth-token for anything stateful |
| Local MCP server | 2025-2026 trend made concrete: DEVONthink 4.3 ships a built-in MCP server (~60 commands, bearer token, redaction, per-item "Exclude from Chat & MCP", menu-bar icon while serving); third-party servers already bridge apps that lack one (things3-mcp: SQLite read + URL-scheme/AppleScript writes, stdio or HTTP+OAuth over Tailscale) | Read tools over the history store are a natural MCP fit: "what was using CPU at 3am" is exactly the question users now ask an agent |

App Intents specifics worth noting from WWDC25: App Entities are the nouns,
App Intents the verbs; donating entities to Spotlight (`IndexedEntity`,
`indexingKey` for property->Spotlight-key mapping) is what makes
Spotlight's action parameters completable; the "Use Model" Shortcuts action
can consume your entities directly and filter them with Apple
Intelligence. All of this is documented for macOS 26.

## Privacy and security of a local history store

### What monitor history reveals

A long-history monitor records a behavioral fingerprint: process names and
paths (which apps, when), focused-app timelines (what you were doing at
each hour), network endpoints and volumes (Little Snitch territory:
where you connect), sleep/wake cycles (when you're home and asleep),
per-app energy (what work costs you). Little Snitch's own docs call this
out directly: "you may live in a country where visiting certain websites
can get you into trouble and you don't want any traces to be stored";
hence its hiding rules. The same argument applies, weaker but real, to a
CPU/process history.

### What the reference apps do

- **Little Snitch**: traffic history is stored encrypted under
  `/Library/Application Support/Objective Development/Little Snitch` in an
  "encrypted proprietary format" (`configuration6.xpl`); the key lives in
  the System keychain as "Little Snitch Encryption Key", so an encrypted
  backup must also carry that keychain entry. Retention is explicit: up to
  1 year, default 50,000 distinct connections, raisable to 200,000;
  exceeding the cap shrinks the retained window rather than growing
  unbounded. **Rules to Hide Connections** collapse matching flows into a
  single anonymous "Hidden Connections" row: redaction at collection time,
  not at export. The geolocation database is stored locally specifically so
  lookups don't leak visited servers to a provider; Research Assistant
  sends connection properties upstream only on an explicit click. Export
  format `.lsbackup` is unencrypted JSON, excludes traffic history, and
  carries a warning that an attacker could learn the rule set.
- **iStat Menus**: client-side, no analytics; ~30 days of history kept
  across restarts; deliberately **doesn't record while asleep**, shown as
  honest gaps in graphs, the same measurement-contract behavior as
  leaving a gap rather than fabricating.
- **PerformanceHUD**: no readings leave the machine; CSV logging is
  opt-in per session, one row/sec, process names included only if the user
  explicitly enabled Misc → Process before logging (PIDs never); a
  recovery CSV under `~/Library/Application Support/.../Logs/` is cleaned
  up after a successful Desktop save; Sparkle system profiling disabled.
- **TMOG**: no telemetry (notes 06).
- **DEVONthink's MCP server** is the adjacent precedent for exposing app
  data to agents: bearer token, local/remote access controls, redaction of
  phone numbers/credit cards/tokens before data leaves, per-item and
  per-database "Exclude from Chat & MCP" (auto-on for encrypted DBs), and a
  menu-bar icon whenever the server is live.

### Mechanisms available on macOS

- `URLResourceValues.isExcludedFromBackup` / `NSURLIsExcludedFromBackupKey`
  marks a file or directory out of Time Machine (and iCloud) backups. Apple
  frames it as guidance, not a guarantee, and (easy to miss) **excluded
  items still appear in Time Machine local snapshots**. Prefer putting the
  store in a dedicated directory and marking the directory. Older
  `CSBackupSetItemExcluded` is the deprecated equivalent.
- **Data Protection classes**: on Apple Silicon Macs the hybrid model
  applies: Class D doesn't exist, Class C (default for third-party app
  data) uses the FileVault volume key and protects at rest; Class A
  (`NSFileProtectionComplete`) and B (`UnlessOpen`) exist on macOS but the
  boundary is **log-out, not lock**: the decrypted class key is discarded
  "shortly after the last user is logged out". Useful against cold
  attacks/multi-user machines; not a lock-screen defense. For non-booted
  volumes, all classes are accessible while mounted.
- At-rest story is therefore: FileVault for everyone; Data Protection class
  for log-out boundaries; an app-level encrypted store with a keychain-held
  key (Little Snitch's pattern) deters casual inspection and backup
  snooping but is not proof against an active admin: whether an admin can
  recover the key depends on the keychain item's access controls and
  unlock state. Use `0700` for the store directory and `0600` for its files.
- Retention controls to copy: a hard cap (count or bytes) plus a time cap,
  redaction-at-ingest rules for sensitive series (process names, window
  titles if ever collected, network endpoints), and exports that either
  exclude the identifying columns or carry an explicit warning, mirroring
  `.lsbackup`'s "unencrypted, excludes traffic history" design.

## Implications for Coreography

- **Ship the HUD, don't fear it.** The recipe is proven end-to-end in
  shipping code (PerformanceHUD's repo is effectively a reference
  implementation): NSPanel + `.nonactivatingPanel` + `.screenSaver`
  + `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
  + `.accessory` policy + `ignoresMouseEvents` toggled by a modifier-drag
  affordance. The `.accessory` policy is what the HUD-only reference apps
  run; it binds the process hosting the panel, so a dashboard app that
  keeps a Dock presence would host the HUD from an accessory helper
  rather than change the whole app's policy. Design it as a density level of the same engine (P16/P17),
  with `constrainFrameRect` overridden for true edge placement.
- **Set expectations on fullscreen explicitly.** The reference app
  reports windowed/borderless support and conditional fullscreen support,
  including scaling and resolution caveats. Those are vendor observations,
  not guarantees for Coreography; publish the configurations validated by
  its own S6 matrix and offer a size override.
- **`metalperftrace listen --json --pid` is the focused-app FPS source on
  27**: NDJSON at 1 s, fields as parsed above; set `NSUnbufferedIO=YES`,
  drain stderr, mark stale after ~3 s, derive GPU busy percent as
  `100 * gpuWalltimeMilliseconds / (activeSeconds * 1000)` for positive
  active time. It is an interval-summary
  stream: for frame-time graphs and 1% lows, plan a separate path through
  `collect`/`overview --json-include-timeline` or `per-frame-metrics`
  signposts. Use `setup --enable hud --pid` to offer "Apple's HUD" as a
  complementary toggle. Pre-27 fallback
  stays the notes-09 path. Budget for a privileged-optional `powermetrics`
  helper the way PerformanceHUD's PowerHelper does (fixed command, signing
  checks, idle when unused).
- **Don't promise capture-invisibility.** `sharingType = .none` is a
  legacy-only partial measure on macOS 15+; if it ships, label it
  "excluded from some window lists and capture paths", not "hidden from
  screenshots or screen recording" (exclusion is not guaranteed across
  tools), and treat ScreenCaptureKit exposure as a documented limitation.
- **The sleep story is a first-class feature at low privilege cost.**
  Build a "night timeline" from `pmset -g log` joined to the app's own
  battery samples: Sleep/DarkWake/Wake segments with reasons, charge deltas
  per segment, and assertion records where logs or prior collection
  retained them. `AssertionOnBehalfOfPID` helps attribute live assertions,
  but current PID ownership must not be projected across sleep or PID
  reuse. Ship
  `IOPMCopyAssertionsByProcess` as a live "what's keeping your Mac awake"
  card. This is the cheapest "why did my battery die overnight" answer on
  the platform (per-app attribution inferential, not certain), and it
  reinforces the honest-availability contract (log
  gaps are gaps).
- **AI workload card: report the real layers.** Per-process "GPU memory" =
  the footprint IOAccelerator share where a footprint/vmmap-class
  breakdown is available, labelled as such (the footprint total alone is
  not GPU-only, and shared unified memory is not additive across
  processes); device total from
  `PerformanceStatistics`. Show the wired-memory setting and Metal's
  recommended working set as separately sourced budgets where available,
  without assuming equality or treating either as measured free VRAM.
  Poll Ollama `/api/ps`, `lms ps --json`, llama-server `--metrics` for
  named-model attribution. A monitor that can say "ollama: gemma4, 5.3 GB
  in GPU memory, unloads at 16:47" beats every competitor's "Memory:
  yellow". ANE activity can't name the model; label it "Neural Engine
  busy" and fold `generativeexperiencesd`/`siriinferenced` into a labelled
  Apple Intelligence group.
- **Automation is a cheap moat.** App Intents (entities: metric, process,
  time range; actions: start/stop capture, toggle HUD) get Spotlight
  execution and Shortcuts automation for free on 26. A Control Center/menu
  bar `ControlWidget` toggle is a second always-visible surface with a
  fraction of a custom MenuBarExtra's cost. Desktop widgets are for slow
  data only (WidgetKit refresh is system-throttled). A bundled `coreography`
  CLI streaming engine samples as JSON, plus an opt-in local MCP server
  over the history store with bearer token and redaction, positions the
  app for the "ask my Mac" workflows users already expect from
  DEVONthink-class apps. Keep MCP read-only at first.
- **Design the history store as a disclosure.** Defaults: dedicated
  directory under `~/Library/Application Support` marked
  `isExcludedFromBackup` (knowing local snapshots still carry it), `0600`
  perms, retention = time cap AND count cap, redaction-at-ingest rules for
  process names/endpoints, exports that either strip identifying columns
  or warn like `.lsbackup` does. If real confidentiality is a goal, the
  Little Snitch pattern (app-encrypted store, key in System keychain) is
  proven; price it as complexity vs. threat model. Document all of it in
  a privacy page like PerformanceHUD's: it doubles as marketing.

## Sources

- [Apple Developer Forums thread 826308 - overlay window above fullscreen apps](https://developer.apple.com/forums/thread/826308) - activation policy `.accessory`, NSPanel `.nonactivatingPanel`, `.screenSaver` level, collectionBehavior recipe
- [Stack Overflow - NSPanel floating above full-screen apps](https://stackoverflow.com/questions/36205834/allow-an-nswindow-nspanel-to-float-above-full-screen-apps) - `.mainMenu` level + `fullScreenAuxiliary` working combination
- [Stack Overflow - programmatic NSWindow over fullscreen](https://stackoverflow.com/questions/58934673/why-does-my-nswindow-not-float-above-full-screen-apps-when-created-programmatica) - `.borderless` style mask fix
- [zzoko/PerformanceHUD](https://github.com/zzoko/PerformanceHUD), [HUDPanel.swift](https://raw.githubusercontent.com/zzoko/PerformanceHUD/main/PerformanceHUD/HUDPanel.swift), [HUDWindowController.swift](https://raw.githubusercontent.com/zzoko/PerformanceHUD/main/PerformanceHUD/HUDWindowController.swift), [HUDStyle.swift](https://raw.githubusercontent.com/zzoko/PerformanceHUD/main/PerformanceHUD/HUDStyle.swift), [MetalPerfTraceMonitor.swift](https://raw.githubusercontent.com/zzoko/PerformanceHUD/main/PerformanceHUD/MetalPerfTraceMonitor.swift), [GameModeMonitor.swift](https://raw.githubusercontent.com/zzoko/PerformanceHUD/main/PerformanceHUD/GameModeMonitor.swift) - shipping HUD implementation, metalperftrace JSON parsing, game-mode notification
- [PerformanceHUD Privacy & access](https://raw.githubusercontent.com/zzoko/PerformanceHUD/main/docs/PRIVACY_AND_ACCESS.md) - glass FPS-cap workaround, helper design, CSV logging rules
- [PerformanceHUD vs Metal HUD](https://raw.githubusercontent.com/zzoko/PerformanceHUD/main/docs/METAL_HUD_COMPARISON.md) - display compatibility caveats
- [metaspartan/mactop overlay.m](https://raw.githubusercontent.com/metaspartan/mactop/main/internal/app/overlay.m) - NSStatusWindowLevel+1 interactive overlay, same collectionBehavior
- [Apple dev forums 792152 - sharingType none and ScreenCaptureKit on 15.4+](https://developer.apple.com/forums/thread/792152) - "no public APIs for preventing screen capture"
- [Apple dev forums 808016 - SCK and NSWindowSharingNone inconsistency](https://developer.apple.com/forums/thread/808016)
- [tauri-apps/tauri issue 14200](https://github.com/tauri-apps/tauri/issues/14200) - macOS 15+ ignores sharingType/content-protection
- [metalperftrace(1) man page, macOS 27.0](https://raw.githubusercontent.com/vitorgalvao/macos-man-pages/main/macOS/27/man1/metalperftrace.1) - listen/collect/overview/setup options, NDJSON
- [Keith's xcode-man-pages: MetalPerformanceHUD(1)](https://keith.github.io/xcode-man-pages/MetalPerformanceHUD.1.html) - always-on recording, setup --enable hud
- [WWDC26 session 388 - Find and fix performance issues in your Metal games](https://developer.apple.com/videos/play/wwdc2026/388/) - collect/overview --json, look-back hours
- [Folivora forum - pinning windows with Stage Manager](https://community.folivora.ai/t/pinning-windows-on-top-doesnt-work-with-stage-manager-turned-on/29804), [Eclectic Light - Stage Manager for the unimpressed](https://eclecticlight.co/2023/01/17/stage-manager-for-the-unimpressed-3-apps-and-windows/) - floating-window wrinkles under Stage Manager
- [MacMost - Keep a note on top / Stage Manager behavior](https://macmost.com/keeping-a-note-on-top-in-the-mac-notes-app.html)
- [LOOBins - pmset](https://loobins.io/binaries/pmset/) - read side unprivileged, writes need root
- [pmset log sample (fastred gist)](https://gist.github.com/fastred/22f9120bb562a02a40c03354cc02d841), [cole-gillespie pmset README](https://github.com/shuhblam/pmset/blob/master/README.md), [gabrielecirulli gist](https://gist.github.com/gabrielecirulli/34462c195d703a577f23a80c3fc9dd28) - Sleep/DarkWake/Wake line formats and reasons
- [Apple Support - pmset options list (sudo.is mirror)](https://www.sudo.is/docs/macos/) - `-g` getters incl. assertionslog, stats, uuid, pslog, thermlog
- [Apple Docs - IOPMCopyAssertionsByProcess](https://developer.apple.com/documentation/iokit/1557130-iopmcopyassertionsbyprocess)
- [mahui.me - What's Keeping My Mac Awake](https://mahui.me/en/blog/mtinker-who-blocks-sleep/) - AssertionTrueType, OnBehalfOfPID, timeout and daemon attribution traps
- [QA1340 - sleep/wake notifications](https://developer.apple.com/library/archive/qa/qa1340/_index.html), [IOKitUser IOPMLib.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h) - message lifecycle, PreventSystemSleep dark-wake preference
- [Apple dev forums 15736 - DarkWake notification suppression](https://developer.apple.com/forums/thread/15736)
- [apple-oss-distributions PowerManagement PrivateLib.h](https://github.com/apple-oss-distributions/PowerManagement/blob/e7753e03/pmconfigd/PrivateLib.h) - powerd unified-log categories, wake-type enum
- [Sleep Aid](https://ohanaware.com/sleepaid/), [version history](https://ohanaware.com/sleepaid/versionHistory.html), [launch post](https://ohanaware.com/blog/202226/Sleep-Aid-Launch.html) - calendar timeline, insomnia detection, wake reasons, admin requirement
- [Eclectic Light - sleep/wake in the unified log](https://eclecticlight.co/2017/06/16/exploring-sierra-10-12-5-sleep-and-wake-in-the-log-2-das-and-cts/) - DAS/CTS dark-wake log markers
- [MLX docs - mlx.core.set_wired_limit](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.set_wired_limit.html) - wired limit semantics, sysctl
- [llama-skein macOS MLX notes](https://github.com/androidand/llama-skein/blob/main/docs/macos-mlx.md) - ~70% default ceiling, runtime-only sysctl
- [llmconfigurator - raising the Metal VRAM ceiling](https://llmconfigurator.com/en/guides/troubleshooting/increase-metal-vram-limit-apple-silicon) - `debug.iogpu.wired_limit` legacy key, silent-failure trap
- [Liquid pipette-mgmt - peak memory on macOS](https://github.com/Liquid4All/pipette-mgmt/blob/main/docs/methodology/peak-memory-macos.md) - no external per-process Metal query; currentAllocatedSize shim
- [jundot/omlx proc_memory.py](https://github.com/jundot/omlx/blob/a86a5587/omlx/utils/proc_memory.py) - phys_footprint includes IOAccelerator, jetsam ledger
- [docs.jacobpevans.com - local-llm memory ceilings](https://docs.jacobpevans.com/local-llm/memory-ceilings) - third-party budget and unit observations, not an API guarantee equating the two limits
- [MetalHUDmenu](https://github.com/Jfishin/MetalHUDmenu) - menu bar Metal HUD configurator on macOS 26
- [ml-explore/mlx issue 3896](https://github.com/ml-explore/mlx/issues/3896) - get_peak_memory vs phys_footprint, allocator pool retention
- [Ollama docs - /api/ps](https://docs.ollama.com/api/ps), [openapi.yaml](https://github.com/ollama/ollama/blob/main/docs/openapi.yaml) - size_vram, context_length, expires_at
- [LM Studio lms CLI](https://lmstudio.ai/docs/cli), [lms ps](https://lmstudio.ai/docs/cli/local-models/ps), [lms load](https://lmstudio.ai/docs/cli/local-models/load) - `lms ps --json`, estimate-only, TTL, daemon
- [StatBar](https://macstats.vercel.app/), [npm page](https://npm.io/package/statbar) - llama-server/Ollama/LM Studio telemetry fields
- [tstats.app](https://tstats.app/) - MLX process GPU-memory monitoring
- [caiovicentino/apple-silicon-internals](https://github.com/caiovicentino/apple-silicon-internals) - Apple Intelligence daemon/model mapping, MobileAsset path
- [Apple ML - Foundation models](https://machinelearning.apple.com/research/introducing-apple-foundation-models) - ~3B on-device model + adapters
- [Tallyburn](https://github.com/seoulpro/tallyburn), [toki-monitor](https://github.com/korjwl1/toki-monitor) - token-usage trackers (adjacent category)
- [WWDC25 session 260 - Develop for Shortcuts and Spotlight with App Intents](https://developer.apple.com/videos/play/wwdc2025/260/) - Spotlight action execution, Use Model action
- [WWDC25 session 275 - Explore new advances in App Intents](https://developer.apple.com/videos/play/wwdc2025/275/) - IndexedEntity, indexingKey, interactive snippets
- [WWDC25 session 278 - What's new in widgets](https://developer.apple.com/videos/play/wwdc2025/278/) - controls in Control Center and menu bar on macOS, accented rendering, Live Activities
- [WidgetKit macOS 26.0 API diff](https://sdkdiffs.furnacecreek.org/macos-26.0/WidgetKit.html) - ControlWidget present in macOS 26 SDK
- [Apple Support - What's new in Shortcuts 26](https://support.apple.com/en-us/125148), [Add automations on Mac](https://support.apple.com/guide/shortcuts-mac/add-automations-apdfbdbd7123/mac) - Mac automation triggers, run-locked option
- [Six Colors - folder automation in Tahoe](https://sixcolors.com/post/2025/08/get-started-with-folder-automation-in-macos-tahoe/), [MacStories Tahoe review](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/4/) - automation UX in practice
- [DEVONthink MCP server announcement](https://devontechnologies.com/blog/20260526-devonthink-mcp-server), [DEVONthink 4.3 forum post](https://discourse.devontechnologies.com/t/devonthink-4-3-herschel/86958) - ~60 commands, redaction, exclude-from-MCP, bearer token
- [SeanMatthewAI/things3-mcp](https://github.com/SeanMatthewAI/things3-mcp), [things-mcp crate](https://docs.rs/crate/things-mcp/latest/source/README.md) - URL scheme + AppleScript + SQLite bridge pattern, things:/// auth token
- [kemalandic/edgecontrol](https://github.com/kemalandic/edgecontrol), [vluncasu/macpulse](https://github.com/vluncasu/macpulse), [haqaliz/deck](https://github.com/haqaliz/deck), [filiphajduch420/Vitals](https://github.com/filiphajduch420/Vitals) - shipping monitor desktop widgets; WidgetKit refresh is periodic
- [Little Snitch help - connection list](https://help.obdev.at/de/littlesnitch6/lsm-connection-list) - 1 year / 50k-200k limits, Rules to Hide Connections
- [Little Snitch - settings/network monitor](https://developer.obdev.at/littlesnitch6/pref-monitor) - capacity semantics, local geolocation DB
- [Little Snitch - backup and restore](https://help.obdev.at/littlesnitch6/lsc-backup), [uninstall](https://developer.obdev.at/littlesnitch6/intro-uninstall) - encrypted store, keychain key, unencrypted .lsbackup excluding history
- [iStat Menus privacy](https://bjango.com/help/istatmenus7/privacy/), [history graphs](https://bjango.com/help/istatmenus7/historygraphs/) - client-side, no sleep recording, gaps
- [Apple Docs - isExcludedFromBackupKey](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey), [iCloud backup optimization](https://apple-docs.everest.mt/docs/foundation/optimizing-your-app-s-data-for-icloud-backup/) - guidance semantics
- [Apple Support - exclude files from Time Machine](https://support.apple.com/guide/mac-help/exclude-files-from-a-time-machine-backup-mh15622/mac) - local-snapshot caveat
- [Apple Platform Security - Data Protection classes](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web), [FileVault](https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web), [encryption overview](https://support.apple.com/guide/security/encryption-and-data-protection-overview-sece3bee0835/web) - macOS hybrid model, log-out boundary, Class C default
- [Apple Developer - protecting data at multiple layers](https://developer.apple.com/news/?id=3xpv8r2m) - per-file classes on Apple Silicon Macs

Unverified leads (all unverified): Stage Manager's exact treatment of
`.canJoinAllSpaces` HUDs at `.screenSaver` level (mechanism suggests it
follows Quick Note behavior; forum evidence is anecdotal); whether
`sharingType = .none` still hides HUDs from specific third-party capture
tools on macOS 26/27 (documented against ScreenCaptureKit only); the
dark-wake notification-suppression scope on macOS 27 (documented in
older threads); Sleep Aid's internal data sources (admin-account
requirement suggests log access, mechanism not published); exact
`NSWindow.Level` needed to sit above fullscreen video-mode scanout on
each compatibility layer.

## Verification log

Independent fact-check pass, 2026-10-17. Scope: decision-relevant claims
re-checked against primary sources (shipping code, man pages, vendor
docs). This was a source review only; no claims were validated at
runtime on real hardware.

Confirmed against primary sources:

- PerformanceHUD window recipe verified in code: `HUDPanel` is an
  `NSPanel` created with `[.borderless, .nonactivatingPanel]`
  (`HUDWindowController.init`), `canBecomeKey`/`canBecomeMain` false,
  `constrainFrameRect` override for edge placement, `isOpaque=false`,
  `backgroundColor=.clear`, `hasShadow=false`, `level =
  HUDStyle.windowLevel` = `.screenSaver`, `collectionBehavior =
  [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
  .ignoresCycle]`, `ignoresMouseEvents=true` toggled by an 80 ms
  modifier-flags poll (`HUDPanel.swift`), top-left position anchoring.
- mactop `overlay.m` verified: borderless `NSWindow` subclass,
  `canBecomeKeyWindow`/`canBecomeMainWindow` = NO, `NSStatusWindowLevel
  + 1`, same four collectionBehavior flags, `ignoresMouseEvents = NO`,
  `orderFrontRegardless`, top-left of `mainScreen.visibleFrame` + 16 pt.
- `metalperftrace(1)` man page (macOS 27.0) verified: `listen --json`
  emits NDJSON (single-line objects; `--output` file rewritten as a
  pretty array on SIGINT/SIGTERM/SIGHUP), `--interval` minimum and
  default 1.0 s; `setup` requires `--pid` and supports `hud`,
  `per-frame-metrics`, `shader-compiler-metrics`; per-frame timeline
  data is only in `overview --json-include-timeline` on a `collect`ed
  trace.
- `MetalPerfTraceMonitor.swift` verified: `listen --json --pid
  --interval 1`, `NSUnbufferedIO=YES`, stderr drained, samples stale
  after 3 s; parser reads `PID`, `Layers[].Configuration`, `Performance
  Stats`/`Presented Frame Stats` (`FPS`, `On-GPU Walltime Stats.Total
  (ms)`), `Time Active (sec)`; GPU busy percent is
  `100 * Total / (TimeActive * 1000)`
  clamped 0-100; largest-area layer wins.
- `GameModeMonitor.swift` verified: `com.apple.system
  .game_mode_status_changed` Darwin notification, 0/1/2 = off/on/paused,
  undocumented contract, read-only.
- PerformanceHUD README/PRIVACY_AND_ACCESS/METAL_HUD_COMPARISON verified:
  display-compat matrix (windowed universal; native fullscreen
  "generally works" with UI-scale caveat and 0.5x-2x override;
  CrossOver fullscreen only at matching "looks like"/2x resolutions);
  CSV logging opt-in, 1 row/s, process names only via Misc->Process,
  no PIDs, recovery CSV in Application Support; powermetrics helper is
  fixed-command, signing-checked, idle when unused; display-refresh
  listener exists to work around an observed game FPS cap with native
  glass and uses an unsupported interface.

Corrections applied in this pass:

- Clarified that `listen` emits per-interval summaries, not raw frame
  times; 1% lows/frame-time percentiles need `collect` +
  `overview --json-include-timeline` or `per-frame-metrics` (added to
  summary, listen section, and implications).
- Flagged that focused-app GPU busy "may exclude the app's helper
  processes" (PerformanceHUD privacy doc), so it is per-process, not
  whole-app.
- Relabelled Stray/Minecraft and RDR2/Requiem fullscreen results as
  vendor-confirmed (PerformanceHUD's own testing), not independent
  measurement.
- Scoped the Liquid Glass FPS-cap caveat correctly: the doc says an
  "observed game FPS cap", not specifically fullscreen games.
- Softened "a solved recipe" to "a proven recipe with known limits".
- Stated explicitly that root does not lift unified-log `<private>`
  redaction (profile-gated) and does not bypass TCC/SIP.
- Added "process presence is not inference" caveat to the Apple
  Intelligence daemon paragraph, and a note that Vitals advertises
  per-app ANE attribution (mechanism unpublished, unverified).
- Softened the Little Snitch keychain claim: encrypted store +
  System-keychain key deters casual inspection but is not proof against
  an active admin (root can recover the key).
- Removed the unverified "53-commit" repo characterization.
- Review follow-up: corrected the missing percent conversion against
  `MetalPerfTraceMonitor.swift` (`milliseconds / (seconds * 1000) * 100`)
  and clarified the separate system/display sleep assertions.

Remaining gaps (not re-verified or unverifiable from sources):

- All Stage Manager, dark-wake-notification-scope, and compatibility-
  layer entries under "Unverified leads" above still stand.
- `pmset -g log` "about 14 days" retention is empirical, not a
  documented guarantee.
- GPU-wired-memory defaults are report-sourced and the sysctl is
  undocumented. Its relationship to Metal's recommended working set
  requires per-device/OS validation, not a fixed percentage formula.
- Apple Intelligence daemon mapping rests on one third-party teardown
  (caiovicentino/apple-silicon-internals), not Apple documentation.
- WWDC26 session 388 and dev-forum thread content were taken as cited;
  forum posts are anecdotal evidence, not API commitments.
- No runtime validation: nothing above was executed on macOS 26/27.
