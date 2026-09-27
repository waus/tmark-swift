import Foundation
import Testing
@testable import TMark

@Test func roundTripDocument() throws {
    let document = Document(
        url: "https://example.com",
        title: "Title",
        description: "Description",
        content: [
            Header(size: 2, children: [TText("Header")]),
            Paragraph([TText("Hello "), Bold([TText("world")])]),
            Divider(),
            ListBlock([
                ListItem([Paragraph([TText("one")])]),
                ListItem([Paragraph([TText("two")])], checked: true),
            ]),
            Table(
                [
                    TableRow([Cell([TText("A")], isHeader: true), Cell([TText("B")], isHeader: true)]),
                    TableRow([Cell([TText("1")]), Cell([TText("2")])]),
                ],
                bordered: true,
                striped: true
            ),
        ]
    )

    let encoded = try marshal(document)
    let decoded = try #require(try unmarshal(encoded) as? Document)
    #expect(decoded.title == "Title")
    #expect(decoded.content.count == 5)
    #expect(try marshal(decoded) == encoded)
}

@Test func softUnknown() throws {
    let decoded = try unmarshal("{custom;value}", soft: true)
    #expect((decoded as? Unknown)?.raw == "{custom;value}")
}

@Test func escaping() throws {
    let encoded = try marshal(Paragraph([TText("#{}\\")]))
    #expect(encoded == "{p;\\#\\{\\}\\\\}")
    let decoded = try #require(try unmarshal(encoded) as? Paragraph)
    #expect((decoded.children.first as? TText)?.text == "#{}\\")
}

@Test func galleryLineMode() throws {
    let collage = "{collage;\n{img;a}\n{img;b}\n}"
    let slideshow = "{slideshow;\n{img;a}\n{video;b}\n}"
    #expect(try marshal(Collage([ImageNode(src: "a"), ImageNode(src: "b")])) == collage)
    #expect(try marshal(Slideshow([ImageNode(src: "a"), VideoNode(src: "b")])) == slideshow)
    #expect(try marshal(try #require(unmarshal(collage) as? Collage)) == collage)
    #expect(try marshal(try #require(unmarshal(slideshow) as? Slideshow)) == slideshow)
}

@Test func validFixturesRoundTripIgnoringFinalNewline() throws {
    for path in try fixtureFiles("valid", suffix: ".tmark") {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        // A file may end with LF outside the document; marshal emits just the node.
        let expected = source.hasSuffix("\n") ? String(source.dropLast()) : source
        #expect(try marshal(try unmarshalDocument(source, soft: true)) == expected, "\(path)")
    }
}

@Test func validNodeFixturesRoundTripByteForByte() throws {
    for path in try fixtureFiles("valid", suffix: ".fixture") {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        #expect(try marshal(try unmarshal(source)) == source, "\(path)")
    }
}

@Test func invalidFixturesAreRejected() throws {
    for path in try fixtureFiles("invalid", suffix: ".tmark") {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        do {
            _ = try unmarshalDocument(source)
            Issue.record("expected invalid fixture to fail: \(path)")
        } catch {
        }
    }
}

func fixtureFiles(_ dir: String, suffix: String) throws -> [String] {
    let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let directory = fixtures.appendingPathComponent(dir).path
    let files = try FileManager.default.contentsOfDirectory(atPath: directory)
        .filter { $0.hasSuffix(suffix) }
        .sorted()
        .map { "\(directory)/\($0)" }
    #expect(!files.isEmpty, "Missing fixtures: \(dir) (\(suffix))")
    return files
}
