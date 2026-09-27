import Foundation

public enum TmarkLayout { case compact, expanded, whenMultiple }

/// A field codec shared by parsing and serialization. Use `mapped` for domain values.
public struct FieldType<Value> {
    let read: ([Part], inout Decoder, Bool) throws -> Value
    let write: (Value, inout Writer) throws -> String
    let fragments: (Value, inout Writer) throws -> [String]
    let isEmpty: (Value) -> Bool
    let count: (Value) -> Int

    init(read: @escaping ([Part], inout Decoder, Bool) throws -> Value,
         write: @escaping (Value, inout Writer) throws -> String,
         isEmpty: @escaping (Value) -> Bool = { _ in false },
         count: @escaping (Value) -> Int = { _ in 1 },
         fragments: ((Value, inout Writer) throws -> [String])? = nil) {
        self.read = read; self.write = write; self.isEmpty = isEmpty; self.count = count
        self.fragments = fragments ?? { value, writer in [try write(value, &writer)] }
    }

    public func mapped<Other>(decode: @escaping (Value) throws -> Other,
                              encode: @escaping (Other) throws -> Value) -> FieldType<Other> {
        FieldType<Other>(
            read: { try decode(self.read($0, &$1, $2)) },
            write: { try self.write(encode($0), &$1) },
            fragments: { try self.fragments(encode($0), &$1) })
    }

    public func optional() -> FieldType<Value?> {
        FieldType<Value?>(read: { try self.read($0, &$1, $2) },
                          write: { value, writer in
                              guard let value else { return "" }
                              return try self.write(value, &writer)
                          }, isEmpty: { $0 == nil })
    }
}

public enum FieldTypes {
    public static var string: FieldType<String> {
        FieldType(read: { parts, _, expanded in try text(parts, expanded: expanded) },
                  write: { value, _ in escape(value) }, isEmpty: { $0.isEmpty })
    }

    public static func scalar<T>(parse: @escaping (String) throws -> T,
                                 format: @escaping (T) throws -> String) -> FieldType<T> {
        string.mapped(decode: parse, encode: format)
    }

    public static var int: FieldType<Int> { scalar(parse: { value in try number(validNumber(value, integer: true) ? Int(value) : nil) }, format: String.init) }
    public static var int64: FieldType<Int64> { scalar(parse: { value in try number(validNumber(value, integer: true) ? Int64(value) : nil) }, format: String.init) }
    public static var double: FieldType<Double> {
        scalar(parse: { value in
            guard validNumber(value), let result = Double(value), result.isFinite else { throw schemaError("expected finite double") }
            return result
        }, format: { value in
            guard value.isFinite else { throw schemaError("expected finite double") }
            return decimal(value)
        })
    }
    public static var boolean: FieldType<Bool> {
        FieldType(read: { parts, _, _ in
            switch try text(parts) {
            case "t": return true
            case "f": return false
            default: throw schemaError("expected t or f")
            }
        }, write: { value, _ in value ? "t" : "f" }, isEmpty: { !$0 })
    }
    public static func enumeration<T: RawRepresentable>(_ type: T.Type) -> FieldType<T> where T.RawValue == String {
        scalar(parse: { value in
            guard let result = T(rawValue: value) else { throw schemaError("invalid \(T.self)") }
            return result
        }, format: { $0.rawValue })
    }
    public static func node<T>(_ type: T.Type) -> FieldType<T> {
        FieldType(read: { parts, decoder, _ in
            let decoded: any TmarkValue
            if let schema = decoder.registry.find(type) { decoded = try schema.read(parts, &decoder) }
            else { decoded = try decoder.single(parts) }
            guard let value = decoded as? T else { throw schemaError("expected \(T.self)") }
            return value
        }, write: { value, writer in
            guard let node = value as? any TmarkValue else { throw schemaError("expected tmark node") }
            let concrete = writer.registry.find(type) != nil
            let encoded = try writer.value(node, omitTag: concrete)
            return concrete ? String(encoded.dropFirst().dropLast()) : encoded
        })
    }
    public static func nodes<T>(_ type: T.Type) -> FieldType<[T]> {
        return FieldType(read: { parts, decoder, _ in
            try dropNl(parts).map { part in
                guard case .node(let parsed) = part else { throw schemaError("expected \(T.self) node") }
                let value = try decoder.registry.find(type).map { try decoder.concrete(parsed, $0) } ?? decoder.single([part])
                guard let typed = value as? T else { throw schemaError("expected \(T.self) node") }
                return typed
            }
        }, write: { values, writer in try values.map { value in
            guard let node = value as? any TmarkValue else { throw schemaError("expected tmark node") }
            return try writer.value(node, omitTag: writer.registry.find(type) != nil)
        }.joined() },
        isEmpty: { $0.isEmpty }, count: { $0.count },
        fragments: { values, writer in try values.map { value in
            guard let node = value as? any TmarkValue else { throw schemaError("expected tmark node") }
            return try writer.value(node, omitTag: writer.registry.find(type) != nil)
        } })
    }
    public static var richText: FieldType<RichText> {
        FieldType(read: { parts, decoder, _ in
            try parts.map { part in
                if case .text(let value) = part { return TText(value) as any RichNode }
                guard let rich = try decoder.single([part]) as? any RichNode else { throw schemaError("expected rich text") }
                return rich
            }
        }, write: { values, writer in try values.map { try writer.value($0) }.joined() },
        isEmpty: { $0.isEmpty }, count: { $0.count })
    }
    public static var blocks: FieldType<RichBlocks> { nodes((any BlockNode).self) }
    public static func record<T>(_ schema: RecordType<T>) -> FieldType<T> {
        FieldType(read: { try schema.read($0, &$1, expanded: $2) },
                  write: { try schema.write($0, &$1, layout: .compact) })
    }
}

/// A typed key path connects a model property to its wire field. Nil name means body.
public struct TmarkField<Owner> {
    public let name: String?
    public let required: Bool
    public let valueType: Any.Type
    let read: ([Part]?, inout Owner, inout Decoder, Bool) throws -> Void
    let write: (Owner, Owner, inout Writer, Bool) throws -> [String]?
    let count: (Owner) -> Int

    public init<Value>(_ name: String?, _ path: WritableKeyPath<Owner, Value>,
                       _ type: FieldType<Value>, required: Bool = false) {
        self.name = name; self.required = required; self.valueType = Value.self
        read = { parts, owner, decoder, expanded in
            guard let parts else {
                if required { throw schemaError("missing field '\(name ?? "content")'") }
                return
            }
            owner[keyPath: path] = try type.read(parts, &decoder, expanded)
        }
        write = { owner, defaults, writer, expanded in
            let value = owner[keyPath: path]
            if !required && type.isEmpty(value) {
                // Preserve explicit empty values when the model default is nonempty.
                if try type.write(value, &writer) == type.write(defaults[keyPath: path], &writer) { return nil }
            }
            if name != nil { return try writer.nested { [try type.write(value, &$0)] } }
            return try expanded ? type.fragments(value, &writer) : [type.write(value, &writer)]
        }
        count = { type.count($0[keyPath: path]) }
    }
}

/// Untagged records and nodes share exactly the same field machinery.
public struct RecordType<Value> {
    public let fields: [TmarkField<Value>]
    let make: () -> Value
    public init(make: @escaping () -> Value, fields: [TmarkField<Value>]) {
        self.make = make; self.fields = fields
    }
    func validate() throws {
        var names = Set<String>()
        for field in fields {
            let key = field.name ?? ""
            if let name = field.name, !validName(name) {
                throw schemaError("invalid field name '\(name)'")
            }
            guard names.insert(key).inserted else { throw schemaError("duplicate field '\(key)'") }
        }
    }
    func read(_ parts: [Part], _ decoder: inout Decoder, expanded: Bool) throws -> Value {
        try validate()
        var body = try Body(parts, expanded: expanded)
        var value = make()
        for field in fields {
            let source: [Part]?
            if let name = field.name { source = body.field(name) } else { source = body.unnamed }
            try field.read(source, &value, &decoder, expanded && field.name == nil)
        }
        if !fields.contains(where: { $0.name == nil }), !dropNl(body.unnamed).isEmpty {
            throw schemaError("unexpected unnamed content")
        }
        try body.done()
        return value
    }
    func write(_ value: Value, _ writer: inout Writer, layout: TmarkLayout) throws -> String {
        try validate()
        let expanded = layout == .expanded || (layout == .whenMultiple && (fields.first { $0.name == nil }?.count(value) ?? 0) > 1)
        let defaults = make()
        var out = ""
        for field in fields {
            guard let fragments = try field.write(value, defaults, &writer, expanded) else { continue }
            if let name = field.name {
                if expanded { out += "\n" }
                out += "#\(name){\(fragments.joined())}"
            } else {
                for fragment in fragments { out += (expanded ? "\n" : "") + fragment }
            }
        }
        if expanded { out += "\n" }
        return out
    }
}

public struct NodeType<Value: TmarkValue> {
    public let tag: String
    public let layout: TmarkLayout
    public let fields: [TmarkField<Value>]
    private let record: RecordType<Value>
    public init(_ tag: String, layout: TmarkLayout = .compact, make: @escaping () -> Value,
                fields: [TmarkField<Value>]) {
        self.tag = tag; self.layout = layout; self.fields = fields
        record = RecordType(make: make, fields: fields)
    }
    public var erased: AnyNodeType {
        AnyNodeType(tag: tag, valueClass: ObjectIdentifier(Value.self), validate: {
            guard validName(tag) else { throw schemaError("invalid tag '\(tag)'") }
            try record.validate()
        }, read: { try record.read($0, &$1, expanded: layout != .compact) }, write: { value, writer, omitTag in
            guard let value = value as? Value else { throw schemaError("schema type mismatch") }
            return "{\(omitTag ? "" : "\(tag);")\(try record.write(value, &writer, layout: layout))}"
        })
    }
}

public protocol TmarkRegistered: TmarkValue {
    static var schema: NodeType<Self> { get }
}

public struct AnyNodeType {
    public let tag: String
    let valueClass: ObjectIdentifier
    let validate: () throws -> Void
    let read: ([Part], inout Decoder) throws -> any TmarkValue
    let write: (any TmarkValue, inout Writer, Bool) throws -> String
}

/// Value semantics: extending a registry never changes another codec.
public struct TmarkRegistry {
    private var byTag: [String: AnyNodeType] = [:]
    private var byClass: [ObjectIdentifier: AnyNodeType] = [:]
    public init() {}
    public var types: [AnyNodeType] { byTag.values.sorted { $0.tag < $1.tag } }
    public func registering(_ types: AnyNodeType...) throws -> Self { try registering(types) }
    public func registering<T: TmarkRegistered>(_ type: T.Type) throws -> Self { try registering(type.schema.erased) }
    public func registering(_ types: [AnyNodeType]) throws -> Self {
        var result = self
        for type in types {
            try type.validate()
            guard type.valueClass != ObjectIdentifier(TText.self), type.valueClass != ObjectIdentifier(Unknown.self) else { throw schemaError("cannot register wire primitive") }
            guard result.byTag[type.tag] == nil, result.byClass[type.valueClass] == nil else { throw schemaError("duplicate tag or model type '\(type.tag)'") }
            result.byTag[type.tag] = type; result.byClass[type.valueClass] = type
        }
        return result
    }
    public static var standard: Self { try! Self().registering(builtInTypes()) }
    func find(_ tag: String) -> AnyNodeType? { byTag[tag] }
    func find(_ value: any TmarkValue) -> AnyNodeType? { byClass[ObjectIdentifier(Swift.type(of: value))] }
    func find<T>(_ type: T.Type) -> AnyNodeType? { byClass[ObjectIdentifier(type)] }
}

func schemaError(_ message: String) -> TmarkError { .message("tmark: \(message)") }
private func number<T>(_ value: T?) throws -> T {
    guard let value else { throw schemaError("expected number") }
    return value
}

private func validNumber(_ value: String, integer: Bool = false) -> Bool {
    let pattern = integer ? #"^-?(0|[1-9][0-9]*)$"# : #"^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$"#
    return value != "-0" && value.range(of: pattern, options: .regularExpression) != nil
}

private func decimal(_ value: Double) -> String {
    if value == 0 { return "0" }
    let raw = String(value).lowercased()
    let pieces = raw.split(separator: "e", maxSplits: 1).map(String.init)
    if pieces.count == 1 { return raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw }
    let mantissa = pieces[0]
    let exponent = Int(pieces[1]) ?? 0
    let sign = mantissa.hasPrefix("-") ? "-" : ""
    let unsigned = mantissa.hasPrefix("-") ? String(mantissa.dropFirst()) : mantissa
    let point = (unsigned.firstIndex(of: ".").map { unsigned.distance(from: unsigned.startIndex, to: $0) } ?? unsigned.count) + exponent
    let digits = unsigned.replacingOccurrences(of: ".", with: "")
    if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + digits }
    if point >= digits.count { return sign + digits + String(repeating: "0", count: point - digits.count) }
    let split = digits.index(digits.startIndex, offsetBy: point)
    return sign + String(digits[..<split]) + "." + String(digits[split...])
}
