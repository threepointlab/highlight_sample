import SwiftUI
import UIKit
import AVFoundation

// MARK: - Constants

private let handleSideWidth: CGFloat = 20
private let frameBarHeight: CGFloat = 5
private let frameCornerRadius: CGFloat = 14
private let innerCutoutRadius: CGFloat = 8
private let dimOpacity: Double = 0.62
private let glowOpacityIdle: Double = 0.35
private let glowOpacityActive: Double = 0.60
private let handleScaleActive: CGFloat = 1.03
private let minZoom: CGFloat = 1
private let maxZoom: CGFloat = 5
private let handleHitSlop: CGFloat = 16

// MARK: - DragState

private enum DragState: Equatable {
    case idle, draggingStart, draggingEnd
}

// MARK: - HandleSide

private enum HandleSide { case start, end }

// MARK: - View

@MainActor
struct ClipRangePicker: View {
    let videoURL: URL
    let videoDuration: TimeInterval
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval

    @State private var thumbnails: [UIImage] = []
    @State private var containerWidth: CGFloat = 0
    @State private var dragState: DragState = .idle
    @State private var dragOriginStart: TimeInterval = 0
    @State private var dragOriginEnd: TimeInterval = 0
    @State private var zoom: CGFloat = 1
    @State private var contentOffset: CGFloat = 0
    @State private var scrollViewRef: UIScrollView?

    private let stripHeight: CGFloat = 56
    private let protrusion: CGFloat = 6
    private var totalHeight: CGFloat { stripHeight + protrusion * 2 }
    private var contentWidth: CGFloat { max(1, containerWidth) * zoom }
    private var zoomBucket: Int { max(1, Int(zoom.rounded(.down))) }

    private var glowOpacity: Double {
        dragState != .idle ? glowOpacityActive : glowOpacityIdle
    }

    private var isHandleDragging: Bool {
        dragState == .draggingStart || dragState == .draggingEnd
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ClipRangeScrollView(
                    contentOffsetX: $contentOffset,
                    zoomScale: $zoom,
                    containerWidth: geo.size.width,
                    totalHeight: totalHeight,
                    onMake: { scrollViewRef = $0 }
                ) {
                    scrollableContentLayer(containerW: geo.size.width)
                }
                .frame(width: geo.size.width, height: totalHeight)

                handleHitZoneLayer(containerW: geo.size.width)
                if dragState != .idle {
                    tooltipLayer(containerW: geo.size.width)
                }
            }
            .onAppear { containerWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, new in containerWidth = new }
            .onChange(of: videoURL) { _, _ in
                contentOffset = 0
                zoom = 1
                scrollViewRef?.setZoomScale(1, animated: false)
                scrollViewRef?.setContentOffset(.zero, animated: false)
            }
            .onChange(of: isHandleDragging) { _, dragging in
                scrollViewRef?.isScrollEnabled = !dragging
            }
        }
        .frame(height: totalHeight)
        .task(id: "\(videoURL)-\(zoomBucket)-\(containerWidth > 0)") { await loadThumbnails() }
    }

    // MARK: - Scrollable content layer (UIScrollView 내부 hosting — scroll/zoom은 UIKit이 담당)

    @ViewBuilder
    private func scrollableContentLayer(containerW: CGFloat) -> some View {
        let cw = max(1, containerW)
        ZStack(alignment: .topLeading) {
            thumbnailLayer(width: cw)
            dimMaskLayer(width: cw)
            frameDecorationLayer(width: cw)
        }
        .frame(width: cw, height: totalHeight, alignment: .topLeading)
    }

    // MARK: - Handle hit zone layer (viewport 좌표, 2 zones: left handle + right handle)

    @ViewBuilder
    private func handleHitZoneLayer(containerW: CGFloat) -> some View {
        let cw = max(1, containerW) * zoom
        let startContentX = clipRangeTimeToX(startTime, width: cw, duration: videoDuration)
        let endContentX   = clipRangeTimeToX(endTime,   width: cw, duration: videoDuration)
        let startVX = startContentX - contentOffset
        let endVX   = endContentX   - contentOffset
        let hitW    = handleHitSlop * 2

        ZStack(alignment: .topLeading) {
            let leftHandleX = max(0, startVX - hitW / 2)
            Color.clear
                .frame(width: hitW, height: totalHeight)
                .contentShape(Rectangle())
                .offset(x: leftHandleX)
                .gesture(handleDragGesture(side: .start, contentW: cw))

            let rightHandleX = max(0, endVX - hitW / 2)
            Color.clear
                .frame(width: hitW, height: totalHeight)
                .contentShape(Rectangle())
                .offset(x: rightHandleX)
                .gesture(handleDragGesture(side: .end, contentW: cw))
        }
        .frame(width: containerW, height: totalHeight, alignment: .topLeading)
    }

    // MARK: - Thumbnail layer

    @ViewBuilder
    private func thumbnailLayer(width: CGFloat) -> some View {
        let count = thumbnails.count
        HStack(spacing: Spacing.xxs) {
            if count == 0 {
                Rectangle()
                    .fill(AppColor.Surface.placeholder)
                    .frame(height: stripHeight)
            } else {
                let cellWidth = max(0, (width - CGFloat(count - 1) * Spacing.xxs) / CGFloat(count))
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cellWidth, height: stripHeight)
                        .clipped()
                }
            }
        }
        .frame(height: stripHeight)
        .padding(.vertical, protrusion)
    }

    // MARK: - Dim mask layer

    @ViewBuilder
    private func dimMaskLayer(width: CGFloat) -> some View {
        let startX = clipRangeTimeToX(startTime, width: width, duration: videoDuration)
        let endX   = clipRangeTimeToX(endTime,   width: width, duration: videoDuration)
        let selW   = max(0, endX - startX)
        Color.black.opacity(dimOpacity)
            .frame(width: width, height: stripHeight)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: innerCutoutRadius)
                    .frame(width: selW, height: stripHeight)
                    .offset(x: startX)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .offset(y: protrusion)
    }

    // MARK: - Frame decoration layer (handles INSIDE selection — no boundary clipping)

    private func frameDecorationLayer(width: CGFloat) -> some View {
        let startX = clipRangeTimeToX(startTime, width: width, duration: videoDuration)
        let endX   = clipRangeTimeToX(endTime,   width: width, duration: videoDuration)
        let selW   = max(0, endX - startX)
        let leftScale: CGFloat  = dragState == .draggingStart ? handleScaleActive : 1
        let rightScale: CGFloat = dragState == .draggingEnd   ? handleScaleActive : 1
        return ZStack(alignment: .topLeading) {
            // Top bar
            AppColor.Accent.brand
                .frame(width: selW, height: frameBarHeight)
                .offset(x: startX, y: protrusion - frameBarHeight)
            // Bottom bar
            AppColor.Accent.brand
                .frame(width: selW, height: frameBarHeight)
                .offset(x: startX, y: protrusion + stripHeight)
            // Left handle — inside selection
            ZStack {
                UnevenRoundedRectangle(cornerRadii: .init(
                    topLeading: frameCornerRadius, bottomLeading: frameCornerRadius,
                    bottomTrailing: 0, topTrailing: 0
                ))
                .fill(AppColor.Accent.brand)
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: handleSideWidth, height: totalHeight)
            .shadow(color: AppColor.Accent.brand.opacity(glowOpacity), radius: 8)
            .scaleEffect(leftScale, anchor: .center)
            .animation(.snappy(duration: 0.15), value: dragState)
            .offset(x: startX)
            // Right handle — inside selection
            ZStack {
                UnevenRoundedRectangle(cornerRadii: .init(
                    topLeading: 0, bottomLeading: 0,
                    bottomTrailing: frameCornerRadius, topTrailing: frameCornerRadius
                ))
                .fill(AppColor.Accent.brand)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: handleSideWidth, height: totalHeight)
            .shadow(color: AppColor.Accent.brand.opacity(glowOpacity), radius: 8)
            .scaleEffect(rightScale, anchor: .center)
            .animation(.snappy(duration: 0.15), value: dragState)
            .offset(x: max(startX, endX - handleSideWidth))
        }
    }

    // MARK: - Tooltip layer (viewport 좌표)

    @ViewBuilder
    private func tooltipLayer(containerW: CGFloat) -> some View {
        let time: TimeInterval = dragState == .draggingEnd ? endTime : startTime
        let contentX = clipRangeTimeToX(time, width: contentWidth, duration: videoDuration)
        let visibleX = contentX - contentOffset
        let formatted = String(format: "%.1f초", time)
        Text(formatted)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.Text.primary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Color.black.opacity(0.7), in: Capsule())
            .offset(x: max(0, min(visibleX - 30, containerW - 60)), y: -28)
    }

    // MARK: - Gesture: Handle drag (즉시, long-press 불필요)

    private func handleDragGesture(side: HandleSide, contentW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragState == .idle {
                    dragState       = side == .start ? .draggingStart : .draggingEnd
                    dragOriginStart = startTime
                    dragOriginEnd   = endTime
                }
                let expected: DragState = side == .start ? .draggingStart : .draggingEnd
                guard dragState == expected else { return }
                let deltaT = clipRangeXToTime(value.translation.width, width: contentW, duration: videoDuration)
                if side == .start {
                    startTime = clipRangeClampStart(dragOriginStart + deltaT, endTime: dragOriginEnd, videoDuration: videoDuration)
                } else {
                    endTime = clipRangeClampEnd(dragOriginEnd + deltaT, startTime: dragOriginStart, videoDuration: videoDuration)
                }
            }
            .onEnded { _ in dragState = .idle }
    }

    // MARK: - Thumbnail loading

    private func loadThumbnails() async {
        guard videoDuration > 0 else { return }
        let cw = containerWidth > 0 ? containerWidth * CGFloat(zoomBucket) : 300
        let count = max(5, min(Int(cw / 44), 60))
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 66, height: 112)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)

        var result: [UIImage] = []
        for i in 0 ..< count {
            let t = videoDuration * Double(i) / Double(max(1, count - 1))
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            if let cgImg = try? await generator.image(at: cmTime).image {
                result.append(UIImage(cgImage: cgImg))
            }
        }
        thumbnails = result
    }
}

// MARK: - Previews

#Preview("로딩 중 (thumbnails = [])") {
    @Previewable @State var start: TimeInterval = 2
    @Previewable @State var end: TimeInterval = 8
    ClipRangePicker(
        videoURL: URL(fileURLWithPath: "/dev/null"),
        videoDuration: 15,
        startTime: $start,
        endTime: $end
    )
    .padding()
    .background(AppColor.BG.primary)
}

#Preview("구조 확인 (실제 URL 없음)") {
    @Previewable @State var start: TimeInterval = 3
    @Previewable @State var end: TimeInterval = 11
    ClipRangePicker(
        videoURL: URL(fileURLWithPath: "/dev/null"),
        videoDuration: 15,
        startTime: $start,
        endTime: $end
    )
    .padding()
    .background(AppColor.BG.primary)
}

// MARK: - Coordinate helpers (internal for @testable import)

let clipRangeMinDuration: TimeInterval = 0.5

func clipRangeXToTime(_ x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
    guard width > 0 else { return 0 }
    return duration * Double(x / width)
}

func clipRangeTimeToX(_ time: TimeInterval, width: CGFloat, duration: TimeInterval) -> CGFloat {
    guard duration > 0 else { return 0 }
    return CGFloat(time / duration) * width
}

func clipRangeClampStart(_ candidate: TimeInterval, endTime: TimeInterval, videoDuration: TimeInterval) -> TimeInterval {
    let hi = max(0, endTime - clipRangeMinDuration)
    return max(0, min(candidate, hi))
}

func clipRangeClampEnd(_ candidate: TimeInterval, startTime: TimeInterval, videoDuration: TimeInterval) -> TimeInterval {
    let lo = startTime + clipRangeMinDuration
    return max(lo, min(candidate, videoDuration))
}

func clipRangeClampRange(newStart: TimeInterval, newEnd: TimeInterval, videoDuration: TimeInterval) -> (TimeInterval, TimeInterval) {
    let dur = max(clipRangeMinDuration, newEnd - newStart)
    let clampedStart = max(0, min(newStart, videoDuration - dur))
    return (clampedStart, clampedStart + dur)
}

func clipRangeOffsetForPinch(
    focalContentX: CGFloat,
    focalViewportX: CGFloat,
    newZoom: CGFloat,
    oldZoom: CGFloat
) -> CGFloat {
    focalContentX * (newZoom / oldZoom) - focalViewportX
}

func clipRangeClampOffset(
    _ offset: CGFloat,
    contentWidth: CGFloat,
    containerWidth: CGFloat
) -> CGFloat {
    let maxOffset = max(0, contentWidth - containerWidth)
    return max(0, min(offset, maxOffset))
}

// MARK: - UIKit scroll + zoom wrapper

@MainActor
struct ClipRangeScrollView<Content: View>: UIViewRepresentable {
    @Binding var contentOffsetX: CGFloat
    @Binding var zoomScale: CGFloat
    let containerWidth: CGFloat
    let totalHeight: CGFloat
    let onMake: (UIScrollView) -> Void
    let content: Content

    init(
        contentOffsetX: Binding<CGFloat>,
        zoomScale: Binding<CGFloat>,
        containerWidth: CGFloat,
        totalHeight: CGFloat,
        onMake: @escaping (UIScrollView) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._contentOffsetX = contentOffsetX
        self._zoomScale      = zoomScale
        self.containerWidth  = containerWidth
        self.totalHeight     = totalHeight
        self.onMake          = onMake
        self.content         = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = minZoom
        scroll.maximumZoomScale = maxZoom
        scroll.bouncesZoom      = true
        scroll.bounces          = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator   = false
        scroll.clipsToBounds           = false
        scroll.delaysContentTouches    = false
        scroll.canCancelContentTouches = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = context.coordinator

        let hosting = UIHostingController(rootView: AnyView(content))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = true
        hosting.view.frame = CGRect(x: 0, y: 0, width: containerWidth, height: totalHeight)
        scroll.addSubview(hosting.view)
        scroll.contentSize = hosting.view.frame.size
        context.coordinator.hosting = hosting

        context.coordinator.onScroll = { [self] x in contentOffsetX = x }
        context.coordinator.onZoom   = { [self] s in zoomScale = s }

        onMake(scroll)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onScroll = { [self] x in contentOffsetX = x }
        context.coordinator.onZoom   = { [self] s in zoomScale = s }

        context.coordinator.hosting?.rootView = AnyView(content)

        let baseSize = CGSize(width: containerWidth, height: totalHeight)
        if context.coordinator.hosting?.view.frame.size != baseSize {
            context.coordinator.hosting?.view.frame = CGRect(origin: .zero, size: baseSize)
            scroll.contentSize = baseSize
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hosting: UIHostingController<AnyView>?
        var onScroll: ((CGFloat) -> Void)?
        var onZoom: ((CGFloat) -> Void)?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hosting?.view
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScroll?(scrollView.contentOffset.x)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            onZoom?(scrollView.zoomScale)
            onScroll?(scrollView.contentOffset.x)
        }
    }
}
