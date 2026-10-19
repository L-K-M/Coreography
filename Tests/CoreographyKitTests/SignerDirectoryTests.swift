import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class SignerDirectoryTests: XCTestCase {
    /// Plan: an opt-in signing column. Each program is checked once; one
    /// that could not be checked is asked about again.
    func testEachProgramIsCheckedOnceAndAnUnreadableOneAgain() async {
        let driver = Signatures()
        let directory = SignerDirectory(driver: driver)
        let paths: Set<String> = ["/System/Applications/Mail.app/Contents/MacOS/Mail", "/opt/tool", "/gone"]

        let first = await directory.signers(for: paths)
        XCTAssertEqual(first, [
            "/System/Applications/Mail.app/Contents/MacOS/Mail": .apple, "/opt/tool": .developer(team: "ABCDE12345")
        ], "an unreadable signature is left out, not called unsigned")
        _ = await directory.signers(for: paths)
        let checks = await driver.checks
        XCTAssertEqual(checks["/opt/tool"], 1)
        XCTAssertEqual(checks["/gone"], 2)
    }
}

private actor Signatures: ProcessDetailReading {
    private(set) var checks: [String: Int] = [:]

    func arguments(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<[String], ProcessDetailError> {
        .failure(.unsupportedPlatform)
    }

    func signing(path: String) async -> CodeSigning {
        checks[path, default: 0] += 1
        switch path {
        case "/opt/tool": return CodeSigning(signature: .otherSigner, identifier: "com.example.tool", teamID: "ABCDE12345")
        case "/gone": return CodeSigning(signature: .unknown, identifier: nil, teamID: nil)
        default: return CodeSigning(signature: .apple, identifier: "com.apple.mail", teamID: nil)
        }
    }
}
