import SwiftUI
import TMark
import TMarkSwiftUI

struct ExampleView: View {
    @State private var examples: [ExampleDocument] = []
    @State private var selectedID: String?
    @State private var error: String?

    var body: some View {
        NavigationSplitView {
            List(examples, selection: $selectedID) { example in
                Text(example.title)
                    .tag(example.id)
            }
            .navigationTitle("tmark examples")
        } detail: {
            if let selected = selectedExample {
                TmarkDocumentView(selected.document)
            } else if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .task {
            guard examples.isEmpty else { return }
            do {
                self.error = nil
                examples = try await loadExamples()
                selectedID = examples.first?.id
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Could not load examples: \(error.localizedDescription)"
            }
        }
    }

    private var selectedExample: ExampleDocument? {
        examples.first { $0.id == selectedID } ?? examples.first
    }
}
