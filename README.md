# HighlightSample

Cliff 앱의 **하이라이트 기능** 구현 과정을 단계별 브랜치로 추적한 self-contained iOS 샘플 프로젝트.

빌드 도구나 별도 설정 없이 `HighlightSample.xcodeproj`를 Xcode 16에서 열고 시뮬레이터를 선택해 바로 실행할 수 있습니다.

---

## TL;DR

- `main` (= `step1`) 은 **최초 구현** (순수 SwiftUI ZStack + DragGesture) 상태입니다.
- `step2` ~ `step5` 브랜치로 갈수록 실제 Cliff 본체의 현재 모습에 가까워집니다.
- 각 브랜치는 직전 단계 위에 누적되며, `git diff step1..step2` 같이 단계별 변화량을 비교할 수 있습니다.

| 브랜치 | 핵심 변경 | 관련 커밋 |
|---|---|---|
| `step1` (= `main`) | 순수 SwiftUI `ZStack + DragGesture` 최초 구현 | `161c1df`, `c3eca74` |
| `step2` | `UIScrollView + UIViewRepresentable` 전환, Pinch zoom, long-press body translate, Haptics | `715fa24` |
| `step3` | `ClipRangeShapeView` 단일 `CAShapeLayer` stroke, 핸들 clip 바깥, `ClipRangeViews` 분리 | `5c1dc3e` |
| `step4` | `ClipRangeInteraction` + `onInteraction` 클로저, `PreviewFrameLoader` actor, 드래그 중 프레임 오버레이 | `3f699de`, `d89a8de`, `7796899` |
| `step5` | `ClipRangePickerController.focus(on:)`, `CASpringAnimation`, 30fps throttle, seek guard | `7c79238`, `b6a9888` |

---

## 실행 방법

1. `HighlightSample.xcodeproj` 를 Xcode 16 이상에서 열기
2. 상단 대상 장치에서 iOS 시뮬레이터(iPhone 16 Pro 등) 선택
3. `⌘R` 로 빌드 및 실행

앱이 뜨면 `DemoRootView` 가 `Trial(duration: 60)` 한 개를 생성하고 `ResultHighlightMock.generate` 로 하이라이트 3개를 만들어 `ResultHighlightsView` 를 표시합니다.

> **참고**: `videoURL` 이 `/dev/null` 이므로 썸네일/프레임 오버레이는 플레이스홀더 색으로만 표시됩니다. 핸들 드래그·핀치 줌·캐러셀 페이지 전환은 정상 동작합니다.

---

## 프로젝트 구조 (main 기준)

```
HighlightSample/
├── HighlightSampleApp.swift   @main 진입점
├── DemoRootView.swift         데모 루트 (Trial mock 1개 주입)
├── Core/
│   ├── ClipRangePicker.swift       ← Cliff 161c1df 원본 그대로
│   ├── ResultHighlightsView.swift  ← Cliff c3eca74 원본 그대로
│   └── ResultHighlightMock.swift   ← Cliff c3eca74 원본 그대로
└── Support/
    ├── DesignTokens.swift     Spacing / AppColor / AppFont 최소 stub
    └── TrialStub.swift        Trial 모델 최소 stub
```

`Core/` 파일은 Cliff 저장소의 해당 커밋 내용에서 **한 줄도 수정하지 않고** 추출했습니다 (각 브랜치에 동일 원칙 적용).

step3 이후로는 `Core/ClipRangeShapeView.swift`, `Core/ClipRangeViews.swift`, step4 이후로는 `Core/PreviewFrameLoader.swift` 가 추가됩니다.

---

## 단계별 진화 — main(step1) 부터 step5 까지

### step1 (= main) — 순수 SwiftUI 최초 구현

**ClipRangePicker — 5-layer ZStack + DragGesture state machine**

레이어 구조 (ZStack, 하단 → 상단):
1. `thumbnailLayer` — AVAssetImageGenerator 로 N장 썸네일을 HStack 에 등간격 배치 (stripHeight 56pt, 위아래 protrusion 5pt)
2. `dimLayer` — 선택 구간 바깥을 `black.opacity(0.52)` 로 덮는 좌/중(투명)/우 3분할 HStack
3. `borderLayer` — 선택 구간 상하단 2.5pt 노란 테두리
4. `handleLayer` — 좌·우 노란 핸들 (`RoundedRectangle` + `.offset`)
5. `tooltipLayer` — 드래그 중에만 현재 시간을 Capsule 배경 텍스트로 표시

드래그 state machine:
- `DragState: idle | draggingStart | draggingEnd | draggingRange`
- 첫 `.onChanged` 에서 hit-test: `|x - handleX| ≤ 16pt` → 핸들 / `startX < x < endX` → 범위 이동 / 그 외 → 가까운 핸들
- 시작 시 좌표 스냅샷 → 매 프레임 `deltaT = x / widthPerSecond` 만 더해 누적 오차 방지

**ResultHighlightsView — peek carousel + per-page picker**
- `TabView(.page(indexDisplayMode: .never))` 로 peek carousel 구현
- `@State private var startTimes/endTimes: [Double]` — mock 값을 View State 배열로 복사
- `ClipRangePicker` 에 `.id(currentPage)` 부여 → 페이지 전환 시 강제 재생성

**ResultHighlightMock — 결정론적 mock 생성**
- **FNV-1a** 로 `trial.id.uuidString` 을 안정 해시(UInt64 seed)로 변환
- **xorshift64** PRNG 로 클립 개수/gap/duration 결정 → 동일 Trial = 동일 결과
- 개수 정책: `duration < 30s → 1개`, `< 90s → 2개`, 그 외 `3개`
- (이후 단계 전체에서 변경 없음)

### step2 — UIScrollView 전환 + Pinch zoom

- `UIViewRepresentable` `ClipRangePicker` + `ClipRangeCoordinator` (UIScrollViewDelegate + UIGestureRecognizerDelegate) 로 완전 재작성
- **전환 이유**: 순수 SwiftUI DragGesture 는 scroll + handle 동시 인식에서 gesture 충돌 발생
- `UIPinchGestureRecognizer` 로 contentWidth 확장, focal point 보정으로 핀치 위치에서 줌
- `UILongPressGestureRecognizer` + `UIPanGestureRecognizer` simultaneous 로 구간 평행 이동
- `Support/Haptics.swift` 추가 — `UISelectionFeedbackGenerator` / `UIImpactFeedbackGenerator` 래퍼

### step3 — ClipRangeShapeView 단일 path

- 기존 4개 UIView (상단바, 하단바, 좌핸들, 우핸들) → `CAShapeLayer` 단일 roundedRect stroke 로 통합
- 핸들이 clip 영역 **바깥**으로 나가 선택 구간을 가리지 않음
- `ClipRangeViews` 신설 — UIView ref 보관 + frame layout 전담으로 Coordinator 에서 분리

### step4 — ClipRangeInteraction + PreviewFrameLoader

- `ClipRangeInteraction` 타입 추가: `.leftHandle(time:)` / `.rightHandle(time:)` / `.bodyTranslate(start:end:)`
- `onInteraction: ((ClipRangeInteraction?) -> Void)?` 클로저로 외부에 인터랙션 이벤트 전달
- `FrameDecoder` 프로토콜 + `AVAssetImageGeneratorFrameDecoder` actor 신설
- `PreviewFrameLoader`: 80ms leading+trailing throttle 로 드래그 중 실제 영상 프레임 오버레이 로딩
- `ResultHighlightsView`: `onInteraction` → `previewLoader.request()` 연동, 썸네일 위에 프레임 오버레이 표시

### step5 — ClipRangePickerController + spring 애니메이션 + 회귀 수정

- `ClipRangePickerController.focus(on:animated:)`: SwiftUI diff 없이 특정 시간으로 스크롤하는 imperative 채널
  - **주의**: picker 에 `.id(...)` 부여 시 thumbnail Task 재시작 회귀 발생 → `.id()` 부여 금지, controller 로 대체
- `ClipRangeShapeView.setRange(animated:)` + `CASpringAnimation(keyPath: "path")` — scroll spring 과 동기화된 dim/handle 애니메이션
- `ResultHighlightsView` 회귀 수정 3건:
  1. `pendingFocusTime` apply 를 layout commit 이후로 defer → thumbnail placeholder spill 버그 해소
  2. `handleInteraction(.some→.some)` 30fps throttle → 드래그 중 매 프레임 Task 생성 제거
  3. seek completion guard + `onDisappear` Task cancel → preview overlay 메모리 누수 해소

---

## 의존성 메모

`Core/` 파일이 참조하는 외부 심볼과 실제 Cliff 에서의 정의. 컴파일에 필요한 부분만 `Support/` 에 최소 stub 으로 제공했으며, 시각이 실제 Cliff 와 동일할 필요는 없습니다.

### 디자인 시스템 토큰

| 심볼 | 실제 값 | 사용 단계 |
|---|---|---|
| `Spacing.xxs` ~ `Spacing.l` | 4pt 그리드 (2/4/8/12/16) | 전 단계 |
| `Spacing.xl` (24) | 4pt 그리드 | step4+ |
| `AppColor.BG.primary` | 다크 배경 | 전 단계 |
| `AppColor.Surface.placeholder` | 어두운 회색 | 전 단계 |
| `AppColor.Text.primary` / `.muted` | 흰색 / `#AAAAAA` | 전 단계 |
| `AppColor.Accent.brand` | 노란-주황 | step2+ |
| `AppFont.caption` | SF Pro 12pt Regular | 전 단계 |

실제 Cliff 정의 위치: `Cliff/DesignSystem/Tokens/{Spacing,Color+Tokens,Font+Tokens}.swift`.

### 도메인 모델

| 심볼 | 실제 정의 | 이 샘플에서 |
|---|---|---|
| `Trial` | SwiftData `@Model` — 세션 메타데이터 전체 포함 | `Support/TrialStub.swift` 에 `struct Trial { id, duration }` 로 최소 stub |
| `HighlightItem` | `ResultHighlightMock.swift` 안에 정의됨 | 별도 의존성 없음 |
