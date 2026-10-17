# Linux and cross-platform system monitors (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

## Summary

- The terminal monitors agree on a glyph ladder for graphs: ASCII dots,
  half/quarter blocks, then braille (U+2800-28FF) for the highest resolution.
  htop, gotop and btop all implement variants of it; btop lets the user pick
  per box (braille / block / tty, tty being a 3-symbol 16-color fallback).
- Two encodings worth stealing: btop's CPU graph draws two metrics in one
  frame (upper/lower half, lower optionally inverted), and htop's stacked
  CPU bar uses semantic segment colors (nice=blue, user=green, system=red,
  irq=yellow, softirq=magenta) that the help screen re-explains as a legend.
- Threshold-driven color is the norm: glances has per-metric
  `*_careful/warning/critical` config keys, atop colors system lines that are
  overloaded, s-tui appends throttle reason labels (T/H/C/W/A/X) to the
  frequency graph, mactop maps kernel memory pressure to green/yellow/red.
- Time is the feature most of them have and Activity Monitor lacks: bottom
  and zenith zoom and scroll charts back in time, atop logs compressed raw
  counters daily (28 days default) and replays them (`atop -r`, `t`/`T` step),
  below does `below replay -t "3m ago"`, zenith persists history across runs.
- On Apple Silicon the sudo question splits cleanly: asitop needs root
  because it shells out to `powermetrics`; macmon and mactop read the same
  channels without root via private APIs (IOReport, SMC, IOHIDEventSystem);
  btop v1.4.7 also added Apple Silicon GPU stats via IOReport. Caveat:
  macOS 27 restricted several rootless energy counters behind a private
  entitlement; macmon now reads hidden AppleCLPC IOReport energy reports
  and mactop falls back to deriving ANE usage from bandwidth.
- The GUI leaders are Windows-Task-Manager-shaped (Mission Center: left
  sidebar of live per-resource thumbnail graphs) and compositor-shaped
  (KDE Plasma System Monitor: pages built from reusable sensor "faces" that
  also render as desktop/panel widgets).
- Netdata's chart chrome is the densest design reference: every chart has a
  per-second area graph topped by an anomaly-rate ribbon, a "definition bar"
  of group/aggregate/node/instance/dimension/label dropdowns where each item
  shows its own series count, volume %, anomaly % and min/avg/max for the
  visible window, and highlighting a range triggers cross-metric correlation.
- The serious tools decouple collection from display: one engine feeding a
  TUI, a web UI, a REST API, stdout CSV/JSON and exports (glances, macmon,
  mactop, below, conky). Coreography should keep the collector layer separate
  for the same reason even if it only ever ships a native UI.

## Tools

### btop++ / btop

- **Status**: C++23 terminal resource monitor, Apache-2.0. Linux, macOS,
  FreeBSD, NetBSD, OpenBSD. Latest release v1.4.7 (2026-05-01); actively
  maintained (about 35k stars). Continuation of bashtop (bash) and bpytop
  (Python) by the same author. v1.4.7 added Apple Silicon GPU support via the
  IOReport API and an option to disable presets; a `btop4win` port exists.
- **What it shows**: CPU (per-core meters, combined usage graph, frequency,
  temperature, package watts when privileged), memory (graphs or meters),
  disks (capacity plus IO activity and read/write speeds), network
  (auto-scaling graph), battery, process list (tree view, filter, sort,
  signals, pause, detailed per-process stats, follow mode), GPU boxes for
  Linux GPUs (NVIDIA/AMD/Intel) and Apple Silicon.
- **How it shows it**: a fixed set of bordered boxes, `cpu mem net proc`,
  toggled per box and rearranged through `presets` (up to 9 presets; each
  preset sets box position and graph symbol). Graph glyphs configurable per
  box: `braille` (highest resolution), `block` (half resolution, common
  chars), `tty` (3 symbols, auto on a real TTY with 16 colors). The CPU graph
  can show two metrics at once via `cpu_graph_upper`/`cpu_graph_lower` with
  `cpu_invert_lower`. Process rows can carry mini CPU graphs
  (`proc_cpu_graphs`) and usage-gradient coloring (`proc_gradient`,
  `proc_colors`). 24-bit truecolor with 256-color fallback. "Game inspired"
  menu system; full mouse support (buttons with highlighted keys are
  clickable, scroll works in lists and menus). Themes are `.theme` files in
  system dirs plus `~/.config/btop/themes`; `theme_background=false` keeps
  terminal transparency. Default update 2000 ms. Keys `5`/`6`/`7`/`0`
  toggle GPU boxes; `E` collapses the whole process tree (v1.4.7).
- **Ideas worth taking**: two metrics sharing one graph frame
  (upper/lower + invert); layout presets the user cycles between; per-process
  sparklines inside the table; a real theme ecosystem as plain files; graph
  resolution degrading gracefully to the display's capabilities; clickable
  hint-letter affordances everywhere.
- **Weaknesses / avoid**: braille needs a font containing U+2800-28FF or the
  graphs break visually; watts on Linux requires setcap/setuid/sudo; density
  can read as busy.
- **Sources**:
  https://github.com/aristocratos/btop,
  https://raw.githubusercontent.com/aristocratos/btop/main/README.md,
  https://github.com/aristocratos/btop/releases.atom

### htop

- **Status**: C/ncurses interactive process viewer, GPL-2.0+. Cross-platform
  including macOS. Latest 3.5.3 (2026-08-16); maintained by the htop-dev
  team since 2020 (originally Hisham Muhammad, 2004-2019).
- **What it shows**: header meters (per-core CPU, memory, swap, tasks/
  threads, load average, uptime, battery, hostname, systemd state, optional
  libsensors temperature) over a scrollable process table with configurable
  columns (PID, USER, PRI, NI, VIRT, RES, SHR, S, CPU%, MEM%, TIME+, Command,
  IO rate, delay-accounting columns when compiled in, etc.).
- **How it shows it**: every meter can render as Text, Bar, Graph or LED.
  Bar mode stacks colored `|` segments inside `[ ]` brackets (monochrome
  falls back to `|#*@$%&.` characters); the default CPU bar is blue=low/
  nice, green=user, red=kernel, yellow=irq, magenta=softirq, plus steal/
  guest/io-wait when "Detailed CPU time" is on. Graph mode is a rolling
  braille graph (4 vertical pixels per row, ASCII `.`/`:` fallback). LED mode
  draws seven-segment-style digits. F2 Setup edits meters, columns, display
  options and color schemes in-app and writes `~/.config/htop/htoprc` on
  clean exit only. Interaction: `/` incremental search, `\` filter (fixed
  strings, `|` separator), `t` tree view (soft/hard "stable" modes that keep
  the selected line visually pinned), Space/`c` tag processes, `k` kill with
   a signal menu, `F` follow, display options that highlight new and removed
   processes, `s` attaches
  strace, `l` lists open files via lsof, `x` shows file locks, `a` sets CPU
  affinity. `pcp-htop` is a variant on Performance Co-Pilot that exposes
  thousands of PCP/OpenMetrics metrics through the same meter UI.
- **Ideas worth taking**: multiple render modes over identical meter data;
  semantic stacked-bar colors with an in-app legend; tagging several
  processes then acting on the set; tree "stable" sorting that does not
  reorder rows under the cursor; setup persisted only on clean exit.
- **Weaknesses / avoid**: process-first layout with tiny meters (the inverse
  of Coreography's goal); bar meters carry no history; ncurses look.
- **Sources**:
  https://github.com/htop-dev/htop,
  https://manpages.debian.org/unstable/htop/htop.1.en.html,
  https://raw.githubusercontent.com/htop-dev/htop/main/Meter.c,
  https://github.com/htop-dev/htop/releases.atom

### glances

- **Status**: Python, LGPL-3.0 (COPYING bundles LGPLv3 + GPLv3). Linux, BSD,
  macOS, Windows. Latest 4.5.8 (2026-10-11); actively maintained (~33.8k
  stars).
- **What it shows**: CPU, memory, swap, load, network (per interface, Wi-Fi),
  disk IO, filesystems, sensors (temperature/voltage/fan), processes,
  containers (Docker, LXC), ports, IRQ rate, folders (monitored dir sizes),
  RAID, SMART, public IP, uptime, logged users. Application Monitoring
  Processes (AMP) attach app-specific stats (e.g. an Nginx AMP scrapes the
  status page).
- **How it shows it**: curses TUI with a left sidebar of plugin sections
  (configurable `left_menu` list) and a process table; mostly numbers and
  inline bars rather than charts. The signature idea is threshold colors:
  every plugin takes `*_careful`, `*_warning`, `*_critical` keys in
  `glances.conf` (e.g. `user_careful=50 user_warning=70 user_critical=90`)
  and values are color-coded accordingly.   `history_size` default 1200 samples
  (~1 h). Four output modes on one engine: standalone TUI; web server
  (`glances -s`/`-w`, port 61208, responsive WebUI that mirrors the TUI,
  REST API under `/api/5`); client/server mode where the terminal client
  reads the server's REST API (password-protected, limits set server-side);
  and
  stdout (`--stdout`, `--stdout-csv`, `--stdout-json`), quiet `--export` to
  CSV/JSON/InfluxDB/Elasticsearch/PostgreSQL-Timescale/Cassandra/ClickHouse/
  CouchDB/OpenTSDB/Prometheus/StatsD/Riemann/Graphite/RabbitMQ-ActiveMQ/NATS/
  ZeroMQ/Kafka. `--browser` opens a central server list (zeroconf
  autodiscovery, sortable columns from `[serverlist]` config, SNMP fallback
  for undetected hosts). `--fetch` prints a static one-shot card (custom
  Jinja template). MCP server for AI assistants since 4.5.1. Config accepts
  dynamic values via backticked shell commands.
- **Ideas worth taking**: per-metric semantic thresholds driving color;
  one collector engine behind TUI/Web/API/file formats; a server browser
  that aggregates many machines into a sortable table; a non-interactive
  "fetch card" mode.
- **Weaknesses / avoid**: TUI is dense text, no real charts; Python overhead;
  the WebUI replicates the terminal layout instead of being designed for the
  web.
- **Sources**:
  https://github.com/nicolargo/glances,
  https://raw.githubusercontent.com/nicolargo/glances/develop/README.rst,
  https://glances.readthedocs.io/en/latest/config.html,
  https://glances.readthedocs.io/en/latest/quickstart.html,
  https://github.com/nicolargo/glances/releases.atom

### bottom (btm)

- **Status**: Rust (ratatui), MIT. Linux, macOS, Windows officially (x86_64,
  i686, aarch64); unofficial FreeBSD/ARM/POWER/RISC-V/LoongArch/Android.
  Latest 0.14.9 (2026-08-27); active, plus nightly builds.
- **What it shows**: time-series widgets for CPU (average plus per-core),
  memory, network I/O, temperature sensors, disk I/O; info widgets for disk
  capacity, temperature table, battery; a process widget with sorting,
  searching, tree mode and kill signals.
- **How it shows it**: a widget grid where each chart supports zooming the
  time interval in/out and one widget can expand to fill the screen. An
  htop-inspired "basic mode" swaps charts for bars. Layout, widget behavior,
  colors (built-in and custom themes, e.g. `--theme gruvbox`) and per-widget
  filters are driven by CLI options and a config file; process columns are
  selectable; default sort order can be set in config (0.14.7); an option
  shows zeroed total network usage on startup (0.14.9).
- **Ideas worth taking**: time-axis zoom on every chart; expand-one-widget;
  a degraded "basic mode" that mirrors the dense tool; full declarative
  config for layout.
- **Weaknesses / avoid**: plain thin-line charts, less visual polish than
  btop; defaults are conservative.
- **Sources**:
  https://github.com/ClementTsang/bottom,
  https://raw.githubusercontent.com/ClementTsang/bottom/master/README.md,
  https://github.com/ClementTsang/bottom/releases.atom

### nvtop

- **Status**: C/ncurses GPU monitor ("Neat Videocard TOP"), GPL-3.0-or-later
  (per the README license section). Linux primary, builds
  for Apple (limited M1/M2 support via Metal). Latest 3.3.2 (2026-02-08);
  active. Vendor coverage: NVIDIA (NVML, plus NvAPI for extra clock domains),
  AMD (amdgpu/radeon DRM/sysfs, per-process via fdinfo on kernel >= 5.14),
  Intel (i915/Xe, fdinfo >= 5.19, needs CAP_PERFMON for memory/frequency),
  Qualcomm Adreno (msm >= 6.0), Apple, Huawei Ascend (DCMI), Iluvatar CoreX,
  Broadcom VideoCore, Rockchip NPU, MetaX, Enflame, Tenstorrent.
- **What it shows**: per GPU: utilization and memory-controller utilization
  bars, VRAM used/total, temperature, power draw, fan, encoder/decoder usage,
  PCIe RX/TX as percentage of link bandwidth, clocks (the `-i` info bar adds
  secondary NvAPI clock domains such as XBAR/SYS/NVD, `-X` adds static
  specs); an "effective load" metric that
  weights utilization by current/max power ratio (3.3.0); a process table
  with per-process GPU usage (device, type, GPU%, CPU%, memory).
- **How it shows it**: htop-style split, device sections on top with a
  rolling line chart per selected metric and a process table below. F2 opens
  a setup window whose "Chart" section picks which metrics get plotted
  (utilization, temperature, power, clocks, PCIe RX/TX); F12 persists
  preferences. `-P` hides the process list entirely; `-s` prints a JSON
  snapshot; `-l` loops snapshots (3.3.2); Ctrl+L redraws.
- **Ideas worth taking**: a chart-picker model (user assigns metrics to a
  fixed chart area); power-weighted "effective utilization"; a hideable
  process pane turning the tool into pure graphs; snapshot modes for scripts.
- **Weaknesses / avoid**: per-vendor metric availability is a matrix of
  caveats; Apple support explicitly early and read-only.
- **Sources**:
  https://raw.githubusercontent.com/Syllo/nvtop/master/README.markdown,
  https://github.com/Syllo/nvtop/releases.atom

### zenith

- **Status**: Rust (ratatui + heim/sysinfo), MIT. Linux, macOS. Latest
  0.15.1 (2026-09-02); maintained.
- **What it shows**: CPU, memory, network, disk charts; "top users" of CPU,
  memory and disk; disk free-space charts; battery percentage, time to
  charge/discharge, power draw; process table with per-process disk usage,
  signal sending, priority change; peak tracking per process (0.15.0);
  NVIDIA GPU utilization including per-process usage (build feature);
  Linux delay accounting when run as root.
- **How it shows it**: vertically stacked chart sections above the process
  table; each section's minimum height is a CLI percentage
  (`--cpu-height`/`--disk-height`/`--net-height`/`--process-height`), and
  setting it to 0 removes the section. `+`/`-` zoom all charts, left/right
  arrows scroll back in time, backtick resets to current time and max zoom;
  `e` expands and `m` minimizes a section, Tab switches, Enter focuses a
  process. History is stored in a database at `~/.zenith` so charts survive
  restarts (`--disable-history`, `--db` to relocate). Default refresh 2 s.
- **Ideas worth taking**: scroll-back + zoom chart interaction with an
  explicit "return to live" reset; history persisted across runs (a spike
  seen yesterday is still inspectable); per-process peak values; "top users
  of each resource" strip.
- **Weaknesses / avoid**: chunkier ratatui charts; 2 s default refresh feels
  slow next to Netdata's per-second norm.
- **Sources**:
  https://raw.githubusercontent.com/bvaisvil/zenith/master/README.md,
  https://github.com/bvaisvil/zenith/releases.atom

### gotop

- **Status**: Go (termui + drawille-go + gopsutil), MIT (Festival variant).
  Linux, FreeBSD, macOS; Windows binaries with limited testing. Last tagged
  GitHub release v4.2.0 (2022-09-29); the maintainer is migrating the repo
  to Sourcehut. Fork of cjbassi's deprecated original (author moved to Rust
  "ytop").
- **What it shows**: seven widgets: cpu, mem, disk, net, temp, batt, procs.
  Optional NVIDIA extension (shells out to `nvidia-smi`), a `remote`
  extension pulling Prometheus metrics from other gotop instances, SMART
  NVMe temperatures on Linux and Darwin.
- **How it shows it**: braille/block line graphs (a patched PSF console font
  is shipped for terminals lacking the glyphs). The notable piece is a
  minimal layout DSL: each line is a row, widgets separated by spaces,
  `widget/weight` sets relative width, `N:` prefixes rowspan; e.g.
  `cpu net` over `disk/2 mem/4`. Built-in layouts include `kitchensink`,
  `battery`, `minimal`, `htop` and `procs`; `-l name` selects one, custom
  files live in `$XDG_CONFIG_HOME/gotop`. Color schemes as files, mouse
  click/wheel on the process list, i18n via embedded translations.
- **Ideas worth taking**: a dead-simple text layout grammar (rows, weights,
  rowspans) that ships named layouts; remote metric aggregation via
  Prometheus pull.
- **Weaknesses / avoid**: unmaintained GitHub line; extension system folded
  back into core after Go plugin pain; font dependency for braille.
- **Sources**:
  https://github.com/xxxserxxx/gotop,
  https://raw.githubusercontent.com/xxxserxxx/gotop/master/docs/layouts.md,
  https://github.com/xxxserxxx/gotop/releases.atom

### s-tui

- **Status**: Python (urwid + psutil), GPL-2.0. Linux (x86, ARM, tested on
  Raspberry Pi). Latest 1.5.0 (PyPI upload 2026-08-19); active.
- **What it shows**: CPU temperature, frequency, power and utilization
  graphs; explicitly not a process monitor. Power read on Intel Sandy
  Bridge+ and AMD 17h via `amd_energy` hwmon. The standout is throttle
  labeling: with root + the `msr` module on Intel it reads
  `IA32_THERM_STATUS` and appends reason letters to the graph and summary:
  `T` thermal (over TjMax), `H` PROCHOT external signal, `C` critical, `W`
  power limit (PL1/PL2), `A` current limit, `X` cross-domain; on AMD a
  `Pc` P-state cap from `PStateCurLim`; without root a sysfs fallback gives
  `Tc`/`Tp` core/package thermal throttle. Labels combine (`T/W`).
- **How it shows it**: graphs on the right, a control sidebar on the left
  (radio buttons for mode, checklists for which graphs and summaries to
  show, Reset/Save Settings/UTF-8/Quit buttons), sensor values as a text
  strip at the bottom. Graphs and text change color when a threshold is
  crossed (default 80 C, `--t_thresh`). A built-in stress test (numpy BLAS
  matmul, SHA-256 fallback without numpy) plus optional stress/stress-ng
  integration. `hooks.d` shell scripts fire every 30 s while a threshold is
  exceeded. Modes: `--csv`, `--json`, `-t` one-line output.
- **Ideas worth taking**: reason-coded throttling indicators on the chart
  itself; "watch the metric while you stress the machine" workflow; threshold
  color change plus user hook scripts.
- **Weaknesses / avoid**: CPU-only scope; urwid block charts look dated.
- **Sources**:
  https://raw.githubusercontent.com/amanusk/s-tui/master/README.md,
  https://pypi.org/pypi/s-tui/json

### bandwhich

- **Status**: Rust, MIT. Linux, macOS, Windows, Android (best effort).
  Latest
  v0.23.1 (2024-10-08); explicitly in passive maintenance (critical fixes
  only, co-maintainers wanted).
- **What it shows**: live network utilization attributed three ways at once:
  per process, per connection, per remote address/hostname; optional DNS
  query display (`-s`); cumulative totals (`-t`); selectable unit family
  (binary bytes/bits, SI bytes/bits).
- **How it shows it**: three stacked tables (Processes / Connections /
  Remote Addresses), or one via `-p`/`-c`/`-a`; a header bar shows total
  utilization. It sniffs packets on an interface and cross-references
  `/proc` (Linux), `lsof` (macOS) or the WinAPI. Reverse DNS resolves
  addresses in the background. The layout degrades by terminal width
  (columns dropped when narrow). Requires `cap_net_raw,cap_net_admin` +
  `cap_sys_ptrace,cap_dac_read_search` via setcap, or sudo.
- **Ideas worth taking**: bandwidth attributed simultaneously to process,
  connection and peer; width-responsive column dropping; hostname resolution
  as a background nicety.
- **Weaknesses / avoid**: needs elevated privileges; tables only, no
  history or graphs; unmaintained feature-wise.
- **Sources**:
  https://raw.githubusercontent.com/imsnif/bandwhich/main/README.md,
  https://github.com/imsnif/bandwhich/releases.atom

### atop

- **Status**: C, GPL-2.0. Linux. Latest 2.13.0 (2026-07-18); actively
  maintained. Optional `netatop` kernel module (3.2.2, 2024-06-01
  (unverified)) adds per-process network accounting.
- **What it shows**: system-level CPU/memory/swap/disk (incl. LVM)/network
  plus process-level CPU, memory growth, disk IO, priority, user, state and
  exit code, including processes that exited inside the interval (PRC line
  `#exit`, ST=`E`, EXCODE column). Views: generic, scheduling (`s` keys:
  policy, nice, rt-prio, per-state thread counts), memory (`m`: VSIZE/RSIZE
  plus VGROW/RGROW growth columns), disk (`d`: RDDSK/WRDSK/WCANCL cancelled
  writes), misc (`v`), command line (`c`), per-process network (`n` with
  netatop). Per-user and per-program accumulations; cgroup v2 utilization
  with PSI pressure values. Writes compressed raw counters to daily logs,
  kept 28 days by default; `atopsar` generates reports; replay with
  `atop -r` and `t`/`T` stepping (`atop -Br y` = yesterday in bar mode).
- **How it shows it**: top half labeled system lines (PRC/CPU/CPL/MEM/SWP/
  PAG/LVM/DSK/NET), bottom half the process table. Key `B` switches to a
  character bar-graph mode: per-CPU bars labeled by category letters (S
  system, U user, I irq, G guest), disk bars split R/W, NIC bars TX/RX (no
  percentage where max bandwidth is unknown), memory bars by slab/shmem/
  pagecache/free plus scan/swapout/oomkill event counters. Columns are added
  and removed as the window is widened or narrowed. Resources near overload
  are highlighted by color. By default only active resources/processes are
  shown.
- **Ideas worth taking**: exited-process accounting (the spike's culprit can
  be a process that already quit); record-everything-then-replay as a first
  class workflow; width-adaptive columns; overload highlighting; the honest
  "bandwidth unknown, no %" choice on interfaces.
- **Weaknesses / avoid**: cryptic abbreviations, steep learning curve;
  per-process network needs an out-of-tree kernel module.
- **Sources**:
  https://www.atoptool.nl/,
  https://www.atoptool.nl/screenshots.php,
  https://raw.githubusercontent.com/Atoptool/atop/master/COPYING

### below

- **Status**: Rust, Apache-2.0, Meta. Linux only, requires cgroup v2.
  Latest v0.11.0 (2025-09-24); no newer release in the year before the
  access date.
- **What it shows**: hardware resource utilization, the cgroup hierarchy
  with per-cgroup stats, process info, PSI pressure stall data, ethtool
  stats, resctrl, slabinfo, zswap, memory.min (0.8.0 additions).
- **How it shows it**: four modes on one store: `below live` interactive
  TUI; `below record` daemon (shipped as a systemd service) writing
  persistent history; `below replay -t "3m ago"` time-travel with relative
  timestamps; `below snapshot` for a replayable file; `below dump` emits
  JSON, CSV or OpenMetrics for scripts (basic Prometheus/Grafana path via
  contrib). The name is a stated rejection of atop's design choices
  (unverified).
- **Ideas worth taking**: relative-time replay UX (`-t "3m ago"`) is the
  friendliest possible API for history; a record daemon plus snapshot file
  format; headless dump formats alongside the TUI.
- **Weaknesses / avoid**: cgroup-v2-only and Linux-only; recording needs
  root; TUI itself is plain.
- **Sources**:
  https://raw.githubusercontent.com/facebookincubator/below/main/README.md,
  https://github.com/facebookincubator/below/releases.atom

### asitop

- **Status**: Python (dashing + psutil), MIT. macOS Apple Silicon only.
  Latest PyPI release 0.0.24 (2023-06-17); not released in 3+ years but still
  the commonly cited tool of its class.
- **What it shows**: E-cluster and P-cluster CPU frequency and utilization,
  GPU utilization/frequency, ANE utilization measured via power, RAM and
  swap, CPU/GPU/ANE/package power in watts, a power history chart with peak
  and rolling-average readouts. README notes Apple removed package power and
  memory bandwidth from `powermetrics`.
- **How it shows it**: dashing gauges: per-cluster bars and a strip-chart
  for watts; flags `--interval`, `--color 0-8`, `--avg` (averaging window).
  Data collection shells out to `sudo powermetrics` (CPU/GPU active
  residency, frequencies, energy counters, DRAM bandwidth via the DCS
  counter where still exposed), plus psutil (memory), sysctl (CPU name,
  core counts) and `system_profiler` (GPU core count). TDP and max
  bandwidth figures are hardcoded estimates.
- **Ideas worth taking**: splitting E vs P clusters as first-class meters;
  ANE utilization surfaced via power when no counter exists; peak + rolling
  average annotations on a power chart.
- **Weaknesses / avoid**: requires sudo (powermetrics needs root); stale
  release; several numbers are hardcoded guesses; Apple keeps removing
  powermetrics fields.
- **Sources**:
  https://raw.githubusercontent.com/tlkh/asitop/main/README.md,
  https://pypi.org/pypi/asitop/json

### macmon

- **Status**: Rust, MIT. Apple Silicon Macs (M1-M5). Latest 0.10.0
  (crates.io, updated 2026-10-14); active. brew, MacPorts, cargo, nix.
- **What it shows**: CPU/GPU/ANE power in watts, CPU frequency-scaled and
  active ratios per cluster, RAM/swap, average CPU/GPU temperature,
  historical sparkline charts with average and max values, and a process
  list with per-process CPU, memory, power and GPU usage.
- **How it shows it**: metric boxes on top, process table below; `/`
  filters processes; follows the terminal's own color scheme instead of a
  theme file; designed to still read correctly in a small window.
  Subcommands make the collector a library: `pipe` (JSON to stdout),
  `serve` (HTTP + Prometheus endpoints, with launchd install/uninstall
  commands), `debug`, `stress` (generate load to verify metrics). Also
  usable as a Rust crate. Key point: it reads the same data powermetrics
  exposes through a private macOS API without root. macOS 27 caveat: the
  named IOReport Energy Model power counters now need a private
  entitlement (sudo does not help), so macmon reads hidden AppleCLPC
  energy reports through opaque IDs instead, maintaining undocumented
  counter mappings.
- **Ideas worth taking**: sudoless Apple Silicon telemetry is proven
  possible; per-cluster frequency-scaled ratios; JSON pipe + Prometheus as
  built-in first-class outputs; "follow the terminal theme" restraint.
- **Weaknesses / avoid**: private API surface can break per macOS release
  (macOS 27 did restrict several rootless power counters);
  averages only for temperatures (no per-sensor list like mactop).
- **Sources**:
  https://github.com/vladkens/macmon,
  https://crates.io/crates/macmon,
  https://github.com/vladkens/macmon/blob/main/changelog.md

### mactop

- **Status**: Go + CGO, MIT. Apple Silicon, macOS 12.3+. Latest v2.1.6
  (2026-09-30); very active. No sudo for reads (native SMC, IOReport, IOKit,
  IOHIDEventSystemClient); root only for fan-speed writes.
- **What it shows**: CPU/GPU/ANE/DRAM/system wattage; E, P and (M5) S-core
  per-core usage via the Mach kernel API; all SMC temperature sensors with
  human-readable labels; thermal state; fan RPM/target/mode plus optional
  interactive or one-shot fan control; memory usage plus kernel memory
  pressure (`kern.memorystatus_vm_pressure_level`) with an approximate
  green/yellow/red history like Activity Monitor's; DRAM read/write
  bandwidth in GB/s (AMC DCS counters on M1-M4, PMP AMCC histograms on M4
  Pro/Max, calibrated power-based estimation on M5+); network up/down;
  Thunderbolt bandwidth, a Thunderbolt/USB4 device tree, RDMA-over-TB5
  detection; battery; disk IO; listening TCP/UDP ports; multiple volumes;
  experimental per-process GPU share.
- **How it shows it**: TUI with 22 named layouts cycled by `l` (a
  `history_soc` layout of four large step-charts for CPU/GPU/ANE/DRAM
  bandwidth, a memory-pressure layout, a ports layout); `c`/`b`/`p` cycle
  foreground/background/party colors; layout and theme persist across runs;
  auto light/dark detection; `f` freezes updates; F9 kills with
  confirmation; `/` filters; vim keys. Headless mode prints JSON/YAML/XML/
  CSV/TOON. Optional Prometheus endpoint. `--menubar` runs a menu-bar status
  item with sparklines and gauges. `--overlay` runs a floating HUD with FPS
  and frame-interval sparklines via CGDisplayStream (needs Screen Recording
  permission); overlay sections, order and opacity configurable in
  `~/.mactop/config.json`; `theme.json` supports per-component colors.
  20-language i18n.
- **Ideas worth taking**: the Apple Silicon metric set itself (ANE, DRAM
  bandwidth, Thunderbolt bandwidth, per-SMC-sensor temps, thermal state,
  kernel memory pressure); named layouts as presets; menu-bar sparkline +
  FPS overlay as separate surfaces; multi-format headless output.
- **Weaknesses / avoid**: feature sprawl (party mode, 20 languages) reads as
  everything-but-the-kitchen-sink; fan control writes to SMC (risk surface);
  heavy private-API reliance.
- **Sources**:
  https://raw.githubusercontent.com/metaspartan/mactop/main/README.md,
  https://github.com/metaspartan/mactop/releases.atom

### Mission Center

- **Status**: Rust + GTK4/libadwaita, GPL-3.0. Linux via Flatpak (official),
  AppImage, Snap; preinstalled on several immutable distros (Aurora, Bazzite,
  Bluefin). Version 1.2.0 (per the AppImage artifacts linked from the
  README); active. GPU metrics powered by a vendored NVTOP.
- **What it shows**: per-resource performance pages: CPU overall or
  per-thread plus process/thread/handle counts, uptime, base and current
  clock, cache sizes; RAM/swap with a usage breakdown; disk utilization and
  transfer rates; per-interface network (card name, connection type, Wi-Fi
  speed and frequency, hardware and IP addresses); GPU usage, video
  encode/decode, memory and power; system fans; SMART data (udisks);
  Applications and Services pages for per-app/per-process breakdown and
  systemd unit management.
- **How it shows it**: deliberately modeled on the Windows 11 Task Manager:
  a left sidebar lists devices (CPU, GPU, memory, each network interface,
  drives, fans) each rendered as a live thumbnail graph; selecting one shows
  the large graph plus stats. The sidebar can be hidden for a full-graph
  "summary view", and devices can be hidden and reordered. Rows
  collapse/expand on double-click or arrow keys; holding CTRL pauses
  refreshes; Alt+1/2/3 switch pages; units are configurable (bits vs bytes,
  base-2 vs base-10); optional "sliding graphs" animation (interaction
  details unverified); all graphs are
  hardware-accelerated to keep the monitor's own CPU cost low. Being
  libadwaita it intentionally ignores system stylesheets.
- **Ideas worth taking**: live per-resource thumbnails in the navigation
  sidebar (the overview is also the navigation); device visibility/order
  controls; hold-to-pause; a dedicated Applications vs Processes split;
  GPU-accelerated plotting as an explicit engineering goal.
- **Weaknesses / avoid**: per-process network requires manual nethogs setup;
  not themeable by design; fixed page taxonomy.
- **Sources**:
  https://gitlab.com/mission-center-devs/mission-center/-/raw/main/README.md,
  https://missioncenter.io/,
  https://flathub.org/en/apps/io.missioncenter.MissionCenter,
  https://www.xda-developers.com/replace-ubuntu-system-monitor-with-this-stunning-tool/,
  https://www.omgubuntu.co.uk/2025/05/mission-center-1-0-adds-new-features

### Resources (GNOME)

- **Status**: Rust + GTK4/libadwaita, GPL-3.0-or-later. Linux, Flatpak-only
  supported install. Latest 51.0 (2026-09-12); recently moved into the GNOME
  Incubator on GNOME GitLab.
- **What it shows**: CPU, memory, GPUs, NPUs, network interfaces, block
  devices, batteries; Apps and Processes lists with terminate actions.
  Stated scope rule: "most of the information most people need most of the
  time", not every counter.
- **How it shows it**: a libadwaita app with an Apps page, a Processes page,
  and one page per device/resource (Processor, Memory, GPU, Drive, Network
  Interface, Battery) combining graphs with detail rows; light/dark theme
  support.
- **Ideas worth taking**: an explicit information-budget philosophy; NPU as
  a first-class resource page; per-device pages so each disk/interface/
  battery gets its own graph plus details.
- **Weaknesses / avoid**: Flatpak sandbox causes app/process detection
  issues on some distros (NixOS); little customization.
- **Sources**:
  https://raw.githubusercontent.com/nokyan/resources/main/README.md,
  https://apps.gnome.org/Resources/

### GNOME System Monitor

- **Status**: C++ (gtkmm4 + libgtop), GPL-2.0. Linux, ships with GNOME.
  Latest 51.1 (2026-10-06); maintained.
- **What it shows**: three views: Processes (tree view, app icons, search,
  hide processes, kill/renice), Resources (CPU history,
  Memory and Swap history, Network history), File Systems.
- **How it shows it**: the Resources tab is the canonical minimal design:
  three stacked labeled graphs, each with the current value in the label and
  a scrolling area/line history; graphs animate by sliding rather than
  redrawing (Mission Center added an option to mimic this). Preferences are
  limited to update interval, units and which columns show.
- **Ideas worth taking**: a fixed, small set of smooth-sliding graphs is
  enough for casual use; per-tab split (processes / resources / filesystems).
- **Weaknesses / avoid**: graphs carry no axes or scale; few metrics; the
  graph area stays a minority of the window.
- **Sources**:
  https://gitlab.gnome.org/GNOME/gnome-system-monitor/-/raw/master/README.md,
  https://apps.gnome.org/SystemMonitor/,
  https://download.gnome.org/sources/gnome-system-monitor/49/

### KDE Plasma System Monitor

- **Status**: Qt/QML, GPL-2.0/3.0. Linux; released alongside KDE Plasma
  (apps.kde.org lists 6.3.90 from 2025-05-15 as the newest indexed version).
  Reads sensors from the ksystemstats daemon.
- **What it shows**: any sensor ksystemstats exposes (CPU, memory, GPU,
  disks, network, temperatures, fan, per-device) plus process and
  application tables.
- **How it shows it**: the most interesting customization model in this
  list. A page is a `.page` file (INI format, user pages live in
  `~/.local/share/plasma-systemmonitor`) containing a grid of "faces": each
  `Face-*` section picks a `chartFace` plugin such as
  `org.kde.ksysguard.piechart`, `linechart`, `barchart`, `horizontalbars`,
  `textonly`, `applicationstable` or the process table, then binds sensors
  via three roles: `highPrioritySensorIds` (the charted series, supports
  regex like `network/(?!all).*/download`), `totalSensors` (defines the
  100% reference) and `lowPrioritySensorIds` ("Text-Only Sensors" rendered
  as legend values). Faces are QML packages with a `FullRepresentation`
  (with title/legend) and a `CompactRepresentation` for tight spaces; the
  same face renders in the app page and as a Plasma panel/desktop widget,
  configured through `main.xml` (KConfigXT) + `Config.qml`. An in-app edit
  mode lets users add/remove/rearrange faces on a page.
- **Ideas worth taking**: one visualization component with full and compact
  representations reused across contexts (main view, panel, widget);
  the sensor-role model (series / total reference / text-only footer);
  regex binding to "all disks" or "all interfaces" without enumeration;
  user-editable pages as shareable files.
- **Weaknesses / avoid**: real power but low discoverability; default faces
  look plain; editing requires understanding the sensor naming scheme.
- **Sources**:
  https://invent.kde.org/plasma/plasma-systemmonitor/-/raw/master/README.md,
  https://github.com/KDE/plasma-systemmonitor/blob/master/src/pages/overview.page,
  https://develop.kde.org/docs/apps/sensor-faces/,
  https://apps.kde.org/plasma-systemmonitor/,
  https://discuss.kde.org/t/configure-system-monitor-widgets/50037

### Netdata

- **Status**: agent in C+Go, GPL-3.0+; dashboard UI described by Netdata as
  closed-source but free to use under the NCUL1 license, served via CDN
  (a bundled fallback copy (unverified)).
  Linux, macOS, FreeBSD, Windows. Latest v2.12.1 (2026-10-08); very active;
  optional free Cloud tier.
- **What it shows**: auto-discovered per-second metrics across CPU, memory,
  disks, network, sensors, containers, VMs, applications, eBPF probes and
  logs; unsupervised ML anomaly detection trains multiple models per metric
  at the edge; ~0.5 bytes/sample storage with tiered retention; per-chart
  collection status and alerting.
- **How it shows it**: every chart has the same anatomy: title bar (name,
  unit, live/error status), an anomaly-rate ribbon above the plot area
  showing per-second anomaly rate over time, a "definition bar" of dropdowns
  (group by, aggregation function, nodes, instances, dimensions, labels,
  time aggregation) where each item lists its number of time series,
  instance count, volume-%, anomaly-% and min/avg/max over the visible
  window; the chart area; and a legend of colored dimensions (click to
  isolate, sortable by name/value/anomaly). Highlighting a region invokes
  Metric Correlations to find other metrics that behaved the same. Data
  model ("NIDL": Nodes, Instances, Dimensions, Labels) means slicing is done
  with dropdowns instead of a query language; deliberate constraints (one
  aggregation per chart, one context per chart) keep the mental model
  simple. Custom dashboards are drag-and-drop with charts retaining full
  interactivity. Tabs: Home, Nodes, Metrics, Live, Dashboards, Alerts,
  Events (unverified).
- **Ideas worth taking**: anomaly-rate ribbon above each chart; dropdowns
  that expose per-item stats for the visible window (volume %, anomaly %,
  min/avg/max) rather than just names; highlight-to-correlate; "if it is
  collected it is visible" auto-dashboards; per-second default granularity.
- **Weaknesses / avoid**: fleet/infra scope far beyond a desktop monitor;
  UI license is not open (NCUL1, free to use); the full NIDL chrome would
  be overkill per-card.
- **Sources**:
  https://raw.githubusercontent.com/netdata/netdata/master/README.md,
  https://learn.netdata.cloud/docs/dashboards-and-charts,
  https://learn.netdata.cloud/docs/dashboards-and-charts/charts,
  https://learn.netdata.cloud/docs/dashboards-and-charts/nidl-framework,
  https://github.com/netdata/netdata/releases.atom

### Conky

- **Status**: C, GPLv3. X11, Wayland (with caveats), macOS, BSDs. Latest
  v1.25.4 (2026-10-14); actively maintained.
- **What it shows**: 300+ built-in objects: CPU per core, load, memory/
  swap, filesystem usage, disk IO, network (up/down rates, addresses, Wi-Fi
  SSID/bitrate), battery, temperatures/fans via hwmon/acpi, top-N processes
  by CPU or memory, plus IMAP/POP3 mail counts and MPD/XMMS2/Audacious
  players; `exec`/`execi` objects run arbitrary shell.
- **How it shows it**: renders text, bars and graphs directly onto the
  desktop (own window types: normal, desktop, override, panel, dock) or
  outputs to console/file/HTTP. Config is Lua-flavored
  `conky.config = {...}` + `conky.text = [[...]]` with `${object}` expansion,
  per-fragment fonts/colors, `${cpugraph}`, `${membar}`, `${diskiograph}`
  style graph objects; Lua scripts with Cairo and Imlib2 bindings draw
  custom widgets (the classic ring meters); mouse events on regions; double
  buffering; X11 alpha-based input shaping for click-through on transparent
  pixels (v1.25.4); SIGUSR1 reloads config without window flash
  (unverified); an HTTP
  output with a Lua response hook exists (v1.25.3).
- **Ideas worth taking**: ambient always-on desktop rendering (monitor as
  wallpaper); scriptable object vocabulary; click-through transparency for
  non-interactive displays; live config reload.
- **Weaknesses / avoid**: text-file configuration only, no GUI;
  X11-centric heritage; fiddly to theme.
- **Sources**:
  https://raw.githubusercontent.com/brndnmtthws/conky/main/README.md,
  https://github.com/brndnmtthws/conky/releases.atom

### Cockpit

- **Status**: web-based server admin UI, LGPL-2.1+, Red Hat sponsored.
  Linux servers; access on port 9090. Latest 368 (2026-10-06); time-based
  release every two weeks.
- **What it shows**: a high-level overview page (health, CPU/memory/disk/
  network), a metrics view that correlates CPU load, memory, network and
  storage performance with the system journal, plus services, storage
  (RAID/LUKS), networking, logs, software updates with CVE links,
  containers and VMs.
- **How it shows it**: PatternFly web app; systemd socket activation means
  it runs on demand and consumes nothing when closed; uses the system's own
  APIs and tools rather than a parallel agent; system logins/privileges
  apply; a sidebar switches between multiple hosts; includes an embedded
  terminal; extensible via packaged add-ons; design iterated through
  usability studies.
- **Ideas worth taking**: metrics correlated with log events on a shared
  timeline; "glanceable" overview as a deliberate product goal; zero-cost
  idle model; management actions sitting next to the metrics they affect.
- **Weaknesses / avoid**: server-administrator scope, not a dense
  resource-monitor UI; chart depth is modest.
- **Sources**:
  https://cockpit-project.org/

### Beszel

- **Status**: Go agent + PocketBase hub, MIT. Self-hosted web app. Latest
  v0.21.0 (2026-10-02); active.
- **What it shows**: CPU, memory (incl. swap and ZFS ARC), disk usage and IO
  per device/partition, network, load average, temperatures, fans
  (`/sys/class/hwmon`), GPU usage/power (NVIDIA, AMD, Intel), battery, full
  Docker/Podman container list with per-container CPU/memory/network
  history, SMART disk health (incl. eMMC wear and mdraid), ZFS pool stats,
  and agent-side network monitors (ICMP/TCP/HTTP/DNS latency and loss).
- **How it shows it**: the hub dashboard lists systems as compact
  cards/rows with mini charts; a per-system page shows the full chart set
  including per-container history. Alerts are configurable for most metrics
  with 20+ notification services; multi-user with per-user systems, OAuth/
  OIDC, automatic backups to disk/S3, REST API. Agent is deliberately tiny
  and needs no public exposure.
- **Ideas worth taking**: per-container history without a heavyweight stack;
  alerting breadth from a simple UI; the hub/agent split done minimally.
- **Weaknesses / avoid**: fleet-oriented list+drilldown, not a visual-first
  single-machine tool; charts functional rather than polished.
- **Sources**:
  https://beszel.dev/,
  https://beszel.dev/guide/what-is-beszel,
  https://github.com/henrygd/beszel,
  https://github.com/henrygd/beszel/releases.atom

## Cross-cutting patterns

- **Glyph resolution ladder**: ASCII/UTF-8 fallback chain appears
  everywhere (htop graph mode braille vs `.`/`:`; gotop/btop braille vs
  block vs tty). Design graph rendering so it degrades in fidelity rather
  than breaking; on macOS this maps to Metal-accelerated lines vs
  lower-DPI/compact variants.
- **Semantic color over decoration**: stacked CPU-time categories
  (htop), threshold bands (glances `careful/warning/critical`), overload
  highlight (atop), throttle reasons (s-tui), memory-pressure states
  (mactop, Activity Monitor). Color encodes a verdict, not a palette.
- **Customization depth spectrum**: fixed layout (GNOME SM) < in-app
  setup UI (htop F2, nvtop F2/F12) < named presets (btop `presets`, mactop
  layouts) < declarative files (gotop DSL, btm config, KDE `.page`) < full
  scripting (Conky Lua). A GUI should pick preset+picker depth: btop
  presets + KDE-style face/sensor picker cover most of the value without a
  page editor.
- **Time interaction**: scroll-back + zoom (btm, zenith), persistent DB
  (zenith), record+replay (atop logs, below `-t "3m ago"`), live-vs-history
  toggle. Ring-buffer history with scrubbing is the single most-requested
  capability this class normalizes.
- **Attribution next to the metric**: atop keeps exited processes visible
  with exit codes; bandwhich splits by process/connection/peer; Mission
  Center separates Apps from Processes; btop embeds per-process mini-graphs.
- **Privilege-aware collection**: capabilities vs sudo on Linux
  (bandwhich setcap, nvtop CAP_PERFMON, zenith delay accounting, btop CPU
  watts); on macOS the split is `sudo powermetrics` (asitop) vs private
  frameworks IOReport/SMC/IOHIDEventSystem (macmon, mactop, btop 1.4.7).
- **One collector, many surfaces**: glances (TUI/WebUI/REST/exports/MCP),
  macmon (TUI/JSON pipe/Prometheus/library), mactop (TUI/headless/
  Prometheus/menubar/overlay), below (TUI/record/dump), conky (desktop/
  console/HTTP). Separating sampling from rendering pays off repeatedly.
- **Compact vs full representation**: KDE faces ship both representations
  and get reuse in app + panel for free; mactop's menubar mode and
  Mission Center's summary view do the same by hand. A shared "compact"
  rendering path enables menu-bar and widget surfaces later.
- **Also seen, lower priority**: `top`/procps lineage, `nmon` (pure-ASCII
  dashboard with toggleable widgets), `iftop`/`iotop`/`nethogs`/`slabtop`/
  `systemd-cgtop`/`virt-top`/`ctop` (single-metric tops), `gtop`/`vtop`
  (Node predecessors of gotop/btm), `bashtop`/`bpytop` (btop ancestors),
  `pcp-htop` (htop on Performance Co-Pilot metrics), `dstat`/`dool`,
  sysstat (`sar`, `iostat`, `mpstat`), `kSysGuard` (deprecated predecessor
  of Plasma System Monitor).

## Implications for Coreography

1. **Make the shared time axis first-class**: scroll-back pan, pinch/scroll
   zoom, and a "return to live" affordance (zenith's backtick). Keep a
   ring buffer of at least several minutes in memory; a user-visible
   "history" mode (below's `-t "3m ago"` model) can come later.
2. **Dual-band graphs for paired metrics**: adopt btop's upper/lower split
   (invertible) for CPU usage+frequency, power+temperature, and the
   mirrored in/out form for network and disk like iStat already does.
3. **Color as verdict**: semantic palette for pressure/thermal/throttle
   states (green/yellow/red memory pressure, thermal-state color, s-tui
   style reason labels rendered on the chart), not decorative gradients.
   Thresholds should be user-configurable like glances' careful/warning/
   critical keys.
4. **Apple Silicon telemetry without sudo is the baseline**: IOReport,
   SMC and IOHIDEventSystemClient cover power, frequencies, temps, fans,
   ANE and DRAM bandwidth (macmon/mactop prove it; btop uses IOReport for
   GPU). On macOS 27 several rootless energy counters moved behind a
   private entitlement; plan fallbacks (macmon's AppleCLPC route,
   mactop's bandwidth-derived ANE). Keep `powermetrics` as an optional
   fallback only. First-class
   meters: E/P(/S) cluster bars, per-core heat strip, ANE, DRAM bandwidth,
   thermal state, fan RPM, Thunderbolt bandwidth.
5. **Attribution on every card**: top processes per subsystem beside its
   graph; count exited processes in interval attribution (atop) so a
   transient spike still names a culprit; separate "Apps" vs raw processes
   like Mission Center.
6. **Presets, not a page editor (v1)**: ship named layouts (btop presets /
   mactop layouts / KDE pages are all this idea), per-card metric pickers
   (nvtop's chart assignment, KDE sensor roles), device hide/reorder
   (Mission Center sidebar). Defer freeform composition.
7. **Chart anatomy to copy from Netdata**: legend doubles as a sortable
   stat table for the visible window (min/avg/max per series); highlight a
   range to filter/zoom; a thin "state ribbon" above charts (anomaly or
   throttle/pressure events) is a high-value second-monitor signal.
8. **Performance is a feature**: hardware-accelerated drawing (Mission
   Center's explicit goal), sub-second sampling only where it pays (Netdata
   per-second as ceiling), and a hold-to-pause affordance (Mission Center's
   CTRL) so the monitor does not fight the workload being watched.
9. **Collector/view separation**: build the sampling layer so a future
   JSON/CSV export or menu-bar sparkline surface is a renderer, not a
   rewrite (macmon `pipe`/`serve`, glances exports, below `dump`).
10. **Compact representation reuse**: design each card to render in a
    collapsed "strip" form (KDE CompactRepresentation, mactop menubar) so a
    menu-bar extra or compact window mode reuses the same drawing code.
11. **Config details worth mirroring**: units toggles (bits/bytes, base
    2/10: Mission Center, bandwhich), update-interval control (btop
    `update_ms`, mactop `-`/`+`), temperature scale, disk include/exclude
    filters, per-process peak markers (zenith 0.15.0), and "zeroed until
    first sample" honesty (btm 0.14.9, TMOG rule).
12. **Anti-goals**: no freeform Conky-style scripting, no regex sensor
    syntax exposed in UI (KDE's power hides well behind pickers, not
    strings), no per-30s hook scripts, no "party mode".

## Sources

- https://github.com/aristocratos/btop
- https://raw.githubusercontent.com/aristocratos/btop/main/README.md
- https://github.com/aristocratos/btop/releases.atom
- https://github.com/htop-dev/htop
- https://raw.githubusercontent.com/htop-dev/htop/main/README.md
- https://raw.githubusercontent.com/htop-dev/htop/main/Meter.c
- https://manpages.debian.org/unstable/htop/htop.1.en.html
- https://github.com/htop-dev/htop/releases.atom
- https://github.com/nicolargo/glances
- https://raw.githubusercontent.com/nicolargo/glances/develop/README.rst
- https://raw.githubusercontent.com/nicolargo/glances/develop/COPYING
- https://glances.readthedocs.io/en/latest/config.html
- https://glances.readthedocs.io/en/latest/quickstart.html
- https://github.com/nicolargo/glances/releases.atom
- https://raw.githubusercontent.com/ClementTsang/bottom/master/README.md
- https://raw.githubusercontent.com/ClementTsang/bottom/master/LICENSE
- https://github.com/ClementTsang/bottom/releases.atom
- https://raw.githubusercontent.com/Syllo/nvtop/master/README.markdown
- https://github.com/Syllo/nvtop/releases.atom
- https://raw.githubusercontent.com/bvaisvil/zenith/master/README.md
- https://raw.githubusercontent.com/bvaisvil/zenith/master/LICENSE
- https://github.com/bvaisvil/zenith/releases.atom
- https://raw.githubusercontent.com/xxxserxxx/gotop/master/README.md
- https://raw.githubusercontent.com/xxxserxxx/gotop/master/docs/layouts.md
- https://raw.githubusercontent.com/xxxserxxx/gotop/master/LICENSE
- https://github.com/xxxserxxx/gotop/releases.atom
- https://raw.githubusercontent.com/amanusk/s-tui/master/README.md
- https://pypi.org/pypi/s-tui/json
- https://raw.githubusercontent.com/imsnif/bandwhich/main/README.md
- https://github.com/imsnif/bandwhich/releases.atom
- https://www.atoptool.nl/
- https://www.atoptool.nl/screenshots.php
- https://raw.githubusercontent.com/Atoptool/atop/master/COPYING
- https://raw.githubusercontent.com/facebookincubator/below/main/README.md
- https://raw.githubusercontent.com/facebookincubator/below/main/LICENSE
- https://github.com/facebookincubator/below/releases.atom
- https://raw.githubusercontent.com/tlkh/asitop/main/README.md
- https://pypi.org/pypi/asitop/json
- https://github.com/vladkens/macmon
- https://crates.io/crates/macmon
- https://github.com/vladkens/macmon/blob/main/changelog.md
- https://raw.githubusercontent.com/vladkens/macmon/main/Cargo.toml
- https://raw.githubusercontent.com/metaspartan/mactop/main/README.md
- https://raw.githubusercontent.com/metaspartan/mactop/main/LICENSE
- https://github.com/metaspartan/mactop/releases.atom
- https://gitlab.com/mission-center-devs/mission-center/-/raw/main/README.md
- https://missioncenter.io/
- https://flathub.org/en/apps/io.missioncenter.MissionCenter
- https://www.xda-developers.com/replace-ubuntu-system-monitor-with-this-stunning-tool/
- https://www.omgubuntu.co.uk/2025/05/mission-center-1-0-adds-new-features
- https://itsfoss.com/mission-center/
- https://raw.githubusercontent.com/nokyan/resources/main/README.md
- https://apps.gnome.org/Resources/
- https://gitlab.gnome.org/GNOME/gnome-system-monitor/-/raw/master/README.md
- https://apps.gnome.org/SystemMonitor/
- https://download.gnome.org/sources/gnome-system-monitor/51/
- https://invent.kde.org/plasma/plasma-systemmonitor/-/raw/master/README.md
- https://github.com/KDE/plasma-systemmonitor/blob/master/src/pages/overview.page
- https://develop.kde.org/docs/apps/sensor-faces/
- https://apps.kde.org/plasma-systemmonitor/
- https://discuss.kde.org/t/configure-system-monitor-widgets/50037
- https://raw.githubusercontent.com/netdata/netdata/master/README.md
- https://learn.netdata.cloud/docs/dashboards-and-charts
- https://learn.netdata.cloud/docs/dashboards-and-charts/charts
- https://learn.netdata.cloud/docs/dashboards-and-charts/nidl-framework
- https://github.com/netdata/netdata/releases.atom
- https://raw.githubusercontent.com/brndnmtthws/conky/main/README.md
- https://github.com/brndnmtthws/conky/releases.atom
- https://cockpit-project.org/
- https://beszel.dev/
- https://beszel.dev/guide/what-is-beszel
- https://github.com/henrygd/beszel
- https://github.com/henrygd/beszel/releases.atom

## Verification log

Fact-check pass on 2026-10-17 against upstream sources (GitHub releases
APIs and feeds, PyPI and crates.io JSON, official project pages).

### What was checked

- Release versions, dates and activity for every tool: btop v1.4.7
  (2026-05-01), htop 3.5.3 (2026-08-16), glances 4.5.8 (2026-10-11,
  ~33.8k stars), bottom 0.14.9 (2026-08-27), nvtop 3.3.2 (2026-02-08),
  zenith 0.15.1 (2026-09-02), gotop v4.2.0 (2022-09-29), s-tui 1.5.0
  (2026-08-19), bandwhich v0.23.1 (2024-10-08), atop 2.13.0 (2026-07-18),
  below v0.11.0 (2025-09-24), asitop 0.0.24 (2023-06-17), macmon 0.10.0
  (crates.io 2026-10-14), mactop v2.1.6 (2026-09-30), Mission Center 1.2.0
  (AppImage artifacts), Resources 51.0 (2026-09-12, apps.gnome.org),
  GNOME System Monitor 51.1 (2026-10-06, download.gnome.org), Netdata
  v2.12.1 (2026-10-08), Conky v1.25.4 (2026-10-14), Cockpit 368
  (2026-10-06), Beszel v0.21.0. All confirmed unless listed below.
- Feature claims against current READMEs/docs: btop (config keys,
  presets, graph symbols, hotkeys, C++23 badge, ~35k stars, Apache-2.0),
  htop Meter.c (Text/Bar/Graph/LED modes, `|#*@$%&.` monochrome bar
  characters, braille 4-pixels-per-row with `.`/`:` ASCII fallback),
  glances config docs (threshold keys with the exact 50/70/90 example,
  history_size=1200, left_menu, backtick dynamic values, /api/5, --fetch,
  --browser, MCP "available in Glances 4.5.1 and higher", export list),
  nvtop vendor matrix and kernel requirements, zenith usage and key
  bindings, gotop layouts/extensions/Sourcehut migration, s-tui throttle
  labels (T/H/C/W/A/X, AMD Pc, sysfs Tc/Tp) and hooks, bandwhich flags
  and capabilities, macmon and mactop metric/feature lists (including
  mactop's 22 layouts, fan control, DRAM bandwidth sources, overlay and
  menubar modes), Mission Center and Resources READMEs, KDE
  overview.page (chartFace plugin ids, highPrioritySensorIds regex,
  totalSensors, lowPrioritySensorIds) and the sensor-faces tutorial
  (FullRepresentation/CompactRepresentation, main.xml KConfigXT,
  Config.qml), Netdata charts docs (anomaly-rate ribbon, definition-bar
  dropdowns with volume/anomaly/min/avg/max, Metric Correlations, NIDL,
  ~0.5 bytes/sample, GPLv3+ agent, NCUL1 UI), Conky README and release
  notes (300+ objects, alpha input shaping in 1.25.4, Lua HTTP response
  hook in 1.25.3), Cockpit site (368, biweekly cadence, port 9090,
  socket activation, usability studies, CVE links, PatternFly), Beszel
  docs (PocketBase hub, metric list, 24 notification integrations).
- Link liveness: every source URL in the Sources list returned HTTP 200
  except the crates.io page for macmon, which blocks non-browser clients
  (403/404 via curl); the page itself is valid.

### Corrections made

- htop: removed the `-H` key claim; highlighting new/removed processes
  is a display option, not that key.
- glances: client/server mode described as the terminal client reading
  the server's REST API (was "XML-RPC on 61209"; port 61209/XML-RPC is
  the pre-4.x design); removed the unverified "URL suffix /10 sets page
  refresh" detail.
- nvtop: license corrected from 'GPL (GitHub reports "Other")' to
  GPL-3.0-or-later per the README; `-i` info-bar description corrected
  (secondary NvAPI clock domains; static specs are `-X`).
- bandwhich: removed FreeBSD from the platform list (README support
  table lists Linux, macOS, Windows, Android best-effort).
- atop: dropped the unverified "maintained since ~2009" claim.
- below: "maintained" qualified to note no release in the year before
  the access date.
- macmon: added the verified macOS 27 power-counter restriction and the
  AppleCLPC hidden-report workaround; weakness updated ("could break" ->
  "did break with macOS 27 power counters").
- Netdata: UI license restated as Netdata describes it (closed-source
  but free to use, NCUL1, via CDN); weakness "source-available" -> "not
  open (NCUL1)".
- Conky: SIGUSR1 config reload marked (unverified).
- Beszel: v0.21.0 date corrected 2026-09-20 -> 2026-10-02; "~30
  notification services" -> "20+" (docs list 24).
- GNOME System Monitor source link updated from the 49/ tarball
  directory to the current 51/ directory.
- Mission Center in-app interaction specifics (CTRL pause, Alt+1/2/3,
  sliding graphs) marked unverified; README confirms the rest.
- Summary and implications updated with the macOS 27 entitlement
  caveat for rootless energy counters.

### Remains unverified

- netatop "3.2.2 (2024-06-01)" (the GitHub repo publishes no releases
  or tags to check against).
- Conky SIGUSR1 reload behavior.
- Netdata tab names (Home/Nodes/Metrics/Live/Dashboards/Alerts/Events)
  and the bundled offline UI fallback.
- Mission Center keyboard interactions and units toggles (in-app
  behavior, not in the README; the cited articles cover the rest).
- below's name being a stated rejection of atop.
- glances COPYING bundling both LGPLv3 and GPLv3 texts (license itself
  confirmed as LGPL-3.0 from the README and PyPI).
- mactop claims beyond its README (all checked claims matched; the
  20-language and TOON-format details come from the README itself).
