import UIKit
import SwiftUI

// MARK: - ClipRangeShapeView
//
// 클립 구간 외곽선을 단일 CAShapeLayer path로 그리는 view.
// stroke: roundedRect([startX − handleW, endX + handleW]) 한 줄.
// handle 구역(좌/우 handleW px): brand tint fill + chevron.
// ClipRangeViews가 startX/endX 갱신 → setNeedsLayout()으로 path 재계산.

@MainActor
final class ClipRangeShapeView: UIView {

    // MARK: Input — ClipRangeViews.layoutViews 호출마다 갱신

    var startX: CGFloat = 0 { didSet { if oldValue != startX { setNeedsLayout() } } }
    var endX: CGFloat = 0   { didSet { if oldValue != endX   { setNeedsLayout() } } }

    // MARK: Active state — Coordinator.setHandleActive 위임

    var leftHandleActive: Bool  = false { didSet { animateActive() } }
    var rightHandleActive: Bool = false { didSet { animateActive() } }

    // MARK: Layers

    private let strokeLayer    = CAShapeLayer()
    private let leftTintLayer  = CAShapeLayer()
    private let rightTintLayer = CAShapeLayer()
    private let leftChevron    = UIImageView()
    private let rightChevron   = UIImageView()

    // MARK: Init

    init(brandColor: UIColor) {
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = false
        setupLayers(brandColor: brandColor)
        setupChevrons()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayers(brandColor: UIColor) {
        let c = ClipRangePickerConstants.self

        strokeLayer.fillColor   = UIColor.clear.cgColor
        strokeLayer.strokeColor = brandColor.cgColor
        strokeLayer.lineWidth   = c.strokeWidth
        strokeLayer.shadowColor   = brandColor.cgColor
        strokeLayer.shadowRadius  = 8
        strokeLayer.shadowOffset  = .zero
        strokeLayer.shadowOpacity = Float(c.glowOpacityIdle)
        strokeLayer.masksToBounds = false

        leftTintLayer.fillColor   = brandColor.withAlphaComponent(c.handleTintAlpha).cgColor
        leftTintLayer.strokeColor = UIColor.clear.cgColor
        rightTintLayer.fillColor  = brandColor.withAlphaComponent(c.handleTintAlpha).cgColor
        rightTintLayer.strokeColor = UIColor.clear.cgColor

        layer.addSublayer(strokeLayer)
        layer.addSublayer(leftTintLayer)
        layer.addSublayer(rightTintLayer)
    }

    private func setupChevrons() {
        let config = UIImage.SymbolConfiguration(
            pointSize: ClipRangePickerConstants.chevronPointSize,
            weight: .bold
        )
        leftChevron.image  = UIImage(systemName: "chevron.left",  withConfiguration: config)
        rightChevron.image = UIImage(systemName: "chevron.right", withConfiguration: config)
        leftChevron.tintColor  = .white
        rightChevron.tintColor = .white
        leftChevron.contentMode  = .center
        rightChevron.contentMode = .center
        addSubview(leftChevron)
        addSubview(rightChevron)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let c  = ClipRangePickerConstants.self
        let hw = c.handleSideWidth    // 20
        let r  = c.frameCornerRadius  // 14
        let sw = c.strokeWidth        // 3
        let h  = bounds.height

        let clipW  = max(0, endX - startX)
        let shapeX = startX - hw
        let shapeW = clipW + hw * 2

        // ── Stroke path: rounded rect [startX-hw … endX+hw] ─────────────────
        let halfStroke = sw / 2
        let strokePath = UIBezierPath(
            roundedRect: CGRect(
                x: shapeX + halfStroke,
                y: halfStroke,
                width: max(0, shapeW - sw),
                height: h - sw
            ),
            cornerRadius: r
        )
        strokeLayer.frame      = bounds
        strokeLayer.path       = strokePath.cgPath
        strokeLayer.shadowPath = strokePath.cgPath

        // ── Left tint: rounded left corners only ─────────────────────────────
        let leftTintPath = UIBezierPath(
            roundedRect: CGRect(x: shapeX, y: 0, width: hw, height: h),
            byRoundingCorners: [.topLeft, .bottomLeft],
            cornerRadii: CGSize(width: r, height: r)
        )
        leftTintLayer.frame = bounds
        leftTintLayer.path  = leftTintPath.cgPath

        // ── Right tint: rounded right corners only ────────────────────────────
        let rightTintPath = UIBezierPath(
            roundedRect: CGRect(x: endX, y: 0, width: hw, height: h),
            byRoundingCorners: [.topRight, .bottomRight],
            cornerRadii: CGSize(width: r, height: r)
        )
        rightTintLayer.frame = bounds
        rightTintLayer.path  = rightTintPath.cgPath

        // ── Chevron frames ───────────────────────────────────────────────────
        leftChevron.frame  = CGRect(x: shapeX, y: 0, width: hw, height: h)
        rightChevron.frame = CGRect(x: endX,   y: 0, width: hw, height: h)
    }

    // MARK: Animated range update

    /// highlight 전환 시 spring 애니메이션으로 path 변경.
    /// animated=false 이면 기존 동기 경로 (setNeedsLayout) 와 동일.
    func setRange(
        startX: CGFloat,
        endX: CGFloat,
        animated: Bool,
        duration: TimeInterval = 0.45,
        damping: CGFloat = 0.85,
        initialVelocity: CGFloat = 0
    ) {
        guard animated else {
            self.startX = startX
            self.endX = endX
            return
        }

        let paths = computePaths(startX: startX, endX: endX, in: bounds)

        func addSpringPath(to cal: CAShapeLayer, new: CGPath, key: String) {
            let anim = CASpringAnimation(keyPath: "path")
            anim.fromValue = cal.presentation()?.path ?? cal.path
            anim.toValue = new
            // mass=1, stiffness=100, damping=28 → UIView spring(damping:0.85, duration:0.45) 에 근사
            anim.mass = 1; anim.stiffness = 100; anim.damping = 28
            anim.initialVelocity = initialVelocity
            anim.duration = anim.settlingDuration
            anim.fillMode = .forwards
            cal.add(anim, forKey: key)
            cal.path = new
        }

        addSpringPath(to: strokeLayer,    new: paths.stroke,    key: "strokePath")
        addSpringPath(to: leftTintLayer,  new: paths.leftTint,  key: "leftTintPath")
        addSpringPath(to: rightTintLayer, new: paths.rightTint, key: "rightTintPath")

        let shadowAnim = CASpringAnimation(keyPath: "shadowPath")
        shadowAnim.fromValue = strokeLayer.presentation()?.shadowPath ?? strokeLayer.shadowPath
        shadowAnim.toValue = paths.stroke
        shadowAnim.mass = 1; shadowAnim.stiffness = 100; shadowAnim.damping = 28
        shadowAnim.duration = shadowAnim.settlingDuration
        shadowAnim.fillMode = .forwards
        strokeLayer.add(shadowAnim, forKey: "shadowPath")
        strokeLayer.shadowPath = paths.stroke

        // chevron 은 frame 기반 → UIView.animate 로 보간
        UIView.animate(
            withDuration: duration, delay: 0,
            usingSpringWithDamping: damping, initialSpringVelocity: initialVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            let c  = ClipRangePickerConstants.self
            let hw = c.handleSideWidth
            let h  = self.bounds.height
            self.leftChevron.frame  = CGRect(x: startX - hw, y: 0, width: hw, height: h)
            self.rightChevron.frame = CGRect(x: endX,        y: 0, width: hw, height: h)
        }

        // model layer 최종 값 반영 (didSet → setNeedsLayout 은 다음 runloop 에 layoutSubviews 를
        // 부르지만, 이미 layer.path 가 final state 이므로 시각적으로 충돌 없음)
        self.startX = startX
        self.endX = endX
    }

    // MARK: Path computation helper

    private struct LayerPaths {
        let stroke: CGPath
        let leftTint: CGPath
        let rightTint: CGPath
    }

    private func computePaths(startX: CGFloat, endX: CGFloat, in bounds: CGRect) -> LayerPaths {
        let c  = ClipRangePickerConstants.self
        let hw = c.handleSideWidth
        let r  = c.frameCornerRadius
        let sw = c.strokeWidth
        let h  = bounds.height
        let clipW  = max(0, endX - startX)
        let shapeX = startX - hw
        let shapeW = clipW + hw * 2
        let halfStroke = sw / 2

        let stroke = UIBezierPath(
            roundedRect: CGRect(
                x: shapeX + halfStroke, y: halfStroke,
                width: max(0, shapeW - sw), height: h - sw
            ),
            cornerRadius: r
        ).cgPath

        let leftTint = UIBezierPath(
            roundedRect: CGRect(x: shapeX, y: 0, width: hw, height: h),
            byRoundingCorners: [.topLeft, .bottomLeft],
            cornerRadii: CGSize(width: r, height: r)
        ).cgPath

        let rightTint = UIBezierPath(
            roundedRect: CGRect(x: endX, y: 0, width: hw, height: h),
            byRoundingCorners: [.topRight, .bottomRight],
            cornerRadii: CGSize(width: r, height: r)
        ).cgPath

        return LayerPaths(stroke: stroke, leftTint: leftTint, rightTint: rightTint)
    }

    // MARK: Active animation

    private func animateActive() {
        let either = leftHandleActive || rightHandleActive
        let targetOpacity = either
            ? Float(ClipRangePickerConstants.glowOpacityActive)
            : Float(ClipRangePickerConstants.glowOpacityIdle)
        UIView.animate(withDuration: ClipRangePickerConstants.handleActiveAnimationDuration) {
            self.strokeLayer.shadowOpacity = targetOpacity
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct ClipRangeShapePreview: UIViewRepresentable {
    let startX: CGFloat
    let endX: CGFloat
    func makeUIView(context: Context) -> ClipRangeShapeView {
        ClipRangeShapeView(brandColor: UIColor(AppColor.Accent.brand))
    }
    func updateUIView(_ uiView: ClipRangeShapeView, context: Context) {
        uiView.startX = startX
        uiView.endX   = endX
    }
}

#Preview("일반 (start=80, end=280)") {
    ClipRangeShapePreview(startX: 80, endX: 280)
        .frame(width: 360, height: ClipRangePickerConstants.totalHeight)
        .background(AppColor.BG.primary)
}

#Preview("좁은 구간 (40px)") {
    ClipRangeShapePreview(startX: 160, endX: 200)
        .frame(width: 360, height: ClipRangePickerConstants.totalHeight)
        .background(AppColor.BG.primary)
}

#Preview("start = end (0px clip)") {
    ClipRangeShapePreview(startX: 180, endX: 180)
        .frame(width: 360, height: ClipRangePickerConstants.totalHeight)
        .background(AppColor.BG.primary)
}

#Preview("왼쪽 엣지 (start=0)") {
    ClipRangeShapePreview(startX: 0, endX: 120)
        .frame(width: 360, height: ClipRangePickerConstants.totalHeight)
        .background(AppColor.BG.primary)
}
#endif
