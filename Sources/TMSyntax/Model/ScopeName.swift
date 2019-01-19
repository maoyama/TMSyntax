import Foundation

public struct ScopeName :
    Equatable,
    CustomStringConvertible,
    Decodable
{
    public var parts: [String]
    
    public init(_ string: String) {
        self.init(parts: string.components(separatedBy: "."))
    }
    
    public init(parts: [String]) {
        self.parts = parts
    }
    
    public var stringValue: String {
        get {
            return parts.joined(separator: ".")
        }
        set {
            self = ScopeName(newValue)
        }
    }
    
    public var description: String {
        return stringValue
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let str = try c.decode(String.self)
        self.init(str)
    }
}

extension ScopeName : CustomReflectable {
    public var customMirror: Mirror {
        return Mirror(self, unlabeledChildren: [])
    }
}