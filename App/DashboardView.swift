import SwiftUI
import Charts
import Accessibility
import CoreographyServices

@MainActor
struct DashboardView: View {
    @Bindable var model: DashboardModel
    @FocusState private var processFilterFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let inventory = model.latest?.inventory {
                    HStack {
                        Text("\(inventory.logicalCPUCount) logical CPUs")
                        Spacer()
                        Text(inventory.operatingSystem)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                lane(.cpu)
                MemoryLane(model: model)
                GPULane(model: model)
                PowerLane(model: model)

                DiskLane(model: model)
                NetworkLane(model: model)
                ThermalLane(model: model)

                ProcessPane(model: model, filterFocused: $processFilterFocused)

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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(ToolbarText.status(model))
                    .font(.caption)
                    .monospacedDigit()
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
        .onDisappear { model.stop() }
    }

    private func lane(_ metric: DashboardMetric) -> some View {
        let reading = model.reading(for: metric)
        let title = metric == .cpu ? String(localized: "CPU") : String(localized: "Memory")
        let maximum = metric == .cpu
            ? MetricText.percentScale
            : Double(model.latest?.inventory.physicalMemoryBytes ?? 1)
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-Layout.visibleSeconds)
        let points = model.points(for: metric).filter { $0.time >= start && $0.time <= end }

        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(metric == .cpu
                     ? MetricText.percent(reading?.numericValue)
                     : MetricText.bytes(reading?.numericValue))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                Text(metric == .cpu ? "Whole-machine activity" : "Used memory, estimated")
                    .font(.caption)
                Text(reading?.reason ?? reading?.method ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if metric == .cpu {
                    ContributorLine(model: model, subsystem: .cpu)
                }
            }
            .frame(width: Layout.headerWidth, alignment: .leading)

            if points.isEmpty {
                Text(reading?.reason ?? String(localized: "Collecting samples…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Layout.graphHeight)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value(title, point.value),
                            series: .value("Segment", point.segment)
                        )
                        .foregroundStyle(metric == .cpu ? Color.blue : Color.teal)
                        .interpolationMethod(.linear)
                    }
                    CursorRule(time: model.cursorTime, range: start...end)
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
                .frame(height: Layout.graphHeight)
                .accessibilityChartDescriptor(MetricChartAccessibility(
                    title: title, metric: metric, points: points,
                    start: start, end: end, maximum: max(1, maximum)
                ))
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
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-Layout.visibleSeconds)
        let stack = model.memoryStack().filter { $0.time >= start && $0.time <= end }
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
                    .frame(maxWidth: .infinity, minHeight: Layout.graphHeight)
            } else {
                chart(stack: stack, pressure: pressure, capacity: capacity, start: start, end: end)
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
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
        .frame(height: Layout.graphHeight)
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
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-Layout.visibleSeconds)
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
                    .frame(maxWidth: .infinity, minHeight: Layout.graphHeight)
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
                ForEach(device.points.filter { $0.time >= start && $0.time <= end }) { point in
                    LineMark(
                        x: .value("Time", point.time), y: .value("Busy", point.value),
                        series: .value("Device", "\(device.id.registryEntryID)-\(point.segment)")
                    )
                    .foregroundStyle(Color.purple)
                    .interpolationMethod(.linear)
                }
            }
            CursorRule(time: model.cursorTime, range: start...end)
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
        .frame(height: Layout.graphHeight)
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
            let visible = device.points.filter { $0.time >= start && $0.time <= end }
            let segments = Dictionary(grouping: visible, by: \.segment)
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
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-Layout.visibleSeconds)
        let points = model.batteryChargePoints().filter { $0.time >= start && $0.time <= end }
        let plugged = model.externalPowerSpans().filter { $0.end >= start && $0.start <= end }
        let latest = model.displayedPowerFrame

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Power").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(MetricText.watts(latest?.systemPowerWatts.numericValue))
                    .font(.system(size: 30, weight: .semibold))
                Text(latest?.systemPowerWatts.numericValue == nil ? "System draw" : "System draw, from battery")
                    .font(.caption)
                Text(PowerText.battery(latest)).font(.caption)
                Text(PowerText.adapterAndHealth(latest)).font(.caption).foregroundStyle(.secondary)
                Text(latest?.systemPowerWatts.reason ?? latest?.systemPowerWatts.method ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: Layout.headerWidth, alignment: .leading)

            if points.isEmpty {
                Text(latest?.batteryChargePercent.reason ?? String(localized: "Collecting samples…"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Layout.graphHeight)
            } else {
                chart(points: points, plugged: plugged, start: start, end: end)
            }
        }
        .padding(Layout.padding)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
            Color(nsColor: .separatorColor), lineWidth: 0.5
        ))
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
        .frame(height: Layout.graphHeight)
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
                ? String(localized: "Battery charge over the last minute; the band marks time on external power.")
                : String(localized: "Battery charge over the last minute, on battery power."),
            xAxis: x, yAxis: y, additionalAxes: [], series: series
        )
    }
}

private struct ThermalLane: View {
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-Layout.visibleSeconds)
        let spans = model.thermalPressureSpans().filter { $0.end >= start && $0.start <= end }
        let reading = model.displayedFrame?.thermalPressure

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Thermal").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(ThermalText.level(reading)).font(.system(size: 30, weight: .semibold))
                Text("System thermal pressure").font(.caption)
                Text(reading?.reason ?? String(localized: "Temperatures and fans are not collected yet"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: Layout.headerWidth, alignment: .leading)

            if spans.isEmpty {
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
    }
}

private enum ThermalText {
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
            summary: String(localized: "System thermal pressure level over the last minute; pressure alone does not prove throttling."),
            xAxis: x, yAxis: y, additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: String(localized: "Thermal pressure"), isContinuous: false, dataPoints: points)]
        )
    }
}

private struct NetworkLane: View {
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-Layout.visibleSeconds)
        let received = model.points(for: .networkReceived).filter { $0.time >= start && $0.time <= end }
        let sent = model.points(for: .networkSent).filter { $0.time >= start && $0.time <= end }
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
                    .frame(maxWidth: .infinity, minHeight: Layout.graphHeight)
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
    @Bindable var model: DashboardModel

    var body: some View {
        let end = model.displayedEndTime ?? Date()
        let start = end.addingTimeInterval(-Layout.visibleSeconds)
        let read = model.points(for: .diskRead).filter { $0.time >= start && $0.time <= end }
        let written = model.points(for: .diskWritten).filter { $0.time >= start && $0.time <= end }
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
                if let inventory = model.diskFrames.last,
                   inventory.enumerationTruncated || !inventory.issues.isEmpty {
                    Text("Storage inventory is incomplete.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .frame(width: Layout.headerWidth, alignment: .leading)
            if read.isEmpty && written.isEmpty {
                Text(model.storageSelectionMessage).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Layout.graphHeight)
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
        .frame(height: Layout.graphHeight)
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

    var body: some View {
        DisclosureGroup("Processes") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Filter by process name, PID or UID", text: $model.processFilter)
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
                        Text("Name").tag(ProcessSort.name)
                    }
                    .frame(width: 180)
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

                Table(model.visibleProcessRows, children: \.children) {
                    TableColumn("Process") { row in
                        Text(row.children == nil ? row.name : "\(row.name) (\(row.memberCount))")
                            .help(ProcessText.grouping(row.groupingMethod))
                    }
                    TableColumn("PID") { Text($0.process?.id.pid.formatted(.number.grouping(.never)) ?? "") }
                        .width(60)
                    TableColumn("UID") { Text($0.process?.uid.formatted(.number.grouping(.never)) ?? "") }
                        .width(65)
                    TableColumn("CPU, machine") {
                        ProcessMetricCell(reading: $0.cpuPercentOfMachine, format: .percent)
                    }
                    TableColumn("Footprint") {
                        ProcessMetricCell(reading: $0.memoryFootprintBytes, format: .bytes)
                    }
                    TableColumn("Disk read/s") {
                        ProcessMetricCell(reading: $0.diskReadBytesPerSecond, format: .rate)
                    }
                    TableColumn("Disk write/s") {
                        ProcessMetricCell(reading: $0.diskWriteBytesPerSecond, format: .rate)
                    }
                }
                .frame(height: 260)
                .textSelection(.enabled)

                Text("CPU uses the whole-machine scale. App totals sum their members; footprint sums can count shared memory twice. Process sampling: 2 s; short-lived processes can be missed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }
}

private enum ProcessText {
    static func grouping(_ method: ProcessGroupingMethod?) -> String {
        switch method {
        case .responsibleProcess: return String(localized: "Grouped under the process macOS holds responsible")
        case .appBundle: return String(localized: "Grouped by its app bundle")
        case .standalone: return String(localized: "No owning app found")
        case nil: return ""
        }
    }
}

private struct ProcessMetricCell: View {
    enum Format { case percent, bytes, rate, watts }
    let reading: DashboardReading
    let format: Format

    var body: some View {
        Text(label)
            .monospacedDigit()
            .help(reading.reason ?? reading.method ?? [reading.source?.provider, reading.source?.driver, reading.source?.channel]
                .compactMap { $0 }.joined(separator: " · "))
    }

    private var label: String {
        guard let value = reading.numericValue else {
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
            }
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

private enum ToolbarText {
    @MainActor
    static func status(_ model: DashboardModel) -> String {
        if model.collectionError != nil { return String(localized: "Collection stopped") }
        if let cursor = model.cursorTime {
            return String(localized: "Cursor \(cursor.formatted(date: .omitted, time: .standard)) · values at cursor")
        }
        return model.displayMode == .live
            ? String(localized: "Live · last minute") : String(localized: "Display held · recording continues")
    }
}

private enum Layout {
    static let padding: CGFloat = 20
    static let cornerRadius: CGFloat = 10
    static let visibleSeconds: TimeInterval = 60
    static let headerWidth: CGFloat = 180
    static let axisLabelWidth: CGFloat = 96
    static let graphHeight: CGFloat = 120
    static let bandHeight: CGFloat = 48
}

private enum MetricText {
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
            title: title, summary: String(localized: "Last minute; missing readings leave gaps."),
            xAxis: x, yAxis: y, additionalAxes: [], series: series
        )
    }
}
