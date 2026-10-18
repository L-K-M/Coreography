# Reference screenshots (research notes)

> Coreography research notes. Analysis of the owner's reference screenshots:
> five Activity Monitor tabs on macOS 26 and three iStat Menus dropdowns.
> The screenshots are not committed because they show a personal process list.

## Summary

- Activity Monitor gives its graphs roughly 2% of the window. The process
  table takes the rest, even when it is empty (Disk tab).
- Activity Monitor shows one subsystem at a time. Seeing CPU and memory
  together means switching tabs or opening extra windows.
- iStat Menus inverts this: each subsystem is a stack of cards led by a big
  number and a graph, with the top five responsible processes directly below.
  Attribution sits next to the metric it explains.
- iStat encodes two series per card with two colours (user/system,
  read/write, efficiency/performance) and repeats the encoding in a legend.
- Both tools are fixed in time: Activity Monitor's graphs cover about a
  minute, iStat's captured dropdowns about two. The captured views offer
  no way to scrub back to a spike; what other iStat surfaces offer is not
  proven by these screenshots.
- Numbers follow the user's locale (`7'167`, `150'623'596`). Coreography
  must format with the system locale, never a hard-coded separator.

## Activity Monitor (macOS 26)

Window anatomy, top to bottom:

```text
+--------------------------------------------------------------------------+
| (o)(o)(o) Activity Monitor   [x][i][...v]  [CPU|Memory|Energy|Disk|Net]  |
|           All Processes                                    [Search    ] |
+--------------------------------------------------------------------------+
| Process Name               | % CPU | CPU Time | Threads | ... | User     |
| ...                        |       |          |         |     |          |
| ... ~30 visible rows, horizontal scrollbar when columns overflow ...    |
+--------------------------------------------------------------------------+
|              +-------------+------------+-------------+                  |
|              | stats       | tiny graph | stats       |  ~110 pt tall    |
|              +-------------+------------+-------------+                  |
+--------------------------------------------------------------------------+
```

Per tab:

| Tab | Columns shown | Bottom panel |
| --- | --- | --- |
| CPU | % CPU, CPU Time, Threads, Idle Wake Ups, Kind, % GPU, GPU Time, PID, User | System % (red), User % (blue), Idle %; CPU LOAD area graph; Threads, Processes |
| Memory | Memory, Threads, Ports, PID, User | MEMORY PRESSURE graph (green); Physical Memory, Memory Used, Cached Files, Swap Used; App Memory, Wired Memory, Compressed |
| Energy | Energy Impact, 12 hr Power, App Nap, Preventing Sleep, User | ENERGY IMPACT graph; remaining charge, charge state, time on AC; BATTERY (last 12 hours) graph |
| Disk | Bytes Written (list empty in the screenshot) | Reads in/out totals and per second; IO or Data graph (switchable); data read/written totals and per second |
| Network | Sent Bytes, Rcvd Bytes, Sent Packets, Rcvd Packets, PID, User | Packets in/out totals and per second; PACKETS or Data graph, mirrored (in up in blue, out down in red); data received/sent totals and per second |

Observations:

- The graphs are about 220 x 80 pt inside a window more than 1,800 pt wide.
  They are too small to read shape, peaks or timing.
- Scale and time axes are absent. A flat green memory pressure block says
  "fine" but not how close to yellow it is.
- The Energy tab title changes to "Applications in last 12 hours" and greys
  out apps that have quit. Long-window history exists, but only for energy.
- One app in the Energy tab shows an Energy Impact of `4'601.2` while the
  rest sit below 50. Outliers like this deserve visual emphasis, not a plain
  number in a column.
- The Disk tab list was empty while the summary showed 83.4 MB/s of reads.
  Totals and per-process attribution disagree with no explanation. TMOG's
  "unavailable is not zero" rule addresses exactly this.
- The memory summary shows 36 GB physical, 13.3 GB compressed and 8 GB of
  swap at only a green pressure reading. The composition matters more than
  the single pressure colour; iStat's segmented ring shows it better.
- Two columns ("Kind: Apple", `% GPU` at 0.0 for most rows) add width but
  little information for most processes.

## iStat Menus 7 dropdowns (owner's theme: purple background, lime and blue)

### CPU dropdown

- Header: `CPU` label in accent colour on the left, `3.68 GHz, 82°` on the
  right. The two most useful secondary facts (frequency, temperature) are in
  the header, not buried.
- History: about 100 stacked bars, user (lime) under system (blue). Below:
  a legend row with coloured dots and percentages (`User 28%`,
  `System 13%`).
- Cores: a row of 12 small donut rings, efficiency cores in blue,
  performance cores in lime, with cluster averages (`Efficiency Cores 44%`,
  `Performance Cores 38%`).
- Processes: top five by CPU with app icons and percentages.
- GPU card: `184 FPS` in the header, four rings (GPU 35%, MEM 25%, TMP 70°,
  0.38 GHz).
- Load averages (`7.08 11.05 19`) and uptime as single-line cards.
- Footer: launcher row for Activity Monitor, Console, Terminal and others.

### Disks dropdown

- One card per volume: a capacity ring with percent used, name, space
  available, and two activity dots (read blue, write lime).
- Network disks as horizontal capacity bars.
- Throughput: two large numbers (`7.3 MB/s Read`, `733 KB/s Write`) over a
  mirrored bar chart, reads up in blue and writes down in lime, with peak
  values below (`Read 80.2 MB/s`, `Write 20.0 MB/s`).
- Processes: top five with separate R and W columns, compact units
  (`2.3M`, `36K`).

### Memory dropdown

- Two large rings: `55% PRESSURE` and `82% MEMORY`. The memory ring is
  segmented: App (lime), Wired (blue), Compressed (pink), Free (grey), with
  a legend giving each in GB.
- Processes: top five with GB and share of RAM (`7.5 GB (20.7%)`).
- Page ins / page outs, then swap as a progress bar (`8.0 GB of 9.0 GB`).

### What works

- Card grouping with generous rounded corners and consistent internal
  padding; every card has a small uppercase accent label.
- Strong typographic hierarchy: large values, smaller units (`%`, `GB`,
  `MB/s` set smaller than the digits), muted labels.
- Metric and cause side by side: every subsystem card carries its own top
  processes.
- A fixed two-colour code per card, repeated in the legend.
- Mirrored charts for paired flows (read/write).

### What does not

- Rings for 12 cores are hard to compare; a bar row or a per-core heat strip
  over time shows the same data more precisely.
- Rings carry no history. The GPU card shows four instant values with no
  trend.
- The captured dropdown is a fixed-size popover: no resizing, no time
  range control, no scrubbing, no drill-down beyond opening Activity
  Monitor. These screenshots show only the dropdown surface; they cannot
  prove the wider iStat Menus app lacks history, ranges or drill-down.
- The custom purple theme ignores system appearance. Coreography should
  derive its look from the system (light, dark, accent colour, increased
  contrast) and offer at most a restrained accent choice.

## Implications for Coreography

1. Invert Activity Monitor's proportions: graphs get most of the window; the
   process list becomes a secondary, resizable pane.
2. Show all subsystems at once as cards (small multiples) with a shared time
   axis, so a spike in one can be lined up against the others.
3. Put attribution next to every metric: each card lists its top processes,
   and clicking one filters or highlights the process pane.
4. Use iStat's typographic hierarchy (large tabular digits, smaller units,
   accent labels) in a system-native palette.
5. Prefer bars, areas and heat strips with history over instantaneous rings.
   Keep rings only for bounded "fullness" values (capacity, pressure).
6. Make every graph scrubbable in time and expandable to a detail view.
7. Distinguish "zero" from "not measured" visibly (empty Disk list with
   non-zero totals is the counter-example).
8. Format every number with the user's locale.
