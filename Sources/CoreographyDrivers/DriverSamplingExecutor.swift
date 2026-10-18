import Dispatch

/// Keep native scans on their driver's serial queue while preserving actor task context.
final class DriverSamplingExecutor: SerialExecutor {
    private let queue: DispatchQueue

    init(label: String) { queue = DispatchQueue(label: label) }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async { [self] in
            dispatchPrecondition(condition: .onQueue(queue))
            job.runSynchronously(on: asUnownedSerialExecutor())
        }
    }
}
