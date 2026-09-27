import Foundation

struct Decoder {
    let registry: TmarkRegistry
    let soft: Bool

    mutating func concrete(_ node: ParsedNode, _ schema: AnyNodeType) throws -> any TmarkValue {
        var parser = Parser(String(node.raw.dropFirst().dropLast()))
        let value = try schema.read(parser.parse(), &self)
        try validateNode(value)
        return value
    }

    mutating func single(_ parts: [Part]) throws -> any TmarkValue {
        let clean = dropNl(parts)
        if clean.count == 1, case .text(let text) = clean[0] { return TText(text) }
        guard case .node(let node)? = singleNode(clean) else { throw schemaError("expected single value") }
        guard let schema = registry.find(node.tag) else {
            if soft, !node.tag.isEmpty { return Unknown(node.raw) }
            throw schemaError("unknown tag '\(node.tag)'")
        }
        let value = try schema.read(node.body, &self)
        try validateNode(value)
        return value
    }
}

struct Body {
    let expanded: Bool
    var unnamed: [Part] = []
    private var fields: [String: [Part]] = [:]

    init(_ raw: [Part], expanded: Bool) throws {
        self.expanded = expanded
        let parts = expanded ? trimNl(raw) : raw
        for part in parts {
            if expanded, isNl(part) { continue }
            if case .field(let field) = part {
                if fields[field.name] != nil {
                    throw TmarkError.message("tmark: duplicate field \"\(field.name)\"")
                }
                fields[field.name] = field.value
            } else {
                unnamed.append(part)
            }
        }
    }

    mutating func field(_ name: String) -> [Part]? {
        fields.removeValue(forKey: name)
    }

    mutating func done() throws {
        if let name = fields.keys.sorted().first {
            throw TmarkError.message("tmark: unknown field \"\(name)\"")
        }
    }
}

func text(_ parts: [Part], expanded: Bool = false) throws -> String {
    var out = ""
    for part in parts {
        guard case .text(let text) = part else {
            throw TmarkError.message("tmark: expected text")
        }
        out += text
    }
    if expanded {
        if out.hasPrefix("\n") { out.removeFirst() }
        if out.hasSuffix("\n") { out.removeLast() }
    }
    return out
}
