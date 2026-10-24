import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class ConnectionDomainTests: XCTestCase {
    private func connection(pid: Int32 = 42, remote: String, port: UInt16 = 443) -> CapturedConnection {
        ConnectionReading(
            process: try! ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0),
            processName: "App", descriptor: Int32(port), transport: .tcp, state: .established,
            local: ConnectionEndpoint(address: "10.0.0.2", port: 50000),
            remote: ConnectionEndpoint(address: remote, port: port)
        )
    }

    private func snapshot(_ connections: [CapturedConnection]) -> CapturedConnections {
        ConnectionSnapshot(
            takenAt: Date(), connections: connections,
            restrictedProcesses: 0, truncatedProcesses: 0, failedProcesses: 0, unavailableReason: nil
        )
    }

    func testDomainDerivesTheRegistrablePart() {
        XCTAssertEqual(DomainName.domain(of: "server-99-163.fra56.r.cloudfront.net"), "cloudfront.net")
        XCTAssertEqual(DomainName.domain(of: "gateway-carry.servers.push.apple.com"), "apple.com")
        XCTAssertEqual(DomainName.domain(of: "edge.example.co.uk"), "example.co.uk")
        XCTAssertEqual(DomainName.domain(of: "www.example.co.jp"), "example.co.jp")
        XCTAssertEqual(DomainName.domain(of: "localhost"), "localhost")
        XCTAssertEqual(DomainName.domain(of: "17.253.144.10"), "17.253.144.10")
    }

    func testConnectedSocketsGroupByDomainThenServer() {
        let apps = ConnectionGroups.apps(
            in: snapshot([
                connection(remote: "10.0.0.9", port: 5223),
                connection(remote: "17.57.150.88", port: 443),
                connection(remote: "17.178.96.59", port: 443)
            ]),
            processes: nil, matching: "",
            serverNames: [
                "17.57.150.88": "gateway-carry.servers.push.apple.com",
                "17.178.96.59": "gateway.push.apple.com"
            ]
        )
        XCTAssertEqual(
            apps.first?.connected.map { $0.remote!.address },
            ["10.0.0.9", "17.57.150.88", "17.178.96.59"],
            "apple.com peers group ahead of later sort keys; within the domain, servers order by name"
        )
    }

    func testFilterMatchesResolvedNames() {
        let apps = ConnectionGroups.apps(
            in: snapshot([connection(remote: "17.57.150.88")]),
            processes: nil, matching: "apple",
            serverNames: ["17.57.150.88": "gateway.push.apple.com"]
        )
        XCTAssertEqual(apps.first?.connected.count, 1, "a resolved name is searchable text")
        XCTAssertTrue(
            ConnectionGroups.apps(
                in: snapshot([connection(remote: "17.57.150.88")]),
                processes: nil, matching: "apple", serverNames: [:]
            ).isEmpty,
            "the bare address does not match the domain word"
        )
    }
}
