import AVFoundation
import CoreGraphics

// MARK: - FrameDecoder

protocol FrameDecoder: Sendable {
    func image(at time: TimeInterval) async throws -> CGImage
}

// MARK: - AVAssetImageGeneratorFrameDecoder

actor AVAssetImageGeneratorFrameDecoder: FrameDecoder {
    private let generator: AVAssetImageGenerator

    init(url: URL, scale: CGFloat) {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        // scale 을 곱하면 3x 기기에서 2160×3840 이 되어 AVFoundation 메모리 한도 초과.
        // 표시 픽셀(480pt × scale)이면 preview overlay 에 충분하다.
        gen.maximumSize = CGSize(width: 480 * scale, height: 960 * scale)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)
        self.generator = gen
    }

    func image(at time: TimeInterval) async throws -> CGImage {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        return try await generator.image(at: cmTime).image
    }
}

// MARK: - PreviewFrameLoader

actor PreviewFrameLoader {
    private let decoder: any FrameDecoder
    private let throttleInterval: Duration
    private let nowFn: @Sendable () -> ContinuousClock.Instant
    private let sleeper: @Sendable (Duration) async throws -> Void

    private var lastFiredAt: ContinuousClock.Instant?
    private var pendingTime: TimeInterval?
    private var pendingToken: UInt64?
    private var pendingOnImage: (@MainActor @Sendable (CGImage?, UInt64) async -> Void)?
    private var pendingTask: Task<Void, Never>?
    private var inFlightTask: Task<Void, Never>?

    init(
        decoder: any FrameDecoder,
        throttleInterval: Duration = .milliseconds(80),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.decoder = decoder
        self.throttleInterval = throttleInterval
        self.nowFn = now
        self.sleeper = sleeper
    }

    // MARK: - Public

    func request(
        time: TimeInterval,
        token: UInt64,
        onImage: @escaping @MainActor @Sendable (CGImage?, UInt64) async -> Void
    ) {
        let canLeadingFire: Bool
        if let last = lastFiredAt {
            canLeadingFire = (nowFn() - last) >= throttleInterval
        } else {
            canLeadingFire = true
        }

        if inFlightTask == nil && canLeadingFire {
            leadingFire(time: time, token: token, onImage: onImage)
        } else {
            pendingTime = time
            pendingToken = token
            pendingOnImage = onImage
            if pendingTask == nil { scheduleTrailing() }
        }
    }

    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingTime = nil
        pendingToken = nil
        pendingOnImage = nil
        inFlightTask?.cancel()
        inFlightTask = nil
        lastFiredAt = nil
    }

    // MARK: - Private

    private func leadingFire(
        time: TimeInterval,
        token: UInt64,
        onImage: @escaping @MainActor @Sendable (CGImage?, UInt64) async -> Void
    ) {
        lastFiredAt = nowFn()
        inFlightTask = Task {
            defer { Task { await self.onInFlightDone() } }
            guard !Task.isCancelled else { return }
            let cg: CGImage
            do {
                cg = try await self.decoder.image(at: time)
            } catch {
                print("[Preview] decode FAILED t=\(String(format: "%.2f", time)) error=\(error)")
                return
            }
            guard !Task.isCancelled else { return }
            await onImage(cg, token)
        }
    }

    private func onInFlightDone() {
        inFlightTask = nil
        guard
            let pt  = pendingTime,
            let ptk = pendingToken,
            let poi = pendingOnImage
        else { return }
        pendingTime = nil
        pendingToken = nil
        pendingOnImage = nil
        pendingTask?.cancel()
        pendingTask = nil
        leadingFire(time: pt, token: ptk, onImage: poi)
    }

    private func scheduleTrailing() {
        let interval = throttleInterval
        pendingTask = Task {
            try? await self.sleeper(interval)
            guard !Task.isCancelled else { return }
            await self.onTrailingFired()
        }
    }

    private func onTrailingFired() {
        pendingTask = nil
        guard
            inFlightTask == nil,
            let pt  = pendingTime,
            let ptk = pendingToken,
            let poi = pendingOnImage
        else { return }
        pendingTime = nil
        pendingToken = nil
        pendingOnImage = nil
        leadingFire(time: pt, token: ptk, onImage: poi)
    }
}
