import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class PrivilegedHelperTests: XCTestCase {
    private static let team = "AB12CD34EF"

    func testRequirementPinsTheTeamAndIdentifier() {
        XCTAssertEqual(
            HelperWire.peerRequirement(identifier: HelperWire.appIdentifier, teamID: Self.team),
            #"anchor apple generic and identifier "ch.lkmc.Coreography" and certificate leaf[subject.OU] = "AB12CD34EF""#
        )
        for team in [nil, "", "ab12cd34ef", "AB12CD34E", #"AB12CD34EF" or anchor trusted"#] {
            XCTAssertNil(HelperWire.peerRequirement(identifier: HelperWire.appIdentifier, teamID: team), "\(team ?? "nil")")
        }
        for identifier in ["", #"ch.lkmc.Coreography" or anchor trusted"#, "-x", "a b"] {
            XCTAssertNil(HelperWire.peerRequirement(identifier: identifier, teamID: Self.team), identifier)
        }
    }

    func testHandlerAnswersHelloAndRefusesAnythingElse() throws {
        let handler = HelperRequestHandler()
        XCTAssertEqual(
            try HelperWire.decode(HelperReply.self, from: handler.reply(to: HelperWire.encode(HelperRequest.hello))),
            .hello(protocolVersion: HelperWire.protocolVersion)
        )

        let unknown = Data(#"{"run":{"path":"/bin/sh","arguments":["-c","id"]}}"#.utf8)
        guard case .refused = try HelperWire.decode(HelperReply.self, from: handler.reply(to: unknown)) else {
            return XCTFail("an unknown request must be refused")
        }
        let huge = Data(repeating: 0x20, count: HelperRequest.maximumBytes + 1)
        XCTAssertEqual(
            try HelperWire.decode(HelperReply.self, from: handler.reply(to: huge)),
            .refused("The request is larger than \(HelperRequest.maximumBytes) bytes.")
        )
    }

    func testStateFollowsRegistrationThenTheHello() async {
        let unsigned = PrivilegedHelper(registration: Registration(.enabled), transport: Answer(), teamID: nil)
        let unsignedState = await unsigned.state()
        XCTAssertEqual(unsignedState, .needsSignedBuild)

        let cases: [(HelperRegistrationStatus, any HelperTransport, HelperState)] = [
            (.notFound, Answer(), .missingFromApp),
            (.notRegistered, Answer(), .notInstalled),
            (.requiresApproval, Answer(), .awaitingApproval),
            (.enabled, Answer(), .ready),
            (.unknown, Answer(), .notResponding("macOS reported a registration state this version does not know.")),
            (.enabled, Reply(.hello(protocolVersion: 99)), .outdated(protocolVersion: 99)),
            (.enabled, Reply(.refused("busy")), .notResponding("busy")),
            (.enabled, Failing(.timedOut), .notResponding("It did not answer in time.")),
            (.enabled, Garbage(), .notResponding("Its answer could not be read."))
        ]
        for (status, transport, expected) in cases {
            let state = await PrivilegedHelper(registration: Registration(status), transport: transport, teamID: Self.team).state()
            XCTAssertEqual(state, expected, "\(status)")
        }
    }

    func testAnUnsignedBuildNeverRegisters() async {
        let registration = Registration(.notRegistered)
        let helper = PrivilegedHelper(registration: registration, transport: Answer(), teamID: nil)
        do {
            try await helper.install()
            XCTFail("an unsigned build must not register")
        } catch {
            XCTAssertEqual(error, .needsSignedBuild)
        }
        XCTAssertEqual(registration.registered, 0)
    }
}

private final class Registration: HelperRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var current: HelperRegistrationStatus
    private var registrations = 0

    init(_ status: HelperRegistrationStatus) { current = status }

    var registered: Int { lock.withLock { registrations } }

    func status() -> HelperRegistrationStatus { lock.withLock { current } }

    func register() throws {
        lock.withLock {
            registrations += 1
            current = .requiresApproval
        }
    }

    func unregister() async throws { lock.withLock { current = .notRegistered } }

    func openApprovalSettings() {}
}

/// Answers the way the real handler does.
private struct Answer: HelperTransport {
    func exchange(_ message: Data) async throws -> Data { HelperRequestHandler().reply(to: message) }
}

private struct Reply: HelperTransport {
    let reply: HelperReply
    init(_ reply: HelperReply) { self.reply = reply }
    func exchange(_ message: Data) async throws -> Data { HelperWire.encode(reply) }
}

private struct Failing: HelperTransport {
    let error: HelperTransportError
    init(_ error: HelperTransportError) { self.error = error }
    func exchange(_ message: Data) async throws -> Data { throw error }
}

private struct Garbage: HelperTransport {
    func exchange(_ message: Data) async throws -> Data { Data("not json".utf8) }
}
