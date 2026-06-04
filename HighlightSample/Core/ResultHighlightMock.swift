import Foundation

// MARK: - HighlightItem

/// 결과 화면에서 사용하는 mock 하이라이트 구간.
///
/// - `SwiftData` 모델이 아님. Result 화면 내에서만 사용되며 화면을 떠나면 폐기된다.
struct HighlightItem: Identifiable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    let label: String
}

// MARK: - ResultHighlightMock

/// Trial.id 를 seed 로 삼아 결정론적 하이라이트 mock 데이터를 생성한다.
///
/// 동일한 Trial.id 에 대해 항상 동일한 결과를 반환한다.
/// `trial.id.hashValue` 는 프로세스 재시작 시 달라질 수 있으므로
/// uuidString 기반 FNV-1a 변형으로 안정 해시를 계산한다.
enum ResultHighlightMock {

    /// Trial 을 기반으로 0~3 개의 하이라이트 구간을 생성한다.
    ///
    /// - duration < 4.0: 0개 반환.
    /// - 각 구간: 2~6초, 비겹침.
    static func generate(for trial: Trial) -> [HighlightItem] {
        let duration = trial.duration
        guard duration >= 4.0 else { return [] }

        // 안정 해시 (FNV-1a 변형)
        let seed = trial.id.uuidString.unicodeScalars.reduce(UInt64(1469598103934665603)) {
            ($0 ^ UInt64($1.value)) &* 1099511628211
        }

        var rng = SeededRNG(seed: seed)

        // duration 기반 최대 개수: short(<30s)→1, mid(<90s)→2, long→3
        let maxCount: Int
        if duration < 30 {
            maxCount = 1
        } else if duration < 90 {
            maxCount = 2
        } else {
            maxCount = 3
        }

        var items: [HighlightItem] = []
        var cursor: Double = 0

        for i in 0 ..< maxCount {
            // gap before this clip: 2~8초
            let gap = Double(rng.nextUInt64() % 7 + 2)
            cursor += gap

            // clip duration: 2~6초
            let clipDur = Double(rng.nextUInt64() % 5 + 2)
            let end = cursor + clipDur

            guard end <= duration else { break }

            items.append(HighlightItem(
                id: UUID(),
                startTime: cursor,
                endTime: end,
                label: "하이라이트 \(i + 1)"
            ))

            cursor = end
        }

        return items
    }
}

// MARK: - SeededRNG

/// 단순 xorshift64 PRNG (Swift 표준 RandomNumberGenerator 미사용 — 결정성 보장).
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
