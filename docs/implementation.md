# Implementation ledger

Track actual delivery against the [product plan](plan.md). A stage is
complete only after its relevant checks and review pass and its PR merges.

## Current slice: network interface counters

The native foundation merged in [PR #5](https://github.com/L-K-M/Coreography/pull/5)
at `aee9494` after two GLM rounds and passing CI. The process slice in
[PR #6](https://github.com/L-K-M/Coreography/pull/6) has passed native CI
and remains in progress until its review and merge.
Its integration CI passed at `0f31a7f`; GLM review is now enabled.

Implemented:

- Swift 6 package boundaries: drivers, engine, application services and CLI.
- Public Mach CPU ticks and VM counters, with explicit source failures.
- Whole-machine CPU share, derived used-memory bytes, bounded sample
  history, real-interval rates and nonnumeric collecting/gap states.
- One native window with CPU/memory lanes, numeric readings, chart
  accessibility descriptors and display hold independent of collection.
- Xcode project, embedded CLI, shared build/release adapters, verified
  universal packaging and CI development artifacts.
- Bounded libproc enumeration with PID/start-time identity checks before
  and after usage, whole-machine CPU share, physical footprint and disk
  read/write rates for readable processes. Permission failures remain
  explicit, and all identified processes are retained in each snapshot.
- A collapsed process table with name/PID/UID filtering and CPU, memory,
  disk and name sorting. The same dashboard scheduler polls processes
  every two seconds. Display hold includes the process table.
- `coreo processes --once --json` captures a real two-sample interval.
- Full-width public interface MIB byte counters, primary IPv4/IPv6 route
  selection, explicit interface scope, mirrored receive/send graphs,
  a chart accessibility descriptor and a numeric table. Network samples
  share the dashboard loop and display hold; source changes split lines.
- `coreo network --once --json` captures per-interface rates and coverage.

This is not the seven-lane product yet. The live buffer currently holds
60 host and network frames. App grouping, process history/attribution,
system disk rates and per-process network attribution remain outstanding.
There is no disk store,
GPU/power/thermal provider, helper, MCP or model integration in this slice.

## Verification

| Check | Status |
| --- | --- |
| Swift tests | 60 passed locally on Linux; 47 process-slice tests passed on macOS; network native tests pending |
| `coreo doctor` on Linux | Reports unsupported native sampling with no numeric Mac readings |
| Build-script regression tests | 30 passed locally and in CI; includes actual release-step rejection, fixture isolation and exact archive selection |
| Xcode/macOS compilation and live CPU/memory smoke | Passed [native CI](https://github.com/L-K-M/Coreography/actions/runs/39098130832) at `f47fe45`; latest integration checks tracked on PR #6 |
| Universal app and CLI slices, code signature and archive | Passed the same native CI; ad-hoc signing only |
| Native chart rendering, VoiceOver and display-hold behavior | [Process candidate](https://github.com/L-K-M/Coreography/actions/runs/39098130832/artifacts/12125279908) delivered; owner checks pending |
| Native process collection and CPU units | Passed native C contracts, `getrusage` cross-check and live embedded-CLI smoke at `f47fe45`; process UI compiled for both architectures |
| Native network MIB, wide-counter mapping and three-lane UI | Pending network-slice macOS CI; the process candidate does not include this slice |
| CPU, memory and wakeup budgets | Unmeasured; S2 pending |
| Developer ID, notarization and signed update delivery | Pending credentials and M7 |

Portable tests use declared fixtures. They do not validate private APIs,
sensor calibration, fullscreen behavior or Mac energy overhead.

## Remaining delivery

| Stage | Outstanding outcome |
| --- | --- |
| M0 / S1-S8 | Native CI foundation and reproducible probes; record hardware findings and missing environments |
| M1 | CPU/memory depth, process app grouping/lifecycle/history, disk provider, network review/native validation, full cadence scheduler and attribution contracts |
| M2 | GPU, clusters, frequency, power, sensors, thermals and honest chip profiles |
| M3 | Seven aligned lanes, shared cursor, scoped selection, process pane, inspector, self-cost and accessibility |
| M4 | SQLite history, app ledger, sleep/log import, retention/deletion, replay, ranges and exports |
| M5 | Secure optional helper, diagnostics, files/ports, startup/connections, filters and bounded read-only MCP |
| M6 / S9 | Menu bar, HUD, raw-frame-qualified session statistics, comparisons, alerts, explanations and optional Ask |
| M7 | Localization, full integration/soak/performance checks, updater and production release validation |

## Owner Mac checks

The owner will test downloadable builds. The process candidate is linked
above and its checks have been sent. For a trusted ad-hoc build blocked on
first launch, use System Settings > Privacy & Security > Open Anyway.
This is not a notarized production release. Check:

1. Open the app and compare CPU and memory trends with Activity Monitor.
   Memory is an estimate and is not memory pressure.
2. Hold the display with Space, wait, and return to live. Collection must
   have continued; holding is distinct from pausing recording.
3. Sleep/wake the Mac. Missing intervals must remain gaps, including in
   the memory line.
4. Check light/dark appearance, keyboard access and VoiceOver chart/table
   readings. Return the OS/build, architecture and concrete discrepancies.

More specific S1/S6 probes follow when those providers and HUD exist.
Do not mark a physical-Mac gate passed from a cross-compile or fixture.

For the process-counter candidate, compare own-user process trends with
Activity Monitor. Its default process CPU scale is one core equals 100%;
Coreography uses the whole machine, so divide Activity Monitor's process
CPU by the logical CPU count before comparing. Check CPU/memory/disk sort,
filters containing spaces, display hold, and unreadable/restricted counts.
Enumeration can miss short-lived processes and is capped at 16,384 PIDs.
No per-process network or app grouping is claimed yet.

For a verified network candidate, check primary/interface selection with
and without a VPN, receive/send direction and byte units, interface
disappearance, hold/resume, and VoiceOver/numeric-table equivalence.
Primary means the SystemConfiguration IPv4 interface, falling back to
IPv6; it is not a sum of physical and tunnel traffic.

## Process source and units

`PROC_PIDTBSDINFO` and `RUSAGE_INFO_V2` are public but access may be denied
for other users' processes. Those identity failures appear in coverage;
they are not empty zero-usage rows. A failed usage read on an identified
process keeps a restricted/unavailable row and drops its rate baseline.

The CPU fields in `proc_pid_rusage` are Mach timebase ticks, not already
nanoseconds. The bridge converts with `mach_timebase_info` using checked
128-bit intermediates. The native C contract test compares busy-loop CPU
deltas against `getrusage`'s microseconds to catch timebase/unit mistakes.
Primary source chain: Apple's [fill_task_rusage](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/bsd_kern.c),
[task_power_info_locked](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c)
and [recount metrics](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/recount.h).

## Network source and units

Use public `IFMIB_IFDATA / IFDATA_GENERAL`: its
[SDK structure](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/net/if_mib.h#L65-L86)
contains `if_data64`, and the
[read-only kernel handler](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/net/if_mib.c#L97-L139)
copies full-width byte counters without a platform-binary gate. Counters
are differenced over each interface's actual monotonic interval; index
and name identify its series. A detached interface's successful but
zero-filled reply has an empty name and is unavailable, not zero traffic.

Reject the tempting routing-statistics byte source: although
`NET_RT_IFLIST2` has 64-bit fields, its
[non-platform output path](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/net/rtsock.c#L2196-L2205)
uses [a 32-bit cast and 1 KiB floor](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/net/rtsock.c#L158-L161).
The interface MIB avoids that truncation and quantization. No private
NStat API, helper or subprocess is needed for these interface counters.

The primary route comes from SystemConfiguration's `PrimaryInterface`
for IPv4, then IPv6. Missing or ambiguous primary metadata stays explicit;
observed interfaces remain selectable. Interfaces are never summed into
an ambiguous system total. Native C fixtures use the SDK's real
`ifmibdata` type and verify values above 4 GiB, bounded names and detached
responses. Linux tests verify the unsupported path, not a copied Mac ABI.

The next disk slice can read 64-bit `IOBlockStorageDriver` statistics by
registry entry identity. Virtual-driver overlap and APFS/Fusion ancestry
must be qualified before labeling a physical total or automatic boot disk.

## Review decisions carried forward

- Foundation review round 2: no actionable or important findings. Defer
  clearer test-extraction failure messages. Production signing remains
  M7; adding placeholder credentials would break the current build.
  The app does not launch its embedded CLI through bundle lookup APIs;
  build and smoke-test paths explicitly use `Contents/Helpers/coreo`.
- Process slice independent review: accept PID 0 as kernel_task and let
  libproc return its real reading or permission failure. The old positive-
  only guard fabricated an `EINVAL` before making the named syscall.
  Reproduced the C contract failure before fixing the guard on both
  platforms; native CI also checks kernel_task's actual result.
- Foundation review round 1: strengthen the release smoke test to reject
  unavailable, non-finite or out-of-range values using the same validator
  as CI. Exercise archive-mutating tests in the output-isolation guard.
- Refuted compile claims: `Duration.nanoseconds` accepts generic integer
  values, and native Xcode 26.6 CI compiled both architectures. Display
  hold freezes `frames`, `latest` and its timestamp; the expanded hold test
  feeds more than a full buffer while checking that displayed points stay.
- Transient Mach failures are already nonnumeric readings returned by the
  engine, not thrown loop errors. Reading factories and decoding reject
  numeric unavailable states. Counter decreases become gaps, not unsigned
  underflow. Keep these invariants rather than adding reviewer workarounds.
- Preserve exact CLI flag validation: both permutations of its two flags
  work; set comparison would also accept unintended duplicate flags.
- No entitlements are configured in this unprivileged, unsandboxed target.
  Production entitlements and signing remain an explicit M7 gate. Space
  with focused controls still needs the owner's native accessibility check.
- Numeric evidence is separate from explanatory hypotheses. Memory/GPU
  quantities and modeled app energy are not universally additive.
- A zero/unset wired-memory setting is not zero effective GPU capacity;
  a recommendation is not an enforced allocation ceiling.
- S1 must define freeze confirmation and fallback validation per source;
  unchanged idle counters alone do not establish freezing.
- Privileged targets use PID plus start time, checked at dispatch.
  Tool paths, argument templates, environment, runtime and output are bounded.
- MCP peer identity needs kernel-attested connection evidence. Client
  names are display data, grants are scoped/revocable and stored securely,
  and revocation cancels that client's queries and suppresses delivery.
- Cursor retries can be idempotent but are reauthorized and charged to
  budgets; revoked/narrowed scopes and expired snapshots invalidate access.
- Release arch tokens are `arm64`, `x86_64`, `universal`; the last requires
  both app and embedded CLI slices.
