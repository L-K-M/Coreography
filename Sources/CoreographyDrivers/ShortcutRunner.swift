import Foundation

public enum ShortcutError: Error, Equatable, Sendable {
    case invalidName
    case unavailable(String)
    case failed(Int32)
    case timedOut
}

public protocol ShortcutRunning: Sendable {
    func list() async -> Result<[String], ShortcutError>
    func run(_ name: String) async -> Result<Void, ShortcutError>
}

/// Runs the person's own Shortcuts through `/usr/bin/shortcuts`, with the
/// name as one argument (no shell), a time limit and an output cap
/// (plan: alert action "run a Shortcut").
public struct ShortcutRunner: ShortcutRunning {
    private static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
    /// A Shortcut may wait on the network or a dialog; longer is a hang.
    private static let runTimeout: Duration = .seconds(60)
    private static let listTimeout: Duration = .seconds(10)
    private static let keepBytes = 256 * 1024
    /// Shortcut names are short; a longer one is not a name.
    static let maximumNameLength = 256
    private let runner = BoundedCommandRunner()

    public init() {}

    public func list() async -> Result<[String], ShortcutError> {
        switch await execute(["list"], timeout: Self.listTimeout) {
        case .failure(let error): return .failure(error)
        case .success(let output):
            let names = String(decoding: output, as: UTF8.self)
                .split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            return .success(names)
        }
    }

    public func run(_ name: String) async -> Result<Void, ShortcutError> {
        guard Self.isValid(name) else { return .failure(.invalidName) }
        return await execute(["run", name], timeout: Self.runTimeout).map { _ in () }
    }

    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= maximumNameLength
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private func execute(_ arguments: [String], timeout: Duration) async -> Result<Data, ShortcutError> {
        #if os(macOS)
        do {
            let output = try await runner.run(Self.executable, arguments: arguments, timeout: timeout, keepBytes: Self.keepBytes)
            if output.timedOut { return .failure(.timedOut) }
            guard output.exitStatus == 0 else { return .failure(.failed(output.exitStatus)) }
            return .success(output.data)
        } catch {
            return .failure(.unavailable("The shortcuts tool could not start"))
        }
        #else
        return .failure(.unavailable("Shortcuts need macOS"))
        #endif
    }
}
