import AVKit
import SwiftUI

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
    // start/end 시간은 하이라이트마다 독립 State (mock 값으로 초기화)
    @State private var startTimes: [Double]
    @State private var endTimes: [Double]

    init(highlights: [HighlightItem], videoURL: URL, videoDuration: Double) {
        self.highlights = highlights
        self.videoURL = videoURL
        self.videoDuration = videoDuration
        self._startTimes = State(initialValue: highlights.map { $0.startTime })
        self._endTimes = State(initialValue: highlights.map { $0.endTime })
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
                    )
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
        TabView(selection: $currentPage) {
            ForEach(Array(highlights.enumerated()), id: \.element.id) { idx, item in
                highlightCard(item: item)
                    .tag(idx)
                    .padding(.horizontal, Spacing.l)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 240)
    }

    private func highlightCard(item: HighlightItem) -> some View {
        ZStack(alignment: .top) {
            // 비디오 placeholder
            VideoPlayer(player: AVPlayer(url: videoURL))
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.m, style: .continuous))

            // 배속 칩 placeholder (0.5x 정적)
            HStack {
                speedChip
                Spacer()
            }
            .padding(.top, Spacing.s)
            .padding(.horizontal, Spacing.m)
        }
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
