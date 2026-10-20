import Foundation
import CoreographyDrivers

// The privileged helper: a launch daemon serving HelperRequest values to
// the Coreography app only. It refuses to start without a team ID, since
// an ad-hoc build has no signature its clients could be checked against.
#if os(macOS)
let teamID = CodeSignatureReader.signing(path: Bundle.main.executablePath ?? CommandLine.arguments[0]).teamID
guard let requirement = HelperWire.peerRequirement(identifier: HelperWire.appIdentifier, teamID: teamID) else {
    FileHandle.standardError.write(Data("CoreographyHelper: this build has no Developer ID team to check clients against; not listening.\n".utf8))
    exit(EXIT_FAILURE)
}
HelperXPCListener(requirement: requirement, handler: HelperRequestHandler()).run()
#else
FileHandle.standardError.write(Data("CoreographyHelper: requires macOS.\n".utf8))
exit(EXIT_FAILURE)
#endif
