// Posts real pointer and key events at the CPU lane, as a person would,
// and takes a still after each step. Chart identifiers make a missing
// target fail rather than sending gestures to an estimated rectangle.
import AppKit
import ApplicationServices
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let started = Date()
/// The region the stills cover: the window's top lanes and the card's reach.
let region = CGRect(x: 0, y: 25, width: 1024, height: 560)

func log(_ message: String) {
    print(String(format: "%6.2f s  ", Date().timeIntervalSince(started)) + message)
    fflush(stdout)
}

func pause(_ seconds: Double) { usleep(UInt32(seconds * 1_000_000)) }

/// The newest instance: one still quitting may share the bundle identifier.
func coreography() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "ch.lkmc.Coreography")
        .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
}

/// The whole placed window, for lanes below the top ones.
let window = CGRect(x: 0, y: 25, width: 1024, height: 743)

func shot(_ name: String, of area: CGRect = region) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    let rect = "\(Int(area.minX)),\(Int(area.minY)),\(Int(area.width)),\(Int(area.height))"
    process.arguments = ["-x", "-C", "-R\(rect)", "\(output)/shots/\(name).png"]
    do {
        try process.run()
        process.waitUntilExit()
        log(process.terminationStatus == 0 ? "still \(name)" : "still \(name) failed with status \(process.terminationStatus)")
    } catch {
        log("still \(name) could not start: \(error)")
    }
}

/// A 3 s profile of the app's threads in the background, for the slow steps.
func profile(_ name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    guard let pid = coreography()?.processIdentifier else {
        log("profile \(name) skipped: Coreography is not running")
        return
    }
    process.arguments = ["-n", "/usr/bin/sample", "\(pid)", "3", "-mayDie", "-file", "\(output)/sample-\(name).txt"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { task in
        if task.terminationStatus != 0 { log("profile \(name) failed with status \(task.terminationStatus)") }
    }
    do {
        try process.run()
        log("profile \(name)")
    } catch {
        log("profile \(name) could not start: \(error)")
    }
}

// MARK: Finding the CPU chart

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    // swiftlint:disable force_cast
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

func text(_ element: AXUIElement) -> String {
    [kAXRoleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXLabelValueAttribute]
        .compactMap { attribute(element, $0) as? String }.joined(separator: " | ")
}

/// The first element whose Accessibility text contains every fragment.
func element(containing fragments: [String] = [], identifier: String? = nil) -> AXUIElement? {
    guard let app = coreography() else { return nil }
    var queue: [(AXUIElement, Int)] = [(AXUIElementCreateApplication(app.processIdentifier), 0)]
    var visited = 0
    while !queue.isEmpty, visited < 6000 {
        let (element, depth) = queue.removeFirst()
        visited += 1
        let label = text(element)
        let matchesIdentifier = identifier == nil || attribute(element, kAXIdentifierAttribute) as? String == identifier
        if matchesIdentifier, fragments.allSatisfy({ label.localizedCaseInsensitiveContains($0) }) { return element }
        guard depth < 40, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
        queue += children.map { ($0, depth + 1) }
    }
    return nil
}

/// A short film of one step, beside the main recording.
func film(_ name: String, seconds: Int) -> Process? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    let rect = "\(Int(window.minX)),\(Int(window.minY)),\(Int(window.width)),\(Int(window.height))"
    process.arguments = ["-x", "-C", "-V", "\(seconds)", "-R\(rect)", "\(output)/\(name).mov"]
    do {
        try process.run()
        return process
    } catch {
        log("film \(name) could not start: \(error)")
        return nil
    }
}

func cpuChart() -> CGRect? {
    element(identifier: "cpu-chart").flatMap(frame)
}

/// The app's windows as Accessibility sees them, identifier included.
func logWindows() {
    guard let app = coreography(),
          let windows = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement]
    else { return }
    for window in windows {
        let identifier = attribute(window, kAXIdentifierAttribute) as? String ?? "none"
        log("window \(text(window)) identifier \(identifier)")
    }
}

// MARK: Input

let source = CGEventSource(stateID: .hidSystemState)

func mouse(_ type: CGEventType, _ point: CGPoint, flags: CGEventFlags = []) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
}

func move(from start: CGPoint, to end: CGPoint, seconds: Double, dragging: Bool = false) {
    let steps = max(1, Int(seconds * 60))
    for step in 1...steps {
        let t = Double(step) / Double(steps)
        let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        mouse(dragging ? .leftMouseDragged : .mouseMoved, point)
        pause(seconds / Double(steps))
    }
}

func click(_ point: CGPoint) {
    mouse(.mouseMoved, point)
    pause(0.05)
    mouse(.leftMouseDown, point)
    pause(0.06)
    mouse(.leftMouseUp, point)
}

enum Key: CGKeyCode {
    case zero = 29, u = 32, returnKey = 36, escape = 53, left = 123, right = 124, down = 125, up = 126
}

func press(_ key: Key, flags: CGEventFlags = []) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        pause(0.04)
    }
    log("key \(key)")
}

// MARK: The scenario

// Without Accessibility trust posted events are dropped silently: a film of
// nothing happening must not pass for a test.
guard AXIsProcessTrusted() else {
    log("error: this process is not trusted for Accessibility; no events can be posted")
    exit(1)
}
logWindows()

enum Destination: String, CaseIterable {
    case overview, cpu, memory, gpu, storage, network, power, processes, timeline, startup, recordings
}

func waitForDestination(_ section: Destination) {
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        if element(identifier: "section-heading-\(section.rawValue)") != nil { return }
        pause(0.1)
    }
    log("error: destination \(section.rawValue) did not appear")
    exit(1)
}

func navigate(to section: Destination) {
    guard let url = URL(string: "coreography://show/\(section.rawValue)"), NSWorkspace.shared.open(url) else {
        log("error: could not open destination \(section.rawValue)")
        exit(1)
    }
    waitForDestination(section)
    log("destination \(section.rawValue) visible")
}

// Check the new destinations before exercising the existing chart gestures.
for section in Destination.allCases { navigate(to: section) }
navigate(to: .overview)
shot("00-overview", of: window)
guard let card = element(identifier: "overview-cpu"), let cardFrame = frame(card) else {
    log("error: Overview has no CPU card")
    exit(1)
}
click(CGPoint(x: cardFrame.midX, y: cardFrame.midY))
waitForDestination(.cpu)
shot("00-cpu-detail", of: window)

guard let chart = cpuChart() else {
    log("error: CPU chart not found on the CPU destination")
    exit(1)
}
log("CPU chart found at \(chart)")
// The plot leaves room for the axis labels: trailing values, dates below.
let plot = CGRect(x: chart.minX + 4, y: chart.minY + 6, width: chart.width - 110, height: chart.height - 28)
func at(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: plot.minX + plot.width * x, y: plot.minY + plot.height * y)
}

shot("00-rest")
profile("idle")
pause(3.2)
profile("hover")
move(from: at(0.3, 0.85), to: at(0.85, 0.85), seconds: 2.0)
shot("01-hover")
// Hovering redraws the toolbar's cursor text on every move, which this
// runner's three cores take a while to catch up with (on main as well).
pause(3)

// Pull: press low on the braid and lift 80 pt.
let grip = at(0.8, 0.85)
mouse(.mouseMoved, grip)
pause(0.2)
profile("pull")
mouse(.leftMouseDown, grip)
log("press for pull at \(grip)")
move(from: grip, to: CGPoint(x: grip.x, y: grip.y - 30), seconds: 0.4, dragging: true)
shot("02-pulling")
move(from: CGPoint(x: grip.x, y: grip.y - 30), to: CGPoint(x: grip.x - 12, y: grip.y - 80), seconds: 0.6, dragging: true)
shot("03-pulled")
mouse(.leftMouseUp, CGPoint(x: grip.x - 12, y: grip.y - 80))
log("release")
pause(0.4)
shot("04-latched")

profile("open")
// Point along the open lens: focus follows the strand under the pointer.
let lensX = grip.x - 12
move(from: CGPoint(x: lensX, y: grip.y - 80), to: CGPoint(x: lensX, y: plot.maxY - 4), seconds: 1.2)
shot("04b-pointer-focus")

press(.up)
pause(0.3)
shot("05-focus")
press(.left, flags: .maskAlternate)
pause(0.4)
shot("06-peak")
press(.returnKey)
shot("07a-glint")
pause(0.15)
shot("07b-glint")
pause(0.4)
shot("07-scoped")

press(.escape)
for name in ["08-fold-a", "08-fold-b", "08-fold-c"] {
    shot(name)
}
pause(0.5)
shot("09-folded")

click(at(0.6, 0.7))
log("click to open")
pause(0.4)
shot("10-click-open")
press(.u)
pause(0.5)
shot("11-u-fold")

// A horizontal drag still selects a range, never pulls.
let from = at(0.4, 0.6)
mouse(.mouseMoved, from)
pause(0.1)
mouse(.leftMouseDown, from)
move(from: from, to: at(0.6, 0.62), seconds: 0.6, dragging: true)
mouse(.leftMouseUp, at(0.6, 0.62))
log("range drag")
pause(0.6)
shot("12-range")

press(.escape)
pause(0.4)
shot("13-escape")
mouse(.mouseMoved, CGPoint(x: 20, y: 700))

// Leaving an open braid must not send the investigation back to live.
press(.zero, flags: .maskCommand)
waitForDestination(.timeline)
navigate(to: .cpu)
press(.u)
pause(0.5)
navigate(to: .memory)
guard element(containing: ["Held display"]) != nil else {
    log("error: leaving the CPU braid lost its held investigation")
    exit(1)
}
shot("14-held-memory", of: window)
press(.zero, flags: .maskCommand)
waitForDestination(.timeline)
log("braid done")

// MARK: The space braid

navigate(to: .storage)

// The startup volume's rope sits on the Storage page; scroll it into view if needed.
let ropeFragments = ["free", "used of"]
/// Scrolls the lanes until the rope is in the window's middle, by Accessibility
/// first and by posted wheel events where SwiftUI does not offer that. The
/// wheel's sign depends on the runner's natural-scrolling setting, so it
/// flips whenever a notch took the rope further away.
func visibleRope(_ rope: AXUIElement) -> CGRect? {
    var lines: Int32 = 0
    var lastDistance = CGFloat.infinity
    for attempt in 0..<24 {
        guard let rect = frame(rope) else { return nil }
        // The middle, not just inside: lines above the rope re-wrap as samples
        // arrive and move it by a line or two.
        if window.insetBy(dx: 0, dy: window.height / 4).contains(rect) { return rect }

        let distance = abs(rect.midY - window.midY)
        log("rope at \(rect), attempt \(attempt)")
        if attempt == 0 {
            AXUIElementPerformAction(rope, "AXScrollToVisible" as CFString)
        } else {
            if lines == 0 {
                lines = rect.midY > window.midY ? -10 : 10
            } else if distance > lastDistance {
                lines = -lines
            }
            mouse(.mouseMoved, CGPoint(x: window.midX, y: window.midY))
            CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
        }
        lastDistance = distance
        pause(0.5)
    }
    return nil
}

// A rope that cannot be driven fails the capture: a run without the space
// stills must not pass for one that filmed them.
guard let rope = element(containing: ropeFragments) else {
    log("error: no space rope found through Accessibility")
    exit(1)
}
guard let rect = visibleRope(rope) else {
    log("error: the space rope could not be scrolled into the window")
    exit(1)
}

log("space rope at \(rect)")
shot("20-space-rest", of: window)
/// The rope's centre now, as the layout may have moved it since the last look.
func ropeCenter() -> CGPoint {
    let now = frame(rope) ?? rect
    return CGPoint(x: now.midX, y: now.midY)
}
let hover = ropeCenter()
move(from: CGPoint(x: hover.x + 80, y: hover.y), to: hover, seconds: 0.4)
shot("21-space-hover", of: window)
let opening = film("space-open", seconds: 4)
pause(0.5)
let target = ropeCenter()
click(target)
log("click the rope at \(target)")
pause(0.12)
shot("22-space-unbraiding", of: window)
pause(0.6)
shot("23-space-open", of: window)
opening?.waitUntilExit()
guard element(containing: ["What takes up space"]) != nil else {
    log("error: the space lens did not open")
    exit(1)
}
// Walking the runner's folders takes a while; Xcode alone is huge.
for (wait, label) in [(15.0, "15s"), (30.0, "45s"), (45.0, "90s")] {
    pause(wait)
    shot("24-space-\(label)", of: window)
}
press(.down)
press(.down)
pause(0.3)
shot("25-space-focus", of: window)
press(.escape)
pause(0.5)
shot("26-space-closed", of: window)
log("done")
