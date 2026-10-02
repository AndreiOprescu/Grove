import Foundation

public enum ItemType: String, Codable, Sendable { case task, event, note }

public struct ItemRef: Hashable, Codable, Sendable {
    public var type: ItemType
    public var id: String
    public init(_ type: ItemType, _ id: String) { self.type = type; self.id = id }
}

public enum LinkOrigin: String, Sendable { case parsed, manual }

public struct LinkRecord: Hashable, Sendable {
    public var src: ItemRef
    public var dst: ItemRef
    public var origin: LinkOrigin
}
