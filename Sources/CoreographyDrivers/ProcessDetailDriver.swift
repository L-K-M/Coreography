import Foundation

#if os(macOS)
import Darwin
import Security
import CoreographySystem
#endif

public enum ProcessDetailError: Error, Equatable, Sendable {
    case unsupportedPlatform
    /// Gone, or the pid now names another process.
    case exited
    /// Another user's process; reading it needs the helper.
    case notPermitted
    case malformed
    case systemCall(code: Int32)
}

/// Who signed a program and as what.
public struct CodeSigning: Equatable, Sendable {
    public let signature: CodeSignature
    /// The signing identifier, e.g. `com.apple.Safari`.
    public let identifier: String?
    /// The developer team; Apple's own code has none.
    public let teamID: String?

    public init(signature: CodeSignature, identifier: String?, teamID: String?) {
        self.signature = signature
        self.identifier = identifier
        self.teamID = teamID
    }
}

public protocol ProcessDetailReading: Sendable {
    func arguments(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<[String], ProcessDetailError>
    func signing(path: String) async -> CodeSigning
    func threads(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<Int, ProcessDetailError>
}

extension ProcessDetailReading {
    /// Readers that cannot count threads say so.
    public func threads(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<Int, ProcessDetailError> {
        .failure(.unsupportedPlatform)
    }
}

/// Reads one process's arguments (never its environment) for the exact
/// identity the caller saw, and a program's code signature.
public actor ProcessDetailDriver: ProcessDetailReading {
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.process-detail")

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func arguments(
        pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64
    ) -> Result<[String], ProcessDetailError> {
        #if os(macOS)
        let capacity = coreo_process_arguments_capacity()
        guard capacity > 0 else { return .failure(.systemCall(code: EIO)) }
        var block = [UInt8](repeating: 0, count: Int(capacity))
        var length: Int32 = 0
        let status = block.withUnsafeMutableBufferPointer {
            coreo_process_arguments(pid, startSeconds, startMicroseconds, $0.baseAddress, capacity, &length)
        }
        switch status {
        case 0:
            guard let arguments = ProcessArguments.parse(Array(block.prefix(Int(length)))) else { return .failure(.malformed) }
            return .success(arguments)
        case ESRCH, EAGAIN: return .failure(.exited)
        case EPERM, EACCES: return .failure(.notPermitted)
        case ENOTSUP: return .failure(.unsupportedPlatform)
        default: return .failure(.systemCall(code: status))
        }
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    public func signing(path: String) -> CodeSigning {
        CodeSignatureReader.signing(path: path)
    }

    public func threads(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) -> Result<Int, ProcessDetailError> {
        #if os(macOS)
        var count: Int32 = 0
        switch coreo_process_threads(pid, startSeconds, startMicroseconds, &count) {
        case 0: return .success(Int(count))
        case ESRCH, EAGAIN: return .failure(.exited)
        case EPERM, EACCES: return .failure(.notPermitted)
        case ENOTSUP: return .failure(.unsupportedPlatform)
        case let status: return .failure(.systemCall(code: status))
        }
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }
}

/// Parses a `KERN_PROCARGS2` block:
///
/// ```text
/// [argc: int32][executable path]\0\0…[arg 0]\0[arg 1]\0…[environment, never read]
/// ```
public enum ProcessArguments {
    /// Enough for any command line a person reads; longer ones are cut.
    static let maximumCount = 512

    public static func parse(_ block: [UInt8]) -> [String]? {
        guard block.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = block.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < block.count, block[index] != 0 { index += 1 }
        while index < block.count, block[index] == 0 { index += 1 }

        var arguments: [String] = []
        let wanted = min(Int(argc), maximumCount)
        while arguments.count < wanted, index < block.count {
            let start = index
            while index < block.count, block[index] != 0 { index += 1 }
            arguments.append(String(decoding: block[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments.count == wanted ? arguments : nil
    }
}

/// Code signatures through the Security framework, with basic validation
/// only: checking every resource of a bundle would take seconds, and the
/// question is who signed it, not whether every file is intact.
public enum CodeSignatureReader {
    public static func signing(path: String) -> CodeSigning {
        #if os(macOS)
        var code: SecStaticCode?
        guard FileManager.default.fileExists(atPath: path),
              SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return CodeSigning(signature: .unknown, identifier: nil, teamID: nil) }

        var information: CFDictionary?
        let readInformation = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        let details = readInformation == errSecSuccess ? information as? [String: Any] : nil
        return CodeSigning(
            signature: signature(of: code),
            identifier: details?[kSecCodeInfoIdentifier as String] as? String,
            teamID: details?[kSecCodeInfoTeamIdentifier as String] as? String
        )
        #else
        return CodeSigning(signature: .unknown, identifier: nil, teamID: nil)
        #endif
    }

    #if os(macOS)
    private static func signature(of code: SecStaticCode) -> CodeSignature {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess else {
            return .unknown
        }
        switch SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), requirement) {
        case errSecSuccess: return .apple
        case errSecCSReqFailed: return .otherSigner
        case errSecCSUnsigned: return .unsigned
        default: return .unknown
        }
    }
    #endif
}
