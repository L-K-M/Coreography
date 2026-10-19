import Foundation
import CoreographyKit

public typealias CapturedTemperature = TemperatureReading

/// One row of the Sensors tab: the current reading and its minimum,
/// maximum and mean since the last reset (plan P15).
public struct SensorStatRow: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case temperature, fan, power
    }

    public let id: String
    public let kind: Kind
    public let name: String
    /// The grouping heading: a region for temperatures, else the kind.
    public let group: String
    public let unit: String
    /// nil when the newest sample did not include this sensor.
    public let current: Double?
    public let minimum: Double
    public let maximum: Double
    public let mean: Double
    public let samples: Int
}

/// Accumulates every sensor reading since a reset. Only measured or
/// estimated values count; a missing reading is not a zero.
struct SensorStats: Sendable {
    private struct Accumulator: Sendable {
        let kind: SensorStatRow.Kind
        let name: String
        let group: String
        let unit: String
        var current: Double?
        var minimum: Double
        var maximum: Double
        var sum: Double
        var count: Int

        init(kind: SensorStatRow.Kind, name: String, group: String, unit: String, value: Double) {
            self.kind = kind
            self.name = name
            self.group = group
            self.unit = unit
            current = value
            minimum = value
            maximum = value
            sum = value
            count = 1
        }

        mutating func add(_ value: Double) {
            current = value
            minimum = min(minimum, value)
            maximum = max(maximum, value)
            sum += value
            count += 1
        }
    }

    private static let unknownRegion = "Other temperatures"
    private static let fanGroup = "Fans"
    private static let powerGroup = "Power"
    private var accumulators: [String: Accumulator] = [:]
    /// When the statistics started; nil before the first reading.
    private(set) var since: Date?

    mutating func reset() {
        accumulators = [:]
        since = nil
    }

    mutating func record(temperatures: [CapturedTemperature], sensors: CapturedSensors?, at time: Date) {
        var seen: [(id: String, kind: SensorStatRow.Kind, name: String, group: String, unit: String, value: Double)] = []
        for temperature in temperatures {
            guard let value = temperature.celsius.numericValue else { continue }
            seen.append((
                "temperature-\(temperature.key)", .temperature, temperature.key,
                temperature.region ?? Self.unknownRegion, "°C", value
            ))
        }
        for fan in sensors?.fans ?? [] {
            guard let value = fan.rpm.numericValue else { continue }
            seen.append(("fan-\(fan.id)", .fan, "Fan \(fan.id)", Self.fanGroup, "rpm", value))
        }
        if let power = sensors?.systemPowerWatts.numericValue {
            seen.append(("power-system", .power, "System power", Self.powerGroup, "W", power))
        }
        // A sensor absent from this sample keeps its history but has no current
        // value; a sample with nothing readable clears every current value.
        for key in accumulators.keys { accumulators[key]?.current = nil }
        guard !seen.isEmpty else { return }
        if since == nil { since = time }

        for reading in seen {
            if accumulators[reading.id] == nil {
                accumulators[reading.id] = Accumulator(
                    kind: reading.kind, name: reading.name, group: reading.group, unit: reading.unit, value: reading.value
                )
            } else {
                accumulators[reading.id]?.add(reading.value)
            }
        }
    }

    /// Grouped by region or kind, then by name.
    func rows() -> [SensorStatRow] {
        accumulators.map { id, value in
            SensorStatRow(
                id: id, kind: value.kind, name: value.name, group: value.group, unit: value.unit,
                current: value.current, minimum: value.minimum, maximum: value.maximum,
                mean: value.sum / Double(value.count), samples: value.count
            )
        }
        .sorted { ($0.group, $0.name) < ($1.group, $1.name) }
    }
}
