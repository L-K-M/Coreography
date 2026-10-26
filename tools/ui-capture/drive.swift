// Posts real pointer and key events at the CPU lane, as a person would,
// and takes a still after each step. The chart is found through
// Accessibility; layout estimates are the fallback, and both are logged.
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

func shot(_ name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    let rect = "\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))"
    process.arguments = ["-x", "-C", "-R\(rect)", "\(output)/shots/\(name).png"]
    try? process.run()
    process.waitUntilExit()
    log("still \(name)")
}

/// A 3 s profile of the app's threads in the background, for the slow steps.
func profile(_ name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    // The newest instance by process ID: one still quitting may share the name.
    let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "ch.lkmc.Coreography")
        .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }?.processIdentifier ?? 0
    process.arguments = ["-n", "/usr/bin/sample", "\(pid)", "3", "-mayDie", "-file", "\(output)/sample-\(name).txt"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    log("profile \(name)")
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

func cpuChart() -> CGRect? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "ch.lkmc.Coreography").first else { return nil }
    var queue: [(AXUIElement, Int)] = [(AXUIElementCreateApplication(app.processIdentifier), 0)]
    var candidates: [(CGRect, String)] = []
    var visited = 0
    while !queue.isEmpty, visited < 4000 {
        let (element, depth) = queue.removeFirst()
        visited += 1
        let label = text(element)
        if let rect = frame(element), label.localizedCaseInsensitiveContains("CPU"),
           rect.width > 300, (50...300).contains(rect.height), rect.minY < 420 {
            candidates.append((rect, label))
        }
        guard depth < 40, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
        queue += children.map { ($0, depth + 1) }
    }
    for (rect, label) in candidates { log("chart candidate \(rect) \(label)") }
    return candidates.min { $0.0.minY < $1.0.minY }?.0
}

/// The app's windows as Accessibility sees them, identifier included.
func logWindows() {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "ch.lkmc.Coreography").first,
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
    case u = 32, returnKey = 36, escape = 53, left = 123, right = 124, down = 125, up = 126
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
let estimate = CGRect(x: 244, y: 147, width: 640, height: 104)
let found = cpuChart()
let chart = found ?? estimate
log("CPU chart \(found == nil ? "estimated" : "found") at \(chart)")
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
log("done")
