import Foundation
import CSQLite

public enum SQLiteValue: Equatable, Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null
}

public struct SQLiteError: Error, Equatable, Sendable {
    public let code: Int32
    public let message: String
}

/// One connection to the system SQLite, owned by a single actor. Every
/// statement is prepared and bound; SQL text never carries values.
public final class SQLiteConnection {
    // SQLITE_TRANSIENT: SQLite copies bound text before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var handle: OpaquePointer?

    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            let error = Self.error(handle, status)
            sqlite3_close_v2(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close_v2(handle) }

    /// Run SQL without parameters or results (schema, pragmas, transactions).
    public func execute(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw Self.error(handle, status) }
    }

    /// Run one prepared statement once per row of bindings.
    public func run(_ sql: String, rows: [[SQLiteValue]]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for row in rows {
            try bind(row, to: statement)
            let status = sqlite3_step(statement)
            guard status == SQLITE_DONE else { throw Self.error(handle, status) }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [[SQLiteValue]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw Self.error(handle, status) }
            rows.append((0..<sqlite3_column_count(statement)).map { column(statement, $0) })
        }
    }

    /// All or nothing: a thrown error rolls back, so a crash or failure
    /// never leaves half a batch or half a retention pass.
    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public var changes: Int { Int(sqlite3_changes(handle)) }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK else { throw Self.error(handle, status) }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32 = switch value {
            case .integer(let number): sqlite3_bind_int64(statement, index, number)
            case .real(let number): sqlite3_bind_double(statement, index, number)
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .null: sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else { throw Self.error(handle, status) }
        }
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, index)))
        default: return .null
        }
    }

    private static func error(_ handle: OpaquePointer?, _ code: Int32) -> SQLiteError {
        let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? String(cString: sqlite3_errstr(code))
        return SQLiteError(code: code, message: message)
    }
}
