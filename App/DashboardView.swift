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

                ForEach([DashboardMetric.cpu, .memory]) { metric in
                    lane(metric)
                }

                DiskLane(model: model)
                NetworkLane(model: model)

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

                Text("Memory is a VM composition estimate, not memory pressure. Missing readings leave gaps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Layout.padding)
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.collectionError != nil ? "Collection stopped" :
                     model.displayMode == .live ? "Live · last minute" : "Display held · recording continues")
                    .font(.caption)
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
            }
            .frame(width: Layout.headerWidth, alignment: .leading)

            if points.isEmpty {
                Text(reading?.reason ?? String(localized: "Collecting samples…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Layout.graphHeight)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value(title, point.value),
                        series: .value("Segment", point.segment)
                    )
                    .foregroundStyle(metric == .cpu ? Color.blue : Color.teal)
                    .interpolationMethod(.linear)
                }
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
                    belowLabel: String(localized: "Sent"), above: received, below: sent, start: start, end: end
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
                    belowLabel: String(localized: "Written"), above: read, below: written, start: start, end: end
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
        }
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

                Table(model.visibleProcesses) {
                    TableColumn("Process", value: \.name)
                    TableColumn("PID") { Text($0.id.pid.formatted(.number.grouping(.never))) }
                        .width(60)
                    TableColumn("UID") { Text($0.uid.formatted(.number.grouping(.never))) }
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

                Text("CPU uses the whole-machine scale. Footprints are not an additive memory total. Process sampling: 2 s; short-lived processes can be missed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }
}

private struct ProcessMetricCell: View {
    enum Format { case percent, bytes, rate }
    let reading: DashboardReading
    let format: Format

    var body: some View {
        Text(label)
            .monospacedDigit()
            .help(reading.reason ?? [reading.source?.provider, reading.source?.driver, reading.source?.channel]
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
        switch format {
        case .percent: return MetricText.percent(value)
        case .bytes: return MetricText.bytes(value)
        case .rate: return MetricText.bytes(value) + "/s"
        }
    }
}

private enum Layout {
    static let padding: CGFloat = 20
    static let cornerRadius: CGFloat = 10
    static let visibleSeconds: TimeInterval = 60
    static let headerWidth: CGFloat = 180
    static let axisLabelWidth: CGFloat = 96
    static let graphHeight: CGFloat = 120
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
