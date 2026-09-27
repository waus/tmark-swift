import Foundation

enum TmarkError: Error, Equatable, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): message
        }
    }
}

enum Part {
    case text(String)
    case node(ParsedNode)
    case field(ParsedField)
}

struct ParsedNode {
    var tag: String
    var body: [Part]
    var raw: String
}

struct ParsedField {
    var name: String
    var value: [Part]
}

struct Parser {
    let data: [Character]
    var pos = 0
    var depth = 0

    init(_ data: String) {
        self.data = Array(data.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    mutating func parse() throws -> [Part] {
        if data.contains("\r") || data.first == "\u{FEFF}" { throw schemaError("invalid line ending or BOM") }
        let parts = try parseParts(stopOnBrace: false)
        if pos != data.count {
            throw TmarkError.message("tmark: unexpected input at byte \(pos)")
        }
        return parts
    }

    mutating func parseSingleNode() throws -> ParsedNode {
        guard case .node(let node)? = singleNode(try parse()) else {
            throw TmarkError.message("tmark: expected single node")
        }
        return node
    }

    mutating func parseParts(stopOnBrace: Bool) throws -> [Part] {
        var parts: [Part] = []
        var contentSeen = false
        var names = Set<String>()
        while pos < data.count {
            let part: Part
            switch data[pos] {
            case "}":
                guard stopOnBrace else {
                    throw TmarkError.message("tmark: unexpected } at byte \(pos)")
                }
                pos += 1
                return parts
            case "{":
                part = .node(try parseNode())
            case "#":
                part = .field(try parseField())
            default:
                let text = try parseText()
                part = .text(text)
            }
            if case .field(let field) = part {
                if contentSeen || !names.insert(field.name).inserted { throw schemaError("invalid field order or duplicate field") }
            } else if !isNl(part) { contentSeen = true }
            parts.append(part)
        }
        if stopOnBrace {
            throw TmarkError.message("tmark: missing }")
        }
        return parts
    }

    mutating func parseNode() throws -> ParsedNode {
        let start = pos
        depth += 1
        if depth > tmarkMaxDepth {
            throw TmarkError.message("tmark: max depth \(tmarkMaxDepth) exceeded")
        }
        defer { depth -= 1 }

        pos += 1
        if pos < data.count, data[pos] == "}" {
            pos += 1
            return ParsedNode(tag: "", body: [], raw: raw(start, pos))
        }
        let tagStart = pos
        while pos < data.count, !";{}#\\".contains(data[pos]) {
            pos += 1
        }
        if pos < data.count, data[pos] == ";" {
            let tag = raw(tagStart, pos)
            guard validName(tag) else { throw schemaError("invalid tag") }
            pos += 1
            let body = try parseParts(stopOnBrace: true)
            return ParsedNode(tag: tag, body: body, raw: raw(start, pos))
        }
        pos = tagStart
        let body = try parseParts(stopOnBrace: true)
        return ParsedNode(tag: "", body: body, raw: raw(start, pos))
    }

    mutating func parseField() throws -> ParsedField {
        depth += 1
        defer { depth -= 1 }
        guard depth <= tmarkMaxDepth else { throw schemaError("max depth exceeded") }
        pos += 1
        let start = pos
        while pos < data.count, isFieldNameChar(data[pos]) {
            pos += 1
        }
        guard start != pos, pos < data.count, data[pos] == "{", validName(raw(start, pos)) else {
            throw TmarkError.message("tmark: malformed field at byte \(start - 1)")
        }
        let name = raw(start, pos)
        pos += 1
        return ParsedField(name: name, value: try parseParts(stopOnBrace: true))
    }

    mutating func parseText() throws -> String {
        var out = ""
        while pos < data.count {
            var c = data[pos]
            if c == "{" || c == "}" || c == "#" { break }
            if c == "\\" {
                pos += 1
                guard pos < data.count else {
                    throw TmarkError.message("tmark: trailing escape")
                }
                c = data[pos]
                guard "#{}\\".contains(c) else { throw schemaError("invalid escape") }
            }
            out.append(c)
            pos += 1
        }
        return out
    }

    func raw(_ start: Int, _ end: Int) -> String {
        String(data[start..<end])
    }
}

func isFieldNameChar(_ c: Character) -> Bool {
    guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else {
        return false
    }
    let v = scalar.value
    return (97...122).contains(v) || (48...57).contains(v) || v == 45 || v == 95
}

func validName(_ value: String) -> Bool {
    (1...32).contains(value.count) && value.allSatisfy(isFieldNameChar)
}

func singleNode(_ parts: [Part]) -> Part? {
    let clean = dropNl(parts)
    return clean.count == 1 ? clean[0] : nil
}

func isNl(_ part: Part) -> Bool {
    if case .text(let text) = part {
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.contains("\n")
    }
    return false
}

func dropNl(_ parts: [Part]) -> [Part] {
    parts.filter { !isNl($0) }
}

func trimNl(_ parts: [Part]) -> [Part] {
    var start = 0
    var end = parts.count
    while start < end, isNl(parts[start]) { start += 1 }
    while end > start, isNl(parts[end - 1]) { end -= 1 }
    return Array(parts[start..<end])
}
