import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// 하이라이트 탭 — 양옆 peek 캐러셀 + 페이지 인디케이터 + ClipRangePicker.
///
/// - start/end 는 View `@State`로만 보유. SwiftData 영속화 없음.
/// - Result 화면을 떠나면 폐기.
@MainActor
struct ResultHighlightsView: View {

    let highlights: [HighlightItem]
    let videoURL: URL
    let videoDuration: Double

    @State private var currentPage: Int = 0
    @State private var scrolledID: UUID?
    // invariant: 모든 highlight는 동일 videoURL을 공유하므로 ratio 1회 로드 재사용
    @State private var videoNativeRatio: CGFloat = 9.0 / 16.0
    @State private var players: [UUID: AVPlayer] = [:]
    // start/end 시간은 하이라이트마다 독립 State (mock 값으로 초기화)
    @State private var startTimes: [Double]
    @State private var endTimes: [Double]
    @State private var previewLoader: PreviewFrameLoader
    @State private var interactions: [ClipRangeInteraction?]
    @State private var previewImages: [UIImage?]
    @State private var generationToken: UInt64 = 0

    init(highlights: [HighlightItem], videoURL: URL, videoDuration: Double) {
        self.highlights = highlights
        self.videoURL = videoURL
        self.videoDuration = videoDuration
        self._startTimes = State(initialValue: highlights.map { $0.startTime })
        self._endTimes = State(initialValue: highlights.map { $0.endTime })
        self._scrolledID = State(initialValue: highlights.first?.id)
        let decoder = AVAssetImageGeneratorFrameDecoder(url: videoURL, scale: UIScreen.main.scale)
        self._previewLoader = State(initialValue: PreviewFrameLoader(decoder: decoder))
        self._interactions = State(initialValue: Array(repeating: nil, count: highlights.count))
        self._previewImages = State(initialValue: Array(repeating: nil, count: highlights.count))
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            // 양옆 peek 캐러셀
            carouselSection

            // 페이지 인디케이터
            pageIndicator

            // 현재 페이지 ClipRangePicker
            if highlights.indices.contains(currentPage) {
                ClipRangePicker(
                    videoURL: videoURL,
                    videoDuration: videoDuration,
                    startTime: Binding(
                        get: { startTimes[currentPage] },
                        set: { startTimes[currentPage] = $0 }
                    ),
                    endTime: Binding(
                        get: { endTimes[currentPage] },
                        set: { endTimes[currentPage] = $0 }
                    ),
                    onInteraction: { interaction in
                        handleInteraction(interaction)
                    }
                )
                .padding(.horizontal, Spacing.l)
                .id(currentPage) // 페이지 전환 시 재생성
            }

            // muted hint
            Text(LocalizedStringKey("result.hint.highlight"))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.Text.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.BG.primary)
    }

    // MARK: - Carousel

    private var carouselSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Spacing.m) {
                ForEach(highlights) { item in
                    highlightCard(item: item)
                        .containerRelativeFrame(.horizontal) { width, _ in
                            width - Spacing.xl * 2
                        }
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.88)
                                .opacity(phase.isIdentity ? 1.0 : 0.6)
                        }
                        .zIndex(item.id == scrolledID ? 1 : 0)
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledID)
        .contentMargins(.horizontal, Spacing.xl, for: .scrollContent)
        .frame(height: 240)
        .task {
            await previewLoader.request(time: 0, token: 0) { _, _ in }
            await loadNativeRatio()
        }
        .onChange(of: scrolledID) { _, newID in
            if let id = newID, let idx = highlights.firstIndex(where: { $0.id == id }) {
                currentPage = idx
            }
        }
        .onChange(of: currentPage) { oldPage, _ in
            guard highlights.indices.contains(oldPage) else { return }
            interactions[oldPage] = nil
            previewImages[oldPage] = nil
            generationToken &+= 1
            Task { await previewLoader.cancelPending() }
        }
    }

    private func highlightCard(item: HighlightItem) -> some View {
        GeometryReader { proxy in
            let displaySize = aspectFitSize(contentRatio: videoNativeRatio, container: proxy.size)
            ZStack(alignment: .top) {
                VideoPlayer(player: player(for: item))
                    .frame(width: displaySize.width, height: displaySize.height)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.m, style: .continuous))
                if let i = highlights.firstIndex(where: { $0.id == item.id }),
                   interactions[i] != nil,
                   let img = previewImages[i] {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.m, style: .continuous))
                        .allowsHitTesting(false)
                }
                HStack {
                    speedChip
                    Spacer()
                }
                .padding(.top, Spacing.s)
                .padding(.horizontal, Spacing.m)
                .frame(width: displaySize.width)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func player(for item: HighlightItem) -> AVPlayer {
        if let cached = players[item.id] { return cached }
        let p = AVPlayer(url: videoURL)
        players[item.id] = p
        return p
    }

    private var speedChip: some View {
        Text("0.5x")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.Text.primary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0 ..< highlights.count, id: \.self) { idx in
                Circle()
                    .fill(idx == currentPage ? AppColor.Text.primary : AppColor.Text.primary.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .animation(.easeOut(duration: 0.15), value: currentPage)
            }
        }
    }

    // MARK: - Video Geometry

    private func aspectFitSize(contentRatio: CGFloat, container: CGSize) -> CGSize {
        guard contentRatio > 0, container.width > 0, container.height > 0 else { return container }
        let containerRatio = container.width / container.height
        if contentRatio < containerRatio {
            let h = container.height
            return CGSize(width: h * contentRatio, height: h)
        } else {
            let w = container.width
            return CGSize(width: w, height: w / contentRatio)
        }
    }

    // TODO: 세 번째 사용처 등장 시 Cliff/Services/Media/VideoGeometry.swift로 추출
    private func loadNativeRatio() async {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let transform   = (try? await track.load(.preferredTransform)) ?? .identity
        let applied = naturalSize.applying(transform)
        let w = abs(applied.width)
        let h = abs(applied.height)
        guard w > 0, h > 0 else { return }
        videoNativeRatio = w / h
    }
}

// MARK: - Preview Interaction

private extension ResultHighlightsView {

    func handleInteraction(_ interaction: ClipRangeInteraction?) {
        let page = currentPage
        guard highlights.indices.contains(page) else { return }
        let prev = interactions[page]
        interactions[page] = interaction

        switch (prev, interaction) {
        case (nil, .some(let new)):
            player(for: highlights[page]).pause()
            generationToken &+= 1
            let token = generationToken
            let loader = previewLoader
            Task {
                await loader.cancelPending()
                await loader.request(time: timeOf(new), token: token) { [page] cgOpt, t in
                    guard t == self.generationToken,
                          self.currentPage == page,
                          self.interactions[page] != nil,
                          let cg = cgOpt else { return }
                    self.previewImages[page] = UIImage(cgImage: cg)
                }
            }

        case (.some, .some(let new)):
            let token = generationToken
            let loader = previewLoader
            Task {
                await loader.request(time: timeOf(new), token: token) { [page] cgOpt, t in
                    guard t == self.generationToken,
                          self.currentPage == page,
                          self.interactions[page] != nil,
                          let cg = cgOpt else { return }
                    self.previewImages[page] = UIImage(cgImage: cg)
                }
            }

        case (.some(let old), nil):
            let seekTime = endSeekTime(for: old, page: page)
            let p = player(for: highlights[page])
            p.seek(
                to: CMTime(seconds: seekTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [page] _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    self.previewImages[page] = nil
                }
            }

        case (nil, nil):
            break
        }
    }

    func timeOf(_ i: ClipRangeInteraction) -> TimeInterval {
        switch i {
        case .leftHandle(let t), .rightHandle(let t): return t
        case .bodyTranslate(let s): return s
        }
    }

    func endSeekTime(for i: ClipRangeInteraction, page: Int) -> TimeInterval {
        switch i {
        case .leftHandle:    return startTimes[page]
        case .rightHandle:   return endTimes[page]
        case .bodyTranslate: return startTimes[page]
        }
    }
}

#Preview {
    let mockHighlights = (0..<3).map { i in
        HighlightItem(id: UUID(), startTime: Double(i * 10 + 2), endTime: Double(i * 10 + 7), label: "하이라이트 \(i+1)")
    }
    ResultHighlightsView(
        highlights: mockHighlights,
        videoURL: URL(fileURLWithPath: "/dev/null"),
        videoDuration: 60
    )
    .preferredColorScheme(.dark)
}
