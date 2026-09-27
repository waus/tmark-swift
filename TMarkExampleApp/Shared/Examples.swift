import Foundation
import TMark

struct ExampleDocument: Identifiable {
    var path: String
    var document: Document

    var id: String { path }

    var title: String { document.title }
}

func loadExamples() async throws -> [ExampleDocument] {
    let baseURL = URL(string: "https://tmark.waus.app/examples/")!
    let filenames = [
        "all_widgets.tmark",
        "edge_cases.tmark",
        "edge_empties.tmark",
        "inline_formatting.tmark",
        "lists_and_tasks.tmark",
        "maps_and_events.tmark",
        "math_and_code.tmark",
        "media_formats.tmark",
        "media_gallery.tmark",
        "quotes_and_details.tmark",
        "references_and_anchors.tmark",
        "tables.tmark",
    ]
    var examples: [ExampleDocument] = []
    for filename in filenames {
        let url = baseURL.appendingPathComponent(filename)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        examples.append(try ExampleDocument(path: filename, document: unmarshalDocument(source, soft: true)))
    }
    return examples
}
