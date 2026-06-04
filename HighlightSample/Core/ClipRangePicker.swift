import SwiftUI
import UIKit
import AVFoundation

// MARK: - Constants

/// 본 컴포넌트의 시각 상수. plan: `cliff-designsystem-components-cliprange-idempotent-hamming.md` 의 "Layer 구조".
enum ClipRangePickerConstants {
    static let stripHeight: CGFloat = 56
    static let protrusion: CGFloat = 6
    static let totalHeight: CGFloat = stripHeight + protrusion * 2
    static let handleSideWidth: CGFloat = 20
    static let frameBarHeight: CGFloat = 5
    static let frameCornerRadius: CGFloat = 14
    static let dimOpacity: CGFloat = 0.62
    static let minClipDuration: TimeInterval = 1.0
    static let strokeWidth: CGFloat = 3
    static let handleTintAlpha: CGFloat = 0.18
    static let chevronPointSize: CGFloat = 14
    static let glowOpacityIdle: CGFloat = 0.35
    static let glowOpacityActive: CGFloat = 0.60
    static let handleScaleActive: CGFloat = 1.03
    static let handleActiveAnimationDuration: TimeInterval = 0.15
    static let longPressDuration: TimeInterval = 0.3
}

// MARK: - Coordinate helpers
//
// 네임스페이스 격리를 위해 enum 안 static func 로 모음. 호출은 `ClipRangeMath.*`.
enum ClipRangeMath {
    @inlinable
    static func timeToX(_ time: TimeInterval, widthPerSecond: CGFloat) -> CGFloat {
        CGFloat(time) * widthPerSecond
    }

    @inlinable
    static func xToTime(_ x: CGFloat, widthPerSecond: CGFloat) -> TimeInterval {
        guard widthPerSecond > 0 else { return 0 }
        return TimeInterval(x / widthPerSecond)
    }

    static func clampStart(_ candidate: TimeInterval, end: TimeInterval, videoDuration: TimeInterval) -> TimeInterval {
        let upper = max(0, end - ClipRangePickerConstants.minClipDuration)
        return max(0, min(candidate, upper))
    }

    static func clampEnd(_ candidate: TimeInterval, start: TimeInterval, videoDuration: TimeInterval) -> TimeInterval {
        let lower = start + ClipRangePickerConstants.minClipDuration
        return max(lower, min(candidate, videoDuration))
    }

    /// BodyPan 평행 이동: `end − start` 길이를 보존하며 [0, videoDuration] 안으로 클램핑.
    /// duration > videoDuration 의 degenerate 케이스는 (0, videoDuration) 반환.
    static func clampRange(
        start: TimeInterval,
        end: TimeInterval,
        videoDuration: TimeInterval
    ) -> (TimeInterval, TimeInterval) {
        let duration = end - start
        guard duration > 0 else { return (start, end) }
        guard videoDuration >= duration else { return (0, videoDuration) }
        if start < 0 {
            return (0, duration)
        }
        if end > videoDuration {
            return (videoDuration - duration, videoDuration)
        }
        return (start, end)
    }

    // MARK: - Step 3: 핀치 helpers

    /// 핀치 focal point 보정 식. focal X 가 그대로 손가락 끝에 남게 하는 anchor 보정.
    /// 검증: contentOffset = focalContentX × (newZoom / oldZoom) − focalViewportX
    @inlinable
    static func offsetForPinch(
        focalContentX: CGFloat,
        focalViewportX: CGFloat,
        newZoom: CGFloat,
        oldZoom: CGFloat
    ) -> CGFloat {
        guard oldZoom > 0 else { return 0 }
        return focalContentX * (newZoom / oldZoom) - focalViewportX
    }

    /// contentOffset.x 를 [0, max(0, contentWidth − viewportWidth)] 로 클램핑.
    @inlinable
    static func clampOffset(
        _ offset: CGFloat,
        contentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let maxOffset = max(0, contentWidth - viewportWidth)
        return max(0, min(offset, maxOffset))
    }

    /// 영상 길이에 따른 maxZoom. `max(2, videoDuration / 60)` — 짧은 영상/degenerate 케이스도 최소 2배 보장.
    @inlinable
    static func maxZoom(videoDuration: TimeInterval) -> CGFloat {
        max(2, CGFloat(videoDuration) / 60)
    }
}

// MARK: - ClipRangePicker (SwiftUI 외부 시그니처)

@MainActor
struct ClipRangePicker: View {
    let videoURL: URL
    let videoDuration: TimeInterval
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval

    /// Pinch 결과로 Coordinator 가 push 하는 zoom 값. videoURL 변경 시 Coordinator 가 1 로 reset.
    @State private var zoom: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ClipRangeScrollView(
                videoURL: videoURL,
                videoDuration: videoDuration,
                viewportWidth: geo.size.width,
                startTime: $startTime,
                endTime: $endTime,
                zoom: $zoom
            )
        }
        .frame(height: ClipRangePickerConstants.totalHeight)
    }
}

// MARK: - ClipRangeScrollView (UIScrollView wrapper)

@MainActor
struct ClipRangeScrollView: UIViewRepresentable {
    let videoURL: URL
    let videoDuration: TimeInterval
    let viewportWidth: CGFloat
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval
    @Binding var zoom: CGFloat

    func makeCoordinator() -> ClipRangeCoordinator {
        ClipRangeCoordinator(
            startBinding: $startTime,
            endBinding: $endTime,
            zoomBinding: $zoom
        )
    }

    func makeUIView(context: Context) -> UIScrollView {
        let coordinator = context.coordinator
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 1
        scroll.bounces = true
        scroll.bouncesZoom = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.clipsToBounds = false
        scroll.contentInsetAdjustmentBehavior = .never
        // 좌우 20px 확장 — 영상 양 끝에서도 handle drag 가능
        scroll.contentInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        scroll.delegate = coordinator
        coordinator.scrollView = scroll

        // contentView
        let contentView = UIView(frame: .zero)
        contentView.clipsToBounds = false
        contentView.backgroundColor = .clear
        scroll.addSubview(contentView)
        coordinator.views.contentView = contentView

        // thumbnailStripView
        let thumbnailStripView = UIView()
        thumbnailStripView.clipsToBounds = true
        thumbnailStripView.backgroundColor = .clear
        contentView.addSubview(thumbnailStripView)
        coordinator.views.thumbnailStripView = thumbnailStripView

        // leftDimView / rightDimView
        let dimUIColor = UIColor.black.withAlphaComponent(ClipRangePickerConstants.dimOpacity)
        let leftDimView = UIView()
        leftDimView.backgroundColor = dimUIColor
        contentView.addSubview(leftDimView)
        coordinator.views.leftDimView = leftDimView

        let rightDimView = UIView()
        rightDimView.backgroundColor = dimUIColor
        contentView.addSubview(rightDimView)
        coordinator.views.rightDimView = rightDimView

        // clip range — 단일 shape view (외곽선 + handle tint + chevron)
        let brandUIColor = UIColor(AppColor.Accent.brand)
        let shapeView = ClipRangeShapeView(brandColor: brandUIColor)
        shapeView.clipsToBounds = false
        contentView.addSubview(shapeView)
        coordinator.views.clipRangeShapeView = shapeView

        // 제스처 전용 투명 hit zone (시각 없음)
        let leftHit = UIView()
        leftHit.backgroundColor = .clear
        contentView.addSubview(leftHit)
        coordinator.views.leftHandleHitZone = leftHit

        let rightHit = UIView()
        rightHit.backgroundColor = .clear
        contentView.addSubview(rightHit)
        coordinator.views.rightHandleHitZone = rightHit

        let bodyHitZone = UIView()
        bodyHitZone.backgroundColor = .clear
        contentView.addSubview(bodyHitZone)
        coordinator.views.bodyHitZone = bodyHitZone

        // 제스처 부착
        coordinator.attachGestures()

        // 초기 레이아웃 + 썸네일 로드
        coordinator.configure(
            videoURL: videoURL,
            videoDuration: videoDuration,
            viewportWidth: viewportWidth,
            startTime: startTime,
            endTime: endTime,
            zoom: zoom
        )

        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.configure(
            videoURL: videoURL,
            videoDuration: videoDuration,
            viewportWidth: viewportWidth,
            startTime: startTime,
            endTime: endTime,
            zoom: zoom
        )
    }
}


// MARK: - Coordinator

@MainActor
final class ClipRangeCoordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var scrollView: UIScrollView?

    /// view ref 보관 + 시각 layout 책임 컨테이너. 자세한 분리 근거는 `ClipRangeViews.swift` 참조.
    let views = ClipRangeViews()

    // configure() 변화 추적용 캐시. zoomBucket = 핀치 도중 thumbnail 재로딩 트리거용 정수 버킷.
    private var lastVideoURL: URL?
    private var lastViewportWidth: CGFloat = 0
    private var lastVideoDuration: TimeInterval = 0
    private var lastZoomBucket: Int = 0
    private var thumbnailLoadTask: Task<Void, Never>?

    // MARK: SwiftUI bindings (Step 2 + Step 3) — zoomBinding 은 Coordinator → @State push 경로.
    private let startBinding: Binding<TimeInterval>
    private let endBinding: Binding<TimeInterval>
    private let zoomBinding: Binding<CGFloat>

    // MARK: Test seams — production: Haptics.impact(.soft). 테스트는 spy closure 주입.
    var hapticsImpactSoft: @MainActor () -> Void = { Haptics.impact(.soft) }

    // MARK: 최근 configure 값 캐시 — drag/pinch 핸들러가 widthPerSecond / focal 계산에 사용.
    private var currentVideoDuration: TimeInterval = 0
    private var currentContentWidth: CGFloat = 0
    private var currentViewportWidth: CGFloat = 0
    private var currentZoom: CGFloat = 1

    // MARK: Drag state — isTranslatingRange = LongPress .began 진입 후에만 BodyPan 평행 이동.
    private var dragOriginStart: TimeInterval = 0
    private var dragOriginEnd: TimeInterval = 0
    private var isTranslatingRange: Bool = false

    // MARK: Pinch state — .began 시점의 zoom + focal X (content/viewport) snapshot.
    private var pinchSnapshotZoom: CGFloat = 1
    private var focalContentX: CGFloat = 0
    private var focalViewportX: CGFloat = 0

    // MARK: Gesture recognizers (Step 2 + Step 3)
    private var leftHandlePan: UIPanGestureRecognizer?
    private var rightHandlePan: UIPanGestureRecognizer?
    private var bodyLongPress: UILongPressGestureRecognizer?
    private var bodyPan: UIPanGestureRecognizer?
    private var pinch: UIPinchGestureRecognizer?

    init(
        startBinding: Binding<TimeInterval>,
        endBinding: Binding<TimeInterval>,
        zoomBinding: Binding<CGFloat>
    ) {
        self.startBinding = startBinding
        self.endBinding = endBinding
        self.zoomBinding = zoomBinding
        super.init()
    }

    func configure(
        videoURL: URL,
        videoDuration: TimeInterval,
        viewportWidth: CGFloat,
        startTime: TimeInterval,
        endTime: TimeInterval,
        zoom: CGFloat
    ) {
        guard viewportWidth > 0 else { return }

        // 가정 1 (plan Open Questions): videoURL 변경 시 zoom = 1, contentOffset = 0 으로 리셋.
        let videoChanged = (lastVideoURL != videoURL) && (lastVideoURL != nil)
        let effectiveZoom: CGFloat
        if videoChanged {
            effectiveZoom = 1
            // contentInset.left = 20 이므로 -20 이 영상 시작(x=0) 이 화면 좌측에 정렬되는 초기 offset.
            scrollView?.contentOffset = CGPoint(x: -20, y: 0)
            if abs(zoomBinding.wrappedValue - 1) > 0.0001 {
                zoomBinding.wrappedValue = 1
            }
        } else {
            // 안전 클램핑 — SwiftUI 가 부정 값을 흘려도 maxZoom 이내로 가둠.
            let maxZ = ClipRangeMath.maxZoom(videoDuration: videoDuration)
            effectiveZoom = max(1, min(zoom, maxZ))
        }

        let contentWidth = viewportWidth * effectiveZoom
        let viewportSize = CGSize(width: viewportWidth, height: ClipRangePickerConstants.totalHeight)

        scrollView?.frame.size = viewportSize
        scrollView?.contentSize = CGSize(width: contentWidth, height: ClipRangePickerConstants.totalHeight)

        // Drag/Pinch 핸들러가 widthPerSecond / focal 계산에 사용할 수 있도록 캐시.
        currentVideoDuration = videoDuration
        currentContentWidth = contentWidth
        currentViewportWidth = viewportWidth
        currentZoom = effectiveZoom

        views.layoutViews(
            startTime: startTime,
            endTime: endTime,
            contentWidth: contentWidth,
            videoDuration: videoDuration
        )

        // videoDuration 임계값은 1초로 완화 — 동일 영상에서 float 오차로 인한 재로딩 방지.
        // videoURL 변경이 본 트리거이고, 같은 URL 에서 duration 이 1초 이상 흔들리는 케이스는 없음.
        // Step 3: zoomBucket 변화도 트리거 — 핀치 후 SwiftUI re-render 시점에 재로딩.
        let zoomBucket = max(1, Int(effectiveZoom.rounded(.down)))
        let needsThumbnailReload = (lastVideoURL != videoURL)
            || (abs(lastViewportWidth - viewportWidth) > 0.5)
            || (abs(lastVideoDuration - videoDuration) > 1.0)
            || (lastZoomBucket != zoomBucket)
            || (views.thumbnailStripView?.subviews.isEmpty ?? true)

        lastVideoURL = videoURL
        lastViewportWidth = viewportWidth
        lastVideoDuration = videoDuration
        lastZoomBucket = zoomBucket

        if needsThumbnailReload {
            loadThumbnails(
                videoURL: videoURL,
                videoDuration: videoDuration,
                contentWidth: contentWidth
            )
        }
    }

    // MARK: thumbnails

    private func loadThumbnails(videoURL: URL, videoDuration: TimeInterval, contentWidth: CGFloat) {
        thumbnailLoadTask?.cancel()
        views.thumbnailStripView?.subviews.forEach { $0.removeFromSuperview() }
        guard videoDuration > 0, contentWidth > 0 else { return }
        let count = max(5, min(Int(contentWidth / 44), 60))

        // placeholder 셀 미리 생성 (이미지가 도착하기 전 layout 안정)
        for _ in 0 ..< count {
            let cell = UIImageView()
            cell.contentMode = .scaleAspectFill
            cell.clipsToBounds = true
            cell.backgroundColor = UIColor(AppColor.Surface.placeholder)
            views.thumbnailStripView?.addSubview(cell)
        }
        views.relayoutThumbnailCells(contentWidth: contentWidth)

        let url = videoURL
        let duration = videoDuration
        let cellCount = count

        thumbnailLoadTask = Task { [weak self] in
            let images = await Self.generateThumbnails(
                url: url,
                duration: duration,
                count: cellCount
            )
            await MainActor.run {
                guard let self else { return }
                self.views.assignThumbnailImages(images)
            }
        }
    }

    /// AVAssetImageGenerator로 N개 시점 썸네일 생성. 실패 셀은 nil.
    nonisolated private static func generateThumbnails(
        url: URL,
        duration: TimeInterval,
        count: Int
    ) async -> [UIImage?] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 66, height: 112)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        var result: [UIImage?] = []
        for index in 0 ..< count {
            if Task.isCancelled { return result }
            let denom = max(1, count - 1)
            let time = duration * Double(index) / Double(denom)
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: cmTime).image {
                result.append(UIImage(cgImage: cgImage))
            } else {
                result.append(nil)
            }
        }
        return result
    }

    // MARK: Gesture attachment (Step 2)

    /// makeUIView 종료 직전 1회 호출. 4개 recognizer 부착 + require(toFail) + delegate.
    func attachGestures() {
        guard let scroll = scrollView,
              let leftHit  = views.leftHandleHitZone,
              let rightHit = views.rightHandleHitZone,
              let body = views.bodyHitZone else { return }

        // LeftHandlePan — hit zone이 clip 바깥 좌측 20px
        let leftPan = UIPanGestureRecognizer(target: self, action: #selector(handleLeftHandlePan(_:)))
        leftPan.delegate = self
        leftHit.addGestureRecognizer(leftPan)
        leftHandlePan = leftPan

        // RightHandlePan — hit zone이 clip 바깥 우측 20px
        let rightPan = UIPanGestureRecognizer(target: self, action: #selector(handleRightHandlePan(_:)))
        rightPan.delegate = self
        rightHit.addGestureRecognizer(rightPan)
        rightHandlePan = rightPan

        // LongPress on bodyHitZone
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleBodyLongPress(_:)))
        longPress.minimumPressDuration = ClipRangePickerConstants.longPressDuration
        longPress.delegate = self
        body.addGestureRecognizer(longPress)
        bodyLongPress = longPress

        // BodyPan on bodyHitZone — LongPress 와 simultaneous
        let bPan = UIPanGestureRecognizer(target: self, action: #selector(handleBodyPan(_:)))
        bPan.delegate = self
        body.addGestureRecognizer(bPan)
        bodyPan = bPan

        // ScrollView 의 panGesture 가 handle/longPress 시작 시 트리거되지 않도록 require(toFail)
        scroll.panGestureRecognizer.require(toFail: leftPan)
        scroll.panGestureRecognizer.require(toFail: rightPan)
        scroll.panGestureRecognizer.require(toFail: longPress)
        // bodyPan 은 require(toFail) 없음 — LongPress 와 simultaneous 로만 동작

        // Pinch on UIScrollView (Step 3) — scrollPan 과 자연 simultaneous. zoomScale 비활성 + contentSize 직접 갱신.
        let pinchGR = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGR.delegate = self
        scroll.addGestureRecognizer(pinchGR)
        pinch = pinchGR
    }

    // MARK: Gesture handlers (Step 2)

    @objc private func handleLeftHandlePan(_ pan: UIPanGestureRecognizer) {
        guard let scroll = scrollView else { return }
        let videoDuration = currentVideoDuration
        let contentWidth = currentContentWidth
        guard videoDuration > 0, contentWidth > 0 else { return }
        let widthPerSecond = contentWidth / CGFloat(videoDuration)
        guard widthPerSecond > 0 else { return }

        switch pan.state {
        case .began:
            scroll.isScrollEnabled = false
            dragOriginStart = startBinding.wrappedValue
            views.setHandleActive(side: .left, active: true)
        case .changed:
            let deltaT = TimeInterval(pan.translation(in: scroll).x / widthPerSecond)
            let candidate = dragOriginStart + deltaT
            let newStart = ClipRangeMath.clampStart(
                candidate,
                end: endBinding.wrappedValue,
                videoDuration: videoDuration
            )
            startBinding.wrappedValue = newStart
        case .ended, .cancelled, .failed:
            scroll.isScrollEnabled = true
            views.setHandleActive(side: .left, active: false)
        default:
            break
        }
    }

    @objc private func handleRightHandlePan(_ pan: UIPanGestureRecognizer) {
        guard let scroll = scrollView else { return }
        let videoDuration = currentVideoDuration
        let contentWidth = currentContentWidth
        guard videoDuration > 0, contentWidth > 0 else { return }
        let widthPerSecond = contentWidth / CGFloat(videoDuration)
        guard widthPerSecond > 0 else { return }

        switch pan.state {
        case .began:
            scroll.isScrollEnabled = false
            dragOriginEnd = endBinding.wrappedValue
            views.setHandleActive(side: .right, active: true)
        case .changed:
            let deltaT = TimeInterval(pan.translation(in: scroll).x / widthPerSecond)
            let candidate = dragOriginEnd + deltaT
            let newEnd = ClipRangeMath.clampEnd(
                candidate,
                start: startBinding.wrappedValue,
                videoDuration: videoDuration
            )
            endBinding.wrappedValue = newEnd
        case .ended, .cancelled, .failed:
            scroll.isScrollEnabled = true
            views.setHandleActive(side: .right, active: false)
        default:
            break
        }
    }

    @objc private func handleBodyLongPress(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began:
            enterTranslateMode()
        case .ended, .cancelled, .failed:
            exitTranslateMode()
        default:
            break
        }
    }

    /// LongPress.began 진입 시 호출. spy 가능하도록 internal. guard 로 idempotent 보장.
    @MainActor
    func enterTranslateMode() {
        guard !isTranslatingRange else { return }
        hapticsImpactSoft()
        scrollView?.isScrollEnabled = false
        dragOriginStart = startBinding.wrappedValue
        dragOriginEnd = endBinding.wrappedValue
        isTranslatingRange = true
        views.setHandleActive(side: .left, active: true)
        views.setHandleActive(side: .right, active: true)
    }

    /// LongPress.ended/cancelled/failed 시 호출. spy 가능하도록 internal. guard 로 idempotent 보장.
    @MainActor
    func exitTranslateMode() {
        guard isTranslatingRange else { return }
        isTranslatingRange = false
        scrollView?.isScrollEnabled = true
        views.setHandleActive(side: .left, active: false)
        views.setHandleActive(side: .right, active: false)
    }

    @objc private func handleBodyPan(_ pan: UIPanGestureRecognizer) {
        // BodyPan 은 LongPress 가 발동 중일 때만 평행 이동을 수행.
        guard isTranslatingRange else { return }
        guard let scroll = scrollView else { return }
        let videoDuration = currentVideoDuration
        let contentWidth = currentContentWidth
        guard videoDuration > 0, contentWidth > 0 else { return }
        let widthPerSecond = contentWidth / CGFloat(videoDuration)
        guard widthPerSecond > 0 else { return }

        switch pan.state {
        case .began:
            // LongPress.began 이후 BodyPan touch-down 시 translation 누적값 0점 정렬. 첫 .changed 점프 방지.
            pan.setTranslation(.zero, in: scroll)
        case .changed:
            let deltaT = TimeInterval(pan.translation(in: scroll).x / widthPerSecond)
            let (ns, ne) = ClipRangeMath.clampRange(
                start: dragOriginStart + deltaT,
                end: dragOriginEnd + deltaT,
                videoDuration: videoDuration
            )
            startBinding.wrappedValue = ns
            endBinding.wrappedValue = ne
        case .ended, .cancelled, .failed:
            // LongPress 의 ended 핸들러가 isTranslatingRange/스크롤/시각 복원을 수행.
            break
        default:
            break
        }
    }

    // MARK: Pinch handler (Step 3)

    @objc private func handlePinch(_ pinchGR: UIPinchGestureRecognizer) {
        guard let scroll = scrollView else { return }
        let videoDuration = currentVideoDuration
        let viewportWidth = currentViewportWidth
        guard viewportWidth > 0, videoDuration > 0 else { return }
        let maxZ = ClipRangeMath.maxZoom(videoDuration: videoDuration)

        switch pinchGR.state {
        case .began:
            // .began 시점 zoom + focal point 캐시. viewport 좌표 = scroll.superview 기준 (contentOffset 영향 X).
            pinchSnapshotZoom = currentZoom
            let viewportReference = scroll.superview ?? scroll
            let viewportX = pinchGR.location(in: viewportReference).x
            focalViewportX = viewportX
            focalContentX = viewportX + scroll.contentOffset.x

        case .changed:
            let rawZoom = pinchSnapshotZoom * pinchGR.scale
            let newZoom = max(1, min(rawZoom, maxZ))
            let newContentWidth = viewportWidth * newZoom

            // contentView frame + scrollView contentSize 동시 갱신.
            views.contentView?.frame.size.width = newContentWidth
            scroll.contentSize = CGSize(
                width: newContentWidth,
                height: ClipRangePickerConstants.totalHeight
            )

            // Anchor 보정: focal content X 가 동일한 viewport X 에 머무르도록 offset 조정.
            let rawOffsetX = ClipRangeMath.offsetForPinch(
                focalContentX: focalContentX,
                focalViewportX: focalViewportX,
                newZoom: newZoom,
                oldZoom: pinchSnapshotZoom
            )
            scroll.contentOffset.x = ClipRangeMath.clampOffset(
                rawOffsetX,
                contentWidth: newContentWidth,
                viewportWidth: viewportWidth
            )

            // 모든 자식 frame 재계산 — thumbnail cell, dim, clipRange 자체 등.
            // start/end binding 의 현재 값을 그대로 사용.
            views.layoutViews(
                startTime: startBinding.wrappedValue,
                endTime: endBinding.wrappedValue,
                contentWidth: newContentWidth,
                videoDuration: videoDuration
            )

            // 핸들러 캐시 갱신.
            currentContentWidth = newContentWidth
            currentZoom = newZoom

            // 정책: .changed 에서는 zoomBinding push 안 함 — zoomBucket 경계 통과 시 thumbnail flicker 발생.
            // 실시간 시각 동기화는 contentView frame + contentSize 갱신으로 이미 반영됨.

        case .ended, .cancelled, .failed:
            // 핀치 종료 시점에 한 번만 SwiftUI 동기화. zoomBucket 변화 시 thumbnail 재로딩 트리거.
            if abs(zoomBinding.wrappedValue - currentZoom) > 0.0001 {
                zoomBinding.wrappedValue = currentZoom
            }

        default:
            break
        }
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // LongPress ↔ BodyPan 만 simultaneous = true.
        // Step 3: Pinch 는 다른 모든 제스처와 자연 simultaneous (UIScrollView 의 scrollPan 포함).
        let longPress = bodyLongPress
        let body = bodyPan
        let pinchGR = pinch
        if (gestureRecognizer === longPress && otherGestureRecognizer === body)
            || (gestureRecognizer === body && otherGestureRecognizer === longPress) {
            return true
        }
        if gestureRecognizer === pinchGR || otherGestureRecognizer === pinchGR {
            return true
        }
        return false
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        // UIScrollView 기본 zoom 비활성 (min=max=1). nil 반환으로 세로축 동시 scale 회피.
        nil
    }
}

// MARK: - Previews

#Preview("기본 (15s 영상)") {
    @Previewable @State var start: TimeInterval = 3
    @Previewable @State var end: TimeInterval = 11
    ClipRangePicker(
        videoURL: URL(fileURLWithPath: "/dev/null"),
        videoDuration: 15,
        startTime: $start,
        endTime: $end
    )
    .padding(.horizontal, Spacing.l)
    .frame(maxHeight: .infinity)
    .background(AppColor.BG.primary)
}

#Preview("짧은 구간") {
    @Previewable @State var start: TimeInterval = 7
    @Previewable @State var end: TimeInterval = 9
    ClipRangePicker(
        videoURL: URL(fileURLWithPath: "/dev/null"),
        videoDuration: 30,
        startTime: $start,
        endTime: $end
    )
    .padding(.horizontal, Spacing.l)
    .frame(maxHeight: .infinity)
    .background(AppColor.BG.primary)
}
