import SwiftUI

@main
struct BibleAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await prefetchLectionary() }
        }
    }

    /// Pre-fetch the current and next year's lectionary data to disk cache so the
    /// app works offline after first launch. Runs silently in the background.
    private func prefetchLectionary() async {
        let year = Calendar.current.component(.year, from: Date())
        await LectionaryService.shared.prefetchYearIfNeeded(year)
        await LectionaryService.shared.prefetchYearIfNeeded(year + 1)
    }
}
