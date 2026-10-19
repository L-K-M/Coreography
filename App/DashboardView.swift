import SwiftUI
import AppKit
import Charts
import Accessibility
import UniformTypeIdentifiers
import CoreographyServices

@MainActor
struct DashboardView: View {
    @Bindable var model: DashboardModel
    let hud: HUDController
    @FocusState private var processFilterFocused: Bool
    /// A palette process action, confirmed once the palette has closed.
    @State private var queuedPaletteAction: ProcessActionRequest?
    @State private var markerName = ""
    @State private var paletteAction: ProcessActionRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let inventory = model.latest?.inventory {
                    HStack {
                        Text("\(inventory.logicalCPUCount) logical CPUs")
                        if model.samplingCadence == .lowPower {
                            Text("Low Power Mode: sampling every \(model.samplingSeconds.formatted()) s")
                                .help("Coreography halves its sampling rate while Low Power Mode is on")
                        }
                        Spacer()
                        SelfCostLine(model: model)
                        Spacer()
                        Text(inventory.operatingSystem)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // The person's order, sizes and hidden lanes (plan: each lane's menu).
                ForEach(model.laneLayout.visible) { kind in
                    laneView(kind)
                        .environment(\.laneGraphHeight, Layout.graphHeight(model.laneLayout.size(of: kind)))
                        .overlay(alignment: .topTrailing) { LaneMenu(model: model, lane: kind) }
                }

                AskPanel(model: model)

                if let report = model.rangeReport {
                    RangePanel(model: model, report: report)
                }

                Picker("Detail", selection: $model.detailPane) {
                    Text("Processes").tag(DetailPane.processes)
                    Text("Connections").tag(DetailPane.connections)
                    Text("Startup").tag(DetailPane.startup)
                    Text("Sensors").tag(DetailPane.sensors)
                    Text("Sessions").tag(DetailPane.sessions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 520)

                switch model.detailPane {
                case .processes: ProcessPane(model: model, filterFocused: $processFilterFocused)
                case .connections: ConnectionsPane(model: model)
                case .startup: StartupPane(model: model)
                case .sensors: SensorsPane(model: model)
                case .sessions: SessionsPane(model: model)
                }

                DisclosureGroup("Numeric readings") {
                    Table(Array(model.frames.suffix(10))) {
                        TableColumn("Time") { frame in
                            Text(frame.stamp.wallTime, format: .dateTime.hour().minute().second())
                        }
                        TableColumn("CPU, whole machine") { frame in
                            Text(MetricText.percent(frame.cpuPercentOfMachine.numericValue))
                        }
                        TableColumn("Used memory, estimated") { frame in
                            Text(MetricText.bytes(frame.memoryUsedBytes.numericValue))
                        }
                        TableColumn("Thermal pressure") { frame in
                            Text(ThermalText.level(frame.thermalPressure))
                        }
                    }
                    .frame(height: 150)
                }

                DisclosureGroup("Memory numeric readings") {
                    Table(Array(model.frames.suffix(10))) {
                        TableColumn("Time") { Text($0.stamp.wallTime, format: .dateTime.hour().minute().second()) }
                        TableColumn("Used") { ProcessMetricCell(reading: $0.memoryUsedBytes, format: .bytes) }
                        TableColumn("App") { ProcessMetricCell(reading: $0.memory.appBytes, format: .bytes) }
                        TableColumn("Wired") { ProcessMetricCell(reading: $0.memory.wiredBytes, format: .bytes) }
                        TableColumn("Compressed") { ProcessMetricCell(reading: $0.memory.compressedBytes, format: .bytes) }
                        TableColumn("Cached files") { ProcessMetricCell(reading: $0.memory.cachedBytes, format: .bytes) }
                        TableColumn("Swap used") { ProcessMetricCell(reading: $0.memory.swapUsedBytes, format: .bytes) }
                        TableColumn("Swap in/s") { ProcessMetricCell(reading: $0.memory.swapInBytesPerSecond, format: .rate) }
                        TableColumn("Swap out/s") { ProcessMetricCell(reading: $0.memory.swapOutBytesPerSecond, format: .rate) }
                        TableColumn("Pressure") { Text(MemoryText.pressure($0.memory.pressure)) }
                    }
                    .frame(height: 150)
                }

                DisclosureGroup("GPU numeric readings") {
                    Table(model.gpuReadings) {
                        TableColumn("Time") { Text($0.time, format: .dateTime.hour().minute().second()) }
                        TableColumn("GPU", value: \.name)
                        TableColumn("Busy") { ProcessMetricCell(reading: $0.device.utilizationPercent, format: .percent) }
                        TableColumn("Renderer") { ProcessMetricCell(reading: $0.device.rendererPercent, format: .percent) }
                        TableColumn("Tiler") { ProcessMetricCell(reading: $0.device.tilerPercent, format: .percent) }
                        TableColumn("Memory in use") { ProcessMetricCell(reading: $0.device.inUseMemoryBytes, format: .bytes) }
                    }
                    .frame(height: 150)
                }

                DisclosureGroup("Sensor numeric readings") {
                    Table(Array(model.sensorFrames.suffix(10))) {
                        TableColumn("Time") { Text($0.stamp.wallTime, format: .dateTime.hour().minute().second()) }
                        TableColumn("Hottest sensor") { Text($0.hottest?.key ?? "–") }
                        TableColumn("Temperature") { Text(ThermalText.celsius($0.hottest?.celsius.numericValue)) }
                        TableColumn("SMC system power") { ProcessMetricCell(reading: $0.systemPowerWatts, format: .watts) }
                        TableColumn("Fans") { Text($0.fans.map { ThermalText.rpm($0.rpm.numericValue) }.joined(separator: ", ")) }
                    }
                    .frame(height: 150)
                }

                DisclosureGroup("Power numeric readings") {
                    Table(Array(model.powerFrames.suffix(10))) {
                        TableColumn("Time") { Text($0.stamp.wallTime, format: .dateTime.hour().minute().second()) }
                        TableColumn("Source") { Text(PowerText.source($0)) }
                        TableColumn("System draw") { ProcessMetricCell(reading: $0.systemPowerWatts, format: .watts) }
                        TableColumn("Battery") { ProcessMetricCell(reading: $0.batteryChargePercent, format: .percent) }
                        TableColumn("Battery power") { ProcessMetricCell(reading: $0.batteryPowerWatts, format: .watts) }
                        TableColumn("Adapter rating") { ProcessMetricCell(reading: $0.adapterRatingWatts, format: .watts) }
                    }
                    .frame(height: 150)
                }

                DisclosureGroup("Network numeric readings") {
                    Table(model.networkReadings) {
                        TableColumn("Time") { Text($0.time, format: .dateTime.hour().minute().second()) }
                        TableColumn("Interface") { Text($0.interfaceName ?? "–") }
                        TableColumn("Received/s") { ProcessMetricCell(reading: $0.received, format: .rate) }
                        TableColumn("Sent/s") { ProcessMetricCell(reading: $0.sent, format: .rate) }
                    }
                    .frame(height: 150)
                }

                DisclosureGroup("Disk numeric readings") {
                    Table(model.diskReadings) {
                        TableColumn("Time") { Text($0.time, format: .dateTime.hour().minute().second()) }
                        TableColumn("Device") { Text($0.deviceName ?? $0.status ?? "–") }
                        TableColumn("Read/s") { row in
                            if let reading = row.read { ProcessMetricCell(reading: reading, format: .rate) }
                            else { Text("–") }
                        }
                        TableColumn("Written/s") { row in
                            if let reading = row.written { ProcessMetricCell(reading: reading, format: .rate) }
                            else { Text("–") }
                        }
                    }
                    .frame(height: 150)
                }

                if let error = model.collectionError {
                    Text(error).foregroundStyle(.red)
                    Button("Retry collection") {
                        model.stop()
                        model.start()
                    }
                }

                Text("Used memory is app, wired and compressed memory, estimated from VM page counts. Missing readings leave gaps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Layout.padding)
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: Binding(
            get: { if case .idle = model.sampleState { false } else { true } },
            set: { if !$0 { model.dismissSample() } }
        )) {
            SampleReportView(model: model)
        }
        .sheet(isPresented: $model.paletteShown, onDismiss: {
            paletteAction = queuedPaletteAction
            queuedPaletteAction = nil
        }) {
            CommandPaletteView(model: model, hud: hud) { queuedPaletteAction = $0 }
        }
        .modifier(ProcessActionConfirmation(model: model, pendingAction: $paletteAction))
        .alert("Add a marker", isPresented: $model.markerPromptShown) {
            TextField("Name", text: $markerName)
            Button("Add") {
                model.addMarker(named: markerName)
                markerName = ""
            }
            Button("Cancel", role: .cancel) { markerName = "" }
        } message: {
            Text("It appears on every lane at this moment.")
        }
        .inspector(isPresented: $model.inspectorShown) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Inspector", systemImage: "sidebar.right") { model.inspectorShown.toggle() }
                    .help("Show or hide the inspector")
            }
            ToolbarItem(placement: .primaryAction) {
                // Command-R records a session (plan P19); stopping saves its report.
                if model.recordingName == nil {
                    Button("Record", systemImage: "record.circle") { model.startRecording() }
                        .keyboardShortcut("r", modifiers: .command)
                        .help("Record a session at full resolution")
                } else {
                    Button("Stop", systemImage: "stop.circle.fill") { Task { await model.stopRecording() } }
                        .keyboardShortcut("r", modifiers: .command)
                        .foregroundStyle(.red)
                        .help("Stop and save \(model.recordingName ?? "")")
                }
            }
            ToolbarItem(placement: .principal) {
                Text(ToolbarText.status(model))
                    .font(.caption)
                    .monospacedDigit()
                    .help(model.storedHistoryProblem ?? "")
            }
            if let app = model.scopedApp {
                ToolbarItem(placement: .automatic) {
                    Button("Scope: \(app)", systemImage: "xmark.circle") { model.scopedApp = nil }
                        .help("Clear the app scope")
                }
            }
            ToolbarItem(placement: .automatic) {
                Picker("Time range", selection: $model.timeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(TimeRangeText.label(range)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .help("Visible history; up to one hour is kept in memory")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Marker", systemImage: "flag") { model.markerPromptShown = true }
                    .keyboardShortcut(processFilterFocused ? nil : KeyboardShortcut("m", modifiers: []))
                    .help("Drop a named marker on every lane (M)")
            }
            ToolbarItem(placement: .primaryAction) {
                // Pausing stops sampling; Hold only freezes what is drawn.
                Button(
                    model.samplingPaused ? "Resume recording" : "Pause recording",
                    systemImage: model.samplingPaused ? "play.circle" : "pause.circle"
                ) {
                    model.samplingPaused ? model.resumeSampling() : model.pauseSampling()
                }
                .help("Stop sampling; the pause stays as a labelled gap in every series")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(
                    model.displayMode == .live ? "Hold display" : "Return to live",
                    systemImage: model.displayMode == .live ? "pause" : "play"
                ) {
                    model.toggleDisplayHold()
                }
                .keyboardShortcut(processFilterFocused ? nil : KeyboardShortcut(.space, modifiers: []))
                .help("Hold the display while collection continues")
            }
        }
        .onAppear { model.start() }
    }

    @ViewBuilder private func laneView(_ kind: LaneKind) -> some View {
        switch kind {
        case .cpu: lane(.cpu)
        case .memory: MemoryLane(model: model)
        case .gpu: GPULane(model: model)
        case .power: PowerLane(model: model)
        case .disk: DiskLane(model: model)
        case .network: NetworkLane(model: model)
        case .thermal: ThermalLane(model: model)
        }
    }

    private func lane(_ metric: DashboardMetric) -> some View {
        let reading = model.reading(for: metric)
        let laneSize = model.laneLayout.size(of: .cpu)
        let graphHeight = Layout.graphHeight(laneSize)
        let title = metric == .cpu ? String(localized: "CPU") : String(localized: "Memory")
        let maximum = metric == .cpu
            ? MetricText.percentScale
            : Double(model.latest?.inventory.physicalMemoryBytes ?? 1)
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-model.timeRange.seconds)
        let points = visiblePoints(model.points(for: metric), start, end)
        let scoped = metric == .cpu ? model.scopedSeries().map { visiblePoints($0.cpu, start, end) } : nil
        let split = metric == .cpu ? model.cpuSplitPoints().filter { (start...end).contains($0.time) } : []
        let tiers = metric == .cpu ? model.tierBandCells().filter { $0.end >= start && $0.start <= end } : []

        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(metric == .cpu
                     ? MetricText.percent(reading?.numericValue)
                     : MetricText.bytes(reading?.numericValue))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                if metric == .cpu, let parts = model.displayedCPUSplit {
                    Text("user \(MetricText.percent(parts.user))  system \(MetricText.percent(parts.system))")
                        .font(.caption)
                        .help("User includes nice time; system is the kernel's share")
                } else {
                    Text(metric == .cpu ? "Whole-machine activity" : "Used memory, estimated")
                        .font(.caption)
                }
                Text(reading?.reason ?? reading?.method ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if metric == .cpu {
                    Text(SiliconText.tiers(model.displayedSiliconFrame))
                        .font(.caption).foregroundStyle(.secondary)
                        .help("Activity and frequency per core tier from IOReport residency, estimated")
                    // Heuristics, labelled as such; the evidence shows on hover.
                    ForEach(model.bottleneckHints, id: \.kind) { hint in
                        Text(hint.title)
                            .font(.caption.weight(.medium)).foregroundStyle(.orange)
                            .help(hint.evidence.joined(separator: "\n"))
                            .accessibilityValue(hint.evidence.joined(separator: ", "))
                    }
                    ContributorLine(model: model, subsystem: .cpu)
                    if let app = model.scopedApp {
                        Text("\(app): \(MetricText.percent(scoped?.last?.value))")
                            .font(.caption.weight(.medium)).foregroundStyle(.blue)
                    }
                }
            }
            .frame(width: Layout.headerWidth, alignment: .leading)

            if points.isEmpty {
                Text(reading?.reason ?? String(localized: "Collecting samples…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: graphHeight)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Chart {
                        // User under system (plan: CPU lane); position, not hue, tells them apart.
                        ForEach(split) { point in
                            AreaMark(
                                x: .value("Time", point.time), yStart: .value("User", 0), yEnd: .value("User", point.user),
                                series: .value("Segment", "user-\(point.segment)")
                            )
                            .foregroundStyle(Color.blue.opacity(0.25))
                            AreaMark(
                                x: .value("Time", point.time), yStart: .value("System", point.user),
                                yEnd: .value("System", point.user + point.system),
                                series: .value("Segment", "system-\(point.segment)")
                            )
                            .foregroundStyle(Color.blue.opacity(0.55))
                        }
                        ForEach(points) { point in
                            LineMark(
                                x: .value("Time", point.time),
                                y: .value(title, point.value),
                                series: .value("Segment", "lane-\(point.segment)")
                            )
                            .foregroundStyle(metric == .cpu ? Color.blue : Color.teal)
                            .interpolationMethod(.linear)
                        }
                        // The scoped app's share, as a second series in the lane's hue (plan P8).
                        ForEach(scoped ?? []) { point in
                            LineMark(
                                x: .value("Time", point.time), y: .value(title, point.value),
                                series: .value("Segment", "scoped-\(point.segment)")
                            )
                            .foregroundStyle(Color.blue.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                        }
                        CursorRule(time: model.cursorTime, range: start...end)
                        SelectionBand(selection: model.draftSelection ?? model.selection, range: start...end)
                        SelectionBand(selection: model.draftComparison ?? model.comparison, range: start...end, tint: .orange)
                        MarkerRules(markers: model.timelineMarkers, range: start...end)
                    }
                    .chartCursor(model)
                    .chartLegend(.hidden)
                    .chartXScale(domain: start...end)
                    .chartYScale(domain: 0...max(1, maximum))
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: [0, maximum / 2, maximum]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text(metric == .cpu ? MetricText.percent(number) : MetricText.bytes(number))
                                        .frame(width: Layout.axisLabelWidth, alignment: .leading)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisValueLabel(format: .dateTime.hour().minute().second())
                        }
                    }
                    .frame(height: graphHeight)
                    .accessibilityChartDescriptor(MetricChartAccessibility(
                        title: title, metric: metric, points: points,
                        start: start, end: end, maximum: max(1, maximum)
                    ))
                    // Sheds first when the lane is compact (plan: lane sizes).
                    if laneSize != .compact, !tiers.isEmpty {
                        TierStrip(cells: tiers, range: start...end)
                    }
                }
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
    }
}

private struct MemoryLane: View {
    @Environment(\.laneGraphHeight) private var graphHeight
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-model.timeRange.seconds)
        let stack = Decimation.stack(model.memoryStack().filter { $0.time >= start && $0.time <= end }, start: start, end: end)
        let pressure = model.memoryPressureSpans().filter { $0.end >= start && $0.start <= end }
        let capacity = Double(max(1, model.latest?.inventory.physicalMemoryBytes ?? 1))
        let used = model.reading(for: .memory)
        let detail = model.displayedFrame?.memory

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Memory").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(MetricText.bytes(used?.numericValue))
                    .font(.system(size: 30, weight: .semibold))
                Text("of \(MetricText.bytes(capacity)) used, estimated").font(.caption)
                HStack(spacing: 4) {
                    Circle().fill(MemoryStyle.color(detail?.pressureLevel)).frame(width: 7, height: 7)
                    Text("Pressure " + MemoryText.pressure(detail?.pressure))
                }
                .font(.caption)
                Text("Swap \(MetricText.bytes(detail?.swapUsedBytes.numericValue)) of \(MetricText.bytes(detail?.swapTotalBytes.numericValue))")
                    .font(.caption)
                Text("Swap in \(MetricText.rate(detail?.swapInBytesPerSecond.numericValue)) · out \(MetricText.rate(detail?.swapOutBytesPerSecond.numericValue))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Page-ins \(MetricText.rate(detail?.pageInBytesPerSecond.numericValue)) · compression \(MemoryText.ratio(detail?.compressionRatio.numericValue))")
                    .font(.caption).foregroundStyle(.secondary)
                ContributorLine(model: model, subsystem: .memory)
            }
            .monospacedDigit()
            .frame(width: Layout.headerWidth, alignment: .leading)

            if stack.isEmpty {
                Text(used?.reason ?? String(localized: "Collecting samples…"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: graphHeight)
            } else {
                chart(stack: stack, pressure: pressure, capacity: capacity, start: start, end: end)
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
        .alertTint(model.activeAlerts[.memory])
    }

    // Layers stack under a dashed capacity line; the pressure band sits above it.
    private func chart(
        stack: [MemoryStackPoint], pressure: [MemoryPressureSpan],
        capacity: Double, start: Date, end: Date
    ) -> some View {
        Chart {
            ForEach(stack) { point in
                AreaMark(
                    x: .value("Time", point.time),
                    yStart: .value("Lower", point.lower), yEnd: .value("Upper", point.upper),
                    series: .value("Layer", "\(point.category.rawValue)-\(point.segment)")
                )
                .foregroundStyle(MemoryStyle.color(point.category))
                .interpolationMethod(.linear)
            }
            RuleMark(y: .value("Physical memory", capacity))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(pressure) { span in
                RectangleMark(
                    xStart: .value("Start", max(span.start, start)), xEnd: .value("End", span.end),
                    yStart: .value("Band", capacity * MemoryStyle.bandBottom),
                    yEnd: .value("Band", capacity * MemoryStyle.bandTop)
                )
                .foregroundStyle(MemoryStyle.color(span.level))
            }
            CursorRule(time: model.cursorTime, range: start...end)
            SelectionBand(selection: model.draftSelection ?? model.selection, range: start...end)
            SelectionBand(selection: model.draftComparison ?? model.comparison, range: start...end, tint: .orange)
            MarkerRules(markers: model.timelineMarkers, range: start...end)
        }
        .chartCursor(model)
        .chartLegend(.hidden)
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...(capacity * MemoryStyle.bandTop))
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, capacity / 2, capacity]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(MetricText.bytes(number))
                            .frame(width: Layout.axisLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .frame(height: graphHeight)
        .accessibilityChartDescriptor(MemoryChartAccessibility(
            stack: stack, pressure: model.displayedFrame?.memory.pressure,
            start: start, end: end, capacity: capacity
        ))
    }
}

private enum MemoryStyle {
    // The band occupies the top of the plot, clear of the capacity line.
    static let bandBottom = 1.04
    static let bandTop = 1.1

    static func color(_ category: MemoryCategory) -> Color {
        switch category {
        case .app: return .blue
        case .wired: return .indigo
        case .compressed: return .teal
        case .cached: return .gray.opacity(0.35)
        }
    }

    static func color(_ level: CapturedMemoryPressure?) -> Color {
        switch level {
        case .normal: return .gray.opacity(0.35)
        case .warning: return .yellow
        case .critical: return .red
        case nil: return .clear
        }
    }
}

private enum MemoryText {
    static func pressure(_ reading: DashboardReading?) -> String {
        guard let reading else { return "–" }
        switch CapturedMemoryPressure(reading: reading) {
        case .normal: return String(localized: "normal")
        case .warning: return String(localized: "warning")
        case .critical: return String(localized: "critical")
        case nil:
            return reading.availability == .restricted
                ? String(localized: "restricted") : String(localized: "unavailable")
        }
    }

    static func ratio(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(1))) + "×"
    }
}

private struct MemoryChartAccessibility: AXChartDescriptorRepresentable {
    let stack: [MemoryStackPoint]
    let pressure: DashboardReading?
    let start: Date
    let end: Date
    let capacity: Double

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
            gridlinePositions: []
        ) { Date(timeIntervalSinceReferenceDate: $0).formatted(date: .omitted, time: .standard) }
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Bytes"), range: 0...capacity, gridlinePositions: [capacity]
        ) { MetricText.bytes($0) }

        // Each layer reads as its own bytes, not its stacked position.
        var series: [AXDataSeriesDescriptor] = []
        for category in MemoryCategory.allCases {
            let segments = Dictionary(grouping: stack.filter { $0.category == category }, by: \.segment)
            for segment in segments.keys.sorted() {
                series.append(AXDataSeriesDescriptor(
                    name: category.rawValue.capitalized, isContinuous: true,
                    dataPoints: (segments[segment] ?? []).map {
                        AXDataPoint(x: $0.time.timeIntervalSinceReferenceDate, y: $0.value)
                    }
                ))
            }
        }
        return AXChartDescriptor(
            title: String(localized: "Memory"),
            summary: String(localized: "App, wired, compressed and cached memory; pressure \(MemoryText.pressure(pressure)). Missing readings leave gaps."),
            xAxis: x, yAxis: y, additionalAxes: [], series: series
        )
    }
}

private struct GPULane: View {
    @Environment(\.laneGraphHeight) private var graphHeight
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-model.timeRange.seconds)
        let series = model.gpuSeries()
        let hasVisiblePoints = series.contains { $0.points.contains { $0.time >= start && $0.time <= end } }
        let latest = model.displayedGPUFrame
        let devices = latest?.devices ?? []

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GPU").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(MetricText.percent(devices.first?.utilizationPercent.numericValue))
                    .font(.system(size: 30, weight: .semibold))
                Text(devices.first?.name ?? String(localized: "No GPU observed")).font(.caption)
                ForEach(devices.dropFirst()) { device in
                    Text("\(device.name) \(MetricText.percent(device.utilizationPercent.numericValue))")
                        .font(.caption)
                }
                if let device = devices.first {
                    Text("Memory in use \(MetricText.bytes(device.inUseMemoryBytes.numericValue))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(GPUText.status(latest, cursor: model.cursorTime)).font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: Layout.headerWidth, alignment: .leading)

            if !hasVisiblePoints {
                Text(GPUText.status(latest, cursor: model.cursorTime))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: graphHeight)
            } else {
                chart(series, start: start, end: end)
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
    }

    private func chart(_ series: [GPUSeries], start: Date, end: Date) -> some View {
        Chart {
            ForEach(series) { device in
                ForEach(visiblePoints(device.points, start, end)) { point in
                    LineMark(
                        x: .value("Time", point.time), y: .value("Busy", point.value),
                        series: .value("Device", "\(device.id.registryEntryID)-\(point.segment)")
                    )
                    .foregroundStyle(Color.purple)
                    .interpolationMethod(.linear)
                }
            }
            CursorRule(time: model.cursorTime, range: start...end)
            SelectionBand(selection: model.draftSelection ?? model.selection, range: start...end)
            SelectionBand(selection: model.draftComparison ?? model.comparison, range: start...end, tint: .orange)
            MarkerRules(markers: model.timelineMarkers, range: start...end)
        }
        .chartCursor(model)
        .chartLegend(.hidden)
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...MetricText.percentScale)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, MetricText.percentScale / 2, MetricText.percentScale]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(MetricText.percent(number)).frame(width: Layout.axisLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .frame(height: graphHeight)
        .accessibilityChartDescriptor(GPUChartAccessibility(series: series, start: start, end: end))
    }
}

private enum GPUText {
    static func status(_ frame: CapturedGPU?, cursor: Date?) -> String {
        guard let frame else {
            return cursor == nil
                ? String(localized: "Collecting GPU readings…") : String(localized: "No GPU sample near the cursor")
        }
        if let reason = frame.enumeration.reason { return reason }
        if frame.devices.isEmpty { return String(localized: "No GPU publishes utilization on this Mac") }
        if let reason = frame.devices.first?.utilizationPercent.reason { return reason }
        return String(localized: "IOAccelerator · driver-reported busy time")
    }
}

private struct GPUChartAccessibility: AXChartDescriptorRepresentable {
    let series: [GPUSeries]
    let start: Date
    let end: Date

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
            gridlinePositions: []
        ) { Date(timeIntervalSinceReferenceDate: $0).formatted(date: .omitted, time: .standard) }
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "GPU busy"), range: 0...MetricText.percentScale, gridlinePositions: []
        ) { MetricText.percent($0) }
        var descriptors: [AXDataSeriesDescriptor] = []
        for device in series {
            let segments = Dictionary(grouping: visiblePoints(device.points, start, end), by: \.segment)
            for segment in segments.keys.sorted() {
                descriptors.append(AXDataSeriesDescriptor(
                    name: device.name, isContinuous: true,
                    dataPoints: (segments[segment] ?? []).map {
                        AXDataPoint(x: $0.time.timeIntervalSinceReferenceDate, y: $0.value)
                    }
                ))
            }
        }
        return AXChartDescriptor(
            title: String(localized: "GPU"),
            summary: String(localized: "Driver-reported busy percentage per GPU; missing readings leave gaps."),
            xAxis: x, yAxis: y, additionalAxes: [], series: descriptors
        )
    }
}

private struct PowerLane: View {
    @Environment(\.laneGraphHeight) private var graphHeight
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-model.timeRange.seconds)
        let points = visiblePoints(model.batteryChargePoints(), start, end)
        let plugged = model.externalPowerSpans().filter { $0.end >= start && $0.start <= end }
        let latest = model.displayedPowerFrame
        let system = model.displayedSystemPower

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Power").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(MetricText.watts(system?.numericValue) + (system?.availability == .estimated ? " est." : ""))
                    .font(.system(size: 30, weight: .semibold))
                Text(PowerText.systemSource(system)).font(.caption)
                Text(SiliconText.blocks(model.displayedSiliconFrame)).font(.caption)
                    .help("Modeled block power from IOReport's energy model; not a measured rail")
                Text(PowerText.battery(latest)).font(.caption)
                Text(PowerText.adapterAndHealth(latest)).font(.caption).foregroundStyle(.secondary)
                if let awake = PowerText.keptAwake(model.sleepPreventers) {
                    Text(awake).font(.caption).foregroundStyle(.orange)
                }
                Text(system?.reason ?? system?.method ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: Layout.headerWidth, alignment: .leading)

            if points.isEmpty {
                Text(latest?.batteryChargePercent.reason ?? String(localized: "Collecting samples…"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: graphHeight)
            } else {
                chart(points: points, plugged: plugged, start: start, end: end)
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
        .alertTint(model.activeAlerts[.power])
    }

    // Battery charge on a fixed 0-100% scale; a grey band above marks external power.
    private func chart(
        points: [DashboardPoint], plugged: [ExternalPowerSpan], start: Date, end: Date
    ) -> some View {
        Chart {
            ForEach(plugged) { span in
                RectangleMark(
                    xStart: .value("Start", max(span.start, start)), xEnd: .value("End", span.end),
                    yStart: .value("Band", PowerStyle.bandBottom), yEnd: .value("Band", PowerStyle.bandTop)
                )
                .foregroundStyle(Color.gray.opacity(0.35))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.time), y: .value("Battery", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(Color.green)
                .interpolationMethod(.linear)
            }
            CursorRule(time: model.cursorTime, range: start...end)
            SelectionBand(selection: model.draftSelection ?? model.selection, range: start...end)
            SelectionBand(selection: model.draftComparison ?? model.comparison, range: start...end, tint: .orange)
            MarkerRules(markers: model.timelineMarkers, range: start...end)
        }
        .chartCursor(model)
        .chartLegend(.hidden)
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...PowerStyle.bandTop)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, MetricText.percentScale / 2, MetricText.percentScale]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(MetricText.percent(number)).frame(width: Layout.axisLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .frame(height: graphHeight)
        .accessibilityChartDescriptor(PowerChartAccessibility(
            points: points, pluggedSpans: plugged.count, start: start, end: end
        ))
    }
}

private enum PowerStyle {
    static let bandBottom = 104.0
    static let bandTop = 110.0
}

private enum PowerText {
    /// "Kept awake by Music (Playing audio, 12 min) and 1 other" (plan P2).
    static func keptAwake(_ holders: [AssertionHolder]) -> String? {
        guard let first = holders.first else { return nil }
        let others = holders.count > 1 ? " " + String(localized: "and \(holders.count - 1) other") : ""
        return String(localized: "Kept awake by \(first.processName ?? "PID \(first.assertion.pid)") (\(detail(first.assertion)))") + others
    }

    /// "Prevents system sleep: Playing audio, 12 min".
    static func assertion(_ assertion: CapturedAssertion) -> String {
        switch assertion.effect {
        case .preventsSystemSleep: String(localized: "Prevents system sleep") + ": " + detail(assertion)
        case .preventsDisplaySleep: String(localized: "Keeps the display on") + ": " + detail(assertion)
        // The detail already falls back to the type; naming it twice says nothing.
        case .other: assertion.name == nil ? detail(assertion) : assertion.type + ": " + detail(assertion)
        }
    }

    private static func detail(_ assertion: CapturedAssertion) -> String {
        let name = assertion.name ?? assertion.type
        guard let since = assertion.since else { return name }
        let age = Duration.seconds(max(0, Date().timeIntervalSince(since)))
        return name + ", " + age.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func systemSource(_ reading: DashboardReading?) -> String {
        guard reading?.numericValue != nil else { return String(localized: "System draw") }
        switch reading?.source?.channel {
        case "PSTR", "PDTR": return String(localized: "System draw, SMC power rail")
        default: return String(localized: "System draw, from battery")
        }
    }

    static func source(_ frame: CapturedPower) -> String {
        switch frame.powerSource {
        case .externalPower: return String(localized: "Adapter")
        case .battery: return String(localized: "Battery")
        case nil: return "–"
        }
    }

    static func battery(_ frame: CapturedPower?) -> String {
        guard let frame, let charge = frame.batteryChargePercent.numericValue else {
            return frame?.batteryChargePercent.reason ?? ""
        }
        var parts = [String(localized: "Battery \(MetricText.percent(charge))")]
        if let watts = frame.batteryPowerWatts.numericValue {
            // The charging flag decides the label; a zero current is neither direction.
            if frame.isCharging == true {
                parts.append(String(localized: "charging \(MetricText.watts(watts))"))
            } else if watts < 0 {
                parts.append(String(localized: "discharging \(MetricText.watts(-watts))"))
            } else {
                parts.append(String(localized: "not charging"))
            }
        }
        if let minutes = frame.batteryMinutesRemaining.numericValue {
            let duration = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            parts.append(frame.isCharging == true
                ? String(localized: "full in \(duration)") : String(localized: "\(duration) left"))
        }
        return parts.joined(separator: " · ")
    }

    static func adapterAndHealth(_ frame: CapturedPower?) -> String {
        guard let frame else { return "" }
        var parts: [String] = []
        if let watts = frame.adapterRatingWatts.numericValue {
            parts.append(String(localized: "\(MetricText.watts(watts)) adapter"))
        }
        if let health = frame.batteryHealthPercent.numericValue {
            parts.append(String(localized: "health \(MetricText.percent(health)) est."))
        }
        if let cycles = frame.batteryCycleCount.numericValue {
            parts.append(String(localized: "\(Int(cycles)) cycles"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct PowerChartAccessibility: AXChartDescriptorRepresentable {
    let points: [DashboardPoint]
    let pluggedSpans: Int
    let start: Date
    let end: Date

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
            gridlinePositions: []
        ) { Date(timeIntervalSinceReferenceDate: $0).formatted(date: .omitted, time: .standard) }
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Battery charge"), range: 0...MetricText.percentScale, gridlinePositions: []
        ) { MetricText.percent($0) }
        let segments = Dictionary(grouping: points, by: \.segment)
        let series = segments.keys.sorted().map { segment in
            AXDataSeriesDescriptor(name: String(localized: "Battery charge"), isContinuous: true, dataPoints:
                (segments[segment] ?? []).map { AXDataPoint(x: $0.time.timeIntervalSinceReferenceDate, y: $0.value) }
            )
        }
        return AXChartDescriptor(
            title: String(localized: "Power"),
            summary: pluggedSpans > 0
                ? String(localized: "Battery charge over the visible range; the band marks time on external power.")
                : String(localized: "Battery charge over the visible range, on battery power."),
            xAxis: x, yAxis: y, additionalAxes: [], series: series
        )
    }
}

private struct ThermalLane: View {
    @Environment(\.laneGraphHeight) private var graphHeight
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-model.timeRange.seconds)
        let spans = model.thermalPressureSpans().filter { $0.end >= start && $0.start <= end }
        let temperatures = visiblePoints(model.hottestTemperaturePoints(), start, end)
        let reading = model.displayedFrame?.thermalPressure
        let sensors = model.displayedSensorFrame

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Thermal").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(ThermalText.celsius(sensors?.hottest?.celsius.numericValue))
                    .font(.system(size: 30, weight: .semibold))
                Text(ThermalText.hottest(sensors)).font(.caption)
                Text("Pressure " + ThermalText.level(reading)).font(.caption)
                ForEach(sensors?.fans ?? []) { fan in
                    Text("Fan \(fan.id + 1) \(ThermalText.rpm(fan.rpm.numericValue))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let reason = sensors?.source.reason ?? reading?.reason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .frame(width: Layout.headerWidth, alignment: .leading)

            if !temperatures.isEmpty {
                temperatureChart(temperatures, spans: spans, start: start, end: end)
            } else if spans.isEmpty {
                Text(reading?.reason ?? String(localized: "Collecting samples…"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Layout.bandHeight)
            } else {
                Chart {
                    ForEach(spans) { span in
                        RectangleMark(
                            xStart: .value("Start", max(span.start, start)), xEnd: .value("End", span.end),
                            yStart: .value("Bottom", 0), yEnd: .value("Top", 1)
                        )
                        .foregroundStyle(ThermalText.color(span.level))
                    }
                    CursorRule(time: model.cursorTime, range: start...end)
                    SelectionBand(selection: model.draftSelection ?? model.selection, range: start...end)
                    SelectionBand(selection: model.draftComparison ?? model.comparison, range: start...end, tint: .orange)
                    MarkerRules(markers: model.timelineMarkers, range: start...end)
                }
                .chartCursor(model)
                .chartLegend(.hidden)
                .chartXScale(domain: start...end)
                .chartYScale(domain: 0...1)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .frame(height: Layout.bandHeight)
                .accessibilityChartDescriptor(ThermalChartAccessibility(spans: spans, start: start, end: end))
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
        .alertTint(model.activeAlerts[.thermal])
    }
}

private extension ThermalLane {
    // The hottest-sensor line over full-height pressure bands (plan P12).
    func temperatureChart(
        _ points: [DashboardPoint], spans: [ThermalPressureSpan], start: Date, end: Date
    ) -> some View {
        Chart {
            ForEach(spans) { span in
                RectangleMark(
                    xStart: .value("Start", max(span.start, start)), xEnd: .value("End", span.end),
                    yStart: .value("Bottom", 0), yEnd: .value("Top", ThermalText.celsiusCeiling)
                )
                .foregroundStyle(ThermalText.color(span.level).opacity(0.3))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.time), y: .value("Hottest", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(Color.primary.opacity(0.8))
                .interpolationMethod(.linear)
            }
            CursorRule(time: model.cursorTime, range: start...end)
            SelectionBand(selection: model.draftSelection ?? model.selection, range: start...end)
            SelectionBand(selection: model.draftComparison ?? model.comparison, range: start...end, tint: .orange)
            MarkerRules(markers: model.timelineMarkers, range: start...end)
        }
        .chartCursor(model)
        .chartLegend(.hidden)
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...ThermalText.celsiusCeiling)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(ThermalText.celsius(number)).frame(width: Layout.axisLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .frame(height: graphHeight)
        .accessibilityChartDescriptor(TemperatureChartAccessibility(points: points, start: start, end: end))
    }
}

private struct TemperatureChartAccessibility: AXChartDescriptorRepresentable {
    let points: [DashboardPoint]
    let start: Date
    let end: Date

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
            gridlinePositions: []
        ) { Date(timeIntervalSinceReferenceDate: $0).formatted(date: .omitted, time: .standard) }
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Hottest sensor"), range: 0...ThermalText.celsiusCeiling, gridlinePositions: []
        ) { ThermalText.celsius($0) }
        let segments = Dictionary(grouping: points, by: \.segment)
        let series = segments.keys.sorted().map { segment in
            AXDataSeriesDescriptor(name: String(localized: "Hottest sensor"), isContinuous: true, dataPoints:
                (segments[segment] ?? []).map { AXDataPoint(x: $0.time.timeIntervalSinceReferenceDate, y: $0.value) }
            )
        }
        return AXChartDescriptor(
            title: String(localized: "Thermal"),
            summary: String(localized: "Hottest SMC temperature over the visible range; a change of sensor starts a new line. Pressure alone does not prove throttling."),
            xAxis: x, yAxis: y, additionalAxes: [], series: series
        )
    }
}

/// Shared with the HUD.
enum ThermalText {
    /// Matches the sensor plausibility ceiling, so no shown reading is clipped.
    static let celsiusCeiling = 130.0

    static func celsius(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0))) + " °C"
    }

    static func rpm(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0))) + " rpm"
    }

    static func hottest(_ sensors: CapturedSensors?) -> String {
        guard let hottest = sensors?.hottest else { return String(localized: "Hottest sensor") }
        let region = hottest.region.map { " · " + $0 } ?? ""
        return String(localized: "Hottest: \(hottest.key)\(region)")
    }

    static func level(_ reading: DashboardReading?) -> String {
        guard let reading else { return "–" }
        guard let level = CapturedThermalPressure(reading: reading) else {
            return reading.availability == .restricted
                ? String(localized: "Restricted") : String(localized: "Unavailable")
        }
        return name(level)
    }

    static func name(_ level: CapturedThermalPressure) -> String {
        switch level {
        case .nominal: return String(localized: "Nominal")
        case .moderate: return String(localized: "Moderate")
        case .heavy: return String(localized: "Heavy")
        case .trapping: return String(localized: "Trapping")
        case .sleeping: return String(localized: "Sleeping")
        }
    }

    // Red is reserved for states where the system is throttling hard.
    static func color(_ level: CapturedThermalPressure) -> Color {
        switch level {
        case .nominal: return .gray.opacity(0.35)
        case .moderate: return .yellow
        case .heavy: return .orange
        case .trapping, .sleeping: return .red
        }
    }
}

private struct ThermalChartAccessibility: AXChartDescriptorRepresentable {
    let spans: [ThermalPressureSpan]
    let start: Date
    let end: Date

    func makeChartDescriptor() -> AXChartDescriptor {
        let levels = CapturedThermalPressure.allCases
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
            gridlinePositions: []
        ) { Date(timeIntervalSinceReferenceDate: $0).formatted(date: .omitted, time: .standard) }
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Thermal pressure"),
            range: 0...Double(levels.count - 1), gridlinePositions: []
        ) { value in
            CapturedThermalPressure(rawValue: Int(value.rounded())).map(ThermalText.name) ?? "–"
        }
        let points = spans.map {
            AXDataPoint(x: $0.end.timeIntervalSinceReferenceDate, y: Double($0.level.rawValue))
        }
        return AXChartDescriptor(
            title: String(localized: "Thermal pressure"),
            summary: String(localized: "System thermal pressure level over the visible range; pressure alone does not prove throttling."),
            xAxis: x, yAxis: y, additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: String(localized: "Thermal pressure"), isContinuous: false, dataPoints: points)]
        )
    }
}

private struct NetworkLane: View {
    @Environment(\.laneGraphHeight) private var graphHeight
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-model.timeRange.seconds)
        let received = visiblePoints(model.points(for: .networkReceived), start, end)
        let sent = visiblePoints(model.points(for: .networkSent), start, end)
        let receiveReading = model.reading(for: .networkReceived)
        let sendReading = model.reading(for: .networkSent)

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Network").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("↓ " + MetricText.rate(receiveReading?.numericValue))
                    .font(.system(size: 24, weight: .semibold))
                Text("↑ " + MetricText.rate(sendReading?.numericValue))
                    .font(.system(size: 20, weight: .semibold))
                interfacePicker
                if let inventory = model.networkFrames.last {
                    if inventory.enumerationTruncated {
                        Text("Interface inventory reached capacity.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !inventory.issues.isEmpty {
                        Text("\(inventory.issues.count) interface reads unavailable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(receiveReading?.reason ?? "IFMIB · 64-bit byte counters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: Layout.headerWidth, alignment: .leading)

            if received.isEmpty && sent.isEmpty {
                Text(receiveReading?.reason ?? String(localized: "Collecting samples…"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: graphHeight)
            } else {
                TransferChart(
                    title: String(localized: "Network"), aboveLabel: String(localized: "Received"),
                    belowLabel: String(localized: "Sent"), above: received, below: sent, start: start, end: end,
                    model: model
                )
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
    }

    private var interfacePicker: some View {
        let interfaces = model.networkFrames.last?.interfaces ?? []
        return Picker("Network interface", selection: $model.networkScope) {
            Text("Primary · " + (model.networkFrames.last?.primaryInterface?.name ?? "unavailable"))
                .tag(NetworkScope.primary)
            ForEach(interfaces) { interface in
                Text(interface.id.name).tag(NetworkScope.interface(interface.id))
            }
            if case .interface(let selected) = model.networkScope,
               !interfaces.contains(where: { $0.id == selected }) {
                Text(selected.name + " · unavailable").tag(NetworkScope.interface(selected))
            }
        }
        .labelsHidden()
        .help("Primary prefers IPv4, then IPv6. Interfaces are scoped separately.")
    }

}

private struct DiskLane: View {
    @Environment(\.laneGraphHeight) private var graphHeight
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-model.timeRange.seconds)
        let read = visiblePoints(model.points(for: .diskRead), start, end)
        let written = visiblePoints(model.points(for: .diskWritten), start, end)
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Disk").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("↓ " + MetricText.rate(model.reading(for: .diskRead)?.numericValue))
                    .font(.system(size: 24, weight: .semibold))
                Text("↑ " + MetricText.rate(model.reading(for: .diskWritten)?.numericValue))
                    .font(.system(size: 20, weight: .semibold))
                devicePicker
                Text(model.storageSelectionMessage).font(.caption).foregroundStyle(.secondary)
                ContributorLine(model: model, subsystem: .disk)
                if let app = model.scopedApp {
                    Text("\(app): \(MetricText.rate(model.scopedSeries()?.disk.last?.value)) read + write")
                        .font(.caption.weight(.medium)).foregroundStyle(.blue)
                }
                if let inventory = model.diskFrames.last,
                   inventory.enumerationTruncated || !inventory.issues.isEmpty {
                    Text("Storage inventory is incomplete.").font(.caption).foregroundStyle(.secondary)
                }
                VolumeBars(list: model.volumes)
            }
            .monospacedDigit()
            .frame(width: Layout.headerWidth, alignment: .leading)
            if read.isEmpty && written.isEmpty {
                Text(model.storageSelectionMessage).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: graphHeight)
            } else {
                TransferChart(
                    title: String(localized: "Disk"), aboveLabel: String(localized: "Read"),
                    belowLabel: String(localized: "Written"), above: read, below: written, start: start, end: end,
                    model: model
                )
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
        .alertTint(model.activeAlerts[.disk])
    }

    private var devicePicker: some View {
        let devices = model.diskFrames.last?.devices ?? []
        return Picker("Storage device", selection: $model.storageScope) {
            Text("Automatic · one observed device").tag(StorageScope.automatic)
            ForEach(devices) { device in
                Text(device.name).tag(StorageScope.device(device.id))
            }
            if case .device(let selected) = model.storageScope,
               !devices.contains(where: { $0.id == selected }) {
                Text("Selected device · unavailable").tag(StorageScope.device(selected))
            }
        }
        .labelsHidden()
        .help("Automatic selection requires one observed device and complete inventory. Drivers are not summed.")
    }
}

private struct TransferChart: View {
    @Environment(\.laneGraphHeight) private var graphHeight
    let title: String
    let aboveLabel: String
    let belowLabel: String
    let above: [DashboardPoint]
    let below: [DashboardPoint]
    let start: Date
    let end: Date
    let model: DashboardModel

    var body: some View {
        let maximum = rateCeiling((above + below).map(\.value).max() ?? 1)
        Chart {
            ForEach(above) { point in
                LineMark(
                    x: .value("Time", point.time), y: .value(aboveLabel, point.value),
                    series: .value("Segment", "above-\(point.segment)")
                )
                .foregroundStyle(Color.blue)
            }
            ForEach(below) { point in
                LineMark(
                    x: .value("Time", point.time), y: .value(belowLabel, -point.value),
                    series: .value("Segment", "below-\(point.segment)")
                )
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            CursorRule(time: model.cursorTime, range: start...end)
            SelectionBand(selection: model.draftSelection ?? model.selection, range: start...end)
            SelectionBand(selection: model.draftComparison ?? model.comparison, range: start...end, tint: .orange)
            MarkerRules(markers: model.timelineMarkers, range: start...end)
        }
        .chartCursor(model)
        .chartLegend(.hidden)
        .chartXScale(domain: start...end)
        .chartYScale(domain: -maximum...maximum)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [-maximum, 0, maximum]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(MetricText.rate(abs(number)))
                            .frame(width: Layout.axisLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .frame(height: graphHeight)
        .accessibilityChartDescriptor(TransferChartAccessibility(
            title: title, aboveLabel: aboveLabel, belowLabel: belowLabel,
            above: above, below: below, start: start, end: end, maximum: maximum
        ))
    }

    private func rateCeiling(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        for step in [1.0, 2, 5, 10] where value <= step * magnitude {
            return step * magnitude
        }
        return value
    }
}

private struct TransferChartAccessibility: AXChartDescriptorRepresentable {
    let title: String
    let aboveLabel: String
    let belowLabel: String
    let above: [DashboardPoint]
    let below: [DashboardPoint]
    let start: Date
    let end: Date
    let maximum: Double

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
            gridlinePositions: []
        ) { Date(timeIntervalSinceReferenceDate: $0).formatted(date: .omitted, time: .standard) }
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Bytes per second; \(aboveLabel) above, \(belowLabel) below"),
            range: -maximum...maximum, gridlinePositions: [0]
        ) { MetricText.rate(abs($0)) }
        var series: [AXDataSeriesDescriptor] = []
        for (name, points, sign) in [(aboveLabel, above, 1.0), (belowLabel, below, -1.0)] {
            let segments = Dictionary(grouping: points, by: \.segment)
            for segment in segments.keys.sorted() {
                series.append(AXDataSeriesDescriptor(
                    name: name, isContinuous: true,
                    dataPoints: (segments[segment] ?? []).map {
                        AXDataPoint(x: $0.time.timeIntervalSinceReferenceDate, y: $0.value * sign)
                    }
                ))
            }
        }
        return AXChartDescriptor(
            title: title,
            summary: String(localized: "Selected source; source changes and missing samples split the lines."),
            xAxis: x, yAxis: y, additionalAxes: [], series: series
        )
    }
}

private struct ProcessPane: View {
    @Bindable var model: DashboardModel
    var filterFocused: FocusState<Bool>.Binding
    @State private var pendingAction: ProcessActionRequest?

    var body: some View {
        let rows = model.visibleProcessRows
        let heat = HeatScale(rows)
        DisclosureGroup("Processes") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Filter: name, cpu:>10, mem:>1GB, user:me, port:443, file:~/Downloads, #apps, #new, #listening, #preventing-sleep", text: $model.processFilter)
                        .textFieldStyle(.roundedBorder)
                        .focused(filterFocused)
                    Picker("Group", selection: $model.processGrouping) {
                        Text("By app").tag(ProcessGrouping.app)
                        Text("Flat").tag(ProcessGrouping.flat)
                    }
                    .frame(width: 150)
                    .help("By app folds helpers under their responsible app or app bundle")
                    Picker("Sort", selection: $model.processSort) {
                        Text("CPU").tag(ProcessSort.cpu)
                        Text("Memory").tag(ProcessSort.memory)
                        Text("Disk read").tag(ProcessSort.diskRead)
                        Text("Disk write").tag(ProcessSort.diskWrite)
                        Text("Network").tag(ProcessSort.network)
                        Text("GPU time").tag(ProcessSort.gpu)
                        Text("CPU power").tag(ProcessSort.power)
                        Text("Name").tag(ProcessSort.name)
                    }
                    .frame(width: 180)
                }

                SavedFilterChips(model: model)

                if model.ranksBySelection {
                    Text("Apps ranked by CPU inside the selected range").font(.caption).foregroundStyle(.secondary)
                }

                // The same mistake typed twice is two issues; identity is the position.
                ForEach(Array(model.processFilterIssues.enumerated()), id: \.offset) { _, issue in
                    Text(issue).font(.caption).foregroundStyle(.orange)
                }

                if let snapshot = model.processSnapshot {
                    if let reason = snapshot.enumeration.reason {
                        Text(reason).foregroundStyle(.secondary)
                    }
                    Text("\(snapshot.processes.count) identified · \(snapshot.restrictedUsageCount) restricted · \(snapshot.issues.count) identity failures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if snapshot.enumerationTruncated {
                        Text("Enumeration reached capacity; additional processes may exist.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Table(rows, children: \.children, selection: $model.selectedProcessRow) {
                    TableColumn("Process") { row in
                        // New processes tint briefly (plan: change highlighting).
                        let isNew = row.process.map { model.isNewProcess($0.id) } ?? false
                        Text(row.children == nil ? row.name : "\(row.name) (\(row.memberCount))")
                            .padding(.horizontal, 4)
                            .background(isNew ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 3))
                            .help(isNew ? String(localized: "Started within the last 10 seconds") : ProcessText.grouping(row.groupingMethod))
                            .contextMenu {
                                Button("Show \(row.appName) in lanes") { model.scopedApp = row.appName }
                                if let process = row.process {
                                    ProcessActionMenu(model: model, process: process, pendingAction: $pendingAction)
                                }
                            }
                    }
                    TableColumn("PID") { Text($0.process?.id.pid.formatted(.number.grouping(.never)) ?? "") }
                        .width(60)
                    TableColumn("UID") { Text($0.process?.uid.formatted(.number.grouping(.never)) ?? "") }
                        .width(65)
                    TableColumn(ProcessText.cpuColumn(model.processCPUScale)) { (row: ProcessRow) in
                        ProcessMetricCell(reading: row.cpuPercentOfMachine, format: .percent,
                                          heat: heat.cpu(row), hue: .blue, scale: model.processCPUFactor)
                    }
                    TableColumn("Footprint") {
                        ProcessMetricCell(reading: $0.memoryFootprintBytes, format: .bytes,
                                          heat: heat.memory($0), hue: .teal)
                    }
                    TableColumn("Disk read/s") {
                        ProcessMetricCell(reading: $0.diskReadBytesPerSecond, format: .rate,
                                          heat: heat.read($0), hue: .blue)
                    }
                    TableColumn("Disk write/s") {
                        ProcessMetricCell(reading: $0.diskWriteBytesPerSecond, format: .rate,
                                          heat: heat.write($0), hue: .orange)
                    }
                    TableColumn("Wakeups/s") { ProcessMetricCell(reading: $0.wakeupsPerSecond, format: .wakeups) }
                    TableColumn("Network in/out") { row in
                        Text(NetworkText.processRates(row))
                            .monospacedDigit()
                            .help(row.networkReceivedBytesPerSecond.method ?? row.networkReceivedBytesPerSecond.reason
                                  ?? String(localized: "TCP and UDP bytes per second; no open socket reads as zero"))
                    }
                    // A table takes ten columns per block; the group adds the rest, typed
                    // because a group cannot infer its row.
                    Group {
                        TableColumn("GPU ms/s") { (row: ProcessRow) in
                            ProcessMetricCell(
                                reading: row.gpuMillisecondsPerSecond, format: .gpuTime,
                                note: String(localized: "GPU time per second, not the GPU lane's busy percentage; overlapping work can exceed 1000")
                            )
                        }
                        TableColumn("CPU power") { (row: ProcessRow) in
                            ProcessMetricCell(
                                reading: row.cpuPowerWatts, format: .processWatts,
                                note: String(localized: "Estimated by the kernel's CPU energy model; GPU work is not included")
                            )
                        }
                    }
                }
                .frame(height: 260)
                .textSelection(.enabled)

                if let message = model.actionMessage {
                    Text(message).font(.caption)
                }

                // Ghost rows: the culprit has often already quit (plan: exited rows stay 30 s).
                let exited = model.exitedProcesses
                if !exited.isEmpty {
                    let names = exited.map { "\($0.name) (PID \($0.identity.pid), \($0.appName))" }.joined(separator: " · ")
                    Text("Exited in the last 30 s: \(names)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Exit status is not available without the helper")
                }

                Text("\(ProcessText.cpuScaleNote(model.processCPUScale)) App totals sum their members; footprint sums can count shared memory twice. Process sampling: 2 s; short-lived processes can be missed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        // Destructive actions confirm with their consequences; the identity is re-checked on send.
        .modifier(ProcessActionConfirmation(model: model, pendingAction: $pendingAction))
    }
}

/// Saved filters as chips (plan P22): a click applies one, the menu removes it.
private struct SavedFilterChips: View {
    let model: DashboardModel

    var body: some View {
        HStack(spacing: 6) {
            Button("Save filter", systemImage: "bookmark") { model.saveProcessFilter() }
                .labelStyle(.iconOnly)
                .disabled(!model.canSaveProcessFilter)
                .help("Keep this filter as a chip")
            ForEach(model.savedFilters, id: \.self) { filter in
                let active = model.processFilter.trimmingCharacters(in: .whitespacesAndNewlines) == filter
                Button(filter) { model.processFilter = filter }
                    .lineLimit(1)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(active ? .accentColor : nil)
                    .help("Click to filter; right-click to remove")
                    .contextMenu { Button("Remove", role: .destructive) { model.removeSavedFilter(filter) } }
            }
        }
    }
}

/// Quit and Force Quit confirm with their consequences stated before acting.
private struct ProcessActionConfirmation: ViewModifier {
    let model: DashboardModel
    @Binding var pendingAction: ProcessActionRequest?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            pendingAction.map { "\($0.action.verb) “\($0.name)” (PID \($0.target.pid))?" } ?? "",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible, presenting: pendingAction
        ) { request in
            // A refused action offers only Cancel; its reason is the message.
            if request.refusal == nil {
                Button(ActionText.button(request.action), role: request.action == .resume ? nil : .destructive) {
                    model.perform(request)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(request.refusal ?? request.consequences.joined(separator: "\n"))
        }
    }
}

/// A call-stack sample: progress while the tool runs, then the report to read or save.
private struct SampleReportView: View {
    let model: DashboardModel
    @State private var exportFile: ExportFile?
    @State private var exportName = "Coreography sample"
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.sampleState {
            case .idle:
                EmptyView()
            case .running(let name, let seconds):
                ProgressView("Sampling \(name) for \(seconds) seconds…")
            case .failed(let name, let reason):
                Text("\(name) could not be sampled").font(.headline)
                Text(reason).foregroundStyle(.secondary)
            case .finished(let report):
                Text("\(report.name), \(report.seconds) s at \(report.takenAt.formatted(date: .omitted, time: .standard))")
                    .font(.headline)
                ScrollView {
                    Text(report.text).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Save…") {
                    exportName = "Sample of \(report.name)"
                    exportFile = ExportFile(data: Data(report.text.utf8))
                }
                if let exportError { Text("Not saved: \(exportError)").font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Spacer()
                Button("Close") { model.dismissSample() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
        .fileExporter(
            isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
            document: exportFile, contentType: .plainText, defaultFilename: exportName
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription } else { exportError = nil }
        }
    }
}

/// Whether a process menu lists Quit and Force Quit, which the inspector shows as buttons.
private enum QuitEntries {
    case yes, no
}

/// Every action for one process (plan: Quit, Force Quit, Suspend and Resume,
/// Send Signal, Renice, Reveal in Finder, Copy). Each confirms first, except Resume, which only undoes a suspend.
private struct ProcessActionMenu: View {
    let model: DashboardModel
    let process: ObservedProcess
    @Binding var pendingAction: ProcessActionRequest?
    var includesQuit: QuitEntries = .yes

    var body: some View {
        if includesQuit == .yes {
            Button("Quit…") { ask(.quit) }
            Button("Force Quit…") { ask(.forceQuit) }
            Divider()
        }
        Button("Suspend…") { ask(.suspend) }
        Button("Resume") { model.perform(model.actionRequest(for: process, action: .resume)) }
        Menu("Send Signal") {
            Button("Hang Up (SIGHUP)…") { ask(.hangUp) }
            Button("Interrupt (SIGINT)…") { ask(.interrupt) }
        }
        Button("Lower Priority…") { ask(.lowerPriority) }
        Button("Sample for 3 Seconds") { Task { await model.sampleProcess(process) } }
            .help("Records its call stacks with the system sample tool; the process pauses briefly while it is read")
        Divider()
        if let path = process.executablePath {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        }
        Button("Copy as Text") { copy(model.copyText(for: process)) }
        Button("Copy as JSON") { copy(model.copyJSON(for: process)) }
    }

    private func ask(_ action: ProcessAction) {
        pendingAction = model.actionRequest(for: process, action: action)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private enum ActionText {
    static func button(_ action: ProcessAction) -> String {
        switch action {
        case .quit: String(localized: "Quit")
        case .forceQuit: String(localized: "Force Quit")
        case .suspend: String(localized: "Suspend")
        case .resume: String(localized: "Resume")
        case .hangUp: String(localized: "Send Hang Up")
        case .interrupt: String(localized: "Interrupt")
        case .lowerPriority: String(localized: "Lower Priority")
        }
    }
}

/// One inspector whose content follows the selection (plan: the inspector).
/// A process shows identity, parent chain, signature, arguments, sockets and
/// actions; nothing selected shows the Mac and Coreography's own cost.
private struct InspectorView: View {
    let model: DashboardModel
    @State private var pendingAction: ProcessActionRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let inspection = model.processInspection {
                    details(of: inspection)
                } else if model.selectedProcessRow != nil {
                    Text("Select a single process to inspect it; it may also have exited.")
                        .foregroundStyle(.secondary)
                } else {
                    summary(model.systemFacts())
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(ProcessActionConfirmation(model: model, pendingAction: $pendingAction))
    }

    @ViewBuilder
    private func details(of inspection: ProcessInspection) -> some View {
        let process = inspection.process
        VStack(alignment: .leading, spacing: 4) {
            Text(process.name).font(.title3.weight(.semibold))
            Text("\(inspection.appName) · PID \(process.id.pid.formatted(.number.grouping(.never))) · UID \(process.uid.formatted(.number.grouping(.never)))")
                .font(.caption).foregroundStyle(.secondary)
            Text("Started \(Date(timeIntervalSince1970: TimeInterval(process.id.startSeconds)).formatted(date: .abbreviated, time: .standard))")
                .font(.caption).foregroundStyle(.secondary)
            if let path = process.executablePath {
                Text(path).font(.caption.monospaced()).textSelection(.enabled)
            }
        }

        if let explanation = inspection.explanation {
            InspectorSection("About") {
                Text(explanation.summary)
                Text(explanation.quittingNote).foregroundStyle(.secondary)
                if let maintenance = inspection.maintenance {
                    Text(maintenance.text)
                    Text("Status read \(maintenance.readAt.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(.secondary)
                }
            }
        }

        InspectorSection("Now") {
            Text(ProcessText.cpu(process.cpuPercentOfMachine.numericValue, model.processCPUScale, factor: model.processCPUFactor))
            Text("Footprint \(MetricText.bytes(process.memoryFootprintBytes.numericValue))")
            Text("Disk \(MetricText.bytes(process.diskReadBytesPerSecond.numericValue))/s read, \(MetricText.bytes(process.diskWriteBytesPerSecond.numericValue))/s written")
            Text(WakeupText.rate(process.wakeupsPerSecond.numericValue))
            let network = model.networkRates(for: process)
            Text("Network \(NetworkText.rates(network.received, network.sent))")
            Text("GPU \(ProcessText.gpuTime(process.gpuMillisecondsPerSecond.numericValue)) ms/s · CPU power \(ProcessText.power(process.cpuPowerWatts.numericValue))")
            if let threads = inspection.detail?.threads {
                Text("\(threads) threads")
            } else if let problem = inspection.detail?.threadsProblem {
                Text(problem).foregroundStyle(.secondary)
            }
        }

        InspectorSection("Since selected") {
            ProcessHistoryCharts(points: model.selectedProcessHistory)
        }

        InspectorSection("Identity") {
            Text(InspectorText.signing(inspection.detail))
            if let label = inspection.launchdLabel { Text("launchd job \(label)") }
            Text(inspection.parentChain.isEmpty ? String(localized: "No parent observed")
                 : String(localized: "Parents: ") + inspection.parentChain.map { "\($0.name ?? "?") (\($0.pid))" }.joined(separator: " ← "))
        }

        InspectorSection("Arguments") {
            if let detail = inspection.detail {
                if let arguments = detail.arguments {
                    Text(arguments.joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled)
                } else {
                    Text(detail.argumentsProblem ?? "").foregroundStyle(.secondary)
                }
            } else {
                Text("Reading…").foregroundStyle(.secondary)
            }
        }

        InspectorSection("Open files") {
            if let files = model.inspectedFiles {
                if files.isEmpty { Text("None open").foregroundStyle(.secondary) }
                // Long lists stay readable; the filter's file: term searches them all.
                ForEach(Array(files.prefix(InspectorText.fileLimit).enumerated()), id: \.offset) { _, path in
                    Text(path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                if files.count > InspectorText.fileLimit {
                    Text("and \(files.count - InspectorText.fileLimit) more").font(.caption).foregroundStyle(.secondary)
                }
                if model.inspectedFilesCut {
                    Text("It holds more open files than one read keeps; this list is not all of them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(inspection.detail == nil ? "Reading…" : "Could not be read").foregroundStyle(.secondary)
            }
        }

        if !model.selectedAssertions.isEmpty {
            // Assertions are only ever read now, so a held display says so.
            InspectorSection(model.displayMode == .live ? "Sleep assertions" : "Sleep assertions now") {
                // One process can hold two alike assertions; position keeps the rows apart.
                ForEach(Array(model.selectedAssertions.enumerated()), id: \.offset) { _, assertion in
                    Text(PowerText.assertion(assertion))
                }
            }
        }

        InspectorSection("Sockets") {
            if let sockets = inspection.sockets {
                if sockets.isEmpty { Text("None open").foregroundStyle(.secondary) }
                ForEach(sockets) { socket in
                    Text("\(ConnectionText.transport(socket.transport)) \(ConnectionText.endpoint(socket.local)) \(socket.remote.map { "→ " + ConnectionText.endpoint($0) } ?? "") · \(ConnectionText.state(socket))")
                        .font(.caption.monospaced())
                }
            } else {
                Text(inspection.detail == nil ? "Reading…" : "Could not be read").foregroundStyle(.secondary)
            }
        }

        HStack {
            Button("Quit…") { pendingAction = model.actionRequest(for: process, action: .quit) }
            Button("Force Quit…") { pendingAction = model.actionRequest(for: process, action: .forceQuit) }
            Menu("More") { ProcessActionMenu(model: model, process: process, pendingAction: $pendingAction, includesQuit: .no) }
                .fixedSize()
        }
    }

    @ViewBuilder
    private func summary(_ facts: CapturedSystemFacts) -> some View {
        Text("This Mac").font(.title3.weight(.semibold))
        InspectorSection("System") {
            if let chip = facts.chip { Text(chip) }
            if let identifier = facts.model { Text(identifier) }
            if let build = facts.osBuild { Text("macOS build \(build)") }
            if let boot = facts.bootTime {
                Text("Up since \(boot.formatted(date: .abbreviated, time: .shortened))")
            }
            if let loads = facts.loadAverages {
                Text("Load \(loads.map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: " · "))")
            }
        }
        InspectorSection("Coreography") {
            SelfCostLine(model: model)
        }
        Text("Select a process to inspect it.").font(.caption).foregroundStyle(.secondary)
    }
}

private struct InspectorSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content.font(.callout)
        }
    }
}

private enum InspectorText {
    static let fileLimit = 40

    static func signing(_ detail: CapturedProcessDetail?) -> String {
        guard let detail else { return String(localized: "Signature: reading…") }
        guard let signing = detail.signing else { return String(localized: "Signature: no program path to check") }
        let identifier = signing.identifier.map { " (\($0))" } ?? ""
        switch signing.signer {
        case .apple: return String(localized: "Signed by Apple\(identifier)")
        case .developer(let team): return String(localized: "Signed by team \(team ?? "unknown")\(identifier)")
        case .unsigned: return String(localized: "Unsigned")
        case .unknown: return String(localized: "Signature could not be read")
        }
    }
}

/// Heat for process cells: each value against its column's top visible row.
private struct HeatScale {
    private let maxima: [Double]

    init(_ rows: [ProcessRow]) {
        func top(_ reading: (ProcessRow) -> DashboardReading) -> Double {
            rows.compactMap { reading($0).numericValue }.max() ?? 0
        }
        maxima = [
            top(\.cpuPercentOfMachine), top(\.memoryFootprintBytes),
            top(\.diskReadBytesPerSecond), top(\.diskWriteBytesPerSecond)
        ]
    }

    func cpu(_ row: ProcessRow) -> Double { share(row.cpuPercentOfMachine, maxima[0]) }
    func memory(_ row: ProcessRow) -> Double { share(row.memoryFootprintBytes, maxima[1]) }
    func read(_ row: ProcessRow) -> Double { share(row.diskReadBytesPerSecond, maxima[2]) }
    func write(_ row: ProcessRow) -> Double { share(row.diskWriteBytesPerSecond, maxima[3]) }

    private func share(_ reading: DashboardReading, _ top: Double) -> Double {
        guard let value = reading.numericValue, top > 0 else { return 0 }
        return value / top
    }
}

private enum ProcessText {
    static func cpuColumn(_ scale: ProcessCPUScale) -> String {
        switch scale {
        case .machine: String(localized: "CPU, machine")
        case .oneCore: String(localized: "CPU, one core")
        }
    }

    static func cpuScaleNote(_ scale: ProcessCPUScale) -> String {
        switch scale {
        case .machine: String(localized: "CPU uses the whole-machine scale.")
        case .oneCore: String(localized: "CPU counts one core as 100 %, so busy processes can exceed 100 %.")
        }
    }

    static func cpu(_ percentOfMachine: Double?, _ scale: ProcessCPUScale, factor: Double) -> String {
        let value = MetricText.percent(percentOfMachine.map { $0 * factor })
        return switch scale {
        case .machine: String(localized: "CPU \(value) of the machine")
        case .oneCore: String(localized: "CPU \(value) of one core")
        }
    }

    /// A process often draws tens of milliwatts, so two decimals.
    static func power(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "–" }
        return watts.formatted(.number.precision(.fractionLength(2))) + " W"
    }

    static func gpuTime(_ milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite else { return "–" }
        return milliseconds.formatted(.number.precision(.fractionLength(milliseconds < 10 ? 1 : 0)))
    }

    static func grouping(_ method: ProcessGroupingMethod?) -> String {
        switch method {
        case .responsibleProcess: return String(localized: "Grouped under the process macOS holds responsible")
        case .appBundle: return String(localized: "Grouped by its app bundle")
        case .standalone: return String(localized: "No owning app found")
        case nil: return ""
        }
    }
}

/// Each app's internet sockets (plan: the Connections tab). Sockets are
/// read only while this pane shows or a filter asks for `#listening`.
private struct ConnectionsPane: View {
    @Bindable var model: DashboardModel

    var body: some View {
        let rows = model.appConnections.flatMap { app in
            (app.listening + app.connected).map { ConnectionRow(app: app.app, connection: $0) }
        }
        DisclosureGroup("Connections") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Filter: app, process, address or port", text: $model.connectionFilter)
                    .textFieldStyle(.roundedBorder)
                Text(ConnectionText.coverage(model.connectionSnapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Table(rows) {
                    TableColumn("App") { Text($0.app) }
                    TableColumn("Process") { Text("\($0.connection.processName) (\($0.connection.process.pid.formatted(.number.grouping(.never))))") }
                    TableColumn("Protocol") { Text(ConnectionText.transport($0.connection.transport)) }
                    TableColumn("State") { Text(ConnectionText.state($0.connection)) }
                    TableColumn("Local") { Text(ConnectionText.endpoint($0.connection.local)) }
                    TableColumn("Remote") { Text($0.connection.remote.map(ConnectionText.endpoint) ?? "–") }
                }
                .frame(height: 260)
            }
        }
    }
}

/// Launch agents and daemons joined to what they cost now (plan: the
/// Startup tab). Read-only; Apple's items hidden by default.
private struct StartupPane: View {
    @Bindable var model: DashboardModel

    var body: some View {
        DisclosureGroup("Startup") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Show", selection: $model.startupVisibility) {
                        Text("Third-party").tag(StartupVisibility.thirdParty)
                        Text("All, including Apple").tag(StartupVisibility.all)
                    }
                    .frame(width: 260)
                    Spacer()
                    Button("Refresh") { model.refreshStartupItems() }
                }
                ForEach(StartupText.coverage(model.startupInventory), id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }

                Table(model.startupRows) {
                    TableColumn("Item") { Text($0.item.label).help($0.item.program ?? $0.item.plistPath) }
                    TableColumn("Kind") { Text(StartupText.kind($0.item.kind)) }
                    TableColumn("State") { Text(StartupText.state($0.item)) }
                    TableColumn("Running") { Text($0.processCount == 0 ? "–" : "\($0.processCount)") }
                    TableColumn(ProcessText.cpuColumn(model.processCPUScale)) { (row: StartupRow) in
                        Text(MetricText.percent(row.cpuPercentOfMachine.map { $0 * model.processCPUFactor }))
                    }
                    TableColumn("Footprint") { Text(MetricText.bytes($0.memoryFootprintBytes)) }
                    TableColumn("App CPU, last hour") { Text($0.appCPUSecondsLastHour.map(RangeText.cpuSeconds) ?? "–") }
                }
                .frame(height: 260)
            }
        }
        .monospacedDigit()
    }
}

private enum StartupText {
    static func kind(_ kind: CapturedStartupKind) -> String {
        switch kind {
        case .userAgent: return String(localized: "Your agent")
        case .agent: return String(localized: "Agent, all users")
        case .daemon: return String(localized: "Daemon")
        case .systemAgent: return String(localized: "Apple agent")
        case .systemDaemon: return String(localized: "Apple daemon")
        }
    }

    static func state(_ item: CapturedStartupItem) -> String {
        let trigger = item.keepsAlive ? String(localized: "kept running")
            : item.runsAtLoad ? String(localized: "at load") : String(localized: "on demand")
        switch item.state {
        case .enabled: return String(localized: "Enabled, \(trigger)")
        case .disabled: return String(localized: "Disabled")
        case .unconfirmed: return String(localized: "Unconfirmed, \(trigger)")
        }
    }

    static func coverage(_ inventory: CapturedStartupInventory?) -> [String] {
        guard let inventory else { return [String(localized: "Reading startup items…")] }
        var notes = [CapturedStartupInventory.loginItemsUnavailable]
        if let problem = inventory.stateProblem { notes.append(String(localized: "Enabled state unconfirmed: \(problem)")) }
        if inventory.unreadableDefinitions > 0 {
            notes.append(String(localized: "\(inventory.unreadableDefinitions) definitions could not be read"))
        }
        return notes
    }
}

/// Recorded sessions with their reports (plan P19): minimum, mean, 95th
/// percentile from raw readings, maximum, and the top apps.
private struct SessionsPane: View {
    @Bindable var model: DashboardModel
    @State private var exportFile: ExportFile?
    @State private var exportType: UTType = .json
    @State private var exportError: String?

    var body: some View {
        DisclosureGroup("Sessions") {
            VStack(alignment: .leading, spacing: 12) {
                if let comparison = model.sessionComparison {
                    SessionComparisonView(comparison: comparison)
                }
                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(.red)
                }
                if let name = model.recordingName, let start = model.recordingStart {
                    Text("Recording \(name) since \(start.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(.red)
                }
                if model.sessions.isEmpty {
                    Text("No sessions yet. Command-R starts one.").foregroundStyle(.secondary)
                }
                ForEach(model.sessions) { session in
                    DisclosureGroup {
                        Table(session.summaries) {
                            TableColumn("Metric") { Text($0.metric) }
                            TableColumn("Min") { Text(SessionText.value($0.minimum, $0.unit)) }
                            TableColumn("Mean") { Text(SessionText.value($0.mean, $0.unit)) }
                            TableColumn("95th") { Text(SessionText.value($0.percentile95, $0.unit)) }
                            TableColumn("Max") { Text(SessionText.value($0.maximum, $0.unit)) }
                            TableColumn("Samples") { Text("\($0.samples)") }
                        }
                        .frame(height: 220)
                        Text(RangeText.apps(String(localized: "Top CPU"), session.topApps) { RangeText.cpuSeconds($0.cpuSeconds) })
                            .font(.callout)
                        HStack {
                            SessionNameField(model: model, session: session)
                            Button(model.comparedSessions.contains(session.id) ? "Comparing" : "Compare") {
                                model.toggleComparison(session.id)
                            }
                            Picker("App names", selection: $model.exportNaming) {
                                Text("Redacted").tag(ExportNaming.redacted)
                                Text("Included").tag(ExportNaming.named)
                            }
                            .frame(width: 200)
                            Button("Export JSON…") { export(session, as: .json) }
                            Button("Export CSV…") { export(session, as: .commaSeparatedText) }
                            Button("Delete", role: .destructive) { Task { await model.deleteSession(session.id) } }
                        }
                    } label: {
                        Text(SessionText.title(session))
                    }
                }
            }
        }
        .monospacedDigit()
        .task { await model.refreshSessions() }
        .fileExporter(
            isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
            document: exportFile, contentType: exportType, defaultFilename: "Coreography session"
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
    }

    /// Build the file from the saved session; failures are shown, not swallowed.
    private func export(_ session: RecordedSession, as type: UTType) {
        do {
            let data = type == .json
                ? try SessionExport.json(session, naming: model.exportNaming)
                : Data(SessionExport.csv(session).utf8)
            exportError = nil
            exportType = type
            exportFile = ExportFile(data: data)
        } catch {
            exportError = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }
}

/// Renames on Return; a blank name is ignored.
private struct SessionNameField: View {
    let model: DashboardModel
    let session: RecordedSession
    @State private var name = ""

    var body: some View {
        TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
            .onAppear { name = session.name }
            .onSubmit { Task { await model.renameSession(session.id, to: name) } }
    }
}

/// Two sessions overlaid per shared metric, aligned at their starts (plan P19).
private struct SessionComparisonView: View {
    let comparison: SessionComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comparison").font(.headline)
            ForEach(comparison.metrics, id: \.metric) { metric in
                Text("\(metric.metric) (\(metric.unit.rawValue))").font(.caption.weight(.medium))
                Chart {
                    ForEach(metric.series) { series in
                        ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Seconds from start", point.offset),
                                y: .value(metric.metric, point.value),
                                series: .value("Session", series.label)
                            )
                            .foregroundStyle(by: .value("Session", series.label))
                        }
                    }
                }
                .frame(height: 110)
            }
        }
    }
}

private enum SessionText {
    static func title(_ session: RecordedSession) -> String {
        let duration = Duration.seconds(session.end.timeIntervalSince(session.start))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        return "\(session.name) · \(session.start.formatted(date: .abbreviated, time: .shortened)) · \(duration)"
    }

    /// Values in their recorded unit: bytes and rates readable, percentages and temperatures to one decimal.
    static func value(_ value: Double, _ unit: SessionUnit) -> String {
        switch unit {
        case .bytes: return MetricText.bytes(value)
        case .bytesPerSecond: return MetricText.bytes(value) + "/s"
        case .percentOfMachine, .percent, .watts, .celsius:
            return value.formatted(.number.precision(.fractionLength(1))) + " " + unit.rawValue
        }
    }
}

/// Every sensor with current, minimum, maximum and mean since reset (plan P15).
private struct SensorsPane: View {
    let model: DashboardModel

    var body: some View {
        DisclosureGroup("Sensors") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(SensorText.since(model.sensorStatsSince))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { model.resetSensorStats() }
                        .help("Start minimum, maximum and mean over from now")
                }
                Table(model.sensorRows) {
                    TableColumn("Group") { Text($0.group) }
                    TableColumn("Sensor") { Text($0.name) }
                    TableColumn("Current") { Text(SensorText.value($0.current, of: $0)) }
                    TableColumn("Min") { Text(SensorText.value($0.minimum, of: $0)) }
                    TableColumn("Max") { Text(SensorText.value($0.maximum, of: $0)) }
                    TableColumn("Average") { Text(SensorText.value($0.mean, of: $0)) }
                }
                .frame(height: 260)
            }
        }
        .monospacedDigit()
    }
}

private enum SensorText {
    static func since(_ start: Date?) -> String {
        guard let start else { return String(localized: "No sensor readings yet; Macs without AppleSMC have none") }
        return String(localized: "Since \(start.formatted(date: .omitted, time: .standard))")
    }

    /// One decimal for temperatures and watts; whole revolutions for fans.
    static func value(_ value: Double?, of row: SensorStatRow) -> String {
        guard let value else { return "–" }
        let digits = row.kind == .fan ? 0 : 1
        return value.formatted(.number.precision(.fractionLength(digits))) + " " + row.unit
    }
}

private struct ConnectionRow: Identifiable {
    let app: String
    let connection: CapturedConnection
    var id: String { connection.id }
}

private enum ConnectionText {
    private static let wildcards: Set<String> = ["0.0.0.0", "::"]

    static func transport(_ transport: CapturedTransport) -> String {
        switch transport {
        case .tcp: return String(localized: "TCP")
        case .udp: return String(localized: "UDP")
        }
    }

    static func state(_ connection: CapturedConnection) -> String {
        if connection.isListening { return String(localized: "Listening") }
        guard let state = connection.state else {
            return connection.remote == nil ? String(localized: "Idle") : String(localized: "Connected")
        }
        switch state {
        case .established: return String(localized: "Established")
        case .synSent, .synReceived: return String(localized: "Opening")
        case .closeWait, .finWait1, .finWait2, .closing, .lastAck, .timeWait: return String(localized: "Closing")
        case .closed, .listen: return String(localized: "Closed")
        }
    }

    /// `127.0.0.1:8080`, `[::1]:443`; any-address binds read `*:5353`.
    static func endpoint(_ endpoint: CapturedEndpoint) -> String {
        if wildcards.contains(endpoint.address) { return "*:\(endpoint.port)" }
        return endpoint.address.contains(":") ? "[\(endpoint.address)]:\(endpoint.port)" : "\(endpoint.address):\(endpoint.port)"
    }

    static func coverage(_ snapshot: CapturedConnections?) -> String {
        guard let snapshot else { return String(localized: "Reading sockets…") }
        if let reason = snapshot.unavailableReason { return reason }
        var parts = [String(localized: "\(snapshot.connections.count) sockets in your processes")]
        if snapshot.restrictedProcesses > 0 {
            parts.append(String(localized: "\(snapshot.restrictedProcesses) processes of other users need the helper"))
        }
        if snapshot.truncatedProcesses > 0 {
            parts.append(String(localized: "\(snapshot.truncatedProcesses) over the per-process limit"))
        }
        if snapshot.failedProcesses > 0 {
            parts.append(String(localized: "\(snapshot.failedProcesses) unreadable"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProcessMetricCell: View {
    enum Format { case percent, bytes, rate, watts, wakeups, gpuTime, processWatts }
    let reading: DashboardReading
    let format: Format
    /// 0-1 share of the column's largest value; shades the cell in its subsystem hue.
    var heat: Double = 0
    var hue: Color = .clear
    /// Display multiplier, such as whole-machine CPU to one core = 100 %.
    var scale = 1.0
    /// What the column means, shown on hover when the reading has no reason or method.
    var note: String?

    var body: some View {
        Text(label)
            .monospacedDigit()
            .padding(.horizontal, 4)
            .background(hue.opacity(min(max(heat, 0), 1) * 0.35), in: RoundedRectangle(cornerRadius: 3))
            .help(reading.reason ?? reading.method ?? note ?? [reading.source?.provider, reading.source?.driver, reading.source?.channel]
                .compactMap { $0 }.joined(separator: " · "))
    }

    private var label: String {
        guard let value = reading.numericValue.map({ $0 * scale }) else {
            switch reading.availability {
            case .collecting: return String(localized: "Collecting…")
            case .restricted: return String(localized: "Restricted")
            case .gap: return String(localized: "Gap")
            default: return String(localized: "Unavailable")
            }
        }
        // Plan state grammar: estimates carry "est." and name their method on hover.
        let suffix = reading.availability == .estimated ? " " + String(localized: "est.") : ""
        switch format {
        case .percent: return MetricText.percent(value) + suffix
        case .bytes: return MetricText.bytes(value) + suffix
        case .rate: return MetricText.bytes(value) + "/s" + suffix
        case .watts: return MetricText.watts(value) + suffix
        case .wakeups: return WakeupText.rate(value) + suffix
        case .gpuTime: return ProcessText.gpuTime(value) + suffix
        case .processWatts: return ProcessText.power(value) + suffix
        }
    }
}

/// Totals for the dragged range: lane extremes and the apps that used it.
private struct RangePanel: View {
    @Bindable var model: DashboardModel
    let report: RangeReport
    @State private var exportFile: ExportFile?
    @State private var exportType: UTType = .json
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(RangeText.span(report.requested)).font(.headline)
                Spacer()
                Picker("App names", selection: $model.exportNaming) {
                    Text("Redacted").tag(ExportNaming.redacted)
                    Text("Included").tag(ExportNaming.named)
                }
                .frame(width: 200)
                .help("Redacted exports number apps instead of naming them, for sharing")
                let document = model.rangeExport
                Group {
                    Button("Export JSON…") { export(as: .json) }
                    Button("Export CSV…") { export(as: .commaSeparatedText) }
                    Button("Save Recording…") { saveRecording() }
                        .help("A .coreotrace file that opens back in Coreography for replay")
                }
                .disabled(document == nil)
                .help(RangeText.exportScope(document, requested: report.requested))
                Button("Clear selection") { model.clearSelection() }
                    .keyboardShortcut(.cancelAction)
            }
            if let exportError {
                Text(exportError).font(.caption).foregroundStyle(.red)
            }
            Text(RangeText.lanes(report)).font(.callout)
            Text(RangeText.apps(String(localized: "Top CPU"), report.topCPUApps) { RangeText.cpuSeconds($0.cpuSeconds) })
                .font(.callout)
            Text(RangeText.apps(String(localized: "Top disk"), report.topDiskApps) { MetricText.bytes($0.diskBytes) })
                .font(.callout)
            if let network = report.topNetworkApps {
                Text(RangeText.apps(String(localized: "Top network"), network) { MetricText.bytes($0.networkBytes) })
                    .font(.callout)
            }
            Text(RangeText.coverage(report)).font(.caption).foregroundStyle(.secondary)
            if let comparison = model.rangeComparison {
                Divider()
                HStack {
                    Text("Compared with \(RangeText.span(comparison.second.requested))").font(.headline).foregroundStyle(.orange)
                    Spacer()
                    Button("Clear comparison") { model.clearComparison() }
                }
                Text(RangeText.comparisonLanes(comparison)).font(.callout)
                Text(RangeText.changes(comparison)).font(.callout)
            } else {
                Text("Command-drag across a lane to compare another range.").font(.caption).foregroundStyle(.secondary)
            }
            let inside = model.timelineMarkers.filter { report.requested.contains($0.time) }
            if !inside.isEmpty {
                Text(RangeText.markers(inside)).font(.caption)
            }
        }
        .monospacedDigit()
        .fileExporter(
            isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
            document: exportFile, contentType: exportType, defaultFilename: "Coreography range"
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
    }
}

private extension RangePanel {
    func saveRecording() {
        guard let data = model.recordingData(name: "") else {
            exportError = String(localized: "Only the live hour can be recorded")
            return
        }
        exportError = nil
        exportType = .coreographyRecording
        exportFile = ExportFile(data: data)
    }

    /// Build the file from displayed data; failures are shown, not swallowed.
    func export(as type: UTType) {
        guard let document = model.rangeExport else { return }
        do {
            let data = type == .json ? try RangeExport.json(document) : Data(RangeExport.csv(document).utf8)
            exportError = nil
            exportType = type
            exportFile = ExportFile(data: data)
        } catch {
            exportError = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }
}

/// Already-encoded export bytes handed to the save panel.
extension UTType {
    /// Declared in Info.plist; JSON underneath.
    static let coreographyRecording = UTType(exportedAs: "ch.lkmc.coreography.trace", conformingTo: .json)
}

private struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText, .plainText, .coreographyRecording]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum RangeText {
    static func span(_ range: ClosedRange<Date>) -> String {
        let seconds = range.upperBound.timeIntervalSince(range.lowerBound)
        let duration = Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        let from = range.lowerBound.formatted(date: .omitted, time: .standard)
        let to = range.upperBound.formatted(date: .omitted, time: .standard)
        return String(localized: "Range \(from)–\(to) (\(duration))")
    }

    /// Exports carry live data only; say so when the selection reaches further back.
    static func exportScope(_ document: RangeExport.Document?, requested: ClosedRange<Date>) -> String {
        guard let document else { return String(localized: "Export covers live data only, which this range predates.") }
        guard document.start > requested.lowerBound else { return "" }
        // With the date: a long range often starts the day before live data does.
        let start = document.start.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Export starts at \(start), where live data begins; recorded history is not exported yet.")
    }

    /// "Markers: 10:02 Memory pressure warning · 10:05 Wake: Lid Open".
    /// A long range can hold dozens of transitions; the caption names the first few and counts the rest.
    private static let shownMarkers = 8

    static func markers(_ markers: [TimelineMarker]) -> String {
        let shown = markers.prefix(shownMarkers).map {
            "\($0.time.formatted(date: .omitted, time: .shortened)) \($0.label)"
        }.joined(separator: " · ")
        let more = markers.count - min(markers.count, shownMarkers)
        return more == 0 ? String(localized: "Markers: \(shown)") : String(localized: "Markers: \(shown) · \(more) more")
    }

    /// "CPU mean 12% → 38%, memory peak 9.1 GB → 11.4 GB".
    static func comparisonLanes(_ comparison: RangeComparison) -> String {
        var parts: [String] = []
        if let first = comparison.first.cpuMeanPercent, let second = comparison.second.cpuMeanPercent {
            parts.append(String(localized: "CPU mean \(MetricText.percent(first)) → \(MetricText.percent(second))"))
        }
        if let first = comparison.first.memoryPeakBytes, let second = comparison.second.memoryPeakBytes {
            parts.append(String(localized: "memory peak \(MetricText.bytes(first)) → \(MetricText.bytes(second))"))
        }
        return parts.isEmpty ? String(localized: "No shared lane readings") : parts.joined(separator: ", ")
    }

    /// "Safari 0.20 → 1.05 cores · Xcode 0.9 → 0.1 cores".
    static func changes(_ comparison: RangeComparison) -> String {
        guard !comparison.changes.isEmpty else { return String(localized: "No app changed by a hundredth of a core or more.") }
        let cores = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        let items = comparison.changes.map { change in
            let estimate = change.isLowerBound ? " " + String(localized: "est.") : ""
            return String(localized: "\(change.app) \(change.firstCores.formatted(cores)) → \(change.secondCores.formatted(cores)) cores\(estimate)")
        }
        return String(localized: "Biggest changes: ") + items.joined(separator: " · ")
    }

    static func lanes(_ report: RangeReport) -> String {
        var parts: [String] = []
        if let mean = report.cpuMeanPercent, let peak = report.cpuPeakPercent {
            parts.append(String(localized: "CPU mean \(MetricText.percent(mean)), peak \(MetricText.percent(peak))"))
        }
        if let memory = report.memoryPeakBytes {
            parts.append(String(localized: "memory peak \(MetricText.bytes(memory))"))
        }
        if let gpu = report.gpuPeakPercent {
            parts.append(String(localized: "GPU peak \(MetricText.percent(gpu))"))
        }
        if let hottest = report.hottest {
            let celsius = ThermalText.celsius(hottest.celsius)
            parts.append(hottest.key.map { String(localized: "hottest \($0) \(celsius)") }
                ?? String(localized: "hottest \(celsius)"))
        }
        return parts.isEmpty ? String(localized: "No samples in this range") : parts.joined(separator: " · ")
    }

    static func apps(_ title: String, _ apps: [AppRangeTotal], value: (AppRangeTotal) -> String) -> String {
        guard !apps.isEmpty else { return title + ": " + String(localized: "no recorded activity") }
        let items = apps.map { $0.name + " " + value($0) + ($0.isLowerBound ? " " + String(localized: "est.") : "") }
        return title + ": " + items.joined(separator: " · ")
    }

    static func cpuSeconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))) + " CPU-s"
    }

    static func coverage(_ report: RangeReport) -> String {
        guard let covered = report.covered else {
            return String(localized: "No process samples fall in this range.")
        }
        // Over a day or more, app totals can cover only part of it; the dates say which part.
        let date: Date.FormatStyle.DateStyle = report.requested.upperBound.timeIntervalSince(report.requested.lowerBound) >= TimeRange.day.seconds
            ? .abbreviated : .omitted
        let from = covered.lowerBound.formatted(date: date, time: .standard)
        let to = covered.upperBound.formatted(date: date, time: .standard)
        return String(localized: "\(report.activeAppCount) active apps; process samples cover \(from)–\(to). Own-user processes only; \"est.\" marks lower bounds.")
    }
}

/// Dashed rules where something happened, so the effect shows on every
/// graph; the person's actions and alerts stand out from system events.
private struct MarkerRules: ChartContent {
    let markers: [TimelineMarker]
    let range: ClosedRange<Date>

    var body: some ChartContent {
        ForEach(markers.filter { range.contains($0.time) }) { marker in
            RuleMark(x: .value("Marker", marker.time))
                .foregroundStyle(MarkerStyle.color(marker.kind))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: MarkerStyle.dash(marker.kind)))
                .accessibilityLabel(marker.label)
                // Only the person's own markers carry a caption; the rest would crowd the lanes.
                .annotation(position: .top, alignment: .leading) {
                    if marker.kind == .note {
                        Text(marker.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
        }
    }
}

private enum MarkerStyle {
    static func color(_ kind: MarkerKind) -> Color {
        switch kind {
        case .system: Color.secondary.opacity(0.5)
        case .note: Color.accentColor
        case .action, .alert: Color.secondary
        }
    }

    static func dash(_ kind: MarkerKind) -> [CGFloat] {
        switch kind {
        case .system: [1, 4]
        case .note: []
        case .action, .alert: [2, 3]
        }
    }
}

/// The selected range, shaded across every lane.
private struct SelectionBand: ChartContent {
    let selection: ClosedRange<Date>?
    let range: ClosedRange<Date>
    /// The comparison range is orange, so the two never read as one.
    var tint: Color = .accentColor

    var body: some ChartContent {
        if let selection, selection.overlaps(range) {
            RectangleMark(
                xStart: .value("Selection start", max(selection.lowerBound, range.lowerBound)),
                xEnd: .value("Selection end", min(selection.upperBound, range.upperBound))
            )
            .foregroundStyle(tint.opacity(0.15))
        }
    }
}

private extension View {
    /// Silent alert (plan: most rules tint the lane rather than notify).
    func alertTint(_ title: String?) -> some View {
        overlay {
            if title != nil {
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .fill(Color.red.opacity(0.07))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let title {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }
}

/// One hairline at the shared cursor time, drawn in every lane (plan P4).
private struct CursorRule: ChartContent {
    let time: Date?
    let range: ClosedRange<Date>

    var body: some ChartContent {
        if let time, range.contains(time) {
            RuleMark(x: .value("Cursor", time))
                .foregroundStyle(Color.primary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }
}

private extension View {
    /// Hovering any plot moves the one shared cursor; leaving it returns to live.
    func chartCursor(_ model: DashboardModel) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                ChartInteraction(model: model, proxy: proxy, geometry: geometry)
            }
        }
    }
}

/// Hover and drag over one plot. A drag the system cancels never reaches
/// onEnded; the gesture state resets anyway, which drops its draft.
private struct ChartInteraction: View {
    let model: DashboardModel
    let proxy: ChartProxy
    let geometry: GeometryProxy
    @GestureState private var dragging = false
    /// Decided when a drag starts: Command makes it the comparison range.
    @State private var dragsComparison: Bool?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard let plot = proxy.plotFrame else { return }
                    let x = location.x - geometry[plot].origin.x
                    // The axis margin maps to no date; keep the cursor rather than flicker to live.
                    if let time = proxy.value(atX: x, as: Date.self) { model.cursorTime = time }
                case .ended:
                    model.cursorTime = nil
                }
            }
            // Dragging across any lane selects one range for all of them (plan P7).
            .gesture(DragGesture(minimumDistance: 4).updating($dragging) { _, state, _ in
                state = true
            }.onChanged { drag in
                guard let plot = proxy.plotFrame else { return }
                let origin = geometry[plot].origin.x
                guard let first = proxy.value(atX: drag.startLocation.x - origin, as: Date.self),
                      let second = proxy.value(atX: drag.location.x - origin, as: Date.self) else { return }
                let comparing = dragsComparison ?? (NSEvent.modifierFlags.contains(.command) && model.selection != nil)
                dragsComparison = comparing
                let range = min(first, second)...max(first, second)
                if comparing { model.draftComparison = range } else { model.draftSelection = range }
            }.onEnded { _ in
                // Commit once, so the range report is computed per drag, not per frame.
                if dragsComparison == true {
                    if let draft = model.draftComparison { model.comparison = draft }
                } else if let draft = model.draftSelection {
                    model.selection = draft
                    model.clearComparison()
                }
                model.draftSelection = nil
                model.draftComparison = nil
                dragsComparison = nil
            })
            .onChange(of: dragging) { _, active in
                guard !active else { return }
                model.draftSelection = nil
                model.draftComparison = nil
                dragsComparison = nil
            }
    }
}

private enum ContributorSubsystem { case cpu, memory, disk }

/// "Top then": the leading apps at the process sample nearest the cursor.
private struct ContributorLine: View {
    let model: DashboardModel
    let subsystem: ContributorSubsystem

    var body: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .help("Own-user processes grouped by app, from the process sample nearest the cursor")
    }

    private var label: String {
        guard let snapshot = model.displayedContributors else {
            return model.cursorTime == nil
                ? String(localized: "Top: collecting…")
                : String(localized: "Top: no process sample near this time")
        }
        let contributors = switch subsystem {
        case .cpu: snapshot.cpu
        case .memory: snapshot.memory
        case .disk: snapshot.disk
        }
        let prefix = model.cursorTime == nil
            ? String(localized: "Top")
            : String(localized: "Top at \(snapshot.time.formatted(date: .omitted, time: .standard))")
        guard !contributors.isEmpty else { return prefix + ": " + String(localized: "no readable activity") }
        let items = contributors.map { contributor in
            let value = switch subsystem {
            case .cpu: MetricText.percent(contributor.value)
            case .memory: MetricText.bytes(contributor.value)
            case .disk: MetricText.rate(contributor.value)
            }
            return contributor.name + " " + value + (contributor.isEstimate ? " " + String(localized: "est.") : "")
        }
        return prefix + ": " + items.joined(separator: " · ")
    }
}

/// Keep the visible window's points, decimated to bucket extremes for drawing.
func visiblePoints(_ points: [DashboardPoint], _ start: Date, _ end: Date) -> [DashboardPoint] {
    Decimation.points(points.filter { $0.time >= start && $0.time <= end }, start: start, end: end)
}

/// The monitor measures itself against the published budget (plan P21).
private struct SelfCostLine: View {
    let model: DashboardModel

    var body: some View {
        if let cost = model.selfCost {
            Text(label(cost))
                .monospacedDigit()
                .foregroundStyle(over(cost) ? Color.orange : Color.secondary)
                .help("Coreography's own process, from the latest process sample. One wakeup a second is the sampling itself.")
        } else if let processes = model.processSnapshot {
            // A process sample without our own row is a failure to report, not a wait.
            Text("Self-cost: unavailable · \(processes.enumeration.reason ?? String(localized: "own process not observed"))")
        } else {
            Text("Self-cost: collecting…")
        }
    }

    private func label(_ cost: SelfCost) -> String {
        let cpu = cost.cpuPercentOfOneCore.numericValue.map {
            $0.formatted(.number.precision(.fractionLength(1))) + "% of a core"
        } ?? String(localized: "CPU unavailable")
        let memory = MetricText.bytes(cost.footprintBytes.numericValue)
        let wakeups = WakeupText.rate(cost.wakeupsPerSecond.numericValue)
        let budget = String(localized: "budget \(SelfCost.cpuBudgetPercentOfOneCore.formatted())% · \(MetricText.bytes(SelfCost.footprintBudgetBytes)) · \(SelfCost.wakeupBudgetBeyondSampling.formatted()) wakeups/s beyond sampling")
        let note = over(cost) ? " · " + String(localized: "over budget") : ""
        return String(localized: "Coreography: \(cpu) · \(memory) · \(wakeups) (\(budget))") + note
    }

    private func over(_ cost: SelfCost) -> Bool {
        cost.cpuOverBudget || cost.footprintOverBudget || cost.wakeupsOverBudget
    }
}

private enum WakeupText {
    static func rate(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(localized: "\(value.formatted(.number.precision(.fractionLength(0)))) wakeups/s")
    }
}

private enum TimeRangeText {
    static func label(_ range: TimeRange) -> String {
        switch range {
        case .minute: return String(localized: "1 min")
        case .tenMinutes: return String(localized: "10 min")
        case .hour: return String(localized: "1 h")
        case .sixHours: return String(localized: "6 h")
        case .day: return String(localized: "24 h")
        case .week: return String(localized: "7 d")
        case .month: return String(localized: "30 d")
        }
    }
}

private enum ToolbarText {
    @MainActor
    static func status(_ model: DashboardModel) -> String {
        if model.collectionError != nil { return String(localized: "Collection stopped") }
        if model.samplingPaused { return String(localized: "Recording paused · a gap marks the pause") }
        if let recording = model.openRecording {
            return String(localized: "Recording “\(recording.name)” · Return to live to resume")
        }
        if let cursor = model.cursorTime {
            return String(localized: "Cursor \(cursor.formatted(date: .omitted, time: .standard)) · values at cursor")
        }
        guard model.displayMode == .live else { return String(localized: "Display held · recording continues") }
        let range = TimeRangeText.label(model.timeRange)
        // A long range missing its stored part says so rather than looking empty.
        guard model.storedHistoryProblem == nil else {
            return String(localized: "Live · last \(range) · older history unavailable")
        }
        return String(localized: "Live · last \(range)")
    }
}

private enum Layout {
    static let padding: CGFloat = 20
    static let cornerRadius: CGFloat = 10
    static let headerWidth: CGFloat = 180
    static let axisLabelWidth: CGFloat = 96
    static let regularGraphHeight: CGFloat = 120

    static func graphHeight(_ size: LaneSize) -> CGFloat {
        switch size {
        case .compact: 72
        case .regular: regularGraphHeight
        case .tall: 200
        }
    }
    static let bandHeight: CGFloat = 48
}

enum MetricText {
    static let percentScale = 100.0
    private static let wholePercentThreshold = 10.0

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        let digits = value >= wholePercentThreshold ? 0 : 1
        return (value / percentScale).formatted(.percent.precision(.fractionLength(0...digits)))
    }

    static func bytes(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0, value < Double(Int64.max) else { return "–" }
        return Int64(value).formatted(.byteCount(style: .file))
    }

    static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(1))) + " W"
    }

    static func rate(_ value: Double?) -> String {
        guard let value else { return "–" }
        return bytes(value) + "/s"
    }

    /// "3.2 GHz" from MHz.
    static func frequency(_ megahertz: Double?) -> String {
        guard let megahertz, megahertz.isFinite else { return "–" }
        return (megahertz / 1000).formatted(.number.precision(.fractionLength(1))) + " GHz"
    }
}

/// The selected process's CPU and footprint since selection, gaps kept.
private struct ProcessHistoryCharts: View {
    private static let chartHeight: CGFloat = 60
    let points: [ProcessHistoryPoint]

    var body: some View {
        if points.count < 2 {
            Text("Recording from the next samples…").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("CPU, whole machine").font(.caption).foregroundStyle(.secondary)
                chart(\.cpuPercent, color: .blue)
                    .chartYScale(domain: 0...max(1, points.compactMap(\.cpuPercent).max() ?? 1))
                Text("Footprint").font(.caption).foregroundStyle(.secondary)
                chart(\.footprintBytes, color: .teal)
                if let first = points.first?.time {
                    Text("Since \(first.formatted(date: .omitted, time: .standard)); kept for an hour while selected")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chart(_ value: KeyPath<ProcessHistoryPoint, Double?>, color: Color) -> some View {
        Chart(points.filter { $0[keyPath: value] != nil }) { point in
            LineMark(
                x: .value("Time", point.time), y: .value("Value", point[keyPath: value] ?? 0),
                series: .value("Segment", point.segment)
            )
            .foregroundStyle(color)
        }
        .chartXAxis(.hidden)
        .frame(height: Self.chartHeight)
    }
}

/// Per-process network rates: "↓1.2 MB/s ↑40 KB/s", or "–" while unknown.
enum NetworkText {
    static func processRates(_ row: ProcessRow) -> String {
        rates(row.networkReceivedBytesPerSecond, row.networkSentBytesPerSecond)
    }

    static func rates(_ received: DashboardReading, _ sent: DashboardReading) -> String {
        guard received.numericValue != nil || sent.numericValue != nil else { return "–" }
        let estimate = received.availability == .estimated || sent.availability == .estimated ? " " + String(localized: "est.") : ""
        return "↓\(MetricText.rate(received.numericValue)) ↑\(MetricText.rate(sent.numericValue))\(estimate)"
    }
}

/// IOReport readings as captions: every value is estimated, and a missing
/// source shows its reason rather than zeros.
enum SiliconText {
    /// "E 1.2 GHz 23% · P 3.1 GHz 41%".
    static func tiers(_ frame: CapturedSilicon?) -> String {
        guard let frame else { return String(localized: "Core tiers: collecting…") }
        guard !frame.cpuTiers.isEmpty else {
            return frame.cpuPowerWatts.reason ?? String(localized: "No core tiers reported")
        }
        return frame.cpuTiers.map(tier).joined(separator: " · ")
    }

    static func tier(_ tier: CapturedCPUTier) -> String {
        let frequency = tier.frequencyMHz.availability == .gap
            ? String(localized: "idle") : MetricText.frequency(tier.frequencyMHz.numericValue)
        return "\(tier.kind.rawValue) \(frequency) \(MetricText.percent(tier.activePercent.numericValue))"
    }

    /// "CPU 4.2 W · GPU 1.1 W · ANE 0.0 W est."
    static func blocks(_ frame: CapturedSilicon?) -> String {
        guard let frame else { return String(localized: "Block power: collecting…") }
        guard frame.cpuPowerWatts.numericValue != nil else {
            return frame.cpuPowerWatts.reason ?? String(localized: "Block power: collecting…")
        }
        let parts = [("CPU", frame.cpuPowerWatts), ("GPU", frame.gpuPowerWatts), ("ANE", frame.anePowerWatts)]
            .filter { $0.1.numericValue != nil }
            .map { "\($0.0) \(MetricText.watts($0.1.numericValue))" }
        return parts.joined(separator: " · ") + " " + String(localized: "est.")
    }
}

private struct MetricChartAccessibility: AXChartDescriptorRepresentable {
    let title: String
    let metric: DashboardMetric
    let points: [DashboardPoint]
    let start: Date
    let end: Date
    let maximum: Double

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSinceReferenceDate: value).formatted(date: .omitted, time: .standard)
        }
        let y = AXNumericDataAxisDescriptor(title: title, range: 0...maximum, gridlinePositions: []) {
            metric == .cpu ? MetricText.percent($0) : MetricText.bytes($0)
        }
        let segments = Dictionary(grouping: points, by: \.segment)
        let series = segments.keys.sorted().map { segment in
            AXDataSeriesDescriptor(name: title, isContinuous: true, dataPoints:
                (segments[segment] ?? []).map {
                    AXDataPoint(x: $0.time.timeIntervalSinceReferenceDate, y: $0.value)
                }
            )
        }
        return AXChartDescriptor(
            title: title, summary: String(localized: "Visible range; missing readings leave gaps."),
            xAxis: x, yAxis: y, additionalAxes: [], series: series
        )
    }
}

private struct LaneGraphHeightKey: EnvironmentKey {
    static let defaultValue = Layout.regularGraphHeight
}

private extension EnvironmentValues {
    /// The graph height the person chose for the lane being drawn.
    var laneGraphHeight: CGFloat {
        get { self[LaneGraphHeightKey.self] }
        set { self[LaneGraphHeightKey.self] = newValue }
    }
}

/// One row per core tier, shaded by its activity (plan: the CPU lane's
/// cluster sub-band); holes are samples without a reading.
private struct TierStrip: View {
    private static let rowHeight: CGFloat = 10
    let cells: [TierBandCell]
    let range: ClosedRange<Date>

    var body: some View {
        let tiers = Array(Set(cells.map(\.tier))).sorted()
        Chart(cells) { cell in
            RectangleMark(
                xStart: .value("Start", max(cell.start, range.lowerBound)), xEnd: .value("End", min(cell.end, range.upperBound)),
                y: .value("Tier", cell.tier)
            )
            .foregroundStyle(Color.blue.opacity(0.1 + 0.9 * cell.activePercent / MetricText.percentScale))
        }
        .chartXScale(domain: range)
        .chartYScale(domain: tiers)
        .chartXAxis(.hidden)
        // Labels take the main chart's trailing column, so both plots share one time axis.
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let tier = value.as(String.self) {
                        Text(tier).frame(width: Layout.axisLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: CGFloat(tiers.count) * Self.rowHeight)
        .accessibilityLabel(String(localized: "Core tier activity over the visible range"))
    }
}

/// Each visible volume's used share and free space (plan: per-volume capacity).
private struct VolumeBars: View {
    private static let shown = 4
    /// Red is for bad states only; this matches the startup-disk alert's 10 % free.
    private static let nearlyFull = 0.9
    let list: CapturedVolumes?

    var body: some View {
        if let list {
            if let problem = list.problem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(list.volumes.prefix(Self.shown)) { volume in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(volume.name) · \(MetricText.bytes(Double(volume.availableBytes))) free")
                        .font(.caption)
                        .lineLimit(1)
                    ProgressView(value: volume.usedFraction)
                        .progressViewStyle(.linear)
                        .tint(volume.usedFraction > Self.nearlyFull ? .red : .blue)
                }
                .help(VolumeText.detail(volume))
                .accessibilityElement(children: .combine)
            }
            if list.volumes.count > Self.shown {
                Text("+\(list.volumes.count - Self.shown) more volumes").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private enum VolumeText {
    static func detail(_ volume: CapturedVolume) -> String {
        let kind = switch volume.kind {
        case .internal: volume.isStartup ? String(localized: "Startup volume") : String(localized: "Internal volume")
        case .external: String(localized: "External volume")
        case .network: String(localized: "Network volume")
        }
        let free = MetricText.bytes(Double(volume.availableBytes))
        let total = MetricText.bytes(Double(volume.totalBytes))
        return String(localized: "\(kind) at \(volume.path): \(free) available of \(total), purgeable space included")
    }
}

/// Each lane's menu (plan: hide, reorder and resize from the lane itself).
private struct LaneMenu: View {
    @Bindable var model: DashboardModel
    let lane: LaneKind

    var body: some View {
        Menu {
            Button("Move Up") { model.laneLayout.move(lane, .up) }
                .disabled(!model.laneLayout.canMove(lane, .up))
            Button("Move Down") { model.laneLayout.move(lane, .down) }
                .disabled(!model.laneLayout.canMove(lane, .down))
            Picker("Size", selection: Binding(
                get: { model.laneLayout.size(of: lane) }, set: { model.laneLayout.set(lane, $0) }
            )) {
                ForEach(LaneSize.allCases) { Text(LaneText.size($0)).tag($0) }
            }
            Divider()
            Button("Hide Lane") { model.laneLayout.set(lane, .hidden) }
                .disabled(model.laneLayout.visible == [lane])
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(6)
        .help("Move, resize or hide this lane; Settings shows hidden lanes again")
        .accessibilityLabel("\(LaneText.title(lane)) lane options")
    }
}

enum LaneText {
    static func title(_ lane: LaneKind) -> String {
        switch lane {
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "Memory")
        case .gpu: String(localized: "GPU")
        case .power: String(localized: "Power")
        case .disk: String(localized: "Disk")
        case .network: String(localized: "Network")
        case .thermal: String(localized: "Thermal")
        }
    }

    static func size(_ size: LaneSize) -> String {
        switch size {
        case .compact: String(localized: "Compact")
        case .regular: String(localized: "Regular")
        case .tall: String(localized: "Tall")
        }
    }
}
