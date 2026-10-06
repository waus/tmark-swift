import TMark
import Foundation
import AVFoundation
import AVKit
import MapKit
import SwiftUI

#if os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#else
import UIKit
private typealias PlatformImage = UIImage
#endif

#if os(macOS)
private let defaultInlineIconHeight = NSFont.systemFontSize
#else
private let defaultInlineIconHeight: CGFloat = 17
#endif

public struct TmarkDocumentView: View {
    public var document: TMark.Document
    public var maxWidth: CGFloat

    public init(_ document: TMark.Document, maxWidth: CGFloat = 760) {
        self.document = document
        self.maxWidth = maxWidth
    }

    public var body: some View {
        ScrollView {
            TmarkBlocksView(document.content)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .padding()
        }
        .textSelection(.enabled)
    }
}

private struct TmarkBlockRendererKey: EnvironmentKey {
    static var defaultValue: ((any BlockNode) -> AnyView?)? { nil }
}

private struct TmarkInlineRendererKey: EnvironmentKey {
    static var defaultValue: ((any RichNode) -> Text?)? { nil }
}

private extension EnvironmentValues {
    var tmarkBlockRenderer: ((any BlockNode) -> AnyView?)? {
        get { self[TmarkBlockRendererKey.self] }
        set { self[TmarkBlockRendererKey.self] = newValue }
    }
    var tmarkInlineRenderer: ((any RichNode) -> Text?)? {
        get { self[TmarkInlineRendererKey.self] }
        set { self[TmarkInlineRendererKey.self] = newValue }
    }
}

public extension View {
    /// Renders application-defined blocks and can override built-in blocks.
    func tmarkBlockRenderer<Content: View>(
        _ render: @escaping (any BlockNode) -> Content?
    ) -> some View {
        environment(\.tmarkBlockRenderer, { block in render(block).map { AnyView($0) } })
    }

    /// Renders application-defined inline nodes as composable SwiftUI text.
    func tmarkInlineRenderer(_ render: @escaping (any RichNode) -> Text?) -> some View {
        environment(\.tmarkInlineRenderer, render)
    }
}

public struct TmarkBlocksView: View {
    public var blocks: RichBlocks

    public init(_ blocks: RichBlocks) {
        self.blocks = blocks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                TmarkBlockView(block)
            }
        }
    }
}

public struct TmarkBlockView: View {
    public var block: any BlockNode
    @Environment(\.tmarkBlockRenderer) private var customRenderer

    public init(_ block: any BlockNode) {
        self.block = block
    }

    public var body: some View {
        Group {
            if let customView = customRenderer?(block) {
                customView
            } else {
                builtInView
            }
        }
    }

    @ViewBuilder private var builtInView: some View {
        switch block {
        case let v as Paragraph:
            RichTextView(v.children)
        case let v as Header:
            RichTextView(v.children).font(headerFont(v.size)).padding(.top, 4)
        case let v as Preformatted:
            CodeBlock(v.text)
        case let v as MathBlock:
            CodeBlock(v.expression)
        case is TMark.Divider:
            SwiftUI.Divider()
        case let v as Blockquote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(.secondary.opacity(0.6)).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    TmarkBlocksView(v.blocks)
                    CaptionLines(Caption(credit: v.credit))
                }
            }
        case let v as PullQuote:
            VStack(alignment: .center, spacing: 6) {
                RichTextView(v.text)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                CaptionLines(Caption(credit: v.credit))
            }
            .frame(maxWidth: .infinity)
        case let v as ListBlock:
            TmarkListView(items: v.items)
        case let v as Details:
            TmarkDetailsView(details: v)
        case let v as TMark.Table:
            TmarkTableView(table: v)
        case let v as ImageNode:
            TmarkMediaView(kind: .image, src: v.src, caption: v.caption, hasSpoiler: v.hasSpoiler)
        case let v as VideoNode:
            TmarkMediaView(kind: .video(preview: v.preview, loop: v.loop), src: v.src, caption: v.caption, hasSpoiler: v.hasSpoiler)
        case let v as AudioNode:
            TmarkMediaView(kind: .audio, src: v.src, caption: v.caption)
        case let v as MapBlock:
            VStack(spacing: 6) {
                TmarkMapView(map: v)
                if let caption = v.caption { CaptionLines(caption) }
            }
        case let v as Collage:
            TmarkCollageView(children: v.children, caption: v.caption)
        case let v as Slideshow:
            TmarkSlideshowView(children: v.children, caption: v.caption)
        case is TMark.Anchor:
            EmptyView()
        case let v as Unknown:
            CodeBlock(v.raw).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

public struct RichTextView: View {
    public var nodes: RichText
    @Environment(\.tmarkInlineRenderer) private var customRenderer
    @State private var revealedSpoilers: Set<Int> = []
    @State private var inlineIcons: [String: PlatformImage] = [:]
    @ScaledMetric(relativeTo: .body) private var inlineIconHeight = defaultInlineIconHeight

    public init(_ nodes: RichText) {
        self.nodes = nodes
    }

    public var body: some View {
        richText(
            nodes,
            revealedSpoilers: revealedSpoilers,
            inlineIcons: inlineIcons,
            inlineIconHeight: inlineIconHeight,
            customRenderer: customRenderer
        )
            #if os(macOS)
            .textSelection(.enabled)
            #endif
            .help(richHelp(nodes) ?? "")
            .environment(\.openURL, OpenURLAction { url in
                guard let index = spoilerIndex(from: url) else { return .systemAction }
                revealedSpoilers.insert(index)
                return .handled
            })
            .task(id: iconSources(nodes)) {
                for src in iconSources(nodes) where inlineIcons[src] == nil {
                    guard let url = remoteURL(src),
                          let image = try? await loadAllowedImage(url)
                    else { continue }
                    inlineIcons[src] = image
                }
            }
    }
}

private struct TmarkMapView: View {
    var map: MapBlock

    var body: some View {
        Map(initialPosition: .region(region(for: map))) {
            Marker("Center", coordinate: CLLocationCoordinate2D(latitude: map.lat, longitude: map.lon))
        }
        .frame(height: 280)
    }

    private func region(for map: MapBlock) -> MKCoordinateRegion {
        let zoom = Double(map.zoom ?? 12)
        let delta = 360.0 / pow(2.0, zoom)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: map.lat, longitude: map.lon),
            span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
        )
    }
}

private struct CodeBlock: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.55))
    }
}

private struct TmarkListView: View {
    var items: [ListItem]

    var body: some View {
        let markers = listMarkers(items)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    if let checked = item.checked {
                        CheckboxMark(checked: checked)
                            .frame(width: 28, alignment: .trailing)
                    } else {
                        Text(markers[index])
                            .frame(width: 28, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                    TmarkBlocksView(item.children)
                }
            }
        }
    }
}

private struct CheckboxMark: View {
    var checked: Bool

    var body: some View {
        #if os(macOS)
        Toggle("", isOn: .constant(checked))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(true)
        #else
        Image(systemName: checked ? "checkmark.square" : "square")
            .foregroundStyle(.secondary)
        #endif
    }
}

private struct TmarkDetailsView: View {
    var details: Details
    @State private var isExpanded: Bool

    init(details: Details) {
        self.details = details
        _isExpanded = State(initialValue: details.isOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16)
                    RichTextView(details.summary.isEmpty ? [TText("Details")] : details.summary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(.secondary.opacity(0.4))
                        .frame(width: 1)
                        .frame(width: 16)
                    TmarkBlocksView(details.children)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 8)
                }
                .padding(.top, 6)
            }
        }
    }
}

private enum MediaKind {
    case image
    case video(preview: String, loop: Bool)
    case audio

    var label: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        }
    }
}

private struct TmarkMediaView: View {
    var kind: MediaKind
    var src: String
    var caption: Caption?
    var hasSpoiler = false
    @State private var isSpoilerRevealed = false

    var body: some View {
        VStack(spacing: 6) {
            media
                .overlay {
                    if hasSpoiler && !isSpoilerRevealed {
                        Rectangle()
                            .fill(.regularMaterial)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isSpoilerRevealed = true
                            }
                            .accessibilityLabel("Reveal spoiler")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .onChange(of: src) {
                    isSpoilerRevealed = false
                }
                .onChange(of: hasSpoiler) {
                    isSpoilerRevealed = false
                }
            if let caption {
                CaptionLines(caption)
            }
        }
    }

    @ViewBuilder
    private var media: some View {
        if let url = remoteURL(src) {
            switch kind {
            case .image:
                AllowedImageView(url: url)
            case let .video(preview, loop):
                TmarkVideoView(url: url, preview: preview, loop: loop)
            case .audio:
                AudioPlayerView(url: url)
            }
        } else {
            MediaPlaceholder(text: "\(kind.label): \(src)")
        }
    }
}

private struct AllowedImageView: View {
    var url: URL
    @State private var image: PlatformImage?
    @State private var message: String?

    var body: some View {
        Group {
            if let image {
                inlineImage(image).resizable().scaledToFit()
            } else if let message {
                MediaPlaceholder(text: message)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .task(id: url) {
            image = nil
            message = nil
            do {
                image = try await loadAllowedImage(url)
            } catch ImageLoadError.unsupportedFormat {
                message = "Unsupported image format"
            } catch {
                guard !Task.isCancelled else { return }
                message = "Image load error: \(error.localizedDescription)"
            }
        }
    }
}

private struct MediaPlaceholder: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().stroke(.secondary.opacity(0.35)))
    }
}

private struct TmarkVideoView: View {
    var url: URL
    var preview: String
    var loop: Bool
    @State private var image: PlatformImage?
    @State private var error: String?
    @State private var loopPlayer: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var downloadedFile: URL?
    @State private var modalPlayer: AVPlayer?
    @State private var showingPlayer = false

    private var ratio: CGFloat {
        guard let image, image.size.height > 0 else { return 16 / 9 }
        return image.size.width / image.size.height
    }

    var body: some View {
        ZStack {
            if let loopPlayer {
                SilentVideoSurface(player: loopPlayer)
            } else if let image {
                inlineImage(image).resizable().scaledToFit()
            } else if let error {
                MediaPlaceholder(text: error)
            } else {
                ProgressView()
            }
            if !loop, image != nil {
                Button {
                    modalPlayer = AVPlayer(url: url)
                    showingPlayer = true
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .padding(18)
                        .background(.black.opacity(0.65), in: Circle())
                }
                .accessibilityLabel("Play video")
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(ratio, contentMode: .fit)
        .task(id: "\(url.absoluteString)|\(preview)|\(loop)") {
            stopLoop()
            image = nil
            error = nil
            guard let previewURL = remoteURL(preview) else {
                error = "Video preview unavailable"
                return
            }
            do {
                image = try await loadAllowedImage(previewURL)
            } catch {
                if !Task.isCancelled { self.error = "Video preview error: \(error.localizedDescription)" }
            }
        }
        .task(id: image != nil && loop) {
            if image != nil && loop { await startLoop() }
        }
        .onDisappear {
            stopLoop()
            modalPlayer?.pause()
            modalPlayer = nil
        }
        .sheet(isPresented: $showingPlayer, onDismiss: {
            modalPlayer?.pause()
            modalPlayer = nil
        }) {
            if let modalPlayer {
                VStack {
                    HStack {
                        Spacer()
                        Button("Close") { showingPlayer = false }
                    }
                    VideoPlayer(player: modalPlayer)
                }
                .padding()
                .frame(minWidth: 320, minHeight: 260)
                .onAppear { modalPlayer.play() }
                .onDisappear { modalPlayer.pause() }
            }
        }
    }

    private func startLoop() async {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            try Task.checkCancellation()
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
            try FileManager.default.moveItem(at: temporaryURL, to: localURL)
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: localURL)
                return
            }
            let player = AVQueuePlayer()
            player.isMuted = true
            let repeating = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: localURL))
            downloadedFile = localURL
            looper = repeating
            loopPlayer = player
            player.play()
        } catch {
            // Keep the preview visible if the loop cannot be downloaded.
        }
    }

    private func stopLoop() {
        loopPlayer?.pause()
        loopPlayer = nil
        looper = nil
        if let downloadedFile { try? FileManager.default.removeItem(at: downloadedFile) }
        downloadedFile = nil
    }
}

#if os(macOS)
private struct SilentVideoSurface: NSViewRepresentable {
    var player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = AVPlayerLayer(player: player)
        (view.layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view.layer as? AVPlayerLayer)?.player = player
    }
}
#else
private final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct SilentVideoSurface: UIViewRepresentable {
    var player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
    }
}
#endif

private struct AudioPlayerView: View {
    var url: URL
    @StateObject private var model = AudioPlayerModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    model.toggle()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .disabled(!model.isReady || model.isStarting)

                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent)
                        .lineLimit(1)
                    if let error = model.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    } else if !model.isReady {
                        Text("Loading audio...").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text(formatDuration(model.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { model.currentTime },
                        set: { model.seek(to: $0) }
                    ),
                    in: 0...max(model.duration, 0.01)
                )
                .disabled(!model.isReady)
                Text(formatDuration(model.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
            }
            .opacity(model.isReady ? 1 : 0.45)
        }
        .onDisappear {
            model.stop()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .overlay(Rectangle().stroke(.secondary.opacity(0.35)))
        .task(id: url) {
            await model.load(url: url)
        }
    }
}

private func formatDuration(_ value: TimeInterval) -> String {
    guard value.isFinite, value >= 0 else { return "0:00" }
    let total = Int(value.rounded())
    let minutes = total / 60
    let seconds = total % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
}

@MainActor
private final class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isReady = false
    @Published var isPlaying = false
    @Published var isStarting = false
    @Published var error: String?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var decodedAudioURL: URL?
    private var progressTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?

    func load(url: URL) async {
        stop()
        isReady = false
        error = nil
        currentTime = 0
        duration = 0

        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (loaded, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
                data = loaded
            }

            try Task.checkCancellation()
            guard MediaFormats.allowsAudio(data) else {
                self.error = "Unsupported audio codec, container or profile"
                return
            }
            var decodedURL: URL?
            defer {
                if let decodedURL, decodedAudioURL != decodedURL {
                    try? FileManager.default.removeItem(at: decodedURL)
                }
            }
            let player: AVAudioPlayer
            if data.starts(with: Data("OggS".utf8)) {
                do {
                    let decoded = try await NativeAudioDecoder.decodeOpus(data)
                    decodedURL = decoded
                    try Task.checkCancellation()
                    player = try AVAudioPlayer(contentsOf: decoded)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = "Audio format is not supported by this system"
                    return
                }
            } else {
                player = try AVAudioPlayer(data: data)
            }
            try await NativeAudioSession.activate()
            player.delegate = self
            guard player.prepareToPlay() else {
                self.error = "Audio format is not supported by this system"
                return
            }
            self.player = player
            decodedAudioURL = decodedURL
            duration = player.duration
            isReady = true
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Audio load error: \(error.localizedDescription)"
        }
    }

    func toggle() {
        guard let player, !isStarting else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopProgress()
        } else {
            isStarting = true
            error = nil
            playbackTask = Task { [weak self] in
                do {
                    try await NativeAudioSession.activate()
                    guard let self, self.player === player else { return }
                    self.isStarting = false
                    self.playbackTask = nil
                    guard player.play() else {
                        self.error = "Audio playback failed"
                        return
                    }
                    self.isPlaying = true
                    self.startProgress()
                } catch {
                    guard !Task.isCancelled, let self, self.player === player else { return }
                    self.isStarting = false
                    self.playbackTask = nil
                    self.error = "Audio playback failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isStarting = false
        stopProgress()
        player?.stop()
        player = nil
        if let decodedAudioURL {
            try? FileManager.default.removeItem(at: decodedAudioURL)
            self.decodedAudioURL = nil
        }
        isReady = false
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func startProgress() {
        stopProgress()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    guard let self, let player = self.player else { return }
                    self.currentTime = player.currentTime
                }
            }
        }
    }

    private func stopProgress() {
        progressTask?.cancel()
        progressTask = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let duration = player.duration
        Task { @MainActor in
            currentTime = duration
            isPlaying = false
            stopProgress()
        }
    }
}

private struct TmarkCollageView: View {
    var children: [any GalleryNode]
    var caption: Caption?
    @State private var resolvedRatios: [String: CGFloat] = [:]

    var body: some View {
        let ratios = galleryRatios(children, resolved: resolvedRatios)
        VStack(spacing: 8) {
            GroupedMediaViewLayout(ratios: ratios, minWidth: 96, spacing: 2) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, node in
                    GalleryItemView(node: node)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.08))
                        .clipped()
                }
            }
            if let caption {
                CaptionLines(caption)
            }
        }
        .task(id: children.map(gallerySource)) {
            resolvedRatios = [:]
            for node in children {
                let source: String? = if let image = node as? ImageNode { image.src }
                    else if let video = node as? VideoNode { video.preview }
                    else { nil }
                guard let source, !source.isEmpty,
                      resolvedRatios[source] == nil,
                      let url = remoteURL(source),
                      let loaded = try? await loadAllowedImage(url)
                else { continue }
                resolvedRatios[source] = min(max(loaded.size.width / loaded.size.height, 0.2), 5)
            }
        }
    }
}

private struct GroupedMediaViewLayout: Layout {
    var ratios: [CGFloat]
    var minWidth: CGFloat
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(proposal.width ?? minWidth, minWidth)
        let result = GroupedMediaGeometry(
            ratios: Array(ratios.prefix(subviews.count)),
            maxWidth: width,
            minWidth: minWidth,
            spacing: spacing
        ).layout()
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = GroupedMediaGeometry(
            ratios: Array(ratios.prefix(subviews.count)),
            maxWidth: bounds.width,
            minWidth: minWidth,
            spacing: spacing
        ).layout()
        for (index, subview) in subviews.enumerated() where index < result.tiles.count {
            let rect = result.tiles[index]
            subview.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: rect.width, height: rect.height)
            )
        }
    }
}

private struct GroupedMediaGeometry {
    var ratios: [CGFloat]
    var maxWidth: CGFloat
    var minWidth: CGFloat
    var spacing: CGFloat

    private var count: Int { ratios.count }
    private var maxHeight: CGFloat { maxWidth }
    private var averageRatio: CGFloat {
        guard count > 0 else { return 1 }
        return ratios.reduce(1, +) / CGFloat(count)
    }
    private var proportions: String {
        ratios.map { ratio in
            ratio > 1.2 ? "w" : ratio < 0.8 ? "n" : "q"
        }.joined()
    }

    func layout() -> GroupedMediaGeometryResult {
        let tiles: [CGRect] = switch count {
        case 0: []
        case 1: layoutOne()
        case 2: layoutTwo()
        case 3: layoutThree()
        case 4: layoutFour()
        default: layoutComplex()
        }
        return GroupedMediaGeometryResult(
            tiles: tiles,
            height: tiles.reduce(0) { max($0, $1.maxY) }
        )
    }

    private func layoutOne() -> [CGRect] {
        [tile(0, 0, maxWidth, maxWidth / ratios[0])]
    }

    private func layoutTwo() -> [CGRect] {
        if proportions == "ww", averageRatio > 1.4, abs(ratios[1] - ratios[0]) < 0.2 {
            let height = min(min(maxWidth / ratios[0], maxWidth / ratios[1]), (maxHeight - spacing) / 2)
            return [
                tile(0, 0, maxWidth, height),
                tile(0, height + spacing, maxWidth, height),
            ]
        }

        if proportions == "ww" || proportions == "qq" {
            let width = (maxWidth - spacing) / 2
            let height = min(min(width / ratios[0], width / ratios[1]), maxHeight)
            return [
                tile(0, 0, width, height),
                tile(width + spacing, 0, width, height),
            ]
        }

        let minimalWidth = minWidth * 1.5
        let secondWidth = min(
            max(0.4 * (maxWidth - spacing), (maxWidth - spacing) / ratios[0] / (1 / ratios[0] + 1 / ratios[1])),
            maxWidth - spacing - minimalWidth
        )
        let firstWidth = maxWidth - secondWidth - spacing
        let height = min(maxHeight, min(firstWidth / ratios[0], secondWidth / ratios[1]))
        return [
            tile(0, 0, firstWidth, height),
            tile(firstWidth + spacing, 0, secondWidth, height),
        ]
    }

    private func layoutThree() -> [CGRect] {
        if proportions.first == "n" {
            let firstHeight = maxHeight
            let thirdHeight = min(
                (maxHeight - spacing) / 2,
                ratios[1] * (maxWidth - spacing) / (ratios[2] + ratios[1])
            )
            let secondHeight = firstHeight - thirdHeight - spacing
            let rightWidth = max(
                minWidth,
                min((maxWidth - spacing) / 2, min(thirdHeight * ratios[2], secondHeight * ratios[1]))
            )
            let leftWidth = min(firstHeight * ratios[0], maxWidth - spacing - rightWidth)
            return [
                tile(0, 0, leftWidth, firstHeight),
                tile(leftWidth + spacing, 0, rightWidth, secondHeight),
                tile(leftWidth + spacing, secondHeight + spacing, rightWidth, thirdHeight),
            ]
        }

        let firstHeight = min(maxWidth / ratios[0], (maxHeight - spacing) * 0.66)
        let secondWidth = (maxWidth - spacing) / 2
        let secondHeight = min(
            maxHeight - firstHeight - spacing,
            min(secondWidth / ratios[1], secondWidth / ratios[2])
        )
        let thirdWidth = maxWidth - secondWidth - spacing
        return [
            tile(0, 0, maxWidth, firstHeight),
            tile(0, firstHeight + spacing, secondWidth, secondHeight),
            tile(secondWidth + spacing, firstHeight + spacing, thirdWidth, secondHeight),
        ]
    }

    private func layoutFour() -> [CGRect] {
        if proportions.first == "w" {
            let firstHeight = min(maxWidth / ratios[0], (maxHeight - spacing) * 0.66)
            let height = (maxWidth - 2 * spacing) / (ratios[1] + ratios[2] + ratios[3])
            let firstWidth = max(minWidth, min((maxWidth - 2 * spacing) * 0.4, height * ratios[1]))
            let thirdWidth = max(
                max(minWidth, (maxWidth - 2 * spacing) * 0.33),
                height * ratios[3]
            )
            let secondWidth = maxWidth - firstWidth - thirdWidth - 2 * spacing
            let rowHeight = min(maxHeight - firstHeight - spacing, height)
            return [
                tile(0, 0, maxWidth, firstHeight),
                tile(0, firstHeight + spacing, firstWidth, rowHeight),
                tile(firstWidth + spacing, firstHeight + spacing, secondWidth, rowHeight),
                tile(firstWidth + secondWidth + 2 * spacing, firstHeight + spacing, thirdWidth, rowHeight),
            ]
        }

        let leftWidth = min(maxHeight * ratios[0], (maxWidth - spacing) * 0.6)
        let width = (maxHeight - 2 * spacing) / (1 / ratios[1] + 1 / ratios[2] + 1 / ratios[3])
        let firstHeight = width / ratios[1]
        let secondHeight = width / ratios[2]
        let thirdHeight = maxHeight - firstHeight - secondHeight - 2 * spacing
        let rightWidth = max(minWidth, min(maxWidth - leftWidth - spacing, width))
        return [
            tile(0, 0, leftWidth, maxHeight),
            tile(leftWidth + spacing, 0, rightWidth, firstHeight),
            tile(leftWidth + spacing, firstHeight + spacing, rightWidth, secondHeight),
            tile(leftWidth + spacing, firstHeight + secondHeight + 2 * spacing, rightWidth, thirdHeight),
        ]
    }

    private func layoutComplex() -> [CGRect] {
        let cropped = ratios.map { ratio in
            averageRatio > 1.1 ? min(max(ratio, 1), 2.75) : min(max(ratio, 0.6667), 1)
        }
        var attempts: [GroupedMediaAttempt] = []

        func push(_ counts: [Int]) {
            var offset = 0
            var heights: [CGFloat] = []
            for count in counts {
                let sum = cropped[offset..<(offset + count)].reduce(0, +)
                heights.append((maxWidth - CGFloat(count - 1) * spacing) / sum)
                offset += count
            }
            attempts.append(GroupedMediaAttempt(counts: counts, heights: heights))
        }

        for first in 1..<count {
            let second = count - first
            if first <= 3, second <= 3 { push([first, second]) }
        }
        for first in 1..<(count - 1) {
            for second in 1..<(count - first) {
                let third = count - first - second
                if first <= 3, second <= (averageRatio < 0.85 ? 4 : 3), third <= 3 {
                    push([first, second, third])
                }
            }
        }
        for first in 1..<(count - 2) {
            for second in 1..<(count - first - 1) {
                for third in 1..<(count - first - second) {
                    let fourth = count - first - second - third
                    if first <= 3, second <= 3, third <= 3, fourth <= 3 {
                        push([first, second, third, fourth])
                    }
                }
            }
        }

        if attempts.isEmpty {
            var remaining = count
            var counts: [Int] = []
            while remaining > 0 {
                let next = min(3, remaining)
                counts.append(next)
                remaining -= next
            }
            push(counts)
        }

        func score(_ attempt: GroupedMediaAttempt) -> CGFloat {
            let lineCount = attempt.counts.count
            let totalHeight = attempt.heights.reduce(0, +) + spacing * CGFloat(lineCount - 1)
            let badHeight: CGFloat = (attempt.heights.min() ?? minWidth) < minWidth ? 1.5 : 1
            let badOrder: CGFloat = zip(attempt.counts, attempt.counts.dropFirst()).contains { $0 > $1 } ? 1.5 : 1
            return abs(totalHeight - maxWidth * 4 / 3) * badHeight * badOrder
        }

        let best = attempts.min { score($0) < score($1) }!
        var result: [CGRect] = []
        var index = 0
        var y: CGFloat = 0
        for row in best.counts.indices {
            let columns = best.counts[row]
            let rowHeight = best.heights[row]
            var x: CGFloat = 0
            for column in 0..<columns {
                let width = column == columns - 1 ? maxWidth - x : cropped[index] * rowHeight
                result.append(tile(x, y, width, rowHeight))
                x += width + spacing
                index += 1
            }
            y += rowHeight + spacing
        }
        return result
    }

    private func tile(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}

private struct GroupedMediaGeometryResult {
    var tiles: [CGRect]
    var height: CGFloat
}

private struct GroupedMediaAttempt {
    var counts: [Int]
    var heights: [CGFloat]
}

private func galleryRatios(
    _ children: [any GalleryNode],
    resolved: [String: CGFloat]
) -> [CGFloat] {
    children.enumerated().map { index, node in
        if let ratio = resolved[gallerySource(node)] { return ratio }
        return switch children.count {
        case 1: 1
        case 2: 1
        case 3: index == 0 ? 1.6 : 1
        case 4: index == 0 ? 1.4 : 1
        default: node is VideoNode ? 16 / 9 : 1
        }
    }
}

private func gallerySource(_ node: any GalleryNode) -> String {
    if let image = node as? ImageNode { return image.src }
    if let video = node as? VideoNode { return video.preview }
    return ""
}

private struct TmarkSlideshowView: View {
    var children: [any GalleryNode]
    var caption: Caption?

    var body: some View {
        VStack(spacing: 8) {
            TabView {
                ForEach(Array(children.enumerated()), id: \.offset) { index, node in
                    GalleryItemView(node: node)
                        .tag(index)
                        .padding(.horizontal, 1)
                }
            }
            #if os(iOS)
            .frame(minHeight: 280)
            .tabViewStyle(.page)
            #endif

            if let caption {
                CaptionLines(caption)
            }
        }
    }
}

private struct GalleryItemView: View {
    var node: any GalleryNode

    var body: some View {
        if let image = node as? ImageNode {
            TmarkMediaView(kind: .image, src: image.src, caption: image.caption, hasSpoiler: image.hasSpoiler)
        } else if let video = node as? VideoNode {
            TmarkMediaView(kind: .video(preview: video.preview, loop: video.loop), src: video.src, caption: video.caption, hasSpoiler: video.hasSpoiler)
        } else {
            EmptyView()
        }
    }
}

private struct CaptionLines: View {
    var caption: Caption

    init(_ caption: Caption) {
        self.caption = caption
    }

    var body: some View {
        if !caption.text.isEmpty || !caption.credit.isEmpty {
            VStack(spacing: 2) {
                if !caption.text.isEmpty {
                    RichTextView(caption.text)
                }
                if !caption.credit.isEmpty {
                    RichTextView(caption.credit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct TmarkTableView: View {
    var table: TMark.Table

    var body: some View {
        VStack(spacing: 6) {
            let grid = TableLayout(rows: table.rows)
            TableCellsLayout(grid: grid) {
                ForEach(Array(grid.entries.enumerated()), id: \.offset) { _, entry in
                    TableCellView(cell: entry.cell, striped: table.striped && entry.row % 2 == 1, bordered: table.bordered)
                }
            }
            if !table.caption.isEmpty {
                CaptionLines(Caption(text: table.caption))
            }
        }
    }
}

private struct TableCellsLayout: Layout, @unchecked Sendable {
    let grid: TableLayout
    #if os(macOS)
    private let minRowHeight: CGFloat = 34
    #else
    private let minRowHeight: CGFloat = 44
    #endif

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: rowHeights(subviews, width: width).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = rowHeights(subviews, width: bounds.width)
        let columnWidth = bounds.width / CGFloat(max(grid.columnCount, 1))
        var offsets: [CGFloat] = [0]
        var offset: CGFloat = 0
        for height in heights { offset += height; offsets.append(offset) }
        for (entry, subview) in zip(grid.entries, subviews) {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(entry.column) * columnWidth, y: bounds.minY + offsets[entry.row]),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: columnWidth * CGFloat(entry.colspan),
                    height: offsets[entry.row + entry.rowspan] - offsets[entry.row]
                )
            )
        }
    }

    private func rowHeights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let columnWidth = width / CGFloat(max(grid.columnCount, 1))
        var heights = Array(repeating: minRowHeight, count: grid.rowCount)
        for (entry, subview) in zip(grid.entries, subviews) where entry.rowspan == 1 {
            let needed = subview.sizeThatFits(ProposedViewSize(width: columnWidth * CGFloat(entry.colspan), height: nil)).height
            heights[entry.row] = max(heights[entry.row], needed)
        }
        for (entry, subview) in zip(grid.entries, subviews) where entry.rowspan > 1 {
            let rows = entry.row..<(entry.row + entry.rowspan)
            let needed = subview.sizeThatFits(ProposedViewSize(width: columnWidth * CGFloat(entry.colspan), height: nil)).height
            let extra = max(0, needed - heights[rows].reduce(0, +)) / CGFloat(entry.rowspan)
            for row in rows { heights[row] += extra }
        }
        return heights
    }
}

private struct TableCellView: View {
    var cell: Cell
    var striped: Bool
    var bordered: Bool

    var body: some View {
        RichTextView(cell.children)
            .font(cell.isHeader ? .headline : .body)
            .multilineTextAlignment(textAlignment(cell.align))
            .padding(.horizontal, 8)
            .padding(.vertical, tableCellVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cellAlignment(cell.align, cell.valign))
            .background(striped ? Color.secondary.opacity(0.08) : Color.clear)
            .overlay(Rectangle().stroke(bordered ? Color.secondary.opacity(0.35) : Color.clear))
    }
}

private struct TableLayout {
    var entries: [TableEntry] = []
    var rowCount = 0
    var columnCount = 0

    init(rows: [TMark.TableRow]) {
        rowCount = rows.count
        var occupied = Set<String>()
        for (rowIndex, row) in rows.enumerated() {
            var column = 0
            for cell in row.cells {
                while occupied.contains(key(rowIndex, column)) {
                    column += 1
                }
                let colspan = max(cell.colspan ?? 1, 1)
                let rowspan = max(cell.rowspan ?? 1, 1)
                entries.append(TableEntry(cell: cell, row: rowIndex, column: column, colspan: colspan, rowspan: rowspan))
                for row in rowIndex..<(rowIndex + rowspan) {
                    for col in column..<(column + colspan) {
                        occupied.insert(key(row, col))
                    }
                }
                rowCount = max(rowCount, rowIndex + rowspan)
                columnCount = max(columnCount, column + colspan)
                column += colspan
            }
        }
    }

    private func key(_ row: Int, _ column: Int) -> String {
        "\(row):\(column)"
    }
}

private struct TableEntry {
    var cell: Cell
    var row: Int
    var column: Int
    var colspan: Int
    var rowspan: Int
}

private func richText(
    _ nodes: RichText,
    revealedSpoilers: Set<Int> = [],
    inlineIcons: [String: PlatformImage] = [:],
    inlineIconHeight: CGFloat = defaultInlineIconHeight,
    customRenderer: ((any RichNode) -> Text?)? = nil
) -> Text {
    var spoilerIndex = 0
    return richText(
        nodes,
        revealedSpoilers: revealedSpoilers,
        inlineIcons: inlineIcons,
        inlineIconHeight: inlineIconHeight,
        customRenderer: customRenderer,
        spoilerIndex: &spoilerIndex
    )
}

private func richText(
    _ nodes: RichText,
    revealedSpoilers: Set<Int>,
    inlineIcons: [String: PlatformImage],
    inlineIconHeight: CGFloat,
    customRenderer: ((any RichNode) -> Text?)?,
    spoilerIndex: inout Int
) -> Text {
    nodes.reduce(Text("")) { partial, node in
        partial + richNode(
            node,
            revealedSpoilers: revealedSpoilers,
            inlineIcons: inlineIcons,
            inlineIconHeight: inlineIconHeight,
            customRenderer: customRenderer,
            spoilerIndex: &spoilerIndex
        )
    }
}

private func richNode(
    _ node: any RichNode,
    revealedSpoilers: Set<Int>,
    inlineIcons: [String: PlatformImage],
    inlineIconHeight: CGFloat,
    customRenderer: ((any RichNode) -> Text?)?,
    spoilerIndex: inout Int
) -> Text {
    if let custom = customRenderer?(node) { return custom }
    switch node {
    case let v as TText:
        return Text(v.text)
    case let v as TMark.Link:
        return Text(linkText(label: richPlain(v.children), href: v.href)).underline()
    case let v as AnchorLink:
        return richText(v.children, revealedSpoilers: revealedSpoilers, inlineIcons: inlineIcons, inlineIconHeight: inlineIconHeight, customRenderer: customRenderer, spoilerIndex: &spoilerIndex).foregroundColor(.blue)
    case let v as Reference:
        return richText(v.children, revealedSpoilers: revealedSpoilers, inlineIcons: inlineIcons, inlineIconHeight: inlineIconHeight, customRenderer: customRenderer, spoilerIndex: &spoilerIndex).font(.caption)
    case let v as ReferenceLink:
        return richText(v.children, revealedSpoilers: revealedSpoilers, inlineIcons: inlineIcons, inlineIconHeight: inlineIconHeight, customRenderer: customRenderer, spoilerIndex: &spoilerIndex).foregroundColor(.blue).font(.caption)
    case let v as Bold:
        return richText(v.children, revealedSpoilers: revealedSpoilers, inlineIcons: inlineIcons, inlineIconHeight: inlineIconHeight, customRenderer: customRenderer, spoilerIndex: &spoilerIndex).bold()
    case let v as Italic:
        return richText(v.children, revealedSpoilers: revealedSpoilers, inlineIcons: inlineIcons, inlineIconHeight: inlineIconHeight, customRenderer: customRenderer, spoilerIndex: &spoilerIndex).italic()
    case let v as Marked:
        return richText(v.children, revealedSpoilers: revealedSpoilers, inlineIcons: inlineIcons, inlineIconHeight: inlineIconHeight, customRenderer: customRenderer, spoilerIndex: &spoilerIndex).foregroundColor(.orange)
    case let v as Underline:
        return richText(v.children, revealedSpoilers: revealedSpoilers, inlineIcons: inlineIcons, inlineIconHeight: inlineIconHeight, customRenderer: customRenderer, spoilerIndex: &spoilerIndex).underline()
    case let v as Strikethrough:
        return richText(v.children, revealedSpoilers: revealedSpoilers, inlineIcons: inlineIcons, inlineIconHeight: inlineIconHeight, customRenderer: customRenderer, spoilerIndex: &spoilerIndex).strikethrough()
    case let v as Spoiler:
        let index = spoilerIndex
        spoilerIndex += 1
        return Text(spoilerText(richPlain(v.children), index: index, isRevealed: revealedSpoilers.contains(index)))
    case let v as Subscript:
        return Text(richPlain(v.children)).font(.caption2)
    case let v as Superscript:
        return Text(richPlain(v.children)).font(.caption2).baselineOffset(6)
    case let v as DateTimeNode:
        return Text(formatLocalDateTime(v.unix))
    case let v as Code:
        return Text(v.text).font(.system(.body, design: .monospaced))
    case let v as Math:
        return Text(v.expression).font(.system(.body, design: .monospaced))
    case let v as Icon:
        if let image = inlineIcons[v.src] {
            let image = sizedInlineImage(image, height: inlineIconHeight)
            return Text(inlineImage(image)).baselineOffset(-inlineIconHeight * 0.15)
        }
        return Text(v.alternativeText ?? v.src)
    case let v as Unknown:
        return Text(v.raw)
    default:
        return Text("")
    }
}

private func linkText(label: String, href: String) -> AttributedString {
    var value = AttributedString(label)
    if let url = URL(string: href), url.scheme == "http" || url.scheme == "https" {
        value.link = url
    }
    value.foregroundColor = .blue
    return value
}

private func spoilerText(_ text: String, index: Int, isRevealed: Bool) -> AttributedString {
    var value = AttributedString(text)
    if !isRevealed {
        value.foregroundColor = .clear
        value.backgroundColor = platformLabelColor()
        value.link = URL(string: "tmark-spoiler:\(index)")
    }
    return value
}

private func spoilerIndex(from url: URL) -> Int? {
    guard url.scheme == "tmark-spoiler" else { return nil }
    return Int(url.absoluteString.dropFirst("tmark-spoiler:".count))
}

private func inlineImage(_ image: PlatformImage) -> Image {
    #if os(macOS)
    Image(nsImage: image)
    #else
    Image(uiImage: image)
    #endif
}

private func sizedInlineImage(_ image: PlatformImage, height: CGFloat) -> PlatformImage {
    #if os(macOS)
    guard image.size.width > 0, image.size.height > 0,
          let resized = image.copy() as? NSImage
    else { return image }
    resized.size = CGSize(width: image.size.width * height / image.size.height, height: height)
    return resized
    #else
    guard image.size.width > 0, image.size.height > 0 else { return image }
    let size = CGSize(width: image.size.width * height / image.size.height, height: height)
    return UIGraphicsImageRenderer(size: size).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
    #endif
}

private func platformLabelColor() -> Color {
    #if os(macOS)
    Color(nsColor: .labelColor)
    #else
    Color(uiColor: .label)
    #endif
}

private func remoteURL(_ src: String) -> URL? {
    guard let url = URL(string: src), url.scheme == "http" || url.scheme == "https" else {
        return nil
    }
    return url
}

private enum ImageLoadError: Error {
    case unsupportedFormat
}

private func loadAllowedImage(_ url: URL) async throws -> PlatformImage {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let response = response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
    try Task.checkCancellation()
    guard MediaFormats.allowsImage(data) else { throw ImageLoadError.unsupportedFormat }
    guard let image = PlatformImage(data: data), image.size.height > 0 else {
        throw URLError(.cannotDecodeContentData)
    }
    return image
}

private func richPlain(_ nodes: RichText) -> String {
    nodes.map {
        if let text = $0 as? TText { return text.text }
        if let code = $0 as? Code { return code.text }
        if let date = $0 as? DateTimeNode { return formatLocalDateTime(date.unix) }
        if let children = richChildren($0) { return richPlain(children) }
        return ""
    }.joined()
}

private func iconSources(_ nodes: RichText) -> [String] {
    var sources: [String] = []
    for node in nodes {
        if let icon = node as? Icon {
            sources.append(icon.src)
        }
        if let children = richChildren(node) {
            sources.append(contentsOf: iconSources(children))
        }
    }
    return Array(Set(sources)).sorted()
}

private func richHelp(_ nodes: RichText) -> String? {
    for node in nodes {
        if let date = node as? DateTimeNode {
            return formatSourceDateTime(date.unix, timezone: date.timezone)
        }
        if let children = richChildren(node), let help = richHelp(children) {
            return help
        }
    }
    return nil
}

private func richChildren(_ node: any RichNode) -> RichText? {
    switch node {
    case let v as TMark.Link: v.children
    case let v as AnchorLink: v.children
    case let v as Reference: v.children
    case let v as ReferenceLink: v.children
    case let v as Bold: v.children
    case let v as Italic: v.children
    case let v as Marked: v.children
    case let v as Underline: v.children
    case let v as Strikethrough: v.children
    case let v as Spoiler: v.children
    case let v as Subscript: v.children
    case let v as Superscript: v.children
    default: nil
    }
}

private func headerFont(_ size: Int) -> Font {
    switch size {
    case 1: .largeTitle.bold()
    case 2: .title.bold()
    case 3: .title2.bold()
    case 4: .title3.bold()
    case 5: .headline
    default: .subheadline.bold()
    }
}

private func listMarkers(_ items: [ListItem]) -> [String] {
    let ordered = items.contains { $0.type != nil || $0.order != nil }
    guard ordered else {
        return Array(repeating: "•", count: items.count)
    }

    var current = 0
    return items.map { item in
        current = item.order ?? current + 1
        return "\(orderedMarker(current, type: item.type ?? "1"))."
    }
}

private func orderedMarker(_ value: Int, type: String) -> String {
    switch type {
    case "a": alphaMarker(value).lowercased()
    case "A": alphaMarker(value).uppercased()
    case "i": romanMarker(value).lowercased()
    case "I": romanMarker(value).uppercased()
    default: String(value)
    }
}

private func alphaMarker(_ value: Int) -> String {
    guard value > 0 else { return String(value) }
    var n = value
    var out = ""
    while n > 0 {
        n -= 1
        out = String(UnicodeScalar(65 + n % 26)!) + out
        n /= 26
    }
    return out
}

private func romanMarker(_ value: Int) -> String {
    guard value > 0 else { return String(value) }
    var n = value
    var out = ""
    for (number, symbol) in [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
        while n >= number {
            out += symbol
            n -= number
        }
    }
    return out
}

private func formatLocalDateTime(_ unix: Int64) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
}

private func formatSourceDateTime(_ unix: Int64, timezone: String) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .long
    formatter.timeZone = TimeZone(identifier: timezone) ?? .gmt
    return "\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))) \(timezone)"
}

private func cellAlignment(_ align: TableCellAlign?, _ valign: TableCellValign?) -> Alignment {
    let horizontal: HorizontalAlignment = switch align {
    case .center: .center
    case .right: .trailing
    default: .leading
    }
    let vertical: VerticalAlignment = switch valign {
    case .top: .top
    case .middle: .center
    case .bottom: .bottom
    default: defaultTableCellVerticalAlignment
    }
    return Alignment(horizontal: horizontal, vertical: vertical)
}

#if os(macOS)
private let tableCellVerticalPadding: CGFloat = 5
private let defaultTableCellVerticalAlignment: VerticalAlignment = .center
#else
private let tableCellVerticalPadding: CGFloat = 8
private let defaultTableCellVerticalAlignment: VerticalAlignment = .top
#endif

private func textAlignment(_ align: TableCellAlign?) -> TextAlignment {
    switch align {
    case .center: .center
    case .right: .trailing
    default: .leading
    }
}
