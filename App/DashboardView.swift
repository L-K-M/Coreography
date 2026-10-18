import SwiftUI
import Charts
import Accessibility
import CoreographyServices

@MainActor
struct DashboardView: View {
    @Bindable var model: DashboardModel

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

                ForEach(DashboardMetric.allCases) { metric in
                    lane(metric)
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
                .keyboardShortcut(.space, modifiers: [])
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
        let end = model.latest?.stamp.wallTime ?? Date()
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

private enum Layout {
    static let padding: CGFloat = 20
    static let cornerRadius: CGFloat = 10
    static let visibleSeconds: TimeInterval = 60
    static let headerWidth: CGFloat = 180
    static let axisLabelWidth: CGFloat = 72
    static let graphHeight: CGFloat = 210
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
