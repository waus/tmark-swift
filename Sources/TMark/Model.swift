import Foundation

public let tmarkMaxDepth = 16

public protocol TmarkValue {}
public protocol RichNode: TmarkValue {}
public protocol BlockNode: TmarkValue {}
public protocol GalleryNode: TmarkValue {}

public typealias RichText = [any RichNode]
public typealias RichBlocks = [any BlockNode]

public struct TText: RichNode, Equatable {
    public var text: String
    public init(_ text: String) { self.text = text }
}

public struct Unknown: RichNode, BlockNode, Equatable {
    public var raw: String
    public init(_ raw: String) { self.raw = raw }
}

public struct Caption: TmarkValue {
    public var credit: RichText
    public var text: RichText
    public init(credit: RichText = [], text: RichText = []) {
        self.credit = credit
        self.text = text
    }
}

public struct Link: RichNode {
    public var href: String
    public var children: RichText
    public init(href: String, children: RichText = []) {
        self.href = href
        self.children = children
    }
}

public struct AnchorLink: RichNode {
    public var anchorName: String
    public var children: RichText
    public init(anchorName: String, children: RichText = []) {
        self.anchorName = anchorName
        self.children = children
    }
}

public struct Reference: RichNode {
    public var name: String
    public var children: RichText
    public init(name: String, children: RichText = []) {
        self.name = name
        self.children = children
    }
}

public struct ReferenceLink: RichNode {
    public var referenceName: String
    public var children: RichText
    public init(referenceName: String, children: RichText = []) {
        self.referenceName = referenceName
        self.children = children
    }
}

public struct Bold: RichNode { public var children: RichText; public init(_ children: RichText) { self.children = children } }
public struct Italic: RichNode { public var children: RichText; public init(_ children: RichText) { self.children = children } }
public struct Marked: RichNode { public var children: RichText; public init(_ children: RichText) { self.children = children } }
public struct Underline: RichNode { public var children: RichText; public init(_ children: RichText) { self.children = children } }
public struct Strikethrough: RichNode { public var children: RichText; public init(_ children: RichText) { self.children = children } }
public struct Spoiler: RichNode { public var children: RichText; public init(_ children: RichText) { self.children = children } }
public struct Subscript: RichNode { public var children: RichText; public init(_ children: RichText) { self.children = children } }
public struct Superscript: RichNode { public var children: RichText; public init(_ children: RichText) { self.children = children } }

public struct DateTimeNode: RichNode {
    public var unix: Int64
    public var timezone: String
    public init(unix: Int64, timezone: String) {
        self.unix = unix
        self.timezone = timezone
    }
}

public struct Code: RichNode { public var text: String; public init(_ text: String) { self.text = text } }
public struct Math: RichNode { public var expression: String; public init(_ expression: String) { self.expression = expression } }

public struct Icon: RichNode {
    public var src: String
    public var alternativeText: String?
    public init(src: String, alternativeText: String? = nil) {
        self.src = src
        self.alternativeText = alternativeText
    }
}

public struct Paragraph: BlockNode {
    public var children: RichText
    public init(_ children: RichText) { self.children = children }
}

public struct Header: BlockNode {
    public var size: Int
    public var children: RichText
    public init(size: Int, children: RichText = []) {
        self.size = size
        self.children = children
    }
}

public struct Preformatted: BlockNode {
    public var text: String
    public var language: String?
    public init(_ text: String, language: String? = nil) {
        self.text = text
        self.language = language
    }
}

public struct MathBlock: BlockNode { public var expression: String; public init(_ expression: String) { self.expression = expression } }
public struct Anchor: BlockNode { public var name: String; public init(_ name: String) { self.name = name } }
public struct Divider: BlockNode { public init() {} }

public struct Blockquote: BlockNode {
    public var credit: RichText
    public var blocks: RichBlocks
    public init(_ blocks: RichBlocks, credit: RichText = []) {
        self.credit = credit
        self.blocks = blocks
    }
}

public struct PullQuote: BlockNode {
    public var credit: RichText
    public var text: RichText
    public init(_ text: RichText, credit: RichText = []) {
        self.credit = credit
        self.text = text
    }
}

public struct Collage: BlockNode {
    public var caption: Caption?
    public var children: [any GalleryNode]
    public init(_ children: [any GalleryNode], caption: Caption? = nil) {
        self.caption = caption
        self.children = children
    }
}

public struct ListBlock: BlockNode {
    public var items: [ListItem]
    public init(_ items: [ListItem]) { self.items = items }
}

public struct ListItem: BlockNode {
    public var type: String?
    public var order: Int?
    public var checked: Bool?
    public var children: RichBlocks
    public init(_ children: RichBlocks, type: String? = nil, order: Int? = nil, checked: Bool? = nil) {
        self.type = type
        self.order = order
        self.checked = checked
        self.children = children
    }
}

public struct MapBlock: BlockNode {
    public var lat: Double
    public var lon: Double
    public var zoom: Int?
    public var caption: Caption?
    public init(lat: Double, lon: Double, zoom: Int? = nil, caption: Caption? = nil) {
        self.lat = lat
        self.lon = lon
        self.zoom = zoom
        self.caption = caption
    }
}

public struct ImageNode: BlockNode, GalleryNode {
    public var src: String
    public var caption: Caption?
    public var hasSpoiler: Bool
    public init(src: String, caption: Caption? = nil, hasSpoiler: Bool = false) {
        self.src = src
        self.caption = caption
        self.hasSpoiler = hasSpoiler
    }
}

public struct VideoNode: BlockNode, GalleryNode {
    public var src: String
    public var caption: Caption?
    public var hasSpoiler: Bool
    public init(src: String, caption: Caption? = nil, hasSpoiler: Bool = false) {
        self.src = src
        self.caption = caption
        self.hasSpoiler = hasSpoiler
    }
}

public struct AudioNode: BlockNode {
    public var src: String
    public var caption: Caption?
    public init(src: String, caption: Caption? = nil) {
        self.src = src
        self.caption = caption
    }
}

public struct Slideshow: BlockNode {
    public var caption: Caption?
    public var children: [any GalleryNode]
    public init(_ children: [any GalleryNode], caption: Caption? = nil) {
        self.caption = caption
        self.children = children
    }
}

public enum TableCellAlign: String { case left, center, right }
public enum TableCellValign: String { case top, middle, bottom }

public struct Table: BlockNode {
    public var rows: [TableRow]
    public var caption: RichText
    public var bordered: Bool
    public var striped: Bool
    public init(_ rows: [TableRow], caption: RichText = [], bordered: Bool = false, striped: Bool = false) {
        self.rows = rows
        self.caption = caption
        self.bordered = bordered
        self.striped = striped
    }
}

public struct TableRow: BlockNode {
    public var cells: [Cell]
    public init(_ cells: [Cell]) { self.cells = cells }
}

public struct Cell: BlockNode {
    public var isHeader: Bool
    public var colspan: Int?
    public var rowspan: Int?
    public var align: TableCellAlign?
    public var valign: TableCellValign?
    public var children: RichText
    public init(_ children: RichText, isHeader: Bool = false, colspan: Int? = nil, rowspan: Int? = nil, align: TableCellAlign? = nil, valign: TableCellValign? = nil) {
        self.children = children
        self.isHeader = isHeader
        self.colspan = colspan
        self.rowspan = rowspan
        self.align = align
        self.valign = valign
    }
}

public struct Details: BlockNode {
    public var summary: RichText
    public var isOpen: Bool
    public var children: RichBlocks
    public init(_ children: RichBlocks, summary: RichText = [], isOpen: Bool = false) {
        self.summary = summary
        self.isOpen = isOpen
        self.children = children
    }
}

public struct Document: TmarkValue {
    public var url: String
    public var title: String
    public var description: String?
    public var authorName: String?
    public var authorUrl: String?
    public var imageUrl: String?
    public var content: RichBlocks
    public var attachedMedia: [AttachedMedia]

    public init(url: String, title: String, description: String? = nil, authorName: String? = nil, authorUrl: String? = nil, imageUrl: String? = nil, content: RichBlocks, attachedMedia: [AttachedMedia] = []) {
        self.url = url
        self.title = title
        self.description = description
        self.authorName = authorName
        self.authorUrl = authorUrl
        self.imageUrl = imageUrl
        self.content = content
        self.attachedMedia = attachedMedia
    }
}

public struct AttachedMedia: TmarkValue {
    public var hash: String
    public var content: RichBlocks
    public init(hash: String, content: RichBlocks) {
        self.hash = hash
        self.content = content
    }
}

// Wire schemas are owned by their model types.
extension Document: TmarkRegistered {
    public static var schema: NodeType<Document> {
        NodeType("document", layout: .expanded, make: { Document(url: "", title: "", content: []) }, fields: [
            TmarkField("url", \.url, FieldTypes.string),
            TmarkField("title", \.title, FieldTypes.string),
            TmarkField("description", \.description, FieldTypes.string.optional()),
            TmarkField("author_name", \.authorName, FieldTypes.string.optional()),
            TmarkField("author_url", \.authorUrl, FieldTypes.string.optional()),
            TmarkField("image_url", \.imageUrl, FieldTypes.string.optional()),
            TmarkField("attached_media", \.attachedMedia, FieldTypes.nodes((AttachedMedia).self)),
            TmarkField(nil, \.content, FieldTypes.blocks),
        ])
    }
}

extension AttachedMedia: TmarkRegistered {
    public static var schema: NodeType<AttachedMedia> {
        NodeType("attached", layout: .expanded, make: { AttachedMedia(hash: "", content: []) }, fields: [
            TmarkField("hash", \.hash, FieldTypes.string),
            TmarkField(nil, \.content, FieldTypes.blocks),
        ])
    }
}

extension Link: TmarkRegistered {
    public static var schema: NodeType<Link> {
        NodeType("a", make: { Link(href: "") }, fields: [
            TmarkField("href", \.href, FieldTypes.string),
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension AnchorLink: TmarkRegistered {
    public static var schema: NodeType<AnchorLink> {
        NodeType("anchor-link", make: { AnchorLink(anchorName: "") }, fields: [
            TmarkField("name", \.anchorName, FieldTypes.string),
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Reference: TmarkRegistered {
    public static var schema: NodeType<Reference> {
        NodeType("ref", make: { Reference(name: "") }, fields: [
            TmarkField("name", \.name, FieldTypes.string),
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension ReferenceLink: TmarkRegistered {
    public static var schema: NodeType<ReferenceLink> {
        NodeType("ref-link", make: { ReferenceLink(referenceName: "") }, fields: [
            TmarkField("name", \.referenceName, FieldTypes.string),
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Bold: TmarkRegistered {
    public static var schema: NodeType<Bold> {
        NodeType("b", make: { Bold([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Italic: TmarkRegistered {
    public static var schema: NodeType<Italic> {
        NodeType("i", make: { Italic([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Marked: TmarkRegistered {
    public static var schema: NodeType<Marked> {
        NodeType("m", make: { Marked([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Underline: TmarkRegistered {
    public static var schema: NodeType<Underline> {
        NodeType("u", make: { Underline([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Strikethrough: TmarkRegistered {
    public static var schema: NodeType<Strikethrough> {
        NodeType("s", make: { Strikethrough([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Spoiler: TmarkRegistered {
    public static var schema: NodeType<Spoiler> {
        NodeType("spoiler", make: { Spoiler([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Subscript: TmarkRegistered {
    public static var schema: NodeType<Subscript> {
        NodeType("sub", make: { Subscript([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Superscript: TmarkRegistered {
    public static var schema: NodeType<Superscript> {
        NodeType("sup", make: { Superscript([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension DateTimeNode: TmarkRegistered {
    public static var schema: NodeType<DateTimeNode> {
        NodeType("datetime", make: { DateTimeNode(unix: 0, timezone: "") }, fields: [
            TmarkField("timezone", \.timezone, FieldTypes.string),
            TmarkField(nil, \.unix, FieldTypes.int64),
        ])
    }
}

extension Code: TmarkRegistered {
    public static var schema: NodeType<Code> {
        NodeType("code", make: { Code("") }, fields: [
            TmarkField(nil, \.text, FieldTypes.string),
        ])
    }
}

extension Math: TmarkRegistered {
    public static var schema: NodeType<Math> {
        NodeType("math", make: { Math("") }, fields: [
            TmarkField(nil, \.expression, FieldTypes.string),
        ])
    }
}

extension Icon: TmarkRegistered {
    public static var schema: NodeType<Icon> {
        NodeType("icon", make: { Icon(src: "") }, fields: [
            TmarkField("alt", \.alternativeText, FieldTypes.string.optional()),
            TmarkField(nil, \.src, FieldTypes.string),
        ])
    }
}

extension Paragraph: TmarkRegistered {
    public static var schema: NodeType<Paragraph> {
        NodeType("p", make: { Paragraph([]) }, fields: [
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Header: TmarkRegistered {
    public static var schema: NodeType<Header> {
        NodeType("h", make: { Header(size: 4) }, fields: [
            TmarkField("s", \.size, FieldTypes.int, required: true),
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Preformatted: TmarkRegistered {
    public static var schema: NodeType<Preformatted> {
        NodeType("pre", layout: .expanded, make: { Preformatted("") }, fields: [
            TmarkField("language", \.language, FieldTypes.string.optional()),
            TmarkField(nil, \.text, FieldTypes.string),
        ])
    }
}

extension MathBlock: TmarkRegistered {
    public static var schema: NodeType<MathBlock> {
        NodeType("math-block", layout: .expanded, make: { MathBlock("") }, fields: [
            TmarkField(nil, \.expression, FieldTypes.string),
        ])
    }
}

extension Anchor: TmarkRegistered {
    public static var schema: NodeType<Anchor> {
        NodeType("anchor", make: { Anchor("") }, fields: [
            TmarkField(nil, \.name, FieldTypes.string),
        ])
    }
}

extension Divider: TmarkRegistered {
    public static var schema: NodeType<Divider> {
        NodeType("hr", make: { Divider() }, fields: [

        ])
    }
}

extension Blockquote: TmarkRegistered {
    public static var schema: NodeType<Blockquote> {
        NodeType("q", layout: .whenMultiple, make: { Blockquote([]) }, fields: [
            TmarkField("credit", \.credit, FieldTypes.richText),
            TmarkField(nil, \.blocks, FieldTypes.blocks),
        ])
    }
}

extension PullQuote: TmarkRegistered {
    public static var schema: NodeType<PullQuote> {
        NodeType("as", make: { PullQuote([]) }, fields: [
            TmarkField("credit", \.credit, FieldTypes.richText),
            TmarkField(nil, \.text, FieldTypes.richText),
        ])
    }
}

extension Collage: TmarkRegistered {
    public static var schema: NodeType<Collage> {
        NodeType("collage", layout: .expanded, make: { Collage([]) }, fields: [
            TmarkField("caption", \.caption, FieldTypes.node(Caption.self).optional()),
            TmarkField(nil, \.children, FieldTypes.nodes((any GalleryNode).self)),
        ])
    }
}

extension ListBlock: TmarkRegistered {
    public static var schema: NodeType<ListBlock> {
        NodeType("list", layout: .expanded, make: { ListBlock([]) }, fields: [
            TmarkField(nil, \.items, FieldTypes.nodes((ListItem).self)),
        ])
    }
}

extension ListItem: TmarkRegistered {
    public static var schema: NodeType<ListItem> {
        NodeType("li", layout: .whenMultiple, make: { ListItem([]) }, fields: [
            TmarkField("type", \.type, FieldTypes.string.optional()),
            TmarkField("order", \.order, FieldTypes.int.optional()),
            TmarkField("checked", \.checked, FieldTypes.boolean.optional()),
            TmarkField(nil, \.children, FieldTypes.blocks),
        ])
    }
}

extension MapBlock: TmarkRegistered {
    public static var schema: NodeType<MapBlock> {
        NodeType("map", make: { MapBlock(lat: 0, lon: 0) }, fields: [
            TmarkField("lat", \.lat, FieldTypes.double),
            TmarkField("lon", \.lon, FieldTypes.double),
            TmarkField("zoom", \.zoom, FieldTypes.int.optional()),
            TmarkField("caption", \.caption, FieldTypes.node(Caption.self).optional()),
        ])
    }
}

extension ImageNode: TmarkRegistered {
    public static var schema: NodeType<ImageNode> {
        NodeType("img", make: { ImageNode(src: "") }, fields: [
            TmarkField("caption", \.caption, FieldTypes.node(Caption.self).optional()),
            TmarkField("has_spoiler", \.hasSpoiler, FieldTypes.boolean),
            TmarkField(nil, \.src, FieldTypes.string),
        ])
    }
}

extension VideoNode: TmarkRegistered {
    public static var schema: NodeType<VideoNode> {
        NodeType("video", make: { VideoNode(src: "") }, fields: [
            TmarkField("caption", \.caption, FieldTypes.node(Caption.self).optional()),
            TmarkField("has_spoiler", \.hasSpoiler, FieldTypes.boolean),
            TmarkField(nil, \.src, FieldTypes.string),
        ])
    }
}

extension AudioNode: TmarkRegistered {
    public static var schema: NodeType<AudioNode> {
        NodeType("audio", make: { AudioNode(src: "") }, fields: [
            TmarkField("caption", \.caption, FieldTypes.node(Caption.self).optional()),
            TmarkField(nil, \.src, FieldTypes.string),
        ])
    }
}

extension Slideshow: TmarkRegistered {
    public static var schema: NodeType<Slideshow> {
        NodeType("slideshow", layout: .expanded, make: { Slideshow([]) }, fields: [
            TmarkField("caption", \.caption, FieldTypes.node(Caption.self).optional()),
            TmarkField(nil, \.children, FieldTypes.nodes((any GalleryNode).self)),
        ])
    }
}

extension Table: TmarkRegistered {
    public static var schema: NodeType<Table> {
        NodeType("table", layout: .expanded, make: { Table([]) }, fields: [
            TmarkField("caption", \.caption, FieldTypes.richText),
            TmarkField("bordered", \.bordered, FieldTypes.boolean),
            TmarkField("striped", \.striped, FieldTypes.boolean),
            TmarkField(nil, \.rows, FieldTypes.nodes(TableRow.self)),
        ])
    }
}

extension TableRow: TmarkRegistered {
    public static var schema: NodeType<TableRow> {
        NodeType("tr", make: { TableRow([]) }, fields: [
            TmarkField(nil, \.cells, FieldTypes.nodes(Cell.self)),
        ])
    }
}

extension Cell: TmarkRegistered {
    public static var schema: NodeType<Cell> {
        NodeType("td", make: { Cell([]) }, fields: [
            TmarkField("header", \.isHeader, FieldTypes.boolean),
            TmarkField("colspan", \.colspan, FieldTypes.int.optional()),
            TmarkField("rowspan", \.rowspan, FieldTypes.int.optional()),
            TmarkField("align", \.align, FieldTypes.enumeration(TableCellAlign.self).optional()),
            TmarkField("valign", \.valign, FieldTypes.enumeration(TableCellValign.self).optional()),
            TmarkField(nil, \.children, FieldTypes.richText),
        ])
    }
}

extension Details: TmarkRegistered {
    public static var schema: NodeType<Details> {
        NodeType("details", layout: .whenMultiple, make: { Details([]) }, fields: [
            TmarkField("summary", \.summary, FieldTypes.richText),
            TmarkField("open", \.isOpen, FieldTypes.boolean),
            TmarkField(nil, \.children, FieldTypes.blocks),
        ])
    }
}

extension Caption: TmarkRegistered {
    public static var schema: NodeType<Caption> {
        NodeType("caption", make: { Caption() }, fields: [
            TmarkField("credit", \.credit, FieldTypes.richText),
            TmarkField(nil, \.text, FieldTypes.richText),
        ])
    }
}
