# Process explanation, maintenance states, sub-app attribution, CPU conventions, VMs and containers (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

Covers five gaps left by the earlier surveys: how tools explain what a
process is and whether it is safe to quit; how to detect and present
macOS maintenance work as named states; how far below the app boundary a
Developer ID monitor can attribute load (browser tabs, helpers); the
CPU% conventions other tools use; and how VMs and containers appear on
the host. Process enumeration mechanics (KERN_PROCARGS2,
`responsibility_get_pid_responsible_for_pid`, coalitions, the same-uid
wall) are covered in [notes 10](10-macos-data-sources-processes-memory-io-privileges.md)
and are referenced, not repeated, here.

## Summary

- Process explanation is a live feature category in 2026: TaskExplorer 3
  ships an AI assistant that queries its live process data on-device via
  Apple Intelligence (or a BYO Claude/ChatGPT key, or local Ollama);
  MacStats sells a cloud-backed "AI Process Explainer" with a monthly
  allowance; WhySlow and SystemWatch ship curated offline catalogs
  (85 and 110 entries respectively, verified on their sites) with
  "safe to quit" verdicts.
- The highest-leverage, lowest-risk design is the curated knowledge
  base: every common noisy daemon has a one-line man page or a
  well-documented role, and maintenance daemons carry machine-readable
  scheduling hints in their launchd plists (ProcessType, power and
  maintenance keys) that an app can read offline.
- Apple daemon coverage in man pages is incomplete: `mds`, `cloudd`,
  `bird`, `backupd`, `fileproviderd`, `softwareupdated` and
  `photoanalysisd` have man pages; newer or undocumented services
  (`mediaanalysisd`, `mds_stores`, `corespotlightd`) were not found on
  the consulted man-page mirror.
- Maintenance states are detectable without privilege: process presence
  plus tool status (`tmutil status` gives a full plist with phase,
  percent and time remaining (real progress); `mdutil -s` gives only
  per-volume indexing *enabled* state, not whether indexing is running)
  and launchd scheduling keys tell the user "plug in and wait"
  instead of "a process is misbehaving." Caveat: a running daemon proves
  residency, not active work: presence must be paired with a CPU/IO
  burst or a real status tool before declaring the state active.
- Sub-app attribution is sharply limited. Safari WebContent rows carry
  a registrable domain in their Launch Services display name and
  Activity Monitor's tooltip lists hosted URLs. Chrome/Electron helpers
  use role flags such as `--type=renderer`; Firefox content processes use
  `-contentproc`. These do not provide a reliable PID-to-tab mapping.
  Browser-owned task views and optional Automation access offer different
  levels of detail; neither should be guessed from a generic helper name.
- CPU% has three live conventions: Irix (sum of per-core percentages,
  can exceed 100%), Solaris (share of all cores, max 100%), and now
  Windows Task Manager's 2025 unified formula
  ΔCPU-time ÷ (Δelapsed × logical processors). On Apple Silicon a fixed
  percentage ignores both which cluster ran the work and at what
  frequency; Eclectic Light measured a 3.4x speed difference at
  identical reported %CPU.
- VMs and containers appear as ordinary host processes
  (`com.apple.Virtualization.VirtualMachine`, `prl_vm_app`,
  `container-runtime-linux`, `qemu-system-*`, `com.docker.backend`), so
  their cost is attributable but their interior is not: guest-side
  breakdown requires a vendor API (docker stats, `container stats`,
  OrbStack's `orb top`, guest agents).
- Nothing surveyed combines all of this; the closest is SystemWatch,
  which labels `mds*` as "Spotlight indexing" and shows how long the
  state ran, and WhySlow's per-process verdict format
  ("Leave it - runs while plugged in").

## Explaining processes: what is this process and is it safe to quit

### Windows Task Manager: "Search online"

Windows Task Manager's answer to "what is this process" is a context
menu item. Right-clicking a process on the Processes or Details pages,
or an entry on the Services and Startup apps pages, offers
**Search online**, which opens the default browser with a search for
the process name. That is the entire feature: no local description, no
safety verdict, just a web search launched from the row. The Neowin
tour of the redesigned Task Manager (Dev build 22557) shows it moved to
the three-dot menu on those pages. The pattern matters because it is
the incumbent baseline: the OS ships a lookup verb, not an answer.

### Process Explorer: self-reported metadata plus signature proof

Process Explorer attacks the same question with columns rather than
search:

- **Description** and **Company Name** are read from the executable's
  version resource, i.e. self-reported strings. Russinovich's malware
  hunting deck notes most malware has no version info, and that a
  fake "Microsoft" company string is exactly what the next column is
  for.
- **Verified Signer** validates the image signature against a trusted
  root; verification touches CRL servers over the network. The process
  properties dialog renders the result inline as `(Verified) <subject>`,
  `(Not verified) <name>`, or `(Unable to verify)`.
- **VirusTotal** submits file hashes and shows a detection ratio column;
  unknown files can be uploaded for scanning (opt-in).
- **Search Online** exists in the process menu too, for anything the
  columns do not resolve.

The design lesson: cheap self-reported claims get an identity column,
and the identity column gets a cryptographic check. On macOS the
equivalents are the bundle's `CFBundleName`/copyright strings, the
signature's Team ID and `anchor apple` status, and notarization state.

### TaskExplorer 3 (Objective-See): the AI assistant pattern

TaskExplorer 3.0 (2026, macOS 14+, free and open-source) is a near-complete rewrite on
Apple's Endpoint Security framework with a system extension plus Full
Disk Access, so it sees every process, dylib, file and connection live.
Its headline feature is a built-in AI assistant in a sidebar:

- Providers: **Apple Intelligence on-device via the Foundation Models
  framework is the default where available** (requires macOS 26 with
  Apple Intelligence enabled, Apple silicon only); alternates are the
  user's own Anthropic or OpenAI API key, and (in 3.1) a local Ollama
  model. With Apple Intelligence there is no account and no key, and
  nothing leaves the Mac.
- The assistant is wired to tools that query TaskExplorer's live data
  (processes, dylibs, files, connections, VirusTotal results, the
  `#keyword` filters) and to a few that drive the UI (select a process,
  set a filter, switch pane). Example prompts: "what's listening on the
  network?", "which processes are ad-hoc signed?"
- Limits are stated plainly: the on-device model is small and works
  best with focused questions; long lists are paged ("showing 30 of
  62"); for exhaustive listing use the filter field instead.
- Injection posture: the docs note process names, paths and arguments
  are controlled by whoever started the process, that the assistant is
  instructed to treat them as untrusted data and never as instructions,
  and that it only changes the UI when the user asks. Answers are
  framed as "a starting point for your own investigation, not a
  verdict."
- Its process list already shows a per-process signing status
  (Apple, Developer ID, ad-hoc, unsigned) and VirusTotal result, with
  flagged rows in red and `#flagged`/`#unknown`/`#adhoc`/`#3rdparty`
  filter tokens.

### MacStats: cloud-backed per-process explainer

MacStats (menu bar monitor, first public release June 2026, at 1.0.6 in
September 2026; macOS 13+, Apple silicon) sells an **AI Process
Explainer** on its Pro licence:

- Explanations are the paid feature: Pro is a one-time $14.99 licence
  (not a subscription, per the pricing page) that "adds the
  plain-English explanations"; new licences include 300 AI explanations
  a month, and a monthly allowance meter in Settings (added in 1.0.5)
  shows used, remaining and the reset date.
- Generation is server-side, not on-device: per its privacy policy a
  request sends the process name plus limited diagnostic context (CPU,
  memory, uptime, Mac model, OS/app versions, thermal/memory state) to
  the MacStats API and its configured AI provider, and the context plus
  returned explanation may be stored linked to the licence "to check
  the quality of the explanations". Any claim that descriptions are
  shared or cached across users is unverified: the public pages do not
  say that.
- Related AI surface area: proactive alerts when a process sustains
  high CPU or memory, a "Diagnose My Mac" one-click analysis, baseline
  anomaly detection, weekly health report, and incident recording with
  a replay timeline.
- Early release hazard recorded in its own changelog: "AI Explainer no
  longer produces inaccurate descriptions for unknown processes": the
  hallucination failure mode of name-based explanation.

### Curated offline catalogs: WhySlow, SystemWatch, CoreGuard

Two 2026 indie Mac apps ship hand-written process catalogs, which
doubles as evidence that an offline KB is a viable product feature:

- **WhySlow** (€8, free explanation tier) publishes ~85 process guides
  grouped by symptom domain (Spotlight indexing, media analysis,
  iCloud sync, software updates, helpers, VMs, security agents). Each
  entry has a stable structure: what it is, why it gets busy, whether
  quitting is safe ("Leave it"), and what to do if it stays busy. Its
  `mediaanalysisd` entry is the model: verdict line "Leave it. Runs
  while plugged in", plus where the genuine binary lives
  (`/System/Library`, `/usr/libexec`) as a spoofing check.
- **SystemWatch** (CherryWave LLC, $5.99 launch price, $14.99 list)
  publishes ~110 entries, each tagged "Shown as" (e.g. `mds_stores` is
  shown as "Spotlight indexing") and "Safe to quit: No". It already
  folds related processes into one named maintenance state and pairs
  it with history ("History shows how long the indexing actually
  ran"), and it flags path mismatches (an `mds_stores` outside
  `/System/Library/Frameworks/CoreServices.framework` is suspicious).
- **CoreGuard** maintains a similar daemon explainer; its framing for
  `cloudd`-class processes is the useful one: when a sync daemon is
  busy, "the real question is which app's transfers it's carrying."

Outside apps, the standing public catalog is journalism: How-To Geek
ran a long series explaining individual Activity Monitor processes
(`cloudd`, `backupd`, `mdsworker`, `installd`, `WindowServer`, `blued`,
`launchd`, `opendirectoryd`, `powerd`, `coreauthd`, `configd`,
`mDNSResponder`, `UserEventAgent`, `nsurlstoraged`, `sandboxd`, ...),
and Apple Discussions, Apple.SE and MacRumors threads provide per-process
Q&A evidence.

### Knowledge-base raw materials on macOS itself

An offline KB for Apple processes can be built almost entirely from
artifacts already on the machine:

- **Man pages** exist for many Apple daemons and give one-line truths:
  `mds` "metadata server ... serves all clients of the metadata APIs,
  including Spotlight"; `cloudd` "system daemon backing the CloudKit
  feature"; `bird` "one of the system daemons backing the Documents in
  the Cloud feature"; `backupd` "the Time Machine backup daemon";
  `fileproviderd` "the daemon controlling the interaction between
  extensions and filecoordinationd"; `softwareupdated` "the main daemon
  responsible for running software updates"; `photoanalysisd` "handles
  background processing of photo libraries for Memories, People and
  scene or object based search". Coverage gaps confirmed:
  `mediaanalysisd`, `mds_stores` and `corespotlightd` returned 404 on
  the keith.github.io man-page mirror; that mirror is not exhaustive,
  so it is an absence there, not proof no man page ships anywhere.
  The fallback for those is the
  process path, plist label and forum-verified behavior.
- **Launchd plists** in `/System/Library/LaunchDaemons` and
  `LaunchAgents` carry scheduling class: `ProcessType`
  (Background/Adaptive/Interactive/Standard, where Background is
  throttled to protect the user experience per `launchd.plist(5)`),
  `LowPriorityIO`, `Nice`, `KeepAlive`, `EnablePressuredExit`.
  `com.apple.mediaanalysisd.plist` additionally carries the undocumented
  keys `RequiresExternalPower`, `Priority = Maintenance` and
  `ResourceIntensive` (observed on-disk per the MacRumors thread), which
  are exactly the "why does it only run plugged in" answer.
- **Code signature** classification: TaskExplorer's Apple / Developer
  ID / ad-hoc / unsigned quad, plus team ID on dylibs, is the complete
  trust taxonomy. The genuine-path check (Apple daemons live under
  `/System/Library` and `/usr/libexec`) is the cheap spoof detector
  both curated apps describe.
- **Info.plist** strings give names and versions but rarely
  descriptions; XPC service bundle names (e.g.
  `com.apple.WebKit.WebContent`) serve as stable KB keys.

### Apple's on-device Foundation Models framework

If Coreography adds generative explanation, this is the private,
key-free path:

- Access: `SystemLanguageModel` + `LanguageModelSession` (macOS 26+).
  `availability` reports `.available` or a reason
  (`deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`),
  so the feature must degrade gracefully; an app cannot trigger the
  model download or enable Apple Intelligence itself. On Macs this
  effectively means Apple silicon with Apple Intelligence turned on.
- The on-device model is approximately 3B parameters (Apple's
  foundation-models papers) with a **4096-token context window per
  session**, counting instructions, prompts, tool schemas and outputs,
  and responses together (TN3193). `tokenCount(for:)` and `contextSize`
  (backdeployed to macOS 26.0) expose accounting; Xcode ships a
  Foundation Models instrument.
- Built-in affordances that fit process explanation: guided generation
  (`@Generable`) for structured verdicts like
  `{role, safeToQuit, typicalCPU, advice}`, and tool calling so the
  model reads live rows rather than frozen text (TaskExplorer's exact
  approach).
- WWDC26 (macOS 27): a rebuilt on-device model with better tool
  calling, an optional Private Cloud Compute model with a 32,000-token
  context and reasoning levels, and a new `fm` command-line tool for
  scripting, handy for prototyping prompts against the real model.
- Tradeoffs for this use case: 4096 tokens fits "explain this one
  process with these live counters" comfortably but not a whole process
  table; a ~3B model will not know `corespotlightd`-tier trivia
  reliably, so it should explain *from* a KB entry rather than invent
  one (the MacStats bug above shows the failure mode); and answers are
  non-deterministic, which sits poorly next to an honest-measurement
  contract unless the verdict field is still driven by data.

## Maintenance activities as named states

The recurring "my Mac is slow" cause on macOS is a scheduled service,
not a rogue app. Each is detectable and each has an established answer
to "is this normal and when will it stop".

### Spotlight indexing

Processes: `mds` (metadata server), `mds_stores` (writes the per-volume
index stores under `/.Spotlight-V100`), `mdworker`/`mdworker_shared`
(import workers that extract file contents), `mdbulkimport`,
`mdflagwriter`, `corespotlightd` (app-donated CoreSpotlight content),
`managedcorespotlightd`, `spotlightknowledged`. Detection:
`mdutil -s <vol>` reports per-volume indexing *enabled* state ("Indexing
enabled." / "Indexing and searching disabled."). It does not report
whether indexing is actively running; `mdutil -E` triggers a
rebuild. In-progress indexing has no documented progress API; the
menu-bar Spotlight progress bar exists but does not cover all indexing
(Eclectic Light calls it unreliable), so practical detection is md*
process presence plus their CPU burst. Eclectic Light also documents
that the md* workers run almost exclusively on E cores on Apple
silicon (an observed scheduling bias from their QoS, not a placement
guarantee), which makes an E-cluster-heavy load signature a good
secondary signal. Triggers: post-update reindex, new volume, migration, damaged
index rebuild. SystemWatch already folds these into one labeled state
("Spotlight indexing") and SystemWatch/WhySlow give the same user
guidance: leave the Mac awake and plugged in; if busy for days, rebuild
with `sudo mdutil -E /`.

### Photos and media analysis

Processes: `photoanalysisd` (Faces/Memories/scene and object search
per its man page), `mediaanalysisd` (no man page; per curated catalogs
it performs the newer image/video analysis behind Live Text, Visual
Look Up and search), `photolibraryd` (library agent, "handles all
photo library requests"), plus `cloudphotod` on the iCloud Photos sync
side. Scheduling is the story: these are maintenance-priority jobs:
`com.apple.mediaanalysisd.plist` carries the undocumented
`RequiresExternalPower`, `Priority = Maintenance` and
`ResourceIntensive` keys (reported on-disk via the MacRumors thread,
not documented by Apple), and the
effective conditions reported are "connected to power, battery > 30%,
Photos closed, user idle" (photoanalysisd is suspended while Photos is
open). The correct product presentation is exactly WhySlow's:
"Leave it - runs while plugged in" and "expect a day or two after a
large import." Known pathologies worth a caveat row: mediaanalysisd's
cache under
`~/Library/Containers/com.apple.mediaanalysisd` growing unboundedly
(Apple Discussions reports 10+ GB), and rare battery runs despite the
power key (MacRumors p2). Disabling exists
(`launchctl disable gui/$UID/...`) but requires SIP gymnastics and is
not something a monitor should offer.

### Time Machine

Processes: `backupd` (creates backups, manages history per its man
page), `backupd-helper` (schedules/initiates). Detection is the best in
this list: `tmutil status` emits a parseable plist with `Running`,
`BackupPhase` (e.g. `Copying`), `DestinationMountPoint`, and a
`Progress` dictionary holding `Percent`, `bytes`/`totalBytes`,
`files`/`totalFiles` and `TimeRemaining`; `tmutil currentphase` is a
cheaper phase-only probe. A monitor can therefore show "Time Machine:
copying, 46%, ~40 min left" verbatim rather than "backupd is at 40%
CPU." Note the process-presence caveat from Apple.SE: `backupd` only
appears in `tmutil status` output detail while a session is active,
and snapshot thinning is a separate `backupd-helper` path.

### iCloud and File Provider sync

Processes: `bird` (Documents in the Cloud daemon), `cloudd` (CloudKit
backend; most app iCloud data flows through it, not bird),
`fileproviderd` (FileProvider broker for iCloud Drive plus third-party
providers (Dropbox, OneDrive, Google Drive, Box), including dataless
file materialization), `nsurlsessiond` (background downloads),
`cloudphotod` (iCloud Photos). No public progress API; user-facing
evidence is process activity plus `brctl log -w`/`brctl diagnose` for
the iCloud Drive side and the FileProvider SQLite store under
`~/Library/Application Support/FileProvider/<uuid>/`. The sync wave
is a recognizable signature: `bird` sync-up/sync-down phases plus
`fileproviderd` and `cloudd` work together (Eclectic Light's Sonoma
walkthrough), often alongside `photoanalysisd`-class jobs. Forum
evidence confirms users see it as "fileproviderd high CPU" and the
correct advice is usually "let it finish"; the failure modes worth
naming are a stuck file retried in a loop (visible via `brctl`) and a
third-party provider's database issue (the Dropbox File Provider case
on Apple.SE).

### Software updates and asset downloads

Processes: `softwareupdated` (main Software Update daemon per man
page), `suhelperd`, `appstoreagent` and `storeassetd` (App Store side),
`mobileassetd` (system asset bundles including XProtect payloads),
`XProtectUpdateService` (the newer iCloud-delivered XProtect update
channel, which works without an Apple Account sign-in per Eclectic
Light's August 2026 writeup), `installd`. `softwareupdated` performs
the periodic background check, download and install; user-visible cost
is download bandwidth plus post-install indexing churn, which pairs
naturally with the Spotlight and media-analysis states above.

### XProtect scans

Three layers (Eclectic Light's taxonomy): classic XProtect =
Gatekeeper-time signature checks via `syspolicyd`; **XProtect
Remediator** = scheduled background scanning/remediation with named
modules (`XProtectRemediatorDubRobber` covers XCSSET,
`XProtectRemediatorGreenAcre`, etc., delivered in XProtectPayloads
updates since June 2022); **XProtect Behavioural** = Bastion rules
reporting code behavior to Apple, which moved from reporting-only to
blocking with XProtect 5354 in 2026. Scan cadence (v149, before the
v151 change): a fast scan every 6h that runs on battery, a standard
scan every 24h off battery, a slow scan every 7 days off battery, each
module run once as the user and once as root. Processes visible in
Activity Monitor: `XProtectPluginService` variants and
`XProtectBehaviorService` (seven XProtect-related processes total in
the 2023 account). Since v151 (March 2025) scans vary by Mac and run
least on machines with many accessible TM backups, meaning a monitor
should treat XPR CPU bursts as periodic and bounded, and log-derived
scan history (what SilentKnight/Skint/XProCheck read) is the detection
route if process timing proves noisy.

### Presentation guidance distilled

- Fold each activity's processes into **one named state** ("Spotlight
  indexing", "Photos analysis", "Time Machine backup", "iCloud sync",
  "macOS update check", "XProtect scan"), exactly what
  SystemWatch does in its catalog and WhySlow does per process.
- Attach the conditions that gate it ("needs power; pauses while you
  work") and the expected scale ("minutes after an update", "up to days
  after a big Photos import"), so the advice reads as "plug in and
  wait" rather than "something is wrong."
- Where a real progress source exists (`tmutil status` percent and
  time remaining), show it; where none exists (Spotlight, media
  analysis, iCloud), show the phase name and a duration history of the
  same state (SystemWatch's History pattern), and mark it estimated.
- Keep the safety verdict explicit and asymmetric: these daemons are
  never safe-to-quit targets because launchd restarts them
  (`Safe to quit: No`), which reframes quit-buttons on system rows.
- Keep identity and safety orthogonal: a signature proves who shipped
  the binary (and catches Apple-named binaries at wrong paths); it says
  nothing about whether quitting is safe, which is a curated judgment:
  Apple-signed daemons are the most verified and the least quittable.

## Attribution below the app: browser tabs and multi-process apps

### What the kernel and launchd actually expose

Recapping notes 10 with the attribution lens: `KERN_PROC_ALL` +
`proc_pidinfo`/`proc_pid_rusage` give names, CPU, memory and counters
for every same-uid process; `sysctl(KERN_PROCARGS2, pid)` yields argv
**only for processes owned by the same user** without elevation
(libgetargv docs; this is why libgetargv exists: macOS `ps` cannot
show foreign users' arguments unprivileged). WebKit and app helpers are direct children of launchd
(pid 1), so ppid trees fail and the join key is the responsible pid /
coalition (`launchctl procinfo` exposes `responsible pid` and
`responsible path`; powermetrics has `--show-responsible-pid` and
`--show-process-coalition`). Friendly display names are a Launch
Services mechanism, not a BSD fact: Chromium and WebKit both set them
via the private `LSSetApplicationInformationItem` SPI (Chromium's own
comment calls it reverse-engineered SPI), and `CopyProcessName` only
returns them for WindowServer-registered processes of the current
user. Practical implication: for helpers, `p_comm`/path give role
names ("com.apple.WebKit.WebContent", "Code Helper (Renderer)") while
the localized name can add context when the process registered one.

### Safari and WebKit

- Process names: `com.apple.WebKit.WebContent` XPC services (plus
  `.CaptivePortal`, `.EnhancedSecurity`, `.Development` variants),
  `com.apple.WebKit.Networking`, `com.apple.WebKit.GPU`. `ps` shows
  only these names.
- The per-site attribution Activity Monitor shows is real but Apple
  magic: WebContent's `updateProcessName` renames the process through
  Launch Services during early init (while it still holds the LS
  sandbox extension), producing names like "Safari Web Content
  (prewarmed)" and the hostname-carrying names users report ("Safari
  Web Content (example.com)"); hovering the row in Activity Monitor
  lists the hosted URLs, a behavior present since Mavericks. How
  Activity Monitor resolves the full URL list (as opposed to the name)
  is not documented (unverified mechanism, likely the same private LS
  path). Stats issue #1971 is the public acknowledgment that there is
  no `ps`-visible route to the site name.
- Safari-side escape hatch for humans: the Debug menu's "Show Web
  Process IDs in Page Titles" prefixes titles with `[WP <pid>]`;
  WebKit's own debugging docs rely on it for attaching. There is no
  Safari task manager, and no public API maps pid → tab.

### Chrome, Edge, Brave, Arc and Electron apps

- Naming: renderer tabs/extensions appear as
  "Google Chrome Helper (Renderer)", GPU work as "(GPU)", plugins as
  "(Plugin)", unlabeled helpers are utility processes (network, audio,
  storage). Other Chromium browsers follow the same
  "<App> Helper (Renderer)" scheme, as do Electron apps, whose helpers
  are literally renamed per-app bundles with bundle IDs
  `${appId}.helper[.Renderer|.GPU|.Plugin|.EH|.NP]` (electron-builder
  docs), e.g. "Slack Helper (Renderer)", "Code Helper (Renderer)".
- What argv buys you: `KERN_PROCARGS2` on a same-uid helper returns
  Chromium's role flags (`--type=renderer`, utility sub-types) but
  **no tab title or URL**; the renderer-to-tab mapping is internal
  and explicitly not 1:1 in either direction (one tab can span
  renderers, one renderer can host several tasks). ProcXray's guide
  states it directly: `--type=renderer` identifies the subtype, not the
  document.
- The join surface is the browser's own task manager: Chrome's ⋮ →
  More tools → Task Manager (also Window → Task Manager on macOS)
  lists tasks with CPU and memory and can add a **Process ID** column,
  which is the only sanctioned way to correlate a helper row with a
  tab/extension. VS Code ships an equivalent "Process Explorer" inside
  the app.

### Firefox

Firefox's child binary is `plugin-container`, but on macOS the
processes display as "FirefoxCP Web Content", "FirefoxCP Isolated Web
Content", "FirefoxCP Privileged Content", "FirefoxCP WebExtensions",
plus GPU/socket/RDD/utility helpers. Mozilla's process-model doc
enumerates remote types (`web`, `webIsolated=$SITE`,
`webCOOP+COEP=$SITE`, `webServiceWorker`, `extension`,
`privilegedabout`, ...); the site-isolated names exist internally but
are **not** exported to the OS: Mozilla bug 1971007 confirms "FirefoxCP
Isolated Web Content" rows in Activity Monitor carry no URL and even
Mozilla's own triage couldn't map them to tabs. `about:processes` is
Firefox's task manager and labels each row with its pid
("Shared Web Process ({pid})", per the l10n source), so manual
correlation is possible in-app only.

### Tab URLs via AppleScript and TCC

For a Developer ID (non-sandboxed) app, the honest route to actual tab
URLs is Automation: Safari and Chrome expose `URL`/`name` of tabs via
AppleScript (used by trackers like Tracki for the active tab). Costs
and limits:

- Sending Apple events requires `NSAppleEventsUsageDescription` in
  Info.plist (required since macOS 10.14; Apple docs state an app
  sending Apple events without it is terminated) and a per-target-app
  user consent ("Coreography wants to control Safari"), recorded under
  System Settings → Privacy & Security → Automation.
- Sandbox users additionally need `com.apple.security.scripting-targets`
  entitlements, which adds App Store review friction and is moot for a
  Developer ID build anyway.
- This yields titles/URLs, not a pid mapping, so it complements rather
  than replaces the process table: attach "which tabs exist" to the
  Safari/Chrome app group, not to each helper row. Firefox's
  AppleScript surface is thin, so treat it as unavailable (unverified
  how much of the window/tab model it still answers).

## CPU percentage conventions

### Irix vs Solaris

- Linux `top` defines %CPU as "the task's share of the elapsed CPU
  time ... expressed as a percentage of total CPU time"; in Irix mode
  (the default) a multithreaded process can exceed 100%, and the `I`
  toggle switches to Solaris mode where per-task usage is divided by
  the number of CPUs so nothing exceeds 100. procps `top` also has a
  `5` toggle that labels P-core vs E-core CPUs on heterogeneous Intel.
- `htop` exposes both as columns: `PERCENT_CPU` (Irix-style, "the full
  capacity of the core it is running on") and `PERCENT_NORM_CPU`
  (Solaris-style, normalized by CPU count).
- macOS `top` documents no mode switch and its man page does not pin
  the semantic down beyond "CPU usage"; observed behavior matches
  Activity Monitor's over-100% convention (unverified as a documented
  contract).

### Activity Monitor

Per-process % CPU is Irix-style: 100% means one full core and values
above 100% are normal for multithreaded apps (community documentation
is unanimous; Apple's guide defines only the bottom strip:
System/User/Idle as "the percentage of CPU capability" summing to
100). The caught anomaly: on Apple silicon, Eclectic Light measured
two threads at 200% whether the code ran on six throttled E cores
(744 MHz, finished in 10.2 s) or six P cores and two E cores boosted
(finished in 3.0 s): a 3.4x wall-clock difference at identical
reported %CPU. The number ignores cluster and frequency; and on some
systems the column has been observed exceeding cores×100 (Apple
Discussions thread 7986117, treated here as a reported anomaly).

### Microsoft's 2025 Task Manager change

Windows 11 unified its CPU accounting in 2025 (rolled out from the
May 2025 KB5058411 update on 24H2, re-landed via the August KB5064081
preview). The Processes tab had used a legacy "Processor Utility"
metric with two documented flaws: it ignored core count (one saturated
core on a 16-core CPU displayed as 100%), and it measured against base
clock (turbo pushed values past 100% which were then clipped). The new
formula is identical across Processes, Performance and Users:

```text
CPU % = Δ process CPU time ÷ (Δ elapsed time × logical processors)
```

Rationale per Microsoft's changelog quoted by BleepingComputer and
WindowsLatest: "standard metrics ... aligning with industry standards
and third-party tools", and the sum of per-process rows now matches
the total. The old value survives as an optional "CPU Utility" column
in the Details tab, the same keep-the-legacy-metric-available move a
monitor can copy when changing a displayed convention.

### Options for heterogeneous Apple Silicon

Given E/P clusters (plus the M5-era "super" cluster type in notes 09)
with different frequencies and per-core throughput:

| Convention | Formula | Pros | Cons |
| --- | --- | --- | --- |
| Share of machine (Solaris) | Δcpu_time ÷ (Δt × n_cores) | Sums to total; matches Windows' new default; a row of 3% honestly reads as 3% of the Mac | A busy E core and a busy P core are priced identically in %, while doing very different work |
| Cores' worth (Irix) | Δcpu_time ÷ Δt | Matches Activity Monitor and user expectation; makes "how many cores is X burning" legible | Values scale with core count; on 12-core Macs a runaway looks small |
| Frequency-weighted | Δcpu_time × (cluster freq ÷ cluster max), summed | Approximates delivered cycles; exposes "E core at min clock" vs "P core boosted" as different costs | Needs IOReport/CLPC frequency data (private, per-chip, broke in macOS 27); still misses E-vs-P IPC differences; harder to explain |
| Work-based | `ri_cycles` / `ri_instructions` (rusage) or powermetrics `--show-process-ipc` | Measures actual work, cluster-agnostic | No intuitive scale; cycles per second is not a % |

A fourth orthogonal option: report **which cluster ran it**, using
`ri_cpu_time_qos_*` splits from rusage (background/QoS work is
biased toward E cores, observed rather than guaranteed) plus the
maintenance-state detector above: "mds_stores: 180%
(E cores)" is a far better explanation than either 180% or 15%.

## VMs and containers as seen from the host

### Virtualization.framework VMs

A VZ VM appears to the host as a dedicated helper process named
`com.apple.Virtualization.VirtualMachine` (confirmed by the Claude Code
sandbox issue; the reported mojibake display name also shows the
displayed name is a caller-supplied string passed to the VZ API). Host
process table sees its CPU, memory and I/O; **nothing inside the guest
is visible** without guest cooperation; no guest agent exists in
Virtualization.framework. Memory is sticky: VZ implements only partial
ballooning, so a container/VM's host-reported memory grows to its
high-water mark of touched pages and does not shrink back
(apple/container documents the caveat: `--memory 16g` can show 2 GiB
used in Activity Monitor, and freed guest pages aren't returned).

### Docker Desktop

Architecture per Docker's networking doc: the Docker Engine runs inside
a lightweight Linux VM; on Mac the VM runs on Apple's Virtualization
framework with gRPC FUSE or virtiofs for file sharing (DockerVMM +
`krun` is beta; QEMU is the legacy path). Host processes: the VM shows
as a "Virtual machine service"-named process (for-mac issue 5812), and
`com.docker.backend` carries the network proxy, file sharing (gRPC
FUSE mode) and control plane. Docker notes explicitly that **all
outbound container traffic appears to originate from
`com.docker.backend`**, so per-process network attribution sees Docker
as one pipe. Guest-side data is reachable and rich: the Engine API
`GET /containers/{id}/stats` streams per-container CPU, memory, net
and block I/O plus PID count (the documented CPU% formula is
`(cpu_delta / system_cpu_delta) × online_cpus × 100`), and the same
numbers drive `docker stats` and Docker Desktop's dashboard.

### OrbStack

Not VZ.framework: the dev confirmed on HN (2025) a custom Rust
virtualization stack with custom devices/protocols, shared-kernel
lightweight VM "similar to WSL 2", and dynamic memory that returns
unused memory to macOS ("nothing else supports this, including
Containerization"). Advertised idle cost ~0.1% CPU on M1. A standard
Docker engine runs inside a special machine, so the whole Docker API,
and `docker stats`, works; OrbStack additionally ships `orb top` (a
TUI) and a GUI **Activity Monitor** tab with per-container CPU, memory,
network and disk graphs, so the guest-side join is already a
shipping feature there.

### Apple's container CLI (2025)

`container` (github.com/apple/container, WWDC25, Swift, Apple silicon,
macOS 26-supported) runs **each OCI container in its own lightweight
VM** via Virtualization.framework + vmnet, the opposite of Docker's
one-big-VM. Host process inventory: `container-apiserver` launch agent
plus `container-core-images` and `container-network-vmnet` XPC helpers,
and one `container-runtime-linux` helper per container (launchd labels
`com.apple.container.container-runtime-linux.<name>`). Activity Monitor
today shows each as "Virtual Machine Service for
container-runtime-linux", identical names for different containers;
issue #824 notes the container name is only discoverable via the open-
files inspector, which is the attribution seam a monitor should improve
on. `container stats` (added 2025) streams per-container CPU%, memory,
network and block I/O, and `--format json --no-stream` gives a clean
snapshot API a host monitor could shell out to, though notes 10's TCC
warning about spawned subprocesses applies.

### UTM and Parallels

- **UTM**: QEMU linked as a library and, on macOS, run as a separate
  process via XPC (`QEMUHelper.xpc` → `QEMULauncher`/`qemu-system-*`);
  `hvf` (Hypervisor.framework) accelerates same-arch guests, and
  `UTMAppleVirtualMachine` uses VZ.framework for macOS 12+ guests.
  VMs therefore appear either as `qemu-system-<arch>` processes or as
  VZ VM processes, depending on backend. QEMU's guest agent is the
  inside-the-guest channel where installed (unverified which UTM
  front-ends enable it by default).
- **Parallels**: each running VM is a `prl_vm_app`/"Parallels VM"
  process spawned by its Dispatcher service; Parallels' own KB defines
  the %CPU convention as 100% per assigned CPU unit (a 4-vCPU VM can
  show 400%) and directs users to the guest's Task Manager for the
  interior view, i.e. even the vendor treats host rows as opaque.

### Guest-side reachability matrix

| Runtime | Host-visible process(es) | Interior reachable via |
| --- | --- | --- |
| Virtualization.framework (arbitrary VM) | `com.apple.Virtualization.VirtualMachine` | Nothing on host; needs in-guest agent/SSH/console |
| Apple `container` | `container-runtime-linux` (one per container), apiserver + helpers | `container stats` / Containerization APIs |
| Docker Desktop | `com.docker.backend` (+ VM service / `qemu-system-*` on legacy) | Docker Engine `/containers/{id}/stats`, `docker stats` |
| OrbStack | OrbStack helper processes (custom Rust VMM) | Docker API + `orb top` + its Activity Monitor tab |
| UTM | `QEMULauncher`/`qemu-system-*` or VZ VM process | QEMU guest agent where configured (unverified default) |
| Parallels | `prl_vm_app` per VM | Parallels Tools / guest OS tools (per KB, use guest Task Manager) |

## Implications for Coreography

1. **Ship a curated KB as the explanation spine.** Roughly 100-200
   entries cover every daemon users actually ask about (the two 2026
   catalogs prove the size); key each entry by executable name and
   bundle id, store `{role, displayName, category, safeToQuit,
   typicalBehavior, guidance, pathCheck}` and render verdicts like
   WhySlow's ("Leave it - runs while plugged in"). Sources are already
   on the machine: man pages where they exist, launchd plist
   scheduling keys (`ProcessType`, `RequiresExternalPower`), signature
   classification (Apple/DevID/adhoc/unsigned), and a path sanity check
   for spoofing; these establish identity, not proof a process is safe
   to quit (that verdict stays a curated judgment). This is
   deterministic, offline, free per query, and
   maintainable once per macOS release; it is the only option that
   never invents text, though curated entries can still be wrong.
2. **Add named maintenance states on top of the same catalog.** Fold
   md* → "Spotlight indexing", photoanalysisd/mediaanalysisd/
   photolibraryd → "Photos & media analysis", backupd → "Time Machine"
   (with real % and ETA from `tmutil status`), bird/cloudd/
   fileproviderd/cloudphotod/nsurlsessiond → "iCloud & cloud sync",
   softwareupdated/appstoreagent/storeassetd/mobileassetd/
   XProtectUpdateService/installd → "macOS update check",
   XProtectPluginService/XProtectBehaviorService → "XProtect scan".
   Show gating conditions from the launchd keys and phase/duration from
   history; where no progress API exists (Spotlight, media, iCloud) an
   honest "usually finishes in minutes-hours; leave the Mac plugged in
   and idle" beats a fake progress bar. This answers the
   "why is my Mac slow" question the catalog apps monetize, for the
   Mac's real culprits.
3. **Quitting system processes is a footgun, so gate it.** Every catalog
   agrees these restart immediately and quitting buys nothing; rows in
   a named maintenance state should replace "Quit" with explanation and
   the "watch it" affordance instead (MacStats learned this the hard
   way: it now confirms quits and refuses core macOS processes).
4. **If AI explanation ships, make it read the KB, not replace it.**
   Foundation Models (macOS 26+, Apple Intelligence on, AS only; 4096
   ctx) suits one focused question per process with guided structured
   output; availability must be checked via `SystemLanguageModel
   .availability` and degrade to the KB alone. Never let the model
   invent descriptions for unknown processes (MacStats' documented
   bug); on refusal/unknown say "unidentified" per the honesty
   contract. TaskExplorer's untrusted-data stance is the prompt
   pattern to copy verbatim, and its BYO-key/Ollama alternates are
   optional, not core.
5. **Attribution below the app is best-effort by design.** Render app
   groups via responsible pid (helpers fold into Safari/Chrome/etc.
   per P20); label helper roles from argv (`--type=renderer`,
   "(GPU)"), FirefoxCP kinds, Electron helper suffixes; show Safari
   WebContent's domain from its LS display name where readable and mark
   the gap honestly when not. For real tab truth, deep-link the
   browser's own task manager (Chrome Task Manager with its PID
   column, `about:processes`) and offer the Automation-consent
   AppleScript read for active-tab URLs (consent-gated, optional,
   per-browser, not a default data path).
6. **CPU%: default to share-of-machine, disclose the rest.** Show
   Solaris-style % of the whole SoC so columns sum to the total (the
   direction Microsoft just moved the industry), keep a "cores' worth"
   toggle for Activity-Monitor parity, and in the inspector add the
   cluster/frequency context that makes the number honest on Apple
   silicon (QoS split from rusage; frequency from the IOReport
   pipeline in notes 09 where available, labeled estimated).
   Frequency-weighted % is a power-user option, not a default.
7. **VMs/containers get first-class rows with an honesty boundary.**
   Detect `com.apple.Virtualization.VirtualMachine`,
   `container-runtime-linux`, `prl_vm_app`, `qemu-system-*`,
   `com.docker.backend` and group them as a VM/container category.
   Confirm OrbStack's actual bundle/process identities before adding a
   matcher; `orbstack` is not a verified process-name literal here.
   Name the guest where discoverable (container name,
   `container stats`/`docker stats`/`orb top` guest-side stats as an
   optional integration); where the interior is unreachable, label the
   row "host-attributed total, guest breakdown unavailable" rather
   than implying the VM process is the whole story (its memory is a
   high-water mark under VZ's partial ballooning, and Docker's network
   bytes all surface on `com.docker.backend`).

## Sources

Process explanation:

- [TaskExplorer product page](https://objective-see.org/products/taskexplorer.html) and [releases](https://github.com/objective-see/TaskExplorer/releases/)
- [MacStats changelog](https://macstats.app/changelog) and [monitoring-apps comparison](https://macstats.app/blog/best-mac-monitoring-apps)
- [WhySlow process library](https://whyslow.app/process/) and [mediaanalysisd guide](https://whyslow.app/process/mediaanalysisd/)
- [SystemWatch processes](https://www.systemwatch.app/processes), [mds_stores](https://www.systemwatch.app/processes/mds-stores), [mds](https://www.systemwatch.app/processes/mds)
- [CoreGuard daemon explainer](https://coreguard.app/insights/macos-processes-daemons-explained/)
- [Neowin Task Manager 22557 tour](https://www.neowin.net/news/closer-look-task-manager-in-windows-11-dev-channel-build-22557/)
- [Process Explorer context menu docs (documentation.help mirror)](https://documentation.help/Process-Explorer/The_Process_Context_Menu.htm), [Sysinternals page](https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer), [Russinovich malware-hunting deck](https://untrustednetwork.net/files/russinovich-malware-hunting-with-the-sysinternals-tools.pdf)
- [Process Explorer columns guide (malwaretips)](https://malwaretips.com/threads/how-to-use-sysinternals-process-explorer.45491/)

Foundation Models:

- [TN3193: context window (4096 tokens/session)](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window.md)
- [SystemLanguageModel availability reasons](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason.md)
- [contextSize docs (sosumi mirror)](https://sosumi.ai/documentation/foundationmodels/systemlanguagemodel/contextsize)
- [Foundation Models framework page (fm CLI on macOS 27, PCC)](https://developer.apple.com/foundation-models-framework/)
- [WWDC26 "What's new in the Foundation Models framework"](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Apple Intelligence foundation language models paper](https://machinelearning.apple.com/research/apple-intelligence-foundation-language-models), [2025 update (arXiv 2507.13575)](https://arxiv.org/html/2507.13575v3)

Man pages (keith.github.io mirror): [cloudd](https://keith.github.io/xcode-man-pages/cloudd.8.html), [bird](https://keith.github.io/xcode-man-pages/bird.8.html), [backupd](https://keith.github.io/xcode-man-pages/backupd.8.html), [backupd-helper](https://keith.github.io/xcode-man-pages/backupd-helper.8.html), [softwareupdated](https://keith.github.io/xcode-man-pages/softwareupdated.8.html), [mds](https://keith.github.io/xcode-man-pages/mds.8.html), [fileproviderd](https://keith.github.io/xcode-man-pages/fileproviderd.8.html), [photoanalysisd](https://keith.github.io/xcode-man-pages/photoanalysisd.8.html), [launchd.plist](https://keith.github.io/xcode-man-pages/launchd.plist.5.html), [top](https://keith.github.io/xcode-man-pages/top.1.html), [powermetrics](https://keith.github.io/xcode-man-pages/powermetrics.1.html)

Maintenance states:

- [Eclectic Light: Spotlight in Sequoia](https://eclecticlight.co/2024/11/29/using-and-troubleshooting-spotlight-in-sequoia-summary/), [mdutil -i vs -d (Apple.SE)](https://apple.stackexchange.com/questions/458381/difference-between-mdutil-i-off-and-mdutil-d)
- [photoanalysisd conditions (Apple.SE)](https://apple.stackexchange.com/questions/254567/how-can-i-make-the-face-recognition-process-continue), [mediaanalysisd launchd keys + launchctl disables (MacRumors)](https://forums.macrumors.com/threads/mediaanalysisd-photoanalysisd-and-photolibraryd.2445597/) ([page 2](https://forums.macrumors.com/threads/mediaanalysisd-photoanalysisd-and-photolibraryd.2445597/page-2)), [mediaanalysisd cache growth (Apple Discussions)](https://discussions.apple.com/thread/255835917), [controlling photoanalysisd (dev.to)](https://dev.to/gjbianco/controlling-photoanalysisd-3j2a)
- [tmutil status output (real-world-systems)](https://www.real-world-systems.com/docs/tmutil.1.html), [is TM running (Apple.SE)](https://apple.stackexchange.com/questions/316418/how-do-i-know-if-a-time-machine-backup-is-running), [progress parsing (Apple.SE)](https://apple.stackexchange.com/questions/162464/time-machine-progress-from-the-command-line)
- [fileproviderd explainer (OS X Daily)](https://osxdaily.com/2024/03/16/what-is-fileproviderd-on-mac-why-does-it-use-high-cpu/), [iCloud Drive mechanisms (Eclectic Light)](https://eclecticlight.co/2024/03/05/icloud-drive-in-sonoma-mechanisms-throttling-and-system-limits/), [fileproviderd stuck sync (Apple.SE)](https://apple.stackexchange.com/questions/474017/unbearably-slow-icloud-sync-serious-problem-fileproviderd), [brctl debugging (MPU Talk)](https://talk.macpowerusers.com/t/stop-ongoing-icloud-sync/41204/17)
- [How XProtect is updated (Eclectic Light)](https://eclecticlight.co/2026/08/20/how-xprotect-is-updated/), [XPR behavior change / scan cadence](https://eclecticlight.co/2025/03/11/xprotect-remediator-has-changed-its-behaviour/), [XPR first year](https://eclecticlight.co/2023/06/12/malware-detection-and-remediation-by-xprotect-remediator/), [why scans behave oddly](https://eclecticlight.co/2023/08/12/why-macos-anti-malware-scans-can-behave-oddly/), [XProtect 5354 behavioral blocking](https://eclecticlight.co/2026/08/09/last-week-on-my-mac-climate-change/)

Attribution below the app:

- [Safari Web Content URL tooltip (OS X Daily)](https://osxdaily.com/2013/11/23/show-url-safari-web-content-process-activity-monitor-mac-os-x/), [WebContent↔tab mapping (Apple.SE)](https://apple.stackexchange.com/questions/106866/has-anyone-figured-out-how-to-identify-the-unique-page-of-each-separate-safari-w), [how AM gets the URLs (Apple.SE)](https://apple.stackexchange.com/questions/140445/how-does-activity-monitor-get-the-urls-related-to-a-safari-web-content-process), [pid↔window via Debug menu (macissues)](https://macissues.com/determine-which-os-x-process-ids-are-for-your-safari-windows/)
- [WebKit updateProcessName / LaunchServices rename (commit)](https://github.com/antoniofrighetto/WebKit/commit/39b3935bf0ec4cef3eb62e0b41268f71cec53163), [changeset 272209](https://trac.webkit.org/changeset/272209/webkit), [WebKit debugging guide (WP pid titles)](https://webkit.org/debugging-webkit/)
- [ppid-orphan helpers and responsible pid via launchctl (Apple.SE)](https://apple.stackexchange.com/questions/327290/how-process-hierarchy-works-in-macos), [Stats issue #1971](https://github.com/exelban/stats/issues/1971)
- [Chromium process naming via LSSetApplicationInformationItem (SO)](https://stackoverflow.com/questions/4217947/setting-process-name-on-mac-os-x-at-runtime), [helper glossary (vitalsmac)](https://vitalsmac.com/glossary/helper-processes), [Chrome helper roles (unhogged)](https://unhogged.com/processes/google-chrome-helper-renderer/), [Chrome Task Manager PID column + arg limits (procxray)](https://procxray.com/blog/chrome-helper-memory-mac/), [mole Chrome guide](https://mole.fit/blog/google-chrome-helper-high-cpu-mac)
- [Electron helper bundle IDs (electron-builder)](https://www.electron.build/docs/mac), [helper renames (electron packager, deepwiki)](https://deepwiki.com/electron/packager/6.1-macos-packaging)
- [Firefox process model](https://firefox-source-docs.mozilla.org/dom/ipc/process%5Fmodel.html), [Gecko processes overview](https://firefox-source-docs.mozilla.org/ipc/processes.html), [about:processes strings (searchfox)](https://searchfox.org/mozilla-central/source/toolkit/locales/en-US/toolkit/about/aboutProcesses.ftl), [FirefoxCP naming (HN)](https://news.ycombinator.com/item?id=19432852), [bug 1971007: no URL in FirefoxCP rows](https://bugzilla.mozilla.org/show_bug.cgi?id=1971007), [killing one FirefoxCP proc (silvester)](https://silvester.org.uk/2018/06/01/which-firefox-tab-is-eating-my-computers-performance/)
- [NSAppleEventsUsageDescription (Apple)](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription.md), [Tracki: active-tab AppleScript reader](https://github.com/mmargauxx/tracki), [scripting-targets entitlement thread (Apple forums tag page)](https://developer.apple.com/forums/tags/entitlements/?page=10)

CPU conventions:

- [top(1) Linux man page (Irix/Solaris)](https://man7.org/linux/man-pages/man1/top.1.html), [htop(1) (PERCENT_CPU vs PERCENT_NORM_CPU)](https://www.man7.org/linux/man-pages/man1/htop.1.html), [mode comparison (unix.SE)](https://unix.stackexchange.com/questions/422558/how-do-different-tops-cpu-modes-correspond-to-each-other)
- [Eclectic Light: why % CPU isn't what you think](https://eclecticlight.co/2024/11/08/why-cpu-in-activity-monitor-isnt-what-you-think/), [Apple guide: view CPU activity](https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac), [>100% discussion (Apple.SE)](https://apple.stackexchange.com/questions/210398/acceptable-cpu-usage-for-4-core-3-4ghz-i7), [>200% on 2-core anomaly (Apple Discussions)](https://discussions.apple.com/thread/7986117), [100%+ thread (Apple Discussions)](https://discussions.apple.com/thread/6345789)
- [BleepingComputer: KB5064081 CPU metric cleanup](https://www.bleepingcomputer.com/news/microsoft/windows-11-kb5064081-update-clears-up-cpu-usage-metrics-in-task-manager/), [WindowsLatest: KB5058411 rollout](https://www.windowslatest.com/2025/05/26/windows-11-24h2s-task-manager-new-cpu-usage-formula-rolls-out-to-everyone/), [Ars Technica on the change](https://arstechnica.com/gadgets/2025/07/revamped-task-manager-second-monitor-notifications-coming-soon-to-windows-11/)

VMs and containers:

- [apple/container](https://github.com/apple/container), [technical overview](https://github.com/apple/container/blob/main/docs/technical-overview.md), [command reference (container stats)](https://github.com/apple/container/blob/main/docs/command-reference.md), [issue 824: indistinguishable VM names](https://github.com/apple/container/issues/824), [discussion 679: launchd labels](https://github.com/apple/container/discussions/679), [WWDC25 Meet Containerization](https://developer.apple.com/videos/play/wwdc2025/346/), [containerization package](https://github.com/apple/containerization)
- [Claude Code issue 24641: com.apple.Virtualization.VirtualMachine process name](https://github.com/anthropics/claude-code/issues/24641)
- [Docker Desktop networking doc](https://docs.docker.com/desktop/features/networking/), [Docker networking under the hood](https://www.docker.com/blog/how-docker-desktop-networking-works-under-the-hood/), [docker stats reference](https://docs.docker.com/reference/cli/docker/container/stats/), [docker/for-mac 5812 (qemu vs VZ service)](https://github.com/docker/for-mac/issues/5812)
- [OrbStack architecture](https://docs.orbstack.dev/architecture), [OrbStack docker docs](https://orbstack.dev/docs/docker), [release notes (orb top, Activity Monitor tab)](https://docs.orbstack.dev/release-notes), [OrbStack dev on custom Rust VMM (HN)](https://news.ycombinator.com/item?id=48470145)
- [UTM architecture doc](https://github.com/utmapp/UTM/blob/main/Documentation/Architecture.md), [qemu-system lingering process (UTM issue 4254)](https://github.com/utmapp/UTM/issues/4254), [QEMULauncher/QEMUHelper crash report naming (UTM issue 6881)](https://github.com/utmapp/UTM/issues/6881)
- [Parallels KB 116263: per-vCPU %CPU and guest Task Manager](https://kb.parallels.com/en/116263), [Parallels security white paper (VM app process)](https://www.parallels.com/static/pl/fileadmin/res/doc/pdb/whitepaper/PDB_WP_Security_EN_LTR.pdf), [prl_vm_app forum thread](https://forum.parallels.com/threads/vm-keeps-running.105654/)
- [KERN_PROCARGS2 same-uid limit (libgetargv)](https://github.com/getargv/getargv.rs), [adv_cmds KERN_PROCARGS2 port (SO)](https://stackoverflow.com/questions/72443976/how-to-get-arguments-of-nsrunningapplication)

## Verification log (2026-10-17, post-draft check)

Scope: the claims that drive product decisions: the four process-explainer competitors and their catalog/AI mechanics, MacStats pricing and privacy statements, man-page quotes, `mdutil -s` semantics, maintenance presence vs activity, QoS→E-core claims, the argv same-uid limit, the Windows CPU formula change, and the signature-vs-safe-to-quit distinction. Not a full re-verification of every link.

Verified against vendor/primary sources:

- **WhySlow**: process library page shows exactly 85 guides grouped by symptom domain; the mediaanalysisd entry carries the verdict line "Leave it. Runs while plugged in", "Made by Apple, part of macOS", the /System/Library + /usr/libexec genuine-path check, and "expect it to take a day or two" after a large import; "Free to explain. One-click fixes cost €8, once or yearly." (fetched live 2026-10-17).
- **SystemWatch**: site advertises "110 processes, in plain words" at "$14.99 $5.99 for the first 100 copies"; mds/mds_stores entries show "Shown as Spotlight indexing", "Safe to quit: No", "History shows how long the indexing actually ran", and the CoreServices.framework path-suspicion flag (saved pages).
- **TaskExplorer**: product page confirms v3 (Endpoint Security, system extension + Full Disk Access), AI assistant in the sidebar querying live data via tools, Apple Intelligence as default provider (macOS 26 + Apple Intelligence, Apple silicon only), BYO Anthropic/OpenAI keys, paged lists ("showing 30 of 62"), the untrusted-data injection posture verbatim, the #flagged/#unknown/#adhoc/#3rdparty tokens and the Apple/DevID/ad-hoc/unsigned signing quad. Ollama provider confirmed in the v3.1.0 GitHub release notes ("Native Ollama support"), not the product page. License field softened from "GPL" to "open-source" (not re-verified).
- **MacStats**: changelog confirms 1.0.6 September 2026, releases since June 2026, the monthly AI allowance meter (1.0.5), the "AI Explainer no longer produces inaccurate descriptions for unknown processes" fix, "Diagnose My Mac", baseline anomaly detection, weekly health report, incident recording, and the quit-confirmation + "refuses to signal core macOS processes" hardening. Pricing/FAQ confirm Pro is a one-time $14.99 (not a subscription) that adds the explanations, 300/month allowance for new licences, and macOS 13+/Apple silicon.
- **Man pages**: mds, cloudd, bird, backupd, fileproviderd, softwareupdated, photoanalysisd, photolibraryd quotes match verbatim (saved copies); mediaanalysisd/mds_stores/corespotlightd gap claim retained as a 404 observation on the keith.github.io mirror.
- **Windows Task Manager**: BleepingComputer on KB5064081 confirms the old "Processor Utility" metric ignored core count (1 saturated core on a 16-core CPU showed 100%) and clipped turbo-driven >100% values, the new formula Δ process CPU time ÷ (Δ elapsed × logical processors), standardization across Processes/Performance/Users tabs, and the optional legacy "CPU Utility" column in Details. The KB5058411 (May 2025) initial rollout is per WindowsLatest's headline; not independently re-fetched.
- **Neowin build-22557 tour** (saved copy) confirms "Search online" appears in the three-dotted menus on the Services and Startup apps pages; the Processes/Details context-menu placement is from Task Manager's documented behavior, not that article.
- **CoreGuard**: the daemon explainer contains "when it's busy, the real question is which app's transfers it's carrying"; it is about `nsurlsessiond` specifically, though it generalizes to sync daemons.

Corrections made:

- MacStats: previous draft said process explanations were free and that descriptions are "shared between everyone who asks", contradicted by the vendor's own pricing (explanations are the Pro add-on) and unsupported by the privacy policy. Rewritten to the verified version.
- `mdutil -s` was described as giving "per-volume indexing state"; clarified it reports the *enabled/disabled* flag, not active indexing; added the presence-vs-activity caveat in the summary and Spotlight sections.
- QoS→E-core statements now read "observed scheduling bias, not a placement guarantee" (Spotlight section and CPU-conventions section).
- `mediaanalysisd`'s `RequiresExternalPower`/`Priority = Maintenance`/`ResourceIntensive` plist keys marked undocumented and sourced to the MacRumors thread report, not Apple docs.
- `ps` "setuid bit" claim replaced: on macOS the limit is the KERN_PROCARGS2 same-uid rule (libgetargv docs), not a setuid mechanism.
- Added explicit guidance that signature/identity and safe-to-quit are orthogonal (Presentation section).

Remaining gaps: Apple Stack Exchange (403), MacRumors (403), Reddit, documentation.help (403/Cloudflare) and real-world-systems.com (403) were unreachable, so the Process Explorer context-menu doc mirror, several forum-sourced figures (mediaanalysisd plist keys, battery>30% condition), and the Russinovich deck's "fake Microsoft company string" line were not re-verified; they are consistent with long-standing documented behavior but single-sourced here. How Activity Monitor resolves Safari WebContent URL lists remains an unverified mechanism (already marked). powermetrics' `--show-responsible-pid` flag and the VZ partial-ballooning numbers cite man-page/apple-container docs returned 200 but not re-read this session.
