import Testing
import TMark

private struct Mention: RichNode, TmarkRegistered {
    var user = ""
    var children: RichText = []
    static var schema: NodeType<Self> {
        NodeType("mention", make: { Self() }, fields: [
            TmarkField("user", \.user, FieldTypes.string, required: true),
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

private struct Color: Equatable {
    let value: String
    static var fieldType: FieldType<Self> {
        FieldTypes.string.mapped(decode: { Self(value: $0) }, encode: { $0.value })
    }
}
private struct Appearance {
    var color = Color(value: "black")
    var label: String?
    static var schema: RecordType<Self> {
        RecordType(make: { Self() }, fields: [
            TmarkField("color", \.color, Color.fieldType),
            TmarkField("label", \.label, FieldTypes.string.optional()),
        ])
    }
}
private struct Callout: BlockNode, TmarkRegistered {
    var appearance: Appearance?
    var enabled: Bool?
    var priority = 0
    var children: RichBlocks = []
    static var schema: NodeType<Self> {
        NodeType("callout", layout: .expanded, make: { Self() }, fields: [
            TmarkField("appearance", \.appearance, FieldTypes.record(Appearance.schema).optional()),
            TmarkField("enabled", \.enabled, FieldTypes.boolean.optional()),
            TmarkField("priority", \.priority, FieldTypes.int),
            TmarkField(nil, \.children, FieldTypes.blocks),
        ])
    }
}
private struct ChoiceRow: BlockNode, TmarkRegistered {
    var items: [Mention] = []
    static var schema: NodeType<Self> {
        NodeType("choice-row", make: { Self() }, fields: [
            TmarkField(nil, \.items, FieldTypes.nodes(Mention.self)),
        ])
    }
}
private struct Choices: BlockNode, TmarkRegistered {
    var selected = Mention()
    var rows: [ChoiceRow] = []
    static var schema: NodeType<Self> {
        NodeType("choices", layout: .expanded, make: { Self() }, fields: [
            TmarkField("selected", \.selected, FieldTypes.node(Mention.self), required: true),
            TmarkField(nil, \.rows, FieldTypes.nodes(ChoiceRow.self)),
        ])
    }
}
private func customCodec() throws -> TmarkCodec {
    try TmarkCodec(registry: TmarkRegistry.standard.registering([
        Mention.schema.erased, Callout.schema.erased, ChoiceRow.schema.erased, Choices.schema.erased,
    ]))
}

@Test func externalTypesInsideStandardDocument() throws {
    let codec = try customCodec()
    let document = Document(url: "", title: "", content: [
        Callout(appearance: Appearance(label: ""), enabled: false, priority: 2,
                children: [Paragraph([Mention(user: "42", children: [Bold([TText("name")])])])]),
    ])
    let wire = try codec.marshal(document)
    let decoded = try codec.unmarshalDocument(wire)
    let block = try #require(decoded.content.first as? Callout)
    #expect(block.appearance?.color.value == "black")
    #expect(block.appearance?.label == "")
    #expect(block.enabled == false)
    #expect(block.priority == 2)
    let paragraph = try #require(block.children.first as? Paragraph)
    #expect((paragraph.children.first as? Mention)?.user == "42")
    #expect(try codec.marshal(decoded) == wire)
}

@Test func registryIsolationAndRawFallback() throws {
    let codec = try customCodec()
    let wire = "{mention;#user{42}hello}"
    #expect(try codec.unmarshal(wire) is Mention)
    #expect(throws: (any Error).self) { try unmarshal(wire) }
    #expect((try unmarshal(wire, soft: true) as? Unknown)?.raw == wire)
    #expect(throws: (any Error).self) { try marshal(Mention(user: "42")) }
    #expect(try codec.marshal(codec.unmarshal("{future;#data{x}y}", soft: true)) == "{future;#data{x}y}")
}

@Test func schemaRejectsMalformedFieldsAndCategories() throws {
    let codec = try customCodec()
    for wire in [
        "{mention;text}", "{mention;#user{x}#user{y}}", "{mention;#user{x}#extra{y}}",
        "{mention;#user{x}{p;block}}", "{callout;#priority{bad}}", "{callout;#enabled{yes}}",
        "{callout;#appearance{#color{{p;invalid}}}}", "{choices;#selected{{p;wrong}}}",
        "{choices;#selected{{mention;#user{x}}}{{p;wrong}}}",
    ] {
        #expect(throws: (any Error).self, "\(wire)") { try codec.unmarshal(wire, soft: true) }
    }
}

@Test func typedNodesAndRowsRoundTrip() throws {
    let codec = try customCodec()
    let original = Choices(selected: Mention(user: "a"), rows: [ChoiceRow(items: [Mention(user: "b"), Mention(user: "c")]), ChoiceRow()])
    let wire = try codec.marshal(original)
    let decoded = try #require(codec.unmarshal(wire) as? Choices)
    #expect(decoded.selected.user == "a")
    #expect(decoded.rows.map { $0.items.map(\.user) } == [["b", "c"], []])
    #expect(try codec.marshal(decoded) == wire)
}

@Test func registrationValidatesSchemasAndConflicts() throws {
    let registry = try TmarkRegistry.standard.registering(Mention.self)
    #expect(throws: (any Error).self) { try registry.registering(Mention.self) }
    #expect(throws: (any Error).self) {
        try registry.registering(NodeType("p", make: { Callout() }, fields: []).erased)
    }
    #expect(throws: (any Error).self) {
        try registry.registering(NodeType("other", make: { Mention() }, fields: []).erased)
    }
    for tag in ["", "bad;tag", "bad tag"] {
        #expect(throws: (any Error).self) { try TmarkRegistry().registering(NodeType(tag, make: { Mention() }, fields: []).erased) }
    }
    #expect(throws: (any Error).self) {
        try TmarkRegistry().registering(NodeType("bad", make: { Mention() }, fields: [
            TmarkField("user", \.user, FieldTypes.string), TmarkField("user", \.user, FieldTypes.string),
        ]).erased)
    }
    #expect(throws: (any Error).self) {
        try TmarkRegistry().registering(NodeType("bad", make: { Mention() }, fields: [
            TmarkField("bad field", \.user, FieldTypes.string),
        ]).erased)
    }
}

@Test func defaultsPreserveExplicitEmptyValues() throws {
    struct Notice: BlockNode {
        var title = "default"
        var enabled = true
    }
    let schema = NodeType("notice", make: { Notice() }, fields: [
        TmarkField("title", \.title, FieldTypes.string),
        TmarkField("enabled", \.enabled, FieldTypes.boolean),
    ])
    let codec = try TmarkCodec(registry: TmarkRegistry().registering(schema.erased))
    let defaults = try #require(codec.unmarshal("{notice;}") as? Notice)
    #expect(defaults.title == "default")
    let wire = try codec.marshal(Notice(title: "", enabled: false))
    #expect(wire == "{notice;#title{}#enabled{f}}")
    let decoded = try #require(codec.unmarshal(wire) as? Notice)
    #expect(decoded.title == "")
    #expect(!decoded.enabled)
    #expect(throws: (any Error).self) { try codec.unmarshal("{notice;unexpected}") }
}

@Test func nestedFieldsAndUnknownsRespectDepthLimit() throws {
    let deepFields = "{future;" + String(repeating: "#f{", count: 16) + String(repeating: "}", count: 17)
    #expect(throws: (any Error).self) { try unmarshal(deepFields, soft: true) }
    let raw = String(repeating: "{future;", count: 16) + String(repeating: "}", count: 16)
    #expect(try marshal(Unknown(raw)) == raw)
    #expect(throws: (any Error).self) { try marshal(Paragraph([Unknown(raw)])) }
}
