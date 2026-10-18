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

The process pane adds PID/start-time-safe CPU share, physical footprint
and disk read/write rates, with filtering, sorting and explicit restricted
or unreadable coverage. It refreshes every two seconds using public libproc
APIs. Footprints are not an additive system memory total.

The network lane uses full-width interface MIB counters, with receive/send
graphs on the same time axis. It defaults to the published primary IPv4
interface, then IPv6, and allows explicit interface selection. Its numeric
table and chart accessibility descriptor retain missing-data states.

The disk lane reads each observed storage driver's byte counters. Automatic
selection requires one identified device and complete inventory; otherwise
choose a device. Registry identities keep physical and virtual drivers
separate, with missing data and inventory limits shown explicitly.

App grouping and attribution, SoC providers, persistent history, power tools,
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

Portable engine tests also run on Linux. Linux `coreo doctor` reports
native sampling as unsupported; it does not manufacture Mac telemetry.

```sh
swift run coreo doctor
swift run coreo snapshot --once --json  # macOS only; CPU and memory detail
swift run coreo processes --once --json # macOS only; two-second baseline
swift run coreo network --once --json   # macOS only; per-interface byte rates
swift run coreo disks --once --json     # macOS only; per-storage-driver rates
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
