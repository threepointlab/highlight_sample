import SwiftUI

/// Sample entry point: creates one mock Trial (60 s) and displays ResultHighlightsView.
/// The thumbnail strip will show placeholder colors — /dev/null has no video frames.
struct DemoRootView: View {
    private let trial = Trial(id: UUID(), duration: 60)

    var body: some View {
        let highlights = ResultHighlightMock.generate(for: trial)
        ResultHighlightsView(
            highlights: highlights,
            videoURL: URL(fileURLWithPath: "/dev/null"),
            videoDuration: trial.duration
        )
        .preferredColorScheme(.dark)
    }
}
