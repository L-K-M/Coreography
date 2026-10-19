# Coreography

> [!IMPORTANT]
> LLM disclosure: This codebase was written with substantial help from large language models: AI coding agents working from the [`AGENTS.md`](AGENTS.md) brief in this repo.

A graph-first, native Mac system monitor, in early implementation.

**Development version:** v<!-- version -->0.1.0<!-- /version -->

The first slice collects whole-machine CPU activity and estimated used
memory, shows a minute of aligned graphs, and includes a numeric table
and the `coreo` diagnostic CLI. Holding the display keeps collection
running. Missing readings leave gaps instead of invented zeros.

The memory lane stacks app, wired, compressed and cached memory under the
physical-memory line, with a kernel pressure band above it. Its header and
numeric table add swap use, swap and page-in rates, and compression ratio.

The thermal lane plots the hottest SMC temperature over the pressure
bands and shows fan speeds; the power lane prefers the SMC system rail.

On Apple Silicon, the CPU lane names each core tier's activity and
frequency and the Power lane modeled CPU, GPU and ANE watts, all from
IOReport and labelled as estimates.

The GPU lane plots each GPU's driver-reported busy percentage and shows
memory in use. The power lane plots battery charge with an external-power
band, battery watts, time estimate and health; system draw is shown while
running on battery. The thermal lane shows system thermal pressure as a band;
temperatures and fans come with the sensor provider.

A toolbar picker shows the last minute, ten minutes or hour; an hour of
samples stays in memory, and charts keep every spike when zoomed out.

A menu bar extra shows CPU in the menu bar and opens mini lanes; it shares
the window's sampler and keeps sampling while the window is closed.

MCP clients can query the same read-only diagnostic tools through the
running app. Turn on Settings > MCP access; the app asks once for each
client app and lists approved clients with Revoke. For example, in an MCP
client's server list:

```json
{
  "mcpServers": {
    "coreography": {
      "command": "/Applications/Coreography.app/Contents/Helpers/coreo",
      "args": ["mcp", "--stdio"]
    }
  }
}
```

In the window, Ask Coreography answers plain-language questions with your
own Anthropic API key, stored in the Keychain from Settings, using the same
read-only tools.

`coreo mcp --stdio --standalone` samples in its own process instead,
without history or approval.

Shortcuts and Spotlight get actions for the system summary, top apps,
starting and stopping a recording, and finding who uses a port or has a
file open. `coreography://` links navigate only: `show`, `filter?q=`,
`find?port=` or `find?file=`, `process?pid=`, `range?seconds=`,
`record/start?name=`, `record/stop` and `hud/toggle`. No link or action
quits, signals or exports anything.

Dragging across any lane selects a range; a panel totals CPU-seconds and
disk bytes per app over it, tail apps included.

Hovering any lane moves one cursor through all of them: every header
shows its value at that time, and the CPU, memory and disk headers name
the apps that led then.

The process pane adds PID/start-time-safe CPU share, physical footprint
and disk read/write rates, with filtering, sorting and explicit restricted
or unreadable coverage. It refreshes every two seconds using public libproc
APIs. Footprints are not an additive system memory total. By default it
folds helpers into their app, using the process macOS holds responsible
or the enclosing app bundle; group totals mark unreadable members.

The process table also shows each process's TCP and UDP rates, from the
same private framework nettop uses, matched by PID and name so a reused
PID never borrows another process's bytes.

The network lane uses full-width interface MIB counters, with receive/send
graphs on the same time axis. It defaults to the published primary IPv4
interface, then IPv6, and allows explicit interface selection. Its numeric
table and chart accessibility descriptor retain missing-data states.

The disk lane reads each observed storage driver's byte counters. Automatic
selection requires one identified device and complete inventory; otherwise
choose a device. Registry identities keep physical and virtual drivers
separate, with missing data and inventory limits shown explicitly.

Attribution history, SoC providers, persistent history, power tools,
MCP and Ask are tracked in the [implementation ledger](docs/implementation.md).
The full product is still in progress.

The product definition lives in docs: a [research survey](docs/research/README.md)
of visual system monitors and the [product plan](docs/plan.md) built on it.

## Build and test

Native builds require macOS 26+, Xcode 26.6 and the shared
[`lkm-build`/`lkm-release` tools](https://github.com/L-K-M/release-tool).

```sh
swift test
scripts/build.sh --universal --zip --no-reveal
scripts/build.sh --run
```

Open `Coreography.xcodeproj` to build in Xcode. The shared scheme builds
the app and embeds `coreo` in `Coreography.app/Contents/Helpers/`.
CI uses the same assemble script directly, verifies both executable
slices and uploads `Coreography-v0.1.0-macos-universal.zip` after tests.
Development artifacts are ad-hoc signed, not notarized.

Portable engine tests also run on Linux; they need the SQLite headers
(`libsqlite3-dev`), which macOS includes. Linux `coreo doctor` reports
native sampling as unsupported; it does not manufacture Mac telemetry.

```sh
swift run coreo doctor
swift run coreo snapshot --once --json  # macOS only; CPU and memory detail
swift run coreo processes --once --json # macOS only; two-second baseline
swift run coreo network --once --json   # macOS only; per-interface byte rates
swift run coreo disks --once --json     # macOS only; per-storage-driver rates
swift run coreo gpu --once --json       # macOS only; per-GPU utilization
swift run coreo power --once --json     # macOS only; battery and adapter
swift run coreo sensors --once --json   # macOS only; SMC temperatures, fans, power
swift run coreo silicon --once --json   # Apple Silicon; IOReport power and frequency
swift run coreo connections --once --json # macOS only; your processes' sockets
swift run coreo traffic --once --json   # macOS only; per-process network rates
swift run coreo diagnose --json         # macOS only; summary, signals, top apps
swift run coreo top                     # macOS only; busiest apps, redrawn every 2 s
swift run coreo holders --json --port 8080 # macOS only; who holds a port or file
swift run coreo mcp --stdio             # macOS only; read-only MCP server
swift run coreo history --json cpu      # recorded history for one metric
swift run coreo sleep --json            # macOS only; sleep and wake records
swift run coreo apps --json             # recorded per-app CPU and disk totals
python3 tools/tests/test_buildscripts.py
shellcheck scripts/*.sh
python3 tools/doccheck/checkdocs.py .
node tools/doccheck/mmdcheck.mjs .
```

The icon is generated from `media-sources/icon.png` using
`python3 tools/make_icon.py` (Pillow required). The derived ICNS is
committed; normal builds need no image tooling.

Working practices are in [`AGENTS.md`](AGENTS.md).

## License

[Unlicense](LICENSE) — public domain.
