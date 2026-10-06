import SwiftUI
import TMark
import TMarkSwiftUI
import SwaTex
import SwaTexRender

#if os(macOS)
import AppKit
private let inlineMathSize = NSFont.systemFontSize
#else
import UIKit
private let inlineMathSize: CGFloat = 17
#endif

struct ExampleView: View {
    @State private var examples: [ExampleDocument] = []
    @State private var selectedID: String?
    @State private var error: String?
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var mathSize = inlineMathSize

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
                    .tmarkBlockRenderer { block -> AnyView? in
                        guard let math = block as? MathBlock else { return nil }
                        return AnyView(
                            MathView(math.expression)
                                .font(size: 22)
                                .mathColor(.primary)
                                .frame(maxWidth: .infinity)
                        )
                    }
                    .tmarkInlineRenderer { node -> Text? in
                        if let math = node as? Math {
                            let color: SwaTex.Color = colorScheme == .dark ? .white : .black
                            return inlineMath(math.expression, fontSize: mathSize, color: color)
                        }
                        if let code = node as? Code {
                            var text = AttributedString(code.text)
                            text.backgroundColor = .gray.opacity(0.16)
                            return Text(text).font(.system(.body, design: .monospaced))
                        }
                        return nil
                    }
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

private func inlineMath(_ expression: String, fontSize: CGFloat, color: SwaTex.Color) -> Text? {
    guard let list = try? SwaTexEngine.displayList(for: expression, style: .text, color: color) else {
        return nil
    }
    let options = RenderOptions(fontSize: fontSize, padding: 0)
    let metrics = DisplayListRenderer.metrics(for: list, options: options)
    let scale: CGFloat = 2
    guard let cgImage = SwaTexRender.ImageRenderer.image(
        for: list, options: options, displayScale: scale
    ) else { return nil }
    #if os(macOS)
    let image = NSImage(cgImage: cgImage, size: CGSize(width: metrics.width, height: metrics.height))
    let mathImage = Image(nsImage: image)
    #else
    let image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    let mathImage = Image(uiImage: image)
    #endif
    return Text(mathImage).baselineOffset(metrics.baseline - metrics.height)
}
