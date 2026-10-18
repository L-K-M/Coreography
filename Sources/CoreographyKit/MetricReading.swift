import Foundation

/// How a reading's value should be interpreted.
///
/// Mirrors the plan's availability model: measured and estimated carry a
/// number, every other state is an explicit non-numeric condition the UI
/// renders as collecting, unavailable, restricted, unsupported or a gap.
public enum MetricAvailability: String, Codable, CaseIterable, Sendable {
    case measured
    case estimated
    case collecting
    case unavailable
    case restricted
    case unsupported
    case gap
}

/// Where a reading came from (plan: provider, driver, channel, chip
/// profile version). `provider` is required; the rest name the active
/// rung of the metric's fallback ladder.
public struct MetricSource: Codable, Equatable, Sendable {
    public let provider: String
    public let driver: String?
    public let channel: String?
    public let chipProfile: String?

    public init(
        provider: String,
        driver: String? = nil,
        channel: String? = nil,
        chipProfile: String? = nil
    ) {
        self.provider = provider
        self.driver = driver
        self.channel = channel
        self.chipProfile = chipProfile
    }
}

/// Why a reading factory or decoder rejected a value.
public enum MetricReadingError: Error, Equatable, Sendable {
    /// Measured and estimated values must be finite; NaN and infinity
    /// would corrupt rate math and chart scales.
    case nonFiniteValue(MetricAvailability)
    /// Estimated readings must name their estimation method.
    case missingEstimationMethod
    /// Restricted and unavailable readings must name the reason.
    case missingReason(MetricAvailability)
    /// Measured and estimated readings must carry a number.
    case missingNumericValue(MetricAvailability)
    /// Only measured and estimated readings may carry a number.
    case numericValueWithoutMeasurement(MetricAvailability)
}

/// One immutable metric reading.
///
/// Invariants (enforced by the factories and by decoding):
/// - `measured` and `estimated` always carry a finite `numericValue`;
///   `estimated` also names its `method`.
/// - Every other availability has no `numericValue`; `restricted` and
///   `unavailable` carry a non-empty `reason`.
public struct MetricReading: Equatable, Sendable {
    public let availability: MetricAvailability
    /// Present only for `measured` and `estimated`.
    public let numericValue: Double?
    /// Estimation method; required for `estimated`.
    public let method: String?
    /// Why the value is missing; required for `restricted` and
    /// `unavailable`, optional context elsewhere.
    public let reason: String?
    /// Provenance of the reading.
    public let source: MetricSource?

    private init(
        availability: MetricAvailability,
        numericValue: Double?,
        method: String?,
        reason: String?,
        source: MetricSource?
    ) {
        self.availability = availability
        self.numericValue = numericValue
        self.method = method
        self.reason = reason
        self.source = source
    }

    private static func validate(
        availability: MetricAvailability,
        numericValue: Double?,
        method: String?,
        reason: String?
    ) throws {
        switch availability {
        case .measured, .estimated:
            guard let value = numericValue else {
                throw MetricReadingError.missingNumericValue(availability)
            }
            guard value.isFinite else {
                throw MetricReadingError.nonFiniteValue(availability)
            }
            if availability == .estimated, method?.isEmpty != false {
                throw MetricReadingError.missingEstimationMethod
            }
        case .collecting, .gap, .unsupported:
            if numericValue != nil {
                throw MetricReadingError.numericValueWithoutMeasurement(availability)
            }
        case .restricted, .unavailable:
            if numericValue != nil {
                throw MetricReadingError.numericValueWithoutMeasurement(availability)
            }
            if reason?.isEmpty != false {
                throw MetricReadingError.missingReason(availability)
            }
        }
    }

    /// A directly measured value.
    public static func measured(
        _ value: Double,
        source: MetricSource? = nil
    ) throws -> MetricReading {
        guard value.isFinite else {
            throw MetricReadingError.nonFiniteValue(.measured)
        }
        return MetricReading(
            availability: .measured,
            numericValue: value, method: nil, reason: nil, source: source
        )
    }

    /// A value produced by a named estimation method rather than direct
    /// measurement.
    public static func estimated(
        _ value: Double,
        method: String,
        source: MetricSource? = nil
    ) throws -> MetricReading {
        guard value.isFinite else {
            throw MetricReadingError.nonFiniteValue(.estimated)
        }
        guard !method.isEmpty else {
            throw MetricReadingError.missingEstimationMethod
        }
        return MetricReading(
            availability: .estimated,
            numericValue: value, method: method, reason: nil, source: source
        )
    }

    /// No value yet; emitted until enough samples exist to compute a rate.
    public static func collecting(source: MetricSource? = nil) -> MetricReading {
        MetricReading(
            availability: .collecting,
            numericValue: nil, method: nil, reason: nil, source: source
        )
    }

    /// A break in the series; `reason` may name the missed interval.
    public static func gap(
        reason: String? = nil,
        source: MetricSource? = nil
    ) -> MetricReading {
        MetricReading(
            availability: .gap,
            numericValue: nil, method: nil, reason: reason, source: source
        )
    }

    /// The source failed in an unexplained way on this machine.
    public static func unavailable(
        reason: String,
        source: MetricSource? = nil
    ) throws -> MetricReading {
        guard !reason.isEmpty else {
            throw MetricReadingError.missingReason(.unavailable)
        }
        return MetricReading(
            availability: .unavailable,
            numericValue: nil, method: nil, reason: reason, source: source
        )
    }

    /// The source is gated by permissions, a helper or an entitlement.
    public static func restricted(
        reason: String,
        source: MetricSource? = nil
    ) throws -> MetricReading {
        guard !reason.isEmpty else {
            throw MetricReadingError.missingReason(.restricted)
        }
        return MetricReading(
            availability: .restricted,
            numericValue: nil, method: nil, reason: reason, source: source
        )
    }

    /// The hardware or OS version cannot provide this metric at all.
    public static func unsupported(
        reason: String? = nil,
        source: MetricSource? = nil
    ) -> MetricReading {
        MetricReading(
            availability: .unsupported,
            numericValue: nil, method: nil, reason: reason, source: source
        )
    }
}

extension MetricReading: Codable {
    private enum CodingKeys: String, CodingKey {
        case availability, numericValue, method, reason, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let availability = try container.decode(
            MetricAvailability.self, forKey: .availability
        )
        let numericValue = try container.decodeIfPresent(
            Double.self, forKey: .numericValue
        )
        let method = try container.decodeIfPresent(String.self, forKey: .method)
        let reason = try container.decodeIfPresent(String.self, forKey: .reason)
        let source = try container.decodeIfPresent(
            MetricSource.self, forKey: .source
        )

        do {
            try MetricReading.validate(
                availability: availability, numericValue: numericValue,
                method: method, reason: reason
            )
        } catch let error as MetricReadingError {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "invalid metric reading: \(error)"
                )
            )
        }

        self.init(
            availability: availability, numericValue: numericValue,
            method: method, reason: reason, source: source
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(availability, forKey: .availability)
        try container.encodeIfPresent(numericValue, forKey: .numericValue)
        try container.encodeIfPresent(method, forKey: .method)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(source, forKey: .source)
    }
}
