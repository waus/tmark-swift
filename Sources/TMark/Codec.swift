import Foundation

public struct TmarkCodec {
    public let registry: TmarkRegistry
    public init(registry: TmarkRegistry = .standard) { self.registry = registry }

    public func marshal(_ value: any TmarkValue) throws -> String {
        var writer = Writer(registry: registry)
        let result = try writer.value(value)
        // Validate total nesting, including raw unknown nodes and record fields.
        var parser = Parser(result)
        _ = try parser.parse()
        return result
    }
    public func unmarshal(_ data: String, soft: Bool = false) throws -> any TmarkValue {
        var parser = Parser(data)
        var decoder = Decoder(registry: registry, soft: soft)
        return try decoder.single(parser.parse())
    }
    public func unmarshalDocument(_ data: String, soft: Bool = false) throws -> Document {
        guard let document = try unmarshal(data, soft: soft) as? Document else {
            throw schemaError("expected document node")
        }
        return document
    }
}

public func marshal(_ value: any TmarkValue) throws -> String { try TmarkCodec().marshal(value) }
public func unmarshal(_ data: String, soft: Bool = false) throws -> any TmarkValue {
    try TmarkCodec().unmarshal(data, soft: soft)
}
public func unmarshalDocument(_ data: String, soft: Bool = false) throws -> Document {
    try TmarkCodec().unmarshalDocument(data, soft: soft)
}

struct Writer {
    let registry: TmarkRegistry
    var depth = 0
    mutating func nested<T>(_ operation: (inout Writer) throws -> T) throws -> T {
        depth += 1
        defer { depth -= 1 }
        guard depth <= tmarkMaxDepth else { throw schemaError("max depth exceeded") }
        return try operation(&self)
    }
    mutating func value(_ value: any TmarkValue, omitTag: Bool = false) throws -> String {
        if let text = value as? TText { return escape(text.text) }
        try validateNode(value)
        return try nested { writer in
            if let unknown = value as? Unknown {
                var parser = Parser(unknown.raw)
                _ = try parser.parseSingleNode()
                return unknown.raw
            }
            guard let schema = writer.registry.find(value) else { throw schemaError("unregistered type '\(type(of: value))'") }
            return try schema.write(value, &writer, omitTag)
        }
    }
}

func validateNode(_ value: any TmarkValue) throws {
    if let header = value as? Header, !(1...6).contains(header.size) { throw schemaError("header size must be 1..6") }
    if let item = value as? ListItem, let type = item.type, !["a", "A", "i", "I", "1", "checkbox"].contains(type) { throw schemaError("invalid list item type") }
    if let collage = value as? Collage, collage.children.contains(where: { !($0 is ImageNode || $0 is VideoNode) }) { throw schemaError("invalid collage child") }
    if let slideshow = value as? Slideshow, slideshow.children.contains(where: { !($0 is ImageNode || $0 is VideoNode) }) { throw schemaError("invalid slideshow child") }
}

func escape(_ input: String) -> String {
    var out = ""
    for c in input {
        if "#{}\\".contains(c) {
            out.append("\\")
        }
        out.append(c)
    }
    return out
}
