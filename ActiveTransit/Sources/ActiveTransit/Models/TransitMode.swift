import Foundation

public enum TransitMode: String, Codable, Hashable, Equatable, Sendable {
    case bus
    case tram
    case metro
    case rail
    case water
    case foot
    case unknown
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let rawValue = try? container.decode(String.self) {
            self = TransitMode(rawValue: rawValue.lowercased()) ?? .unknown
        } else {
            self = .unknown
        }
    }
    
    public init(safeRawValue: String) {
        self = TransitMode(rawValue: safeRawValue.lowercased()) ?? .unknown
    }
}
