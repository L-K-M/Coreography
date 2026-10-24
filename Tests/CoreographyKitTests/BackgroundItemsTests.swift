import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class BackgroundItemsTests: XCTestCase {
    /// The shape `sfltool dumpbtm` prints: per-UID sections, records marked
    /// by bare "#N" lines, "(null)" for absent values, embedded items as
    /// "#N: child" lines that must not split a record.
    private let dump = """
        Opened /private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v7.btm

        ========================
         Records for UID 501 : 1CAA5D2B-A526-49E2-9A6F-58CACBDF0AFB
        ========================

        #1
         UUID:              68D88F8B-A750-4A4D-AD31-520E2436FE9F
         Name:              LuLu
         Developer Name:    (null)
         Team Identifier:   VBG97UB4TA
         Type:              app (0x2)
         Disposition:       [enabled allowed visible notified] (11)
         Identifier:        com.objective-see.lulu.app
         URL:               file:///Applications/LuLu.app/
         Executable Path:   (null)
         Generation:        2
         Parent Identifier: (null)

        #2
         UUID:              FEE750CF-984A-463D-BCDD-9CAD067EC6BF
         Name:              WireGuardLoginItemHelper
         Developer Name:    (null)
         Team Identifier:   L82V4Y2P3C
         Type:              login item (0x4)
         Disposition:       [disabled, allowed, visible, notified] (10)
         Identifier:        anchor apple generic and identifier "com.wireguard.macos.login-item-helper" and certificate leaf[subject.OU] = L82V4Y2P3C
         URL:               (null)
         Generation:        2
         Bundle Identifier: com.wireguard.macos.login-item-helper
         Executable Path:   /Applications/WireGuard.app/Contents/Library/LoginItems/WireGuardLoginItemHelper
         Embedded Item Identifiers:
            #1: us.wireguard.anchored-child

        ========================
         Records for UID 0 : 4E2B7B5E-1111-2222-3333-444455556666
        ========================

        #1
         UUID:              17A60CB8-537A-44D1-A6F8-2EBD22439076
         Name:              AGSService
         Developer Name:    Adobe Creative Cloud
         Team Identifier:   JQ525L2MZD
         Type:              curated legacy daemon (0x90010)
         Disposition:       [enabled allowed visible notified] (11)
         Identifier:        Adobe_Genuine_Software_Integrity_Service
         URL:               file:///Library/LaunchDaemons/com.adobe.agsservice.plist
         Executable Path:   /Library/Application Support/Adobe/AdobeGCClient/AGSService
         Generation:        1

        #2
         UUID:              99999999-0000-1111-2222-333344445555
         Name:              WindowShim
         Developer Name:    Apple
         Team Identifier:   (null)
         Type:              login item (0x4)
         Disposition:       (13)
         Identifier:        com.apple.windowshim
         URL:               file:///System/Library/PrivateFrameworks/Shim.framework/Shim.app/
         Executable Path:   /System/Library/PrivateFrameworks/Shim.framework/Shim.app/Contents/MacOS/Shim
        """

    func testDumpParsesPerUserRecordsWithKindsStatesAndOwners() {
        let items = BackgroundItems.items(in: dump)
        XCTAssertEqual(items.count, 4, "every bare-#N record is an item; embedded #N: lines are not")
        XCTAssertEqual(items.map(\.kind), [.backgroundItem, .loginItem, .daemon, .loginItem])
        XCTAssertEqual(items.map(\.ownerUID), [501, 501, 0, 0])
        XCTAssertEqual(items.map(\.state), [.enabled, .disabled, .enabled, .enabled])
    }

    func testLabelsPreferBundleIdentifiersAndPathsComeFromURLs() throws {
        let items = BackgroundItems.items(in: dump)
        let wireguard = try XCTUnwrap(items.first { $0.label == "com.wireguard.macos.login-item-helper" },
                                      "the Bundle Identifier names an item whose Identifier is a code requirement")
        XCTAssertEqual(wireguard.plistPath, "btm:FEE750CF-984A-463D-BCDD-9CAD067EC6BF", "a null URL keeps the record under its UUID")
        XCTAssertEqual(wireguard.program, "/Applications/WireGuard.app/Contents/Library/LoginItems/WireGuardLoginItemHelper")

        let lulu = try XCTUnwrap(items.first { $0.label == "com.objective-see.lulu.app" })
        XCTAssertEqual(lulu.plistPath, "/Applications/LuLu.app/")
        XCTAssertNil(lulu.program, "(null) is not a program path")
    }

    func testAppleRecordsAreMarkedAndADispositionMaskDecodes() throws {
        let items = BackgroundItems.items(in: dump)
        let shim = try XCTUnwrap(items.first { $0.label == "com.apple.windowshim" })
        XCTAssertTrue(shim.isApple, "Apple developer and a /System path")
        XCTAssertEqual(shim.state, .enabled, "(13) has the enabled bit set")
        XCTAssertEqual(items.filter(\.isApple).count, 1)
    }

    func testUnknownDispositionsStayUnconfirmed() {
        let bare = """
            #1
             UUID:              00000000-0000-0000-0000-000000000001
             Name:              Mystery
             Type:              login item (0x4)
            """
        let item = BackgroundItems.items(in: bare).first
        XCTAssertEqual(item?.state, .unconfirmed)
        XCTAssertEqual(item?.ownerUID, nil, "outside a UID section the owner is unknown")
    }

    private struct Listed: LaunchJobReading {
        var jobs: [RawLaunchJob] = []
        var overrides: [LaunchOverrideDomain: [String: Bool]] = [:]
        func read() async -> RawLaunchJobs {
            RawLaunchJobs(jobs: jobs, unreadable: 0, overrides: overrides, overridesProblem: nil)
        }
    }

    func testRecordsAlreadyListedFromTheirPlistsAreSkipped() async {
        let dump = self.dump
        let provider = StartupProvider(driver: Listed(jobs: [RawLaunchJob(
            domain: .daemons, plistPath: "/Library/LaunchDaemons/com.adobe.agsservice.plist",
            label: "com.adobe.agsservice", program: "/opt/ags", runAtLoad: true, keepAlive: false,
            disabledInPlist: true, signature: .unknown
        )], overrides: [.system: ["com.adobe.agsservice": false]]), backgroundDump: { .success(dump) })
        let inventory = await provider.load()
        let adobe = inventory.items.filter { $0.plistPath == "/Library/LaunchDaemons/com.adobe.agsservice.plist" }
        XCTAssertEqual(adobe.count, 1, "the plist listing wins; the BTM record adds nothing")
        XCTAssertEqual(adobe.first?.state, .enabled, "launchd's override, not the record's disposition")
        XCTAssertNil(inventory.loginItemsProblem)
        XCTAssertEqual(inventory.items.filter { $0.kind == .loginItem }.count, 2)
    }

    func testHelperFailureAndAbsenceLeaveTheRightNote() async {
        let failed = await StartupProvider(
            driver: Listed(),
            backgroundDump: { .failure(HelperReadFailure(reason: "sfltool exited with status 1")) }
        ).load()
        XCTAssertEqual(failed.loginItemsProblem, "Login and background items could not be read: sfltool exited with status 1")

        let absent = await StartupProvider(driver: Listed()).load()
        XCTAssertEqual(absent.loginItemsProblem, StartupInventory.loginItemsUnavailable)
    }

    func testTheHandlerAnswersWithTheDumpTextAndCapsIt() async throws {
        let handler = HelperRequestHandler(readBackgroundItems: { .success("dump text") })
        let reply = try HelperWire.decode(HelperReply.self, from: await handler.reply(to: HelperWire.encode(HelperRequest.backgroundItems)))
        XCTAssertEqual(reply, .backgroundItems("dump text"))

        let failed = HelperRequestHandler()
        let refusal = try HelperWire.decode(HelperReply.self, from: await failed.reply(to: HelperWire.encode(HelperRequest.backgroundItems)))
        guard case .backgroundItemsFailed(let reason) = refusal else { return XCTFail("a failure reason was expected") }
        XCTAssertFalse(reason.isEmpty)

        let huge = HelperRequestHandler(readBackgroundItems: { .success(String(repeating: "x", count: HelperReply.maximumBytes)) })
        let message = await huge.reply(to: HelperWire.encode(HelperRequest.backgroundItems))
        XCTAssertLessThanOrEqual(message.count, HelperReply.maximumBytes + 4096, "the reply fits its cap")
        guard case .backgroundItems(let kept) = try HelperWire.decode(HelperReply.self, from: message) else {
            return XCTFail("a dump was expected")
        }
        XCTAssertTrue(kept.hasSuffix("[The output was cut to fit the helper's reply.]"))
    }
}
