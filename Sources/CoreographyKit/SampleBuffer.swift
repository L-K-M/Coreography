import Foundation

enum SampleBufferError: Error, Equatable, Sendable {
    /// Capacity must be at least one element.
    case invalidCapacity(Int)
}

/// Fixed-capacity ring of samples in chronological order.
///
/// Once full, appending overwrites the oldest element. Capacity is
/// validated before storage is allocated. Used to bound retained
/// snapshot frames (e.g. the in-memory "live" history tier).
struct SampleBuffer<Element: Sendable>: Sendable {
    /// Maximum number of retained elements.
    let capacity: Int
    private var storage: [Element?]
    /// Index of the oldest element; the next overwrite position when full.
    private var head = 0
    private var stored = 0

    init(capacity: Int) throws {
        guard capacity > 0 else {
            throw SampleBufferError.invalidCapacity(capacity)
        }
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    var count: Int { stored }
    var isEmpty: Bool { stored == 0 }
    var isFull: Bool { stored == capacity }

    /// All retained elements, oldest first.
    var elements: [Element] {
        var result: [Element] = []
        result.reserveCapacity(stored)
        for offset in 0..<stored {
            result.append(storage[(head + offset) % capacity]!)
        }
        return result
    }

    /// The most recently appended element.
    var last: Element? {
        guard stored > 0 else { return nil }
        return storage[(head + stored - 1) % capacity]
    }

    /// Append `element`; when full, evicts the oldest element.
    mutating func append(_ element: Element) {
        if stored < capacity {
            storage[(head + stored) % capacity] = element
            stored += 1
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Drop all retained elements; capacity is unchanged.
    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        stored = 0
    }
}
