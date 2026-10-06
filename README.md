# TMark Swift

Swift implementation of the tmark model, parser, serializer, and a SwiftUI renderer.

## Installation

Requires Swift 6.0 or newer, iOS 17 or macOS 14.

In Xcode, choose **File → Add Package Dependencies** and enter
`https://github.com/waus/tmark-swift`.
Select `TMark` for parsing and serialization, and add `TMarkSwiftUI` for rendering.
Select version `0.3.0`.

For another Swift package, add this dependency:

```swift
.package(url: "https://github.com/waus/tmark-swift.git", from: "0.3.0")
```

Then add the products your target needs:

```swift
.product(name: "TMark", package: "tmark-swift"),
.product(name: "TMarkSwiftUI", package: "tmark-swift"), // Optional rendering
```

## Modules

- `TMark`: document models, schema registry, parser and serializer. Depends on Foundation.
- `TMarkSwiftUI`: SwiftUI views and native media support. Depends on `TMark` and Apple UI/media frameworks.

```swift
import TMark

let source = "{p;Hello}"
let node = try unmarshal(source)
let serialized = try marshal(node)
```

To render a parsed document:

```swift
import SwiftUI
import TMark
import TMarkSwiftUI

struct DocumentView: View {
    let document: TMark.Document

    var body: some View {
        TmarkDocumentView(document)
    }
}
```

`Math` and `MathBlock` render as monospaced text by default. Applications can
replace them with `.tmarkInlineRenderer` and `.tmarkBlockRenderer`.
The example app shows both hooks.

## Example App

Open `TMarkExampleApp/TMarkExampleApp.xcodeproj` in Xcode and run:

- `TMarkExampleMac` for macOS
- `TMarkExampleiOS` for iPhone simulator

The app uses the same SwiftUI source for both platforms and local package products.
Its deployment targets are macOS 15 and iOS 18.
It downloads the fixed list of examples from `https://tmark.waus.app/examples/`,
so loading examples requires network access.

## Application types

Each model owns a `static var schema: NodeType<Self>`. The schema declares the tag,
wire layout, a factory supplying defaults, and typed writable key paths. Parsing
and serialization use the same fields; neither needs a switch over model types.

```swift
import TMark

struct Callout: BlockNode, TmarkRegistered {
    var title = ""
    var children: RichBlocks = []

    static var schema: NodeType<Self> {
        NodeType("callout", layout: .expanded, make: { Self() }, fields: [
            TmarkField("title", \.title, FieldTypes.string, required: true),
            TmarkField(nil, \.children, FieldTypes.blocks),
        ])
    }
}

let registry = try TmarkRegistry.standard.registering(Callout.self)
let codec = TmarkCodec(registry: registry)
let document = try codec.unmarshalDocument(source)
let wire = try codec.marshal(document)
```

For several types, use `registering([Callout.schema.erased, Mention.schema.erased])`.
A registry has value semantics: registration returns a copy and rejects duplicate
tags or model types. `TmarkRegistry()` starts empty. Standard schemas are composed
in `BuiltInTypes.swift`; new application types need no edits to library sources.
Global `marshal`, `unmarshal` and `unmarshalDocument` still use the standard registry.

Use `TmarkDocumentView(document, maxWidth: 760)` for a scrollable SwiftUI document,
or `TmarkBlocksView(document.content)` inside your own layout. Application-defined
block types can provide their own view anywhere in the tree:

```swift
TmarkDocumentView(document)
    .tmarkBlockRenderer { block -> Text? in
        guard let callout = block as? Callout else { return nil }
        return Text(callout.title)
    }
```

Returning `nil` uses the built-in renderer. The modifier also allows replacing
the view for a built-in block.

Inline types use the same pattern:

```swift
.tmarkInlineRenderer { node -> Text? in
    guard let mention = node as? Mention else { return nil }
    return Text("@\(mention.user)")
}
```

The result is `Text` so it can compose with surrounding formatting.

A named field with `required: true` must be present. Other missing fields retain
the value supplied by `make`. A nil field name describes the unnamed body.
`.optional()` preserves the distinction between missing values and explicit empty
strings or `false`. Nonempty defaults are preserved when serializing empty values.
Use a fresh model from `make`; factory and mapping closures should have no side effects.

`FieldTypes` includes strings, integers, finite doubles, booleans, string-backed
enums, typed `node`/`nodes`/`rows`, `richText`, and `blocks`. Untagged records use
`RecordType` and `FieldTypes.record`. Custom scalar values use `FieldTypes.scalar`
or an existing field codec's `mapped(decode:encode:)`. Node codecs validate the
requested concrete type or protocol, including for externally registered nodes.

Unknown tags throw in strict mode; `soft: true` preserves them as raw `Unknown`
values. Known schemas still reject malformed fields and wrong node categories.
