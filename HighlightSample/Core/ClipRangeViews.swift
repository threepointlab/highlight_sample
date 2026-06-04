import UIKit

// MARK: - ClipRangeViews
//
// `ClipRangeCoordinator` 의 자식 UIView 보관 + 시각 layout 책임 전담 컨테이너.
// gesture/state/delegate 책임은 Coordinator 가, view ref + frame 계산은 본 타입이 보유한다.
// 외부 시그니처 (ClipRangePicker / ClipRangeScrollView / ClipRangeCoordinator init) 는 그대로 유지된다.

@MainActor
final class ClipRangeViews {

    // MARK: 자식 view ref

    var contentView: UIView?
    var thumbnailStripView: UIView?
    var leftDimView: UIView?
    var rightDimView: UIView?

    /// 단일 path 외곽선 + handle tint + chevron 을 담당하는 통합 shape view.
    var clipRangeShapeView: ClipRangeShapeView?

    /// 제스처 전용 투명 hit zone — 시각 없음.
    var leftHandleHitZone: UIView?
    var rightHandleHitZone: UIView?
    var bodyHitZone: UIView?

    // MARK: Handle active state

    enum HandleSide { case left, right }

    /// Coordinator가 제스처 시작/종료 시 호출. shape view 의 active 프로퍼티 갱신.
    func setHandleActive(side: HandleSide, active: Bool) {
        guard let shape = clipRangeShapeView else { return }
        switch side {
        case .left:  shape.leftHandleActive  = active
        case .right: shape.rightHandleActive = active
        }
    }

    // MARK: layoutViews

    /// startTime/endTime/contentWidth 변경 시 모든 자식 frame 재계산.
    func layoutViews(
        startTime: TimeInterval,
        endTime: TimeInterval,
        contentWidth: CGFloat,
        videoDuration: TimeInterval
    ) {
        guard contentWidth > 0, videoDuration > 0 else { return }

        let widthPerSecond = contentWidth / CGFloat(videoDuration)
        let startX = ClipRangeMath.timeToX(startTime, widthPerSecond: widthPerSecond)
        let endX   = ClipRangeMath.timeToX(endTime,   widthPerSecond: widthPerSecond)
        let clipW  = max(0, endX - startX)

        let hw     = ClipRangePickerConstants.handleSideWidth
        let totalH = ClipRangePickerConstants.totalHeight
        let stripH = ClipRangePickerConstants.stripHeight
        let py     = ClipRangePickerConstants.protrusion

        contentView?.frame        = CGRect(x: 0, y: 0, width: contentWidth, height: totalH)
        thumbnailStripView?.frame = CGRect(x: 0, y: py, width: contentWidth, height: stripH)

        // dim: thumbnail 영역(startX~endX) 기준
        leftDimView?.frame  = CGRect(x: 0,   y: py, width: max(0, startX),              height: stripH)
        rightDimView?.frame = CGRect(x: endX, y: py, width: max(0, contentWidth - endX), height: stripH)

        // shape view: contentView 전체에 배치, startX/endX 갱신으로 path 재계산
        clipRangeShapeView?.frame  = CGRect(x: 0, y: 0, width: contentWidth, height: totalH)
        clipRangeShapeView?.startX = startX
        clipRangeShapeView?.endX   = endX

        // hit zones (clip 바깥 좌/우 hw px)
        leftHandleHitZone?.frame  = CGRect(x: max(0, startX - hw), y: 0, width: hw, height: totalH)
        rightHandleHitZone?.frame = CGRect(x: endX,                y: 0, width: hw, height: totalH)

        // body: clip 내부 전체 — handle이 바깥으로 나갔으므로 clipW 그대로 사용
        bodyHitZone?.frame = CGRect(x: startX, y: 0, width: max(0, clipW), height: totalH)

        relayoutThumbnailCells(contentWidth: contentWidth)
    }

    // MARK: relayoutThumbnailCells

    func relayoutThumbnailCells(contentWidth: CGFloat) {
        guard let strip = thumbnailStripView else { return }
        let cells = strip.subviews.compactMap { $0 as? UIImageView }
        let count = cells.count
        guard count > 0 else { return }
        let gap   = Spacing.xxs
        let cellW = max(0, (contentWidth - CGFloat(count - 1) * gap) / CGFloat(count))
        let h     = ClipRangePickerConstants.stripHeight
        for (index, cell) in cells.enumerated() {
            let x = (cellW + gap) * CGFloat(index)
            cell.frame = CGRect(x: x, y: 0, width: cellW, height: h)
        }
    }

    // MARK: assignThumbnailImages

    func assignThumbnailImages(_ images: [UIImage?]) {
        guard let strip = thumbnailStripView else { return }
        let cells = strip.subviews.compactMap { $0 as? UIImageView }
        for (index, cell) in cells.enumerated() where index < images.count {
            cell.image = images[index]
        }
    }
}
