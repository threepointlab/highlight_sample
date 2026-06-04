# HighlightSample

Cliff 앱의 **하이라이트 기능 최초 구현** 코드를 공유하기 위한 self-contained iOS 샘플 프로젝트.

빌드 도구나 별도 설정 없이 `HighlightSample.xcodeproj`를 Xcode 16에서 열고 시뮬레이터를 선택해 바로 실행할 수 있습니다.

---

## TL;DR — 어떤 코드를 보는 건가

두 커밋에서 추출한 세 파일이 핵심입니다.

| 파일 | 커밋 | 역할 |
|---|---|---|
| `Core/ClipRangePicker.swift` | `161c1df` (2026-05-26 09:17) | 영상 썸네일 띠 위에서 좌/우 핸들을 드래그해 클립 구간(start/end)을 정하는 SwiftUI 컴포넌트 |
| `Core/ResultHighlightsView.swift` | `c3eca74` (2026-05-26 21:52) | peek carousel + 페이지별 ClipRangePicker 를 조합한 하이라이트 탭 뷰 |
| `Core/ResultHighlightMock.swift` | `c3eca74` | Trial 을 seed 로 삼아 결정론적 mock 하이라이트 구간을 생성하는 유틸 |

---

## 실행 방법

1. `HighlightSample.xcodeproj` 를 Xcode 16 이상에서 열기
2. 상단 대상 장치에서 iOS 시뮬레이터(iPhone 16 Pro 등) 선택
3. `⌘R` 로 빌드 및 실행

앱이 뜨면 `DemoRootView` 가 `Trial(duration: 60)` 한 개를 생성하고 `ResultHighlightMock.generate` 로 하이라이트 3개를 만들어 `ResultHighlightsView` 를 표시합니다.

> **참고**: `videoURL` 이 `/dev/null` 이므로 썸네일 띠는 플레이스홀더 색으로만 표시됩니다. 핸들 드래그와 carousel 페이지 전환은 정상 동작합니다.

---

## 프로젝트 구조

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

`Core/` 파일 3개는 Cliff 저장소의 원본 커밋 내용에서 **한 줄도 수정하지 않고** 추출했습니다.

---

## 의존성 메모

`Core/` 파일이 참조하는 외부 심볼과 실제 Cliff 에서의 정의.

### 디자인 시스템 토큰

| 심볼 | 실제 값 | 파일 |
|---|---|---|
| `Spacing.xxs` | 2 pt | `Cliff/DesignSystem/Tokens/Spacing.swift` |
| `Spacing.xs` | 4 pt | 상동 |
| `Spacing.s` | 8 pt | 상동 |
| `Spacing.m` | 12 pt | 상동 |
| `Spacing.l` | 16 pt | 상동 |
| `AppColor.BG.primary` | 다크 배경 | `Cliff/DesignSystem/Tokens/Color+Tokens.swift` |
| `AppColor.Surface.placeholder` | 어두운 회색 | 상동 |
| `AppColor.Text.primary` | 흰색 | 상동 |
| `AppColor.Text.muted` | `#AAAAAA` | 상동 |
| `AppFont.caption` | SF Pro 12pt Regular | `Cliff/DesignSystem/Tokens/Font+Tokens.swift` |

### 도메인 모델

| 심볼 | 실제 정의 | 이 샘플에서 |
|---|---|---|
| `Trial` | SwiftData `@Model` — 세션 메타데이터 전체 포함 | `Support/TrialStub.swift` 에 `struct Trial { id, duration }` 로 최소 stub |
| `HighlightItem` | `ResultHighlightMock.swift` 안에 정의됨 | 별도 의존성 없음 |

---

## 핵심 구현 로직 요약

### ClipRangePicker — 5-layer ZStack + DragGesture state machine

**레이어 구조** (ZStack, 하단 → 상단):
1. `thumbnailLayer` — AVAssetImageGenerator 로 N장 썸네일을 HStack 에 등간격 배치 (stripHeight 56pt, 위아래 protrusion 5pt)
2. `dimLayer` — 선택 구간 바깥을 `black.opacity(0.52)` 로 덮는 좌/중(투명)/우 3분할 HStack
3. `borderLayer` — 선택 구간 상하단 2.5pt 노란 테두리
4. `handleLayer` — 좌·우 노란 핸들 (`RoundedRectangle` + `.offset`)
5. `tooltipLayer` — 드래그 중에만 현재 시간을 Capsule 배경 텍스트로 표시

**드래그 state machine**:
- `DragState: idle | draggingStart | draggingEnd | draggingRange`
- 첫 `.onChanged` 에서 hit-test:
  - `|x - handleX| ≤ 16pt` → 해당 핸들
  - `startX < x < endX` → 범위 전체 이동
  - 그 외 → 가까운 핸들로 폴백
- 시작 시 좌표 스냅샷(`dragOriginX`, `dragOriginStart`, `dragOriginEnd`) → 매 프레임 `deltaT = x / widthPerSecond` 만 더해 누적 오차 방지

**좌표 헬퍼** — 파일 스코프 자유 함수 5개 (`@testable import` 가능):
- `clipRangeTimeToX` / `clipRangeXToTime` — 선형 변환
- `clipRangeClampStart` / `clipRangeClampEnd` — 최소 길이 0.5s 보장
- `clipRangeClampRange` — 범위 이동 시 길이 보존 + [0, duration] 클램핑

### ResultHighlightMock — 결정론적 mock 생성

- **FNV-1a** 로 `trial.id.uuidString` 을 안정 해시(UInt64 seed)로 변환 (`Hashable.hashValue` 는 프로세스 재시작마다 달라지므로 불사용)
- **xorshift64** PRNG(SeededRNG) 로 클립 개수/gap/duration 결정 → 동일 Trial = 동일 결과
- 개수 정책: `duration < 30s → 1개`, `< 90s → 2개`, 그 외 `3개`
- cursor 누적으로 자연스럽게 비겹침 보장, `end > duration` 이면 break

### ResultHighlightsView — peek carousel + per-page picker

- `TabView(.page(indexDisplayMode: .never))` 로 peek carousel 구현, `.tag(idx)` 로 페이지 바인딩
- `@State private var startTimes: [Double]` / `endTimes: [Double]` — mock 값을 View State 배열로 복사 (화면을 떠나면 폐기, SwiftData 영속화 없음)
- `ClipRangePicker` 에 `.id(currentPage)` 부여 → 페이지 전환 시 강제 재생성 (썸네일 Task 재시작 트리거)

---

## 단계별 브랜치 — 구현 진화 추적

각 브랜치는 직전 단계 위에 쌓이며, 해당 시점의 소스를 그대로 담고 있어 `git diff step1..step2` 등으로 변화량을 비교할 수 있습니다.

| 브랜치 | 핵심 변경 | 관련 커밋 |
|---|---|---|
| `step1` (`main`) | 순수 SwiftUI `ZStack + DragGesture` 최초 구현 | `161c1df`, `c3eca74` |
| `step2` | `UIScrollView + UIViewRepresentable` 전환, Pinch zoom, long-press body translate, Haptics | `715fa24` |
| `step3` | `ClipRangeShapeView` 단일 `CAShapeLayer` stroke, 핸들 clip 바깥, `ClipRangeViews` 분리 | `5c1dc3e` |
| `step4` | `ClipRangeInteraction` + `onInteraction` 클로저, `PreviewFrameLoader` actor, 드래그 중 프레임 오버레이 | `3f699de`, `d89a8de`, `7796899` |
| `step5` | `ClipRangePickerController.focus(on:)`, `CASpringAnimation`, 30fps throttle, seek guard | `7c79238`, `b6a9888` |

### 각 단계 상세

#### step1 — 순수 SwiftUI (최초 구현)
- `ZStack` 5-레이어: thumbnailLayer → dimLayer → borderLayer → handleLayer → tooltipLayer
- `DragGesture` 로 left/right/range 세 가지 인터랙션을 단일 state machine 으로 처리
- `DragState: idle | draggingStart | draggingEnd | draggingRange`
- `ResultHighlightsView`: `TabView(.page)` peek carousel + `@State` 배열로 각 페이지 start/end 보관

#### step2 — UIScrollView 전환 + Pinch zoom
- `UIViewRepresentable` `ClipRangePicker` + `ClipRangeCoordinator` (UIScrollViewDelegate + UIGestureRecognizerDelegate)
- **전환 이유**: 순수 SwiftUI DragGesture 는 scroll + handle 동시 인식에서 gesture 충돌 발생
- `UIPinchGestureRecognizer` 로 contentWidth 확장, focal point 보정으로 핀치 위치에서 줌
- `UILongPressGestureRecognizer` + `UIPanGestureRecognizer` simultaneous 로 구간 평행 이동
- `UISelectionFeedbackGenerator` / `UIImpactFeedbackGenerator` 햅틱 피드백

#### step3 — ClipRangeShapeView 단일 path
- 기존 4개 UIView (상단바, 하단바, 좌핸들, 우핸들) → `CAShapeLayer` 단일 roundedRect stroke
- 핸들이 clip 영역 **바깥**으로 나가 선택 구간을 가리지 않음
- `ClipRangeViews`: UIView ref 보관 + frame layout 전담으로 Coordinator 에서 분리

#### step4 — ClipRangeInteraction + PreviewFrameLoader
- `ClipRangeInteraction` 타입: `.leftHandle(time:)` / `.rightHandle(time:)` / `.bodyTranslate(start:end:)`
- `onInteraction: ((ClipRangeInteraction?) -> Void)?` 클로저로 외부에 인터랙션 이벤트 전달
- `FrameDecoder` 프로토콜 + `AVAssetImageGeneratorFrameDecoder` actor
- `PreviewFrameLoader`: 80ms leading+trailing throttle 로 드래그 중 실제 영상 프레임 오버레이 로딩
- `ResultHighlightsView`: `onInteraction` → `previewLoader.request()` 연동

#### step5 — ClipRangePickerController + spring 애니메이션 + 회귀 수정
- `ClipRangePickerController.focus(on:animated:)`: SwiftUI diff 없이 특정 시간으로 스크롤하는 imperative 채널
  - **주의**: picker 에 `.id(...)` 부여 시 thumbnail Task 재시작 회귀 → controller 로 대체
- `ClipRangeShapeView.setRange(animated:)` + `CASpringAnimation(keyPath: "path")`: scroll spring 동기화 애니메이션
- `ResultHighlightsView` 회귀 수정 3건:
  1. `pendingFocusTime` apply defer → thumbnail placeholder spill 버그 해소
  2. `handleInteraction` 30fps throttle → 드래그 중 Task 폭발 방지
  3. seek guard + `onDisappear` Task cancel → preview overlay 메모리 누수 해소

---

## 이후 주요 진화 포인트 (참고)

Cliff 본체에서 이 최초 구현이 어떻게 발전했는지 요약합니다.

### ClipRangePicker

**최초**: 순수 SwiftUI `ZStack + DragGesture`. contentWidth = viewportWidth 고정, 스크롤 없음.

**현재**: `UIScrollView` 기반 `UIViewRepresentable` + `ClipRangeCoordinator` 로 완전 재작성.
- **Pinch zoom**: `UIPinchGestureRecognizer` 로 contentWidth 확장, focal point 보정으로 손가락 위치에서 줌.
- **Long-press body translate**: `UILongPressGestureRecognizer` + `UIPanGestureRecognizer` simultaneous 로 구간 평행 이동. 햅틱 피드백 포함.
- **Imperative channel**: `ClipRangePickerController.focus(on:)` 로 SwiftUI diff 없이 특정 시간으로 스크롤.
- **배경**: 순수 SwiftUI DragGesture 는 scroll + handle 동시 인식에서 충돌이 발생해 UIScrollView 로 이전.

### ResultHighlightsView

현재도 `TabView(.page)` + `@State` 배열 구조는 동일하게 유지됩니다.

**주의**: `.id(currentPage)` 를 `ClipRangePicker` 자체에 부여하면 페이지 전환 때마다 picker 가 재생성되어 썸네일 Task가 재시작되는 **회귀**가 발생합니다. 현재 코드에서는 picker 에 `.id()` 부여를 명시적으로 금지하고, `ClipRangePickerController.focus(on:)` 로 뷰 재생성 없이 스크롤 위치만 이동합니다.

### ResultHighlightMock

FNV-1a + xorshift64 구조 그대로 유지. 변경 없음.
