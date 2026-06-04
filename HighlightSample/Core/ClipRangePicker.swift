import SwiftUI
import AVFoundation

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
    @State private var dragOriginX: CGFloat = 0
    @State private var dragOriginStart: TimeInterval = 0
    @State private var dragOriginEnd: TimeInterval = 0

    private let handleWidth: CGFloat = 10
    private let handleHitSlop: CGFloat = 16
    private let stripHeight: CGFloat = 56
    private let protrusion: CGFloat = 5
    private var totalHeight: CGFloat { stripHeight + protrusion * 2 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                thumbnailLayer(width: geo.size.width)
                dimLayer(width: geo.size.width)
                borderLayer(width: geo.size.width)
                handleLayer(width: geo.size.width)
                if dragState != .idle {
                    tooltipLayer(width: geo.size.width)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: geo.size.width))
            .onAppear { containerWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, new in containerWidth = new }
        }
        .frame(height: totalHeight)
        .task(id: videoURL) { await loadThumbnails() }
    }
}

private enum DragState: Equatable {
    case idle, draggingStart, draggingEnd, draggingRange
}

// MARK: - Layers

private extension ClipRangePicker {

    @ViewBuilder
    func thumbnailLayer(width: CGFloat) -> some View {
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

    @ViewBuilder
    func dimLayer(width: CGFloat) -> some View {
        let startX = clipRangeTimeToX(startTime, width: width, duration: videoDuration)
        let endX   = clipRangeTimeToX(endTime,   width: width, duration: videoDuration)
        HStack(spacing: 0) {
            Color.black.opacity(0.52).frame(width: startX)
            Color.clear.frame(width: max(0, endX - startX))
            Color.black.opacity(0.52)
        }
        .frame(height: stripHeight)
        .padding(.vertical, protrusion)
    }

    @ViewBuilder
    func borderLayer(width: CGFloat) -> some View {
        let startX = clipRangeTimeToX(startTime, width: width, duration: videoDuration)
        let endX   = clipRangeTimeToX(endTime,   width: width, duration: videoDuration)
        let selW   = max(0, endX - startX)
        Group {
            Color.yellow.frame(width: selW, height: 2.5)
                .offset(x: startX, y: protrusion)
            Color.yellow.frame(width: selW, height: 2.5)
                .offset(x: startX, y: protrusion + stripHeight - 2.5)
        }
    }

    @ViewBuilder
    func handleLayer(width: CGFloat) -> some View {
        let startX = clipRangeTimeToX(startTime, width: width, duration: videoDuration)
        let endX   = clipRangeTimeToX(endTime,   width: width, duration: videoDuration)
        Group {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.yellow)
                .frame(width: handleWidth, height: totalHeight)
                .offset(x: startX - handleWidth / 2)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.yellow)
                .frame(width: handleWidth, height: totalHeight)
                .offset(x: endX - handleWidth / 2)
        }
    }

    @ViewBuilder
    func tooltipLayer(width: CGFloat) -> some View {
        let time: TimeInterval = dragState == .draggingEnd ? endTime : startTime
        let x = clipRangeTimeToX(time, width: width, duration: videoDuration)
        let formatted = String(format: "%.1f초", time)
        Text(formatted)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.Text.primary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Color.black.opacity(0.7), in: Capsule())
            .offset(x: max(0, min(x - 30, width - 60)), y: -28)
    }

    func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if dragState == .idle {
                    let x = value.startLocation.x
                    let startX = clipRangeTimeToX(startTime, width: width, duration: videoDuration)
                    let endX   = clipRangeTimeToX(endTime,   width: width, duration: videoDuration)
                    if abs(x - startX) <= handleHitSlop {
                        dragState = .draggingStart
                    } else if abs(x - endX) <= handleHitSlop {
                        dragState = .draggingEnd
                    } else if x > startX && x < endX {
                        dragState = .draggingRange
                    } else {
                        dragState = x < startX ? .draggingStart : .draggingEnd
                    }
                    dragOriginX     = value.startLocation.x
                    dragOriginStart = startTime
                    dragOriginEnd   = endTime
                }
                let deltaT = clipRangeXToTime(value.location.x - dragOriginX, width: width, duration: videoDuration)
                switch dragState {
                case .draggingStart:
                    startTime = clipRangeClampStart(dragOriginStart + deltaT, endTime: dragOriginEnd, videoDuration: videoDuration)
                case .draggingEnd:
                    endTime = clipRangeClampEnd(dragOriginEnd + deltaT, startTime: dragOriginStart, videoDuration: videoDuration)
                case .draggingRange:
                    let (ns, ne) = clipRangeClampRange(
                        newStart: dragOriginStart + deltaT,
                        newEnd:   dragOriginEnd   + deltaT,
                        videoDuration: videoDuration
                    )
                    startTime = ns
                    endTime   = ne
                case .idle:
                    break
                }
            }
            .onEnded { _ in dragState = .idle }
    }

    func loadThumbnails() async {
        guard videoDuration > 0 else { return }
        let w = containerWidth > 0 ? containerWidth : 300
        let count = max(5, min(Int(w / 44), 20))
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

// MARK: - Preview

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
