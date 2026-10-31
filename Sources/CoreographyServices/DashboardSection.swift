import Foundation

/// Window destinations also used by widgets and automation links.
public enum DashboardSection: String, CaseIterable, Identifiable, Sendable {
    case overview, cpu, memory, gpu, storage, network, power
    case processes, timeline, startup, recordings

    public var id: Self { self }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .storage: "Storage"
        case .network: "Network"
        case .power: "Power & Thermals"
        case .processes: "Processes"
        case .timeline: "Timeline"
        case .startup: "Startup"
        case .recordings: "Recordings"
        }
    }

    public var lanes: [LaneKind] {
        switch self {
        case .cpu: [.cpu]
        case .memory: [.memory]
        case .gpu: [.gpu]
        case .storage: [.disk]
        case .network: [.network]
        case .power: [.power, .thermal]
        default: []
        }
    }

    var detailPane: DetailPane? {
        switch self {
        case .network: .connections
        case .power: .sensors
        case .startup: .startup
        case .recordings: .sessions
        case .timeline: nil
        default: .processes
        }
    }

    init(pane: DetailPane) {
        switch pane {
        case .processes: self = .processes
        case .connections: self = .network
        case .startup: self = .startup
        case .sensors: self = .power
        case .sessions: self = .recordings
        }
    }

    public var url: URL {
        // Every component is a closed enum value, never user input.
        URL(string: "\(AutomationLink.scheme)://show/\(rawValue)")!
    }
}
