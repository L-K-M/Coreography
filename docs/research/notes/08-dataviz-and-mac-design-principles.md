# Data visualisation and Mac-native design principles (research notes)

> Coreography research notes. Sources accessed 2026-10-17.

## Summary

- Apple's own guidance (HIG Charts, WWDC22 sessions) treats a chart as a focused statement, not a data dump: prefer common chart types, establish a visual hierarchy where data is most prominent and axes/labels are secondary, and progressively disclose complexity from small static thumbnails to large interactive charts.
- The monitoring literature converges on the same discipline: Tufte's data-ink maximisation, sparklines and small multiples; Few's dashboards built from dense linear media (bullet graphs, sparklines) instead of space-wasting circular gauges; and encoding by length and 2-D position, the most accurate preattentive attributes.
- Colour must carry status meaning without being the only channel: aim for 4.5:1 contrast, avoid red/green pairings, choose palettes whose colours differ in lightness as well as hue (Okabe-Ito is the reference 8-colour set), label series directly, and add redundant encodings (shape, dashing, position).
- Honesty choices that matter for a monitor: bars must start at zero, percent metrics should keep their natural 0 to 100 domain, autoscaling needs visible axis labels, decimation should be min/max or LTTB (peak-preserving) rather than smoothing, and units must follow macOS convention (decimal GB) with bits vs bytes always explicit.
- Swift Charts is the right default renderer: WWDC24 added vectorized LinePlot/AreaPlot/BarPlot for whole collections plus function plots, and accessibility (VoiceOver summaries, Audio Graphs) is built in. But it has no virtualization: tens of thousands of marks drop frames, so downsample to roughly pixel width and use RectangleMark for heatmaps. Reserve Metal/Core Animation custom drawing for always-on, per-pixel-refresh surfaces.
- Liquid Glass is a functional layer for controls and navigation (toolbar, sidebar, inspector), not content: Apple explicitly says do not put it in the content layer, use it sparingly in custom controls, and reserve the Clear variant for floating over rich media with a dimming layer. macOS 27 Golden Gate adds a user-facing glass opacity slider, so the app must look right at both extremes.
- The modern Mac chrome vocabulary is: unified toolbar, edge-to-edge sidebar (restored in macOS 27 after Tahoe's floating sidebar), inspector pane for selection detail, MenuBarExtra for ambient status, Control Center controls and desktop widgets as satellite surfaces, and a Settings scene behind Cmd-,.
- The best-in-class references: iStat Menus 7 (tiny multi-mode menu-bar graphs, dropdowns with history graphs at 10 min to 28 days, per-core colouring by E/P type), Little Snitch 6 (selection linked across connection list, traffic diagram and map; Control Center menu-bar chart), DaisyDisk (drill-down sunburst), Instruments (aligned multi-track timeline), and Activity Monitor's per-core CPU History.
- Real-time rendering is an energy problem as much as a smoothness problem: ProMotion displays adapt their refresh rate to the content (up to 120 Hz, and higher rates cost significant power), so sample-rate-bound updates, preferredFrameRateRange hints, and honouring Reduce Motion/Transparency/Increase Contrast are both accessibility and battery features.
- Audio Graphs via AXChartDescriptor make time series perceivable without vision (VoiceOver rotor plays each series as a tone, drag to scrub); shipping them is a differentiator almost no third-party monitor has.

## Tools

### Edward Tufte: data-ink, sparklines, small multiples

- **Status**: Foundational theory. The Visual Display of Quantitative Information introduced the data-ink ratio; Beautiful Evidence introduced sparklines. Tufte still publishes worked examples on edwardtufte.com.
- **What it shows**: Principles for quantitative graphics, applied here to dense always-on instrumentation.
- **How it shows it**: Sparklines are "datawords": word-sized, high-resolution line fragments with almost no non-data ink, no frames, ticks or axes; they get quantitative context from adjacent numbers (current value, min, max) rather than from scales. The data-ink ratio is defined as ink devoted to non-redundant data-information over total ink; erase everything that does not change when the data changes. Aspect ratio matters: William Cleveland's banking-to-45-degrees rule says time series slopes read best when average hill-slopes are about 45 degrees, producing a "lumpy" rather than spiky or flat profile; Tufte's example financial sparkline runs about 5:1 (unverified). Small multiples repeat one chart form across many items (cores, disks, interfaces) with identical scales so comparison is preattentive.
- **Ideas worth taking**: Every summary row or sidebar item gets a sparkline plus its current value in text; identical fixed domains across small multiples; near-zero chrome inside the plot (no gridlines fighting the curve); end-point labels (last value, peak) instead of full axes in compact contexts.
- **Weaknesses / avoid**: Sparklines sacrifice precise reading, so they must link to a full chart; banking to 45 degrees fights fixed-window real-time graphs, so pick a fixed, declared aspect instead of autoscaling to fit; zero non-data-ink is a direction, not a dogma (grids help precise reading at large sizes).
- **Sources**: https://www.edwardtufte.com/notebook/sparklines-history-by-tufte-1324-to-now/ , https://www.edwardtufte.com/notebook/sparkline-theory-and-practice-edward-tufte/ , https://faculty.salisbury.edu/~jtanderson/teaching/cosc311/fa21/files/tufte.pdf

### Stephen Few: Information Dashboard Design

- **Status**: Practitioner's reference for glanceable monitoring (Information Dashboard Design; Show Me the Numbers; Perceptual Edge whitepapers). Few's work targets exactly Coreography's problem: rapid situation awareness.
- **What it shows**: What belongs on a monitoring dashboard and how to encode it for at-a-glance reading.
- **How it shows it**: The bullet graph replaces the gauge: a horizontal bar (primary measure) over qualitative background ranges (shades of grey for good/satisfactory/poor) with a short vertical marker for a comparison value. It carries a gauge's information in a fraction of the space. Few's dashboard principles for real-time awareness: use flicker and sound sparingly to grab attention, encourage active thinking rather than passive alarm reaction, do not over-automate, provide a common picture, match the user's mental model. In "Rich Data, Poor Data" he shows circular gauges waste space and a panel of linear displays is faster to scan; the exception he allows is a wall of identically oriented gauges where "needle straight up" is the normal state.
- **Ideas worth taking**: A memory tile can literally be a bullet graph (used bar over capacity, marker for pressure threshold); give every metric a qualitative context (normal vs pressure vs critical) through background banding rather than colour changes alone; dense linear media scale to many widgets per row.
- **Weaknesses / avoid**: His aesthetic is austere enterprise BI; applied literally it would look flat on macOS. Take the encodings, not the skin.
- **Sources**: https://perceptualedge.com/articles/Whitepapers/Dashboard_Design.pdf , https://www.perceptualedge.com/articles/Whitepapers/Rich_Data_Poor_Data.pdf , https://perceptualedge.com/articles/visual_business_intelligence/pervasive_hurdles_to_dd.pdf , https://www.tableau.com/videos/bullet-graphs

### Preattentive attributes and status colour

- **Status**: Perception research (Treisman, Julesz; catalogued by Healey at NCSU and Colin Ware) plus Few's practitioner subset; colour-blind practice anchored by the Okabe-Ito palette (2008).
- **What it shows**: Which visual channels are detected in a fraction of a second without scanning, and how to build a status palette that survives colour-vision deficiency.
- **How it shows it**: Preattentive attributes in four groups: form (length, width, area, shape, orientation, enclosure, blur), colour (hue, lightness, saturation), location (2-D position, spatial grouping), motion (direction, speed, flicker). Detection is asymmetric (a sloped line pops among verticals, not vice versa), and channels have limited bandwidth: position on a line supports roughly 10 to 15 distinguishable levels, hue about 10, brightness about 5. Colour-blind practice: about 8% of men have red-green deficiency; lightness differences survive all deficiency types while equal-lightness red/green pairs merge. The Okabe-Ito palette's 8 colours are tested under simulated deficiencies (CIEDE2000 distance checks); it is a guarantee for up to 8 categories, not a starting point for more. Apple's accessibility session recommends contrast ratios of at least 4.5:1 and avoiding red/green pairings.
- **Ideas worth taking**: Order encodings by accuracy: position and length for values, lightness/hue for series identity, motion or flicker reserved for genuine alarms. Status colours mean something only within a redundant system: warn via colour plus icon plus position. A colour-blind-safety check (simulate protanopia/deuteranopia/tritanopia on final screens) is cheap and catches bad pairings.
- **Weaknesses / avoid**: More than about 8 simultaneously meaningful colours fails; hue alone cannot encode quantity; flicker is powerful but hostile, so keep it out of routine animation.
- **Sources**: https://www.csc2.ncsu.edu/faculty/healey/PP/ , https://www.perceptualedge.com/articles/visual_business_intelligence/the_visual_perception_of_variation.pdf , https://www.ida.liu.se/~732A98/info/2/Lecture2.html , https://jfly.uni-koeln.de/color/index.html , https://colourwise.app/data-visualisation/colour-vision-deficiency-safe-charts , https://developer.apple.com/videos/play/wwdc2021/10122/

### Horizon charts

- **Status**: Established compact time-series technique (Cubism.js, Vega, CDC COVE guidance); supported by research showing preserved resolution at reduced height.
- **What it shows**: Many time series stacked in minimal vertical space, trading instant readability for density.
- **How it shows it**: An area chart is sliced into horizontal bands, bands are given graduated colour intensity (darker or more saturated for higher values, often a second hue for negatives flipped upward), then layered on top of each other. A 5-layer horizon chart shows the same data in one fifth the height. Vega's example demonstrates that spatial resolution per unit height stays constant as layers increase; the data.europa.eu guide packs 73 series of 2 years of daily values (over 53,000 points) into one readable figure.
- **Ideas worth taking**: Ideal small-multiple form for per-core CPU or per-disk I/O rows in a sidebar: each row 24 to 32 pt tall, colour intensity for load, a second hue for a semantic negative (e.g., memory pressure vs free). Bands make peaks pop preattentively.
- **Weaknesses / avoid**: Not familiar to general users; needs a legend or onboarding cue and an exact-value readout on hover. Colour quantization into bands loses fine granularity; pair with a numeric label.
- **Sources**: https://en.wikipedia.org/wiki/Horizon_chart , https://www.cdc.gov/cove/data-visualization-types/horizon-charts.html , https://data.europa.eu/apps/data-visualisation-guide/data-dense-time-series , https://vega.github.io/vega/examples/horizon-graph/

### Heatmaps for per-core history

- **Status**: Standard density display; trivially expressible in Swift Charts with RectangleMark, and Apple shipped a heatmap in its WWDC24 vectorized-plots sample.
- **What it shows**: Two dimensions plus an intensity channel: time on x, category (core, disk, interface) on y, value as colour.
- **How it shows it**: A grid of cells whose fill colour encodes the value on a sequential or diverging scale. For a Mac with 10 to 24 CPU cores, one heatmap row per core over a scrolling time window shows load migration and saturation patterns that per-core line charts obscure. Apple's WWDC24 sample code builds heatmaps from vectorized plots; third-party performance notes recommend RectangleMark over BarMark for dense grids because it avoids per-mark layout passes.
- **Ideas worth taking**: The CPU panel's "history" view can be a core-by-time heatmap with a perceptually uniform sequential ramp; E vs P cores separated by a group gap rather than different hues. Hover reads out the exact percentage.
- **Weaknesses / avoid**: Colour intensity is imprecise (a preattentive bandwidth of about 5 levels for brightness); always pair with numeric readout and offer the per-core stacked-area alternative Activity Monitor users know.
- **Sources**: https://developer.apple.com/videos/play/wwdc2024/10155/ , https://developer.apple.com/documentation/Charts/creating-a-data-visualization-dashboard-with-swift-charts , https://nagarjuna2997.github.io/ios-agent-skill/guides/frameworks-swift-charts.html

### Stacked areas and mirrored charts

- **Status**: Bread-and-butter forms already used by Activity Monitor and Little Snitch.
- **What it shows**: Part-to-whole over time (user + system + idle = 100%) or opposing flows (read vs write, sent vs received).
- **How it shows it**: Activity Monitor's CPU pane stacks System (red) and User (green) against Idle; its per-core CPU History uses the same stacking inside per-core boxes. Little Snitch's traffic diagram renders per-time-unit bars and lets the user hover for sent/received totals, page backward and forward, zoom through day/week/month domains and jump back to "Now". Mirrored layouts put one direction above the axis and the other below, making asymmetry visible at a glance.
- **Ideas worth taking**: CPU stacked area with two hues only (user vs system) and a thin total line; network and disk mirrored up/down or left/right charts with independent magnitude but a shared scale; semantic colour pairs that are not red/green (e.g., teal up, orange down).
- **Weaknesses / avoid**: Stacked areas above 3 to 4 layers become unreadable (only the bottom series has a baseline); never stack unbounded metrics like memory bytes against percentages. Mirrored charts need a clearly drawn zero axis.
- **Sources**: https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac , https://eclecticlight.co/2021/05/18/getting-more-from-activity-monitor-cpu/ , https://help.obdev.at/littlesnitch6/lsm-traffic-chart

### Treemaps and sunbursts

- **Status**: Two proven Mac implementations: DaisyDisk (sunburst, commercial) and GrandPerspective (treemap, open source). Both actively maintained as of late 2026.
- **What it shows**: Hierarchical part-to-whole data where area encodes size.
- **How it shows it**: DaisyDisk renders the disk as a sector diagram: rings are depth levels, arc length is size; click a segment to drill down, click the centre to bubble up, hover shows name and path, Space triggers Quick Look, drag items into a "collector" for deletion. GrandPerspective draws a classic treemap: each file a rectangle with area proportional to size, files of a folder clustered; colour can be assigned by attributes such as file size (with a configurable upper bound) so outliers pop.
- **Ideas worth taking**: The interaction grammar, more than the shape: hover identity, single click drills, parent navigation via centre or breadcrumb, keyboard navigation (DaisyDisk added it in 4.25), and a staged deletion collector instead of immediate deletion. The same layout works for "which processes eat memory" (treemap by resident bytes) or network traffic by app/domain.
- **Weaknesses / avoid**: Neither form is a real-time display (rescan cost, unstable layout as data changes); use for on-demand drill-down views, not live ticks. Treemaps make small items unreachable without aggregation buckets ("smaller objects" group, as DaisyDisk does).
- **Sources**: https://daisydiskapp.com/releases/ , https://grandperspectiv.sourceforge.net/ , https://sourceforge.net/projects/grandperspectiv/files/grandperspective/ , https://nmac.to/daisydisk/

### Sankey and flow diagrams

- **Status**: Classic flow visualization (Minard 1869, Sankey 1898); ubiquitous on the web (d3-sankey), rare in native Mac monitors.
- **What it shows**: Conserved flows between nodes where link width is proportional to flow quantity.
- **How it shows it**: Nodes are stages or endpoints; links between them carry width proportional to flow. Standard uses are energy and material balances; LLNL and the IEA maintain canonical energy-flow examples.
- **Ideas worth taking**: A process-to-host or app-to-interface Sankey is the honest answer to "where is my bandwidth going": apps on the left, remote endpoints on the right, link width by bytes/sec. It complements rather than replaces Little Snitch's list-plus-map approach. Also a natural fit for a static energy picture (battery to display/radio/compute) if per-component energy data exists.
- **Weaknesses / avoid**: Sankeys are expensive layout, poor at hundreds of flows, and unreadable while animating; keep them to filtered, on-demand views. Do not fake flow diagrams where a sorted bar chart would answer the question.
- **Sources**: https://en.wikipedia.org/wiki/Sankey_diagram

### Gauges, rings and bars

- **Status**: Few's critique of circular gauges is the standard position; Apple's Activity rings are the famous counter-example of rings done well.
- **What it shows**: Single scalar values relative to a capacity or goal.
- **How it shows it**: Few shows circular gauges spend most pixels on chrome and only a sliver on data; a bullet graph communicates value, comparison and qualitative range in a thin strip. Apple's Move/Exercise/Stand rings work because they show progress toward 100% of a goal, are learned once, and are read with VoiceOver as label plus percentage. Dashboards of many circular gauges are only defensible in Few's narrow exception (identical dials scanned for "all pointing up").
- **Ideas worth taking**: Rings are justified for goal-relative metrics (battery charge, disk used, ring-fan duty) where "how full" is the question and the audience is consumer. For everything else use horizontal bars or bullet graphs; a row of 8 rings for CPU cores would burn space Activity Monitor instead spends on 10-segment LED columns.
- **Weaknesses / avoid**: Donut gauges with a big number inside and no comparison context; ring overload (more than about 3 concurrent rings); ring charts for metrics without a meaningful 100%.
- **Sources**: https://www.perceptualedge.com/articles/Whitepapers/Rich_Data_Poor_Data.pdf , https://fossheim.io/writing/posts/apple-health-dataviz-a11y/ , https://www.howtogeek.com/690252/how-to-show-macs-hidden-floating-performance-panels/

### Scales, units and numeric typography

- **Status**: Established research on axis truncation plus Apple's documented conventions for capacity and fonts.
- **What it shows**: How axis domains, units and digit rendering affect honest, fast reading.
- **How it shows it**: Correll, Bertini and Franconeri's "Truncating the Y-Axis: Threat or Menace?" finds axis truncation persistently distorts perceived effect size even when visually signalled; the standing rule is bars must include zero, while line charts may crop when the communicative goal is pattern not magnitude (Tufte's "lie factor" quantifies the exaggeration). Apple's convention since Mac OS X 10.6 Snow Leopard (2009) is decimal storage capacity: 1 GB = 1,000,000,000 bytes, matching drive manufacturers and Disk Utility. SF Pro offers nine weights and variable optical sizes; SwiftUI's monospacedDigit() and AppKit's monospacedDigitSystemFont yield tabular figures, and SF Mono suits columnar data.
- **Ideas worth taking**: Percent metrics (CPU, memory pressure, battery) use fixed 0 to 100 domains; throughput metrics autoscale but always label the axis and never imply a zero baseline that is not drawn. Show "MB/s" vs "Mb/s" deliberately and offer a bits/bytes preference; storage follows the system decimal GB convention, optionally exposing GiB in a power-user setting. All numeric readouts use tabular numerals so columns and ticking values do not jitter horizontally; this is one line of code per label.
- **Weaknesses / avoid**: Mixing SI and IEC units silently; autoscaling that rescales the axis every tick so a flat noisy line dances; proportional digits in animated counters.
- **Sources**: https://arxiv.org/html/1907.02035v2 , https://observablehq.com/blog/never-okay-crop-y-axis-except-when-it-is , https://support.apple.com/en-us/102119 , https://developer.apple.com/fonts/ , https://developer.apple.com/documentation/swiftui/font/monospaceddigit() , https://useyourloaf.com/blog/monospace-digits/

### Streaming data: ring buffers and decimation

- **Status**: Standard engineering practice; LTTB (Largest-Triangle-Three-Buckets) is the best-known visual downsample, from Sveinn Steinarsson's 2013 MSc thesis.
- **What it shows**: How to keep a real-time series bounded in memory and pixels without lying about peaks.
- **How it shows it**: A ring buffer holds the visible window (plus a longer in-memory history for scrubbing). Rendering needs only as many points as horizontal pixels; beyond that, downsample. LTTB divides the series into buckets and picks the point per bucket that maximizes the triangle formed with neighbours, preserving the contour; it is explicitly a visual technique, not statistical aggregation. ClickHouse ships it as the largestTriangleThreeBuckets aggregate; Rust and Python ports exist. Min/max decimation keeps both extremes per bucket and is spike-faithful, which suits monitoring where a 100% burst is the story.
- **Ideas worth taking**: Sample at a fixed cadence into a ring buffer sized to the longest viewable range; decimate at draw time to pixel width with min/max or LTTB; keep raw history for the inspector readout so hover can show true values, not rendered approximations.
- **Weaknesses / avoid**: Smoothing or averaging for display flattens exactly the spikes a monitor exists to reveal; downsampling once and treating the result as data loses peaks.
- **Sources**: https://skemman.is/bitstream/1946/15343/3/SS_MSthesis.pdf , https://www.datylon.com/blog/line-charts-sampling-time-series-data-sets , https://clickhouse.com/docs/reference/functions/aggregate-functions/largestTriangleThreeBuckets , https://docs.rs/lttb/latest/lttb/ , https://nagarjuna2997.github.io/ios-agent-skill/guides/frameworks-swift-charts.html

### Rendering stack: Swift Charts vs Core Animation vs Metal

- **Status**: Three practical tiers on macOS, with Apple's own guidance on refresh-rate cost from the ProMotion sessions.
- **What it shows**: Which layer to draw live graphs with, and what the energy bill looks like.
- **How it shows it**: Swift Charts is declarative and accessibility-complete but has no virtualization: community measurement shows 50,000 marks drop frames while conveying no more than the ~500 points a chart that size can show; the fix is downsampling, and .drawingGroup() (flatten to one Metal layer) helps only past thousands of marks and hurts small charts. Synchronizing several scrollable charts via a shared chartScrollPosition binding caused "update multiple times per frame" jank in reported cases. For bespoke always-on surfaces, Core Animation layers or Metal drawing driven by a display link are the traditional route; Apple's variable-refresh session explains that ProMotion adapts the refresh rate to onscreen content (up to 120 Hz), that higher refresh rates can consume significant power, and that apps should pass preferredFrameRateRange hints to Core Animation. Older Apple performance guidance budgets blur/vibrancy offscreen passes carefully and favours fewer blending passes.
- **Ideas worth taking**: Default to Swift Charts for interactive charts (free axes, Audio Graphs, scrubbing). For the continuously ticking surfaces (menu-bar sparkline, hero real-time graph), render a fixed-width path inside a lightweight view updated at sample cadence, or a single CAMetalLayer/MTKView if profiling demands it; cap render rate at the slower of sample rate and display need, and set preferredFrameRateRange honestly. Instruments' own track-view UI went through a full redesign around the track pane (the Xcode 6-era rewrite was its biggest UI change), a reminder to treat the graph engine as a separate, profiled component.
- **Weaknesses / avoid**: Per-sample SwiftUI body recompute of thousands of marks; animating at 120 fps because it is possible rather than needed; offscreen blur behind live graphs.
- **Sources**: https://nagarjuna2997.github.io/ios-agent-skill/guides/frameworks-swift-charts.html , https://stackoverflow.com/questions/76903274/ , https://developer.apple.com/videos/play/wwdc2021/10147/ , https://developer.apple.com/videos/play/wwdc2019/411/ , https://devstreaming-cdn.apple.com/videos/wwdc/2014/419xxli6f60a6bs/419/419_advanced_graphics_and_animation_performance.pdf

### Apple HIG: Charts guidance

- **Status**: Current HIG page plus two canonical WWDC22 design sessions (one by Nicholas Felton of Apple's Human Interface team).
- **What it shows**: Apple's rules of thumb for when and how to use charts in apps.
- **How it shows it**: Charts provide focus: only the most important information should become a chart. Prefer common chart types people can already read. Keep charts simple and reveal detail gradually: small static charts (watch complications, Stocks thumbnails, Health trend platters) need no gridlines or labels and act as previews of a larger interactive chart; the largest charts support deep investigation and may add functionality progressively. Establish visual hierarchy: data most prominent, descriptive elements and axes secondary. Write information-rich titles and labels so VoiceOver users get the chart's purpose before investigating. Chart anatomy is marks, axes, labels, legend.
- **Ideas worth taking**: Two-tier design throughout: sparkline in a row or menu, full chart on selection; every chart has one stated question it answers; descriptive titles ("CPU dropped to idle after the build finished") beat bare metric names.
- **Weaknesses / avoid**: The guidance assumes discrete datasets more than continuous streams; the live-monitor twist is deciding what deserves a chart at all versus a number.
- **Sources**: https://appguidelines.com/human-interface-guidelines/version/22/charting-data/ , https://developer.apple.com/videos/play/wwdc2022/110342/ , https://developer.apple.com/videos/play/wwdc2022/110340/

### Swift Charts framework

- **Status**: Shipping since 2022; last feature additions June 2025 (Chart3D) per Apple's updates page; no WWDC26 additions noted there, and third-party wishlists still cite missing pan/zoom and candlestick types.
- **What it shows**: Declarative chart construction for all Apple platforms.
- **How it shows it**: Charts compose marks (BarMark, LineMark, PointMark, AreaMark, RectangleMark, RuleMark) inside a Chart view; modifiers control axes, scales, legends, foreground styles. WWDC24 (iOS 18/macOS 15 era) added vectorized plots: LinePlot, AreaPlot, BarPlot and friends conforming to VectorizedChartContent plot an entire RandomAccessCollection efficiently in one plot, and function plots evaluate a Double closure to graph equations. WWDC25 (iOS/macOS 26) added Chart3D with 3-D PointMark/RectangleMark/RuleMark and SurfacePlot, plus camera pose and orthographic/perspective projection modifiers. Interaction APIs include chartScrollableAxes, chartXVisibleDomain and chartScrollPosition (macOS 14+); accessibility is on by default (VoiceOver chart descriptions, Audio Graph on function plots).
- **Ideas worth taking**: Vectorized plots map directly onto ring-buffer data; scrollable axes plus visible domain give scrubbing through history for free; rule marks give threshold lines; the framework's built-in accessibility is a large head start.
- **Weaknesses / avoid**: No virtualization and documented perf cliffs at tens of thousands of marks; synchronized scrolling across multiple charts has produced jank reports, so a multi-track "Instruments-like" layout may need custom drawing or careful binding design. No built-in pan/zoom or live-append conveniences.
- **Sources**: https://developer.apple.com/documentation/updates/swiftcharts , https://developer.apple.com/videos/play/wwdc2024/10155/ , https://developer.apple.com/videos/play/wwdc2025/313/ , https://developer.apple.com/videos/play/wwdc2023/10037/ , https://developer.apple.com/forums/thread/820382 , https://martiancraft.com/blog/2026/06/looking-forward-to-wwdc-26/

### Chart accessibility: Audio Graphs and VoiceOver

- **Status**: Apple's audio graphs shipped in 2021; AXChartDescriptor API documented; Swift Charts automates much of it.
- **What it shows**: How blind and low-vision users explore charts sonically and structurally.
- **How it shows it**: With VoiceOver, an Audio Graph entry appears in the rotor; playing it renders each series as a continuous tone where pitch tracks value, and an interactive mode lets the user double-tap-hold and drag to hear data at their own pace. Developers supply an accessibilityChartDescriptor; custom charts should become an accessibility container (semanticGroup) with a label and one element per data point. Apple's session adds the visual rules (contrast at least 4.5:1, avoid red/green pairs, do not encode by colour alone). Fossheim's walkthrough shows Health exposes each hour as a labelled column and reads ring labels plus percentages, and praises offering the same data in multiple formats.
- **Ideas worth taking**: Every chart ships an AXChartDescriptor describing axes and series; the process table gets proper table accessibility; Reduced Motion stops decorative animation and slows graph scrolling; Increase Contrast thickens gridlines and plot strokes; Reduce Transparency is free if charts avoid translucency behind data.
- **Weaknesses / avoid**: Sonifying a live stream is undefined territory: provide descriptors for the visible window and update them; do not let VoiceOver announce every tick of a live counter (throttle announcements).
- **Sources**: https://developer.apple.com/videos/play/wwdc2021/10122/ , https://developer.apple.com/documentation/accessibility/audio-graphs , https://developer.apple.com/documentation/accessibility/axchart/accessibilitychartdescriptor , https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor(_:) , https://fossheim.io/writing/posts/apple-health-dataviz-a11y/

### Liquid Glass on macOS 26/27

- **Status**: Liquid Glass debuted June 2025 across iOS/macOS 26 (Tahoe); refined in macOS 27 Golden Gate (released 2026-09-14) with a user-facing opacity slider, more effective diffusion of busy content, uniform toolbars, edge-to-edge sidebars and uniform window corner radii.
- **What it shows**: The current native chrome language Coreography must live in.
- **How it shows it**: Apple defines two layers: Liquid Glass for controls and navigation floating above content, and standard materials inside the content layer. Explicit prohibitions: do not use Liquid Glass in the content layer, do not mix the Regular and Clear variants, use glass sparingly in custom controls, and only choose Clear over visually rich backgrounds (adding a dark dimming layer when overlaying bright content). AppKit adoption: NSSplitViewController sidebar and inspector behaviours get glass automatically; NSToolbarItem's prominent style tints the glass with the accent colour; scroll edge effects (soft-edge progressive fade) separate content under floating chrome. Accessibility adaptions are automatic: Reduce Transparency makes glass frostier, Increase Contrast makes elements predominantly black or white with contrasting borders, Reduce Motion cuts elastic effects. macOS 27 adds the Appearance slider from ultra-clear to fully tinted (default mid; cannot go fully opaque), restores edge-to-edge sidebars with coloured icons, uses fewer icons in drop-down menus, and gives traffic-light buttons a revamped look; Apple's release notes, MacRumors' roundup and 9to5Mac's release coverage describe the changes.
- **Ideas worth taking**: Get chrome glass for free by using real toolbars, NSSplitViewController sidebars and inspectors; keep the chart plane on standard materials with opaque, high-contrast surfaces; test at both slider extremes plus Reduce Transparency; use the prominent toolbar style for the one action that deserves accent tint (e.g., pause/resume sampling).
- **Weaknesses / avoid**: Custom glass chrome around graphs (competes with data, costs GPU); Clear glass behind dense charts; assuming a fixed material appearance since the slider and accessibility toggles change it; icon-heavy menus, which Apple itself rolled back in 27.
- **Sources**: https://developer.apple.com/design/human-interface-guidelines/materials , https://developer.apple.com/videos/play/wwdc2025/219/ , https://developer.apple.com/videos/play/wwdc2025/310/ , https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ , https://9to5mac.com/2026/09/14/macos-27-golden-gate-now-available-here-is-everything-new/ , https://www.macrumors.com/roundup/macos-27/ , https://www.theverge.com/tech/946567/apple-macos-27-golden-gate-dev-beta-hands-on

### SF Symbols and SF Pro

- **Status**: SF Symbols 7 (2025) added Draw animations, Variable Draw, gradients and Magic Replace improvements; symbols work on macOS 27-era systems; SF Pro remains the system typeface (nine weights, variable optical sizes, four widths), with SF Mono for columnar contexts.
- **What it shows**: Apple's integrated iconography and typography for status display.
- **How it shows it**: Symbols come in nine weights and three scales, aligning with text automatically; rendering modes are monochrome, hierarchical, palette and multicolor, with optional gradients. Variable Rendering lets a symbol express a 0-to-1 value: Variable Color sequences layer opacity (e.g., wifi strength), Variable Draw uses stroke-progress annotation (e.g., thermometer fill). Symbol effects (bounce, pulse, scale, replace) animate state changes. monospacedDigit() produces fixed-width figures inside the proportional system font.
- **Ideas worth taking**: Variable-draw symbols as miniature gauges in sidebar rows and menu items (battery, thermometer, gauge icons that literally fill); hierarchical mode for dim secondary status; symbol effects for state transitions instead of custom animation; tabular numerals everywhere a value ticks.
- **Weaknesses / avoid**: Custom icon artwork next to SF Symbols (weight and corner radius will not match); relying on the default variable-rendering mode when a symbol supports both Variable Color and Variable Draw, since only one can be active at render time (set the mode explicitly).
- **Sources**: https://developer.apple.com/sf-symbols/ , https://developer.apple.com/videos/play/wwdc2025/337/ , https://developer.apple.com/videos/play/wwdc2023/10258/ , https://developer.apple.com/fonts/

### Menu bar extras, widgets and Control Center

- **Status**: MenuBarExtra (macOS 13+), interactive desktop widgets (macOS 14 Sonoma+), and ControlWidget/ControlCenter API reaching macOS in Tahoe 26 (ControlCenter is macOS 26.0+); per developer reports macOS 26 also added a Menu Bar privacy permission under System Settings > Menu Bar, and Tahoe reportedly lets any control or menu-bar item live in Control Center or a menu-bar page (unverified).
- **What it shows**: The ambient surfaces around the main window.
- **How it shows it**: MenuBarExtra puts a persistent item in the menu bar with two styles: the default pull-down menu and .window, a chromeless anchored window; resizing the window style requires reaching into AppKit (styleMask). Window restoration is automatic for Window scene types and can be disabled per scene with .restorationBehavior(.disabled); WindowGroup with a data initializer plus openWindow gives per-entity windows. The Settings scene provides the standard Cmd-, settings window (single-instance, TabView panes, @AppStorage). WidgetKit on Sonoma put interactive widgets on the desktop and in Notification Center, including iPhone widgets on Mac via iCloud. Tahoe's Controls Gallery brings iOS-style controls to macOS Control Center, with ControlCenter.reloadControls APIs and push-based updates; users can also tuck menu-bar items into Control Center (unverified).
- **Ideas worth taking**: Ship a MenuBarExtra that shows a condensed live dashboard (the Little Snitch 6 Control Center is the model: sparkline, current rates, recent events) with .window style for the rich variant; offer a Control Center toggle/indicator control; provide one small desktop widget (CPU graph) as a bonus surface; use per-entity WindowGroup for "detach this graph into its own window" float-on-top panels; restore window layouts so the dashboard reopens exactly.
- **Weaknesses / avoid**: Menu-bar real estate is scarce and macOS 26 can hide the item behind the new permission; keep the item compact and degrade gracefully. Do not rely on a widget for anything time-critical (budgeted reloads).
- **Sources**: https://developer.apple.com/videos/play/wwdc2022/10061/ , https://developer.apple.com/documentation/swiftui/menubarextrastyle/window , https://stackoverflow.com/questions/79127814/resizing-a-menubarextra-window , https://developer.apple.com/videos/play/wwdc2024/10148/ , https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system , https://developer.apple.com/documentation/widgetkit/controlcenter , https://www.apple.com/nz/os/pdf/All_New_Features_macOS_Tahoe_Sept_2025_NZ_Final.pdf , https://github.com/exelban/stats/issues/3120 , https://developer.apple.com/documentation/swiftui/settings

### iStat Menus

- **Status**: Bjango's flagship; version 7.5 released 2026-09-14 with Liquid Glass menus for macOS 27 and a new Astronomy item; requires macOS 13.5+. Paid licence (single/family, price rendered dynamically on the site, unverified), 14-day trial, included in Setapp ($9.99/mo bundle). Actively maintained since 2007.
- **What it shows**: CPU (per-core, E/P cores, frequency, load averages, top apps), GPU (usage, memory, temperature, frequency, FPS), memory (usage, pressure, compressed, swap, top apps), disks (space, activity, S.M.A.R.T., per-app usage), network (rates, history, per-app bandwidth, IP info, connectivity), sensors (temperatures, fans, voltages, power), battery/power incl. Bluetooth devices, time/world clocks, weather, astronomy.
- **How it shows it**: Ten independent menu-bar items (Astronomy arrived with 7.5), each with selectable menu-bar modes: pie chart, bar graph, history graph, percentage/text value, label, icon, dual-line label+bar and dual-line label+value variants; a compact-spacing option; themes with a macOS accent-colour default; optional dark graph backgrounds in light mode. Dropdown menus pair large history graphs (ranges: 10 minutes, 1/3/6/12 hours, 1/3/7/14/28 days) with tables of top processes; hovering rows pops richer detail. Combined mode merges items into one menu-bar item with separate menu-bar vs menu content. Version 7.0 reworked efficiency (claimed down to one fifth of v6 CPU usage) and added per-core E/P colouring and an iOS-style battery graph; 7.2 added a Liquid Glass icon; 7.5 rebuilt menus on Liquid Glass.
- **Ideas worth taking**: The tiered disclosure (glanceable menu-bar glyph -> dropdown with real charts -> hover popovers) and the honesty of configurable update frequency and explicit per-item enable switches; per-core E/P visual distinction; history ranges spanning minutes to weeks.
- **Weaknesses / avoid**: Extreme configurability means settings screens of intimidating density; the information is spread across menu-bar clicks rather than a unified glanceable window, which is precisely Coreography's opening.
- **Sources**: https://bjango.com/mac/istatmenus/ , https://bjango.com/mac/istatmenus/versionhistory/ , https://bjango.com/help/istatmenus7/welcome/ , https://bjango.com/help/istatmenus7/combined/ , https://www.macworld.com/article/538718/mac-gems-istat-menus-review.html , https://www.forbes.com/sites/barrycollins/2024/09/07/istat-menus-7-review-this-great-mac-app-has-just-got-better/

### DaisyDisk and GrandPerspective

- **Status**: DaisyDisk 4.34.2 (2026-07-10), commercial, actively maintained (recent APFS-clone accounting, Tahoe glass icons). GrandPerspective 3.8.1 (2026-09-13), free via SourceForge and also distributed through the Mac App Store, actively maintained (Liquid Glass compatibility in 3.7.0, macOS 14 deployment target in 3.8.0).
- **What it shows**: Disk usage by folder/file hierarchy; the question "what is eating my disk" answered spatially.
- **How it shows it**: DaisyDisk's sunburst: concentric rings by depth, segment arc proportional to size; click drills down, centre click ascends, hover shows name/path/preview, Space for Quick Look, drag to a collector then batch delete; keyboard navigation added in 4.25. GrandPerspective's treemap: file rectangles with area proportional to size, folders clustered, colour assignable by attributes like size with a tunable upper bound; control panel for scan and display settings.
- **Ideas worth taking**: One big visual answering one question, with drill-down + hover identity + safe staged destructive action; colour mapped to a user-tunable range so outliers pop; keyboard navigability of a spatial layout.
- **Weaknesses / avoid**: Static-scan model does not transfer to live monitoring; colourful palettes look dated next to current macOS restraint.
- **Sources**: https://daisydiskapp.com/releases/ , https://grandperspectiv.sourceforge.net/ , https://nmac.to/daisydisk/

### Little Snitch 6 Network Monitor

- **Status**: Objective Development; Little Snitch 6 current (release notes through 6.x into Tahoe era; exact latest point version unverified). Paid licence with demo mode (full function for three-hour sessions; Network Monitor expires after 30 days without a licence).
- **What it shows**: Live and historic network activity per process, domain and server: data rates, totals over time (statistics kept up to a year), ports/protocols, geographic server location, denied connections.
- **How it shows it**: Three linked views sharing one selection model. The connection list is a hierarchical outline whose grouping is configurable (Process > Domain > Server, or Domain > Process, or Country > Process > Domain > Server, etc.); the Traffic Diagram draws per-time-unit bars with hover readouts (total sent/received in the range), paging and zoom steps across day/week/month domains and a "Now" button; the Map draws connection lines over an Apple Maps base (blue idle, flashing green on fresh traffic, red where rules deny all listed connections), with location marks sourced from local GeoIP databases (MaxMind, IP2Location, db-ip, Geonames) and no online lookups. Selecting in any view narrows the others per documented rules. The menu-bar Control Center offers a compact 5-minute history chart or a live in/out meter, plus recent activity and recently denied connections. Sound notifications, Float on Top, and a global hotkey complete the surface.
- **Ideas worth taking**: Selection-as-filter across heterogeneous views is the strongest pattern here (pick an app, every chart and the map rescope to it); local-only GeoIP for privacy; a menu-bar extra that is a real mini-dashboard, not a shortcut; configurable history depth.
- **Weaknesses / avoid**: The map is decorative for most workflows and Apple Maps cannot zoom to a whole-world view; information density depends on the user configuring grouping well.
- **Sources**: https://obdev.at/en/products/littlesnitch/whatsnew.html , https://help.obdev.at/littlesnitch6/lsm-overview , https://help.obdev.at/littlesnitch6/lsm-map , https://help.obdev.at/littlesnitch6/lsm-traffic-chart , https://help.obdev.at/littlesnitch6/pref-statusmenu , https://help.obdev.at/littlesnitch5/lsm-selections , https://www.obdev.at/support/littlesnitch/nssdp

### Apple's own charting apps: Health, Fitness, Stocks, Weather, Battery

- **Status**: Shipping system apps; their chart idioms are what the WWDC22 sessions codify, and they set user expectations for "an Apple chart".
- **What it shows**: Personal data (steps, heart rate, prices, temperature, battery level) rendered with one consistent grammar.
- **How it shows it**: Stocks (macOS): a line chart with a range pill selector (1D, 1W, 1M, 3M, 6M, YTD, 1Y, 2Y, 5Y, 10Y, ALL), hover scrubbing that shows date/time and price above the chart, drag-to-select custom ranges highlighted darker, and a remembered range applying to all symbols. Health: a Summary page of small static "trend platters" and favourites that tap through to large interactive charts with hour/day/week/month/year views and overlays (averages, latest, range); VoiceOver reads grouped values per hour and ring labels with percentages. Activity rings render three goal-progress rings learned once. Weather: a scrolling stack of single-metric cards under an animated backdrop that itself encodes conditions; the hourly strip swipes sideways; tapping a card expands detail; next-hour precipitation gets a minute-resolution chart. Battery settings (macOS): two range tabs where Last 24 Hours shows a Battery Level line of 15-minute averages with shaded charging regions plus Screen On Usage bars per hour, and Last 10 Days shows daily Energy Usage bars.
- **Ideas worth taking**: Range pills plus scrubbing as the standard interaction (1m/5m/1h/24h for a monitor); static thumbnail -> interactive detail as the navigation contract; shaded context regions behind a line (charging, thermal throttling, sleep); one card per metric with progressive disclosure.
- **Weaknesses / avoid**: These are leisurely exploration apps; a monitor needs denser defaults and faster legibility than Stocks offers.
- **Sources**: https://support.apple.com/guide/stocks/change-the-chart-display-stc4cfc704df/mac , https://developer.apple.com/videos/play/wwdc2022/110342/ , https://fossheim.io/writing/posts/apple-health-dataviz-a11y/ , https://typenorm.com/apps/apple-weather , https://support.apple.com/guide/mac-help/change-battery-settings-mchlfc3b7879/mac , https://support.apple.com/en-gb/guide/mac-help/mchle6eb6928/mac

### Apple Design Award winners that visualise data

- **Status**: The 2025 ADA slate includes several data-visualisation apps; none are Mac system monitors, but they show what Apple rewards in data-heavy design.
- **What it shows**: Which data-forward designs Apple itself certifies as best-in-class.
- **How it shows it**: Watch Duty: Wildfire Maps (Social Impact winner) made real-time wildfire maps the primary interface, praised for clarity under pressure. Ground News (Social Impact finalist) pairs coverage lists with a bias-comparison graph and colour-coded markers that encode meaning redundantly with layout. Lumy (Delight and Fun finalist) wraps sun/moon timing data in widgets and Live Activities with a restrained palette. The 2026 winners had not been reviewed for this note.
- **Ideas worth taking**: Award-winning data apps pair a map or chart with obvious, calm hierarchy and encode meaning in more than colour; real-time public-safety mapping proves dense live data can stay glanceable.
- **Weaknesses / avoid**: These are mobile-first consumer apps; none of their idioms transfer wholesale to a pro macOS monitor.
- **Sources**: https://developer.apple.com/design/awards/2025/ , https://9to5mac.com/2025/06/03/apple-announces-2025-apple-design-award-winners/

### Xcode Instruments

- **Status**: Ships with Xcode; the pro-tool reference for multi-metric timelines on macOS.
- **What it shows**: Time-aligned traces from many instruments (CPU, memory, energy, network, signposts) recorded into a document.
- **How it shows it**: Templates preconfigure instrument sets. The window splits into the track pane (top; one track per instrument, process, thread or CPU core, with strategies like per-core/per-thread for Time Profiler), a navigation bar, and the detail pane (bottom) with Record Settings, Display Settings and Extended Detail inspectors. "Last Few Seconds" (windowed) mode bounds resource use while recording; tracks share one time axis so anomalies correlate across metrics; selections in tracks filter the detail tables. The Xcode 6-era redesign rebuilt the whole UI around the track pane (the biggest UI change in Xcode 6 per third-party write-ups).
- **Ideas worth taking**: The single shared time axis with vertically stacked tracks is the canonical answer to "CPU spiked while network stalled"; per-core track strategies; record/windowed modes and flag markers; inspector detail for the selected interval.
- **Weaknesses / avoid**: Instruments is dense and tool-flavoured (fine for its audience); its aesthetic predates current macOS chrome.
- **Sources**: https://developer.apple.com/videos/play/wwdc2019/411/ , https://nonstrict.eu/wwdcindex/wwdc2015/412/ , https://www.meandmark.com/xcode-6-instruments-ui-changes/ , https://developer.apple.com/library/archive/documentation/Performance/Conceptual/CellularBestPractices/Appendix/Appendix.html

### Activity Monitor as design baseline

- **Status**: Ships with macOS; functionally current (E/P core grouping on Apple Silicon) but visually conservative; the app Coreography replaces.
- **What it shows**: Per-process CPU/memory/energy/disk/network tables plus system-level graphs.
- **How it shows it**: Five tabs each with a process table and a bottom summary pane: CPU shows stacked System (red) + User (green) + Idle percentages with a scrolling stacked-area graph; Memory shows pressure and app/wired/compressed figures; Energy, Disk and Network get analogous bottom graphs. The Window menu hides the interesting displays: CPU Usage (Cmd-2) shows a 10-segment LED column per core; CPU History (Cmd-3) shows per-core mini stacked-area charts scrolling right to left, grouped into Efficiency and Performance core blocks on Apple Silicon, resizable for longer history but with fixed colours and labels; GPU History likewise. View > Dock Icon can render CPU usage/history, network, disk or memory live in the Dock; View > Update Frequency controls sample cadence (5 seconds per Eclectic Light's account); Window > Keep CPU Windows on Top floats the panels.
- **Ideas worth taking**: Per-core small multiples grouped by E/P topology; detachable float-on-top metric panels; live Dock icon; user-settable sample rate; the process table as a secondary tool, not the home view.
- **Weaknesses / avoid**: Graphs are buried (Window menu, bottom of tabs), undecorated, and non-configurable; no history persistence, no network/disk history windows, no thresholds or annotations; red/green user/system pairing is exactly the colour-blind unfriendly choice.
- **Sources**: https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac , https://eclecticlight.co/2021/05/18/getting-more-from-activity-monitor-cpu/ , https://www.howtogeek.com/690252/how-to-show-macs-hidden-floating-performance-panels/

## Cross-cutting patterns

- Two-tier disclosure everywhere: glanceable miniature (sparkline, variable-draw symbol, ring, LED column) linked to a full interactive chart. Apple encodes this as static preview -> interactive detail; iStat Menus does menu-bar glyph -> dropdown; Little Snitch does menu-bar chart -> Network Monitor window.
- Selection drives scope: Little Snitch's list/chart/map triad and Instruments' track-to-detail both narrow every other view to the selection. One selection model across heterogeneous views is the strongest structural idea available to Coreography.
- Small multiples beat overloaded charts: per-core CPU history, Battery's daily bars, Weather's card stack, Tufte's repetition principle. Fixed shared scales make differences preattentive.
- Live displays separate "now" from "then": the right edge is always the current instant, history scrolls away leftward, and scrubbing/paging (Little Snitch's Now button, Stocks' scrub, chartScrollPosition) detaches inspection from the live edge.
- Context banding turns numbers into status: qualitative ranges behind values (Few's bullet graphs, Battery's charging shading) read faster than colour alone and survive colour-vision issues.
- Density is configurable, not chosen once: iStat Menus' per-item modes, Little Snitch's grouping options, Instruments' track strategies all let the same app serve glance-mode and forensic-mode users.
- Energy and privacy are design features: iStat Menus advertises its own efficiency and local-only data; Little Snitch does GeoIP lookups offline; a monitor that wastes the resources it measures fails its premise. macOS 26's Menu Bar permission and the Liquid Glass slider show the platform moving toward user-controlled chrome.
- Accessibility is architecture, not polish: Audio Graphs, VO containers, Reduce Motion and Increase Contrast all need decisions at the data-pipeline and rendering level, not bolt-on labels.

## Implications for Coreography

- Lead with charts, literally: the main window should be a wall of live graphs with the process table in a secondary tab or inspector, inverting Activity Monitor. Organise like Instruments: a shared time axis with per-metric tracks (CPU, GPU, memory pressure, network, disk, energy, thermals) so cross-metric correlation is free.
- Adopt the three-layer chrome: unified toolbar (global controls: pause/resume, sample rate, range, add track), edge-to-edge sidebar for metric and process selection, inspector pane for the selected series/process. Use standard materials for the chart plane; Liquid Glass only for chrome. Test at both macOS 27 glass-slider extremes.
- Pick chart forms per metric: CPU = stacked user/system area plus per-core small multiples (offer both stacked-area rows and a core-by-time heatmap); memory = bullet-graph style bar (used vs wired vs compressed over capacity with pressure banding); network/disk = mirrored up/down rate charts with linear scale and labelled autoscale; energy = line plus shaded context regions (charging, throttling); thermals/fans = aligned line tracks with threshold rule marks; battery = ring for charge plus bar history.
- Palette: define a small semantic set colour-blind-verified (start from Okabe-Ito, adapt to macOS system colours): one hue per resource domain, lightness variants for sub-series, red reserved for real alert states and never paired opposite green. Direct-label series at line ends where space allows; dashing or markers as redundant encoding for the two most important series.
- Scales and honesty: fixed 0-100 for percents; autoscale rates with a "nice numbers" ceiling, labelled axis, and a one-click reset to a known full scale; min/max or LTTB decimation at draw time, never smoothing; keep raw samples for hover readouts; decimal GB for storage matching Disk Utility, explicit bit/byte choice for network rates; tabular numerals throughout.
- Rendering: Swift Charts for interactive/history charts (vectorized plots, built-in accessibility, scrollable axes with snapping). For the continuously ticking surface(s), a purpose-built view driven at sample cadence with an honest preferredFrameRateRange; profile before reaching for Metal. Synchronise multiple chart tracks via shared visible-domain state, and measure: Swift Charts scroll-sync jank is a documented risk.
- Ambient surfaces: MenuBarExtra (.window style) showing the current rates, a sparkline per metric and recent alerts (Little Snitch Control Center model); a Control Center control for pause/resume or a live status pill; one small desktop widget (CPU); float-on-top detached panels per metric (Activity Monitor precedent); live Dock icon option.
- Accessibility: AXChartDescriptor on every chart (updated for the visible window), VO container with per-point elements for static ranges, throttled announcements for ticking values, full keyboard navigation for drill-downs (DaisyDisk lesson), and explicit Reduced Motion behaviour: slower scroll cadence and no elastic effects rather than frozen charts.
- Power tools worth shipping: user-configurable sample interval and history depth, threshold rules with notifications (iStat Menus' Rules concept), annotation flags on the shared timeline (Instruments flags), per-process drill-down (select a process, all charts rescope), and a one-question-per-chart rule for the default layout to keep it honest.

## Sources

- https://developer.apple.com/videos/play/wwdc2022/110342/ (Design app experiences with charts, WWDC22)
- https://developer.apple.com/videos/play/wwdc2022/110340/ (Design an effective chart, WWDC22)
- https://appguidelines.com/human-interface-guidelines/version/22/charting-data/ (HIG Charts text mirror)
- https://developer.apple.com/videos/play/wwdc2024/10155/ (Swift Charts: Vectorized and function plots, WWDC24)
- https://developer.apple.com/documentation/updates/swiftcharts (Swift Charts updates timeline)
- https://developer.apple.com/videos/play/wwdc2025/313/ (Bring Swift Charts to the third dimension, WWDC25)
- https://developer.apple.com/videos/play/wwdc2023/10037/ (Explore pie charts and interactivity in Swift Charts, WWDC23)
- https://developer.apple.com/documentation/Charts/creating-a-data-visualization-dashboard-with-swift-charts (WWDC24 sample project)
- https://developer.apple.com/forums/thread/820382 (Swift Charts scrolling performance reports)
- https://nagarjuna2997.github.io/ios-agent-skill/guides/frameworks-swift-charts.html (Swift Charts performance notes)
- https://stackoverflow.com/questions/76903274/ (synchronized-scroll jank report)
- https://developer.apple.com/videos/play/wwdc2021/10122/ (Bring accessibility to charts in your app, WWDC21)
- https://developer.apple.com/documentation/accessibility/audio-graphs
- https://developer.apple.com/documentation/accessibility/axchart/accessibilitychartdescriptor
- https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor(_:)
- https://fossheim.io/writing/posts/apple-health-dataviz-a11y/ (Apple Health dataviz accessibility teardown)
- https://developer.apple.com/design/human-interface-guidelines/materials (HIG Materials / Liquid Glass rules)
- https://developer.apple.com/videos/play/wwdc2025/219/ (Meet Liquid Glass, WWDC25)
- https://developer.apple.com/videos/play/wwdc2025/310/ (Build an AppKit app with the new design, WWDC25)
- https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ (Liquid Glass announcement)
- https://9to5mac.com/2026/09/14/macos-27-golden-gate-now-available-here-is-everything-new/ (macOS 27 release coverage)
- https://9to5mac.com/2026/09/09/macos-27-golden-gate-here-are-apples-full-release-notes/ (release notes)
- https://www.macrumors.com/roundup/macos-27/ (macOS 27 design changes roundup)
- https://www.theverge.com/tech/946567/apple-macos-27-golden-gate-dev-beta-hands-on (Liquid Glass slider hands-on)
- https://developer.apple.com/sf-symbols/ (SF Symbols 7)
- https://developer.apple.com/videos/play/wwdc2025/337/ (What's new in SF Symbols 7, WWDC25)
- https://developer.apple.com/videos/play/wwdc2023/10258/ (Animate symbols in your app, WWDC23)
- https://developer.apple.com/fonts/ (SF Pro/SF Mono)
- https://developer.apple.com/documentation/swiftui/font/monospaceddigit()
- https://useyourloaf.com/blog/monospace-digits/ (monospaced digits walkthrough)
- https://developer.apple.com/videos/play/wwdc2022/10061/ (MenuBarExtra and window scenes, WWDC22)
- https://developer.apple.com/documentation/swiftui/menubarextrastyle/window
- https://stackoverflow.com/questions/79127814/resizing-a-menubarextra-window
- https://developer.apple.com/videos/play/wwdc2024/10148/ (Tailor macOS windows with SwiftUI, WWDC24)
- https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system
- https://developer.apple.com/documentation/widgetkit/controlcenter
- https://www.apple.com/nz/os/pdf/All_New_Features_macOS_Tahoe_Sept_2025_NZ_Final.pdf (Tahoe features incl. Controls gallery)
- https://developer.apple.com/videos/play/wwdc2023/10027/ (Bring widgets to new places, WWDC23)
- https://9to5mac.com/2023/11/07/macos-sonoma-widgets-desktop-iphone/ (Sonoma desktop widgets)
- https://developer.apple.com/documentation/swiftui/settings (Settings scene)
- https://github.com/exelban/stats (Stats open-source menu-bar monitor)
- https://github.com/exelban/stats/issues/3120 (macOS 26 Menu Bar permission)
- https://bjango.com/mac/istatmenus/ (iStat Menus product page)
- https://bjango.com/mac/istatmenus/versionhistory/ (iStat Menus version history)
- https://bjango.com/help/istatmenus7/welcome/ (iStat Menus 7 help)
- https://bjango.com/help/istatmenus7/combined/ (combined mode)
- https://www.macworld.com/article/538718/mac-gems-istat-menus-review.html (iStat Menus 6 review)
- https://www.forbes.com/sites/barrycollins/2024/09/07/istat-menus-7-review-this-great-mac-app-has-just-got-better/ (iStat Menus 7 review)
- https://obdev.at/en/products/littlesnitch/whatsnew.html (Little Snitch 6)
- https://help.obdev.at/littlesnitch6/lsm-overview (Network Monitor overview)
- https://help.obdev.at/littlesnitch6/lsm-map (map view)
- https://help.obdev.at/littlesnitch6/lsm-traffic-chart (traffic chart)
- https://help.obdev.at/littlesnitch6/pref-statusmenu (status menu options)
- https://help.obdev.at/littlesnitch5/lsm-selections (selection/filter model)
- https://www.obdev.at/support/littlesnitch/nssdp (map zoom limitation)
- https://daisydiskapp.com/releases/ (DaisyDisk release notes)
- https://nmac.to/daisydisk/ (DaisyDisk interaction description)
- https://grandperspectiv.sourceforge.net/ (GrandPerspective)
- https://sourceforge.net/projects/grandperspectiv/files/grandperspective/ (GrandPerspective releases)
- https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac (Activity Monitor)
- https://eclecticlight.co/2021/05/18/getting-more-from-activity-monitor-cpu/ (CPU windows detail)
- https://www.howtogeek.com/690252/how-to-show-macs-hidden-floating-performance-panels/ (floating panels)
- https://developer.apple.com/videos/play/wwdc2019/411/ (Getting Started with Instruments, WWDC19)
- https://nonstrict.eu/wwdcindex/wwdc2015/412/ (Profiling in Depth, WWDC15 transcript)
- https://www.meandmark.com/xcode-6-instruments-ui-changes/ (Instruments UI)
- https://developer.apple.com/library/archive/documentation/Performance/Conceptual/CellularBestPractices/Appendix/Appendix.html (Instruments track/detail panes)
- https://support.apple.com/guide/stocks/change-the-chart-display-stc4cfc704df/mac (Stocks chart controls)
- https://typenorm.com/apps/apple-weather (Weather app design analysis)
- https://support.apple.com/guide/mac-help/change-battery-settings-mchlfc3b7879/mac (Battery settings charts)
- https://support.apple.com/en-gb/guide/mac-help/mchle6eb6928/mac (battery usage history)
- https://developer.apple.com/design/awards/2025/ (Apple Design Awards 2025)
- https://9to5mac.com/2025/06/03/apple-announces-2025-apple-design-award-winners/ (ADA 2025 winners list)
- https://www.edwardtufte.com/notebook/sparklines-history-by-tufte-1324-to-now/ (sparkline principles)
- https://www.edwardtufte.com/notebook/sparkline-theory-and-practice-edward-tufte/ (sparkline practice)
- https://faculty.salisbury.edu/~jtanderson/teaching/cosc311/fa21/files/tufte.pdf (VDQI excerpt: data-ink)
- https://perceptualedge.com/articles/Whitepapers/Dashboard_Design.pdf (Few, real-time situation awareness)
- https://www.perceptualedge.com/articles/Whitepapers/Rich_Data_Poor_Data.pdf (Few, gauges vs bullet graphs)
- https://perceptualedge.com/articles/visual_business_intelligence/pervasive_hurdles_to_dd.pdf (Few, dashboard hurdles)
- https://www.perceptualedge.com/articles/visual_business_intelligence/the_visual_perception_of_variation.pdf (Few, preattentive attributes)
- https://www.tableau.com/videos/bullet-graphs (bullet graph intro)
- https://www.csc2.ncsu.edu/faculty/healey/PP/ (Healey, preattentive features)
- https://jfly.uni-koeln.de/color/index.html (Okabe-Ito colour universal design)
- https://colourwise.app/data-visualisation/colour-vision-deficiency-safe-charts (CVD-safe chart practice)
- https://en.wikipedia.org/wiki/Horizon_chart
- https://www.cdc.gov/cove/data-visualization-types/horizon-charts.html
- https://data.europa.eu/apps/data-visualisation-guide/data-dense-time-series
- https://vega.github.io/vega/examples/horizon-graph/
- https://en.wikipedia.org/wiki/Sankey_diagram
- https://arxiv.org/html/1907.02035v2 (Truncating the Y-Axis study)
- https://observablehq.com/blog/never-okay-crop-y-axis-except-when-it-is (axis cropping discussion)
- https://support.apple.com/en-us/102119 (how Apple measures storage capacity)
- https://skemman.is/bitstream/1946/15343/3/SS_MSthesis.pdf (Steinarsson LTTB thesis)
- https://www.datylon.com/blog/line-charts-sampling-time-series-data-sets (LTTB explained)
- https://clickhouse.com/docs/reference/functions/aggregate-functions/largestTriangleThreeBuckets (LTTB in ClickHouse)
- https://docs.rs/lttb/latest/lttb/ (LTTB Rust crate)
- https://developer.apple.com/videos/play/wwdc2021/10147/ (Optimize for variable refresh rate displays, WWDC21)
- https://devstreaming-cdn.apple.com/videos/wwdc/2014/419xxli6f60a6bs/419/419_advanced_graphics_and_animation_performance.pdf (offscreen-pass costs)
- https://martiancraft.com/blog/2026/06/looking-forward-to-wwdc-26/ (Swift Charts gaps noted pre-WWDC26)

## Verification log

Fact-check pass on 2026-10-17. Every cited URL was fetched or status-checked (Stack Overflow, Forbes, CDC, Skemman and Salisbury return bot-block 403s to automated fetches but resolve; no dead links found). Concrete claims were checked against the fetched source content.

Verified against primary sources (no change needed):

- WWDC session identities and content: 10155 (vectorized and function plots, including the self-attention heatmap example), 313 (Chart3D, SurfacePlot, pose and camera projection), 337 (SF Symbols 7 Draw, Variable Draw, gradients, Magic Replace), 219 (Liquid Glass layer rules, Regular/Clear variants, accessibility adaptations), 310 (NSSplitViewController glass, prominent toolbar style), 110342 (presented by Nicholas Felton), 110340, 10122 (4.5:1 contrast, avoid red/green, Audio Graphs), 10147 (variable refresh rate, preferredFrameRateRange), 411, 10258, 10061 (MenuBarExtra introduction), 10037, 10148 (.restorationBehavior(.disabled)).
- Swift Charts updates page: June 2024 vectorized plots, June 2025 Chart3D, no later entries.
- iStat Menus: 7.5 on 2026-09-14 with Liquid Glass menus and Astronomy; macOS 13.5+; 14-day trial; Setapp USD 9.99/mo; 7.0 CPU claim of one fifth of v6; E/P core colouring; history ranges 10 minutes to 28 days; 7.2 Liquid Glass icon; price not published server-side.
- DaisyDisk: 4.34.2 on 2026-07-10; APFS clone accounting in 4.34; Tahoe glass icons in 4.33; keyboard navigation in 4.25.
- GrandPerspective: 3.8.1 on 2026-09-13; Liquid Glass compatibility in 3.7.0; macOS 14 deployment target in 3.8.0; SourceForge plus Mac App Store distribution.
- Little Snitch: demo terms (three-hour restartable sessions, Network Monitor expires after 30 days); grouping options; traffic chart hover totals, day/week/month focus, Now button, one year of history; map line colours (blue idle, flashing green active, red fully denied); local GeoIP from MaxMind, IP2Location, db-ip, Geonames; Apple Maps world-zoom limitation; menu-bar five-minute chart or live meter.
- macOS 27: 2026-09-14 release; Appearance slider ultra-clear to fully tinted, no fully opaque; uniform toolbars; edge-to-edge sidebars with colour icons; uniform window corner radii; fewer icons in drop-down menus; revamped traffic-light buttons; Liquid Glass diffuses busy content more effectively.
- macOS 26: ControlCenter class availability macOS 26.0+; Menu Bar permission reported under System Settings > Menu Bar (exelban/stats issue 3120).
- Fonts: SF Pro nine weights, variable optical sizes, four widths; SF Pro nine weights and three scales for symbols.
- Community performance notes (50,000 marks, no virtualization, drawingGroup trade-offs, RectangleMark over BarMark) and martiancraft wishlist (pan/zoom, candlesticks) match their pages.
- data.europa.eu horizon chart example: 73 series, two years of daily values, over 53,000 points.
- Activity Monitor details via Eclectic Light (CPU Usage and CPU History windows, 5-second default update frequency, E/P grouping, resizable history, fixed user-green and system-red colours); Little Snitch traffic chart details via obdev help; SF Pro and monospacedDigit claims via Apple fonts and docs.

Corrections made (old -> new):

- Tufte: "sparklines... with a data-ink ratio of 1.0" -> "with almost no non-data ink" (the 1.0 figure is not in Tufte's text); "sparkline runs 5:1" -> "about 5:1 (unverified)".
- Swift Charts: dropped "chartScrollTargetBehavior(.valueAligned)" from the interaction API list (could not confirm the symbol); kept chartScrollableAxes, chartXVisibleDomain, chartScrollPosition.
- Liquid Glass: "more uniform refraction" -> "more effective diffusion of busy content" (matches MacRumors wording); dropped "around 35% opacity" from the Clear-variant dimming layer (no source states a figure); "gives traffic-light buttons a glassy look; Verge's hands-on and Apple's release notes describe the changes" -> revamped traffic-light buttons attributed to Apple release notes, MacRumors and 9to5Mac (the Verge hands-on does not mention them).
- SF Symbols: replaced the forum-report claim about symbolVariableValueMode defaults with the session 337 finding that symbols supporting both Variable Color and Variable Draw pick one at render time; removed the forums tag link.
- Menu bar extras: hedged the Menu Bar permission and the control-in-Control-Center claims as reported/unverified where they rest on a single issue report; noted ControlCenter is macOS 26.0+.
- iStat Menus: "Nine independent menu-bar items" -> "Ten independent menu-bar items (Astronomy arrived with 7.5)"; dropped "and hotkeys" from the 7.0 additions (hotkeys predate 7.0; 7.0 moved them to the rules tab).
- Instruments: "The Instruments team rebuilt the track view for version 7 explicitly for responsiveness, profiling it with Instruments itself" -> Xcode 6-era redesign rebuilt the UI around the track pane (the unverified version-7 rewrite claim is removed; WWDC 411's responsiveness demo concerns a sample app, not Instruments itself). Same fix applied to the rendering-stack section.
- Links: both apple-docs.everest.mt mirror links replaced with the official developer.apple.com pages (WWDC24 sample article and the SwiftUI Settings documentation).
- Added the missing scope section "Apple Design Award winners that visualise data" with verified 2025 winners (Watch Duty, Ground News, Lumy).

Remains unverified:

- The exact 5:1 aspect ratio of Tufte's example financial sparkline.
- CDC COVE horizon chart page content (the site bot-blocks automated fetches; link resolves).
- Little Snitch's exact latest 6.x point version (release notes page not item-checked).
- iStat Menus licence prices (rendered client-side only).
- Claims resting on single community reports: MenuBarExtra window resizing via styleMask (Stack Overflow), Swift Charts synchronized-scrolling jank quote (developer forum thread 820382 renders via JavaScript and could not be text-checked), and macOS 26 letting users tuck menu-bar items into Control Center.
- Stocks range pill list and Battery settings chart details were checked for link liveness only; the Apple support pages render via JavaScript and their exact wording was not text-verified.

