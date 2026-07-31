import SwiftUI
import UIKit

enum LeftSelection: Equatable {
    case daily
    case book(String)
}

private enum DrawerPage: Hashable {
    case left
    case main
}

private struct DrawerScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.purba.rawValue
    @AppStorage("appColorScheme") private var appColorSchemeRaw: String = AppColorScheme.light.rawValue
    @AppStorage("appTextSize") private var appTextSizeRaw: String = AppTextSize.pt20.rawValue
    @AppStorage("appSpacing") private var appSpacingRaw: String = AppSpacing.normal.rawValue

    @AppStorage("bibleSource") private var bibleSourceRaw: String = BibleSource.alkitab.rawValue
    @AppStorage("lectionaryRegion") private var lectionaryRegion: String = "ID"

    @State private var scrolledID: DrawerPage? = .main
    @State private var leftSelection: LeftSelection = .daily
    @State private var selectedRightLabel: String? = Calendar.current.startOfDay(for: Date())
        .formatted(.dateTime.day().month(.wide))

    @State private var showPreferences = false
    @State private var showAppSettings = false
    /// True while reading (scroll down or tap); hides bottom bar and status bar.
    @State private var isReadingState = false
    /// 0 when fully closed, 1 when fully open. Continuously tracks scroll offset.
    @State private var drawerProgress: CGFloat = 0

    @State private var readingProvider = DailyReadingProvider()
    @State private var chapterProvider = BibleChapterProvider()

    @Environment(\.colorScheme) private var systemScheme

    private var currentTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .purba }
    private var colorSchemePreference: AppColorScheme { AppColorScheme(rawValue: appColorSchemeRaw) ?? .light }
    private var textSize: AppTextSize { AppTextSize(rawValue: appTextSizeRaw) ?? .pt20 }
    private var spacing: AppSpacing { AppSpacing(rawValue: appSpacingRaw) ?? .normal }

    private var currentThemeBinding: Binding<AppTheme> {
        Binding(get: { AppTheme(rawValue: appThemeRaw) ?? .purba }, set: { appThemeRaw = $0.rawValue })
    }
    private var colorSchemePreferenceBinding: Binding<AppColorScheme> {
        Binding(
            get: { AppColorScheme(rawValue: appColorSchemeRaw) ?? .light },
            set: { appColorSchemeRaw = $0.rawValue }
        )
    }
    private var textSizeBinding: Binding<AppTextSize> {
        Binding(get: { AppTextSize(rawValue: appTextSizeRaw) ?? .pt20 }, set: { appTextSizeRaw = $0.rawValue })
    }
    private var spacingBinding: Binding<AppSpacing> {
        Binding(get: { AppSpacing(rawValue: appSpacingRaw) ?? .normal }, set: { appSpacingRaw = $0.rawValue })
    }

    private var resolvedMode: AppMode {
        switch colorSchemePreference {
        case .light:  return .day
        case .dark:   return .night
        case .system: return systemScheme == .dark ? .night : .day
        }
    }

    private var preferredInterfaceScheme: ColorScheme? {
        switch colorSchemePreference {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let topSafeArea = geo.safeAreaInsets.top
            let bottomSafeArea = geo.safeAreaInsets.bottom
            let leftW = W * 0.88

            let colors = Colors.theme(currentTheme, mode: resolvedMode)
            let topContentInset: CGFloat = 0

            ZStack {
                // Full-screen base. Acts as a safety fill behind any spring overshoot.
                colors.background.ignoresSafeArea()

                // Drawer powered by a horizontal paging ScrollView. Native pan
                // physics handle finger tracking, deceleration, and rubber-band.
                // `scrollPosition` can apply one frame late — first paint would show
                // the leading (left) column. ScrollViewReader jumps to main without
                // animation after layout so the default state is always main content.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            LeftPaneView(
                                selection: $leftSelection,
                                selectedLabel: $selectedRightLabel,
                                isOpen: scrolledID == .left,
                                topSafeArea: topSafeArea,
                                bottomSafeArea: bottomSafeArea,
                                onOpenAppSettings: {
                                    closeDrawer()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        showAppSettings = true
                                    }
                                },
                                onClose: { closeDrawer() }
                            )
                            .frame(width: leftW)
                            .background(colors.surface)
                            .environment(\.appTheme, currentTheme)
                            .environment(\.appMode,  resolvedMode)
                            .environment(\.appTextSize, textSize)
                            .id(DrawerPage.left)

                            ZStack(alignment: .top) {
                                Group {
                                    switch leftSelection {
                                    case .daily:
                                        DailyMassView(
                                            isReadingState: $isReadingState,
                                            topContentInset: topContentInset,
                                            onTap: { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isReadingState.toggle() } }
                                        )
                                        .environment(readingProvider)
                                    case .book:
                                        BibleChapterView(
                                            isReadingState: $isReadingState,
                                            topContentInset: topContentInset,
                                            onTap: { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isReadingState.toggle() } },
                                            onChapterChange: { bookName, chapter in
                                                handleVisibleChapterChange(bookName: bookName, chapter: chapter)
                                            }
                                        )
                                        .environment(chapterProvider)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .environment(\.appTheme, currentTheme)
                                .environment(\.appMode,  resolvedMode)
                                .environment(\.appTextSize, textSize)
                                .environment(\.appSpacing, spacing)
                                .scrollDisabled(scrolledID == .left)

                                Color.black
                                    .opacity(Double(drawerProgress) * 0.35)
                                    .contentShape(Rectangle())
                                    .onTapGesture { closeDrawer() }
                                    .allowsHitTesting(scrolledID == .left)
                            }
                            .frame(width: W)
                            .id(DrawerPage.main)
                        }
                        .scrollTargetLayout()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: DrawerScrollOffsetKey.self,
                                    value: -proxy.frame(in: .named("drawerScroll")).origin.x
                                )
                            }
                        )
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                    .scrollPosition(id: $scrolledID)
                    .scrollDisabled(showPreferences)
                    .coordinateSpace(name: "drawerScroll")
                    .onPreferenceChange(DrawerScrollOffsetKey.self) { offset in
                        let progress = max(0, min(1, (leftW - offset) / max(leftW, 1)))
                        if abs(progress - drawerProgress) > 0.0005 {
                            drawerProgress = progress
                        }
                    }
                    .onAppear {
                        // After first layout, snap to main so we never flash the left pane.
                        DispatchQueue.main.async {
                            var t = Transaction()
                            t.animation = nil
                            withTransaction(t) {
                                proxy.scrollTo(DrawerPage.main, anchor: .leading)
                            }
                            scrolledID = .main
                            drawerProgress = 0
                        }
                    }
                }

                // Bottom bar pinned to the screen, fades out as drawer opens.
                if !isReadingState {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        BottomBar(
                            primaryTitle: topBarPrimaryTitle,
                            secondaryTitle: topBarSecondaryTitle,
                            bottomSafeArea: bottomSafeArea,
                            onOpenLeft: { openDrawer() },
                            onOpenRight: { openDrawer() },
                            onOpenThemeSettings: {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    showPreferences = true
                                }
                            }
                        )
                        .environment(\.appTheme, currentTheme)
                        .environment(\.appMode,  resolvedMode)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(1 - Double(drawerProgress))
                    .allowsHitTesting(drawerProgress < 0.5 && !showPreferences)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showPreferences {
                    Rectangle()
                        .fill(colors.background.opacity(0.18))
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                showPreferences = false
                            }
                        }
                        .transition(.opacity)
                        .zIndex(20)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PreferencesView(
                            colorSchemePreference: colorSchemePreferenceBinding,
                            currentTheme: currentThemeBinding,
                            textSize: textSizeBinding,
                            spacing: spacingBinding,
                            onClose: {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    showPreferences = false
                                }
                            }
                        )
                        .environment(\.appTheme, currentTheme)
                        .environment(\.appMode,  resolvedMode)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .zIndex(21)
                }
            }
            .onAppear {
                applyBibleSource(bibleSourceRaw)
                ensureDefaultRightSelection()
                triggerLoadForSelectedDate()
            }
            .onChange(of: bibleSourceRaw) { _, newValue in
                applyBibleSource(newValue)
                readingProvider.clearCache()
                switch leftSelection {
                case .daily: triggerLoadForSelectedDate()
                case .book:  triggerLoadForChapter()
                }
            }
            .onChange(of: leftSelection) { old, new in
                isReadingState = false

                if case .book(let newBook) = new {
                    let switchedBooks: Bool = {
                        if case .book(let oldBook) = old { return oldBook != newBook }
                        return true
                    }()
                    if switchedBooks {
                        let validChapters = chapterItems(for: newBook)
                        if let selectedRightLabel,
                           validChapters.contains(selectedRightLabel) {
                            // Keep current selection.
                        } else {
                            selectedRightLabel = validChapters.first
                        }
                    }
                }

                ensureDefaultRightSelection()
                if scrolledID == .left { closeDrawer() }
                if case .book = new { triggerLoadForChapter() }
            }
            .onChange(of: selectedRightLabel) { _, _ in
                switch leftSelection {
                case .daily: triggerLoadForSelectedDate()
                case .book:  triggerLoadForChapter()
                }
            }
            .onChange(of: readingProvider.loadedMassDayTimeInterval) { _, _ in
                syncRightPaneLabelFromMassDay()
            }
            .onChange(of: scrolledID) { oldValue, newValue in
                guard oldValue != newValue else { return }
                if newValue == .left {
                    playPaneOpenHaptic()
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showPreferences)
            .sheet(isPresented: $showAppSettings) {
                AcknowledgementsView()
                    .environment(\.appTheme, currentTheme)
                    .environment(\.appMode,  resolvedMode)
            }
            .onChange(of: lectionaryRegion) { _, _ in
                readingProvider.clearCache()
                Task { await readingProvider.loadDay(readingProvider.selectedDate) }
            }
            .ignoresSafeArea(.all)
        }
        .preferredColorScheme(preferredInterfaceScheme)
        .statusBarHidden(isReadingState)
    }

    // MARK: - Drawer commands

    private func openDrawer() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            scrolledID = .left
        }
    }

    private func closeDrawer() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            scrolledID = .main
        }
    }

    // MARK: - Titles

    private var topBarPrimaryTitle: String {
        switch leftSelection {
        case .daily: return "Hari Ini"
        case .book(let name): return name
        }
    }

    private var topBarSecondaryTitle: String? {
        switch leftSelection {
        case .daily:
            return selectedRightLabel ?? Date().formatted(.dateTime.day().month(.wide))
        case .book:
            return selectedRightLabel
        }
    }

    private func playPaneOpenHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Data

    private func applyBibleSource(_ raw: String) {
        let source = BibleSource(rawValue: raw) ?? .alkitab
        BibleDatabase.shared.setSource(source)
    }

    private func ensureDefaultRightSelection() {
        if selectedRightLabel != nil { return }
        switch leftSelection {
        case .daily:
            selectedRightLabel = DailyPaneCalendar.todayFormattedLabel
        case .book(let book):
            selectedRightLabel = chapterItems(for: book).first
        }
    }

    private func triggerLoadForSelectedDate() {
        guard case .daily = leftSelection else { return }
        let date = dateFromSelectedLabel() ?? Calendar.current.startOfDay(for: Date())
        Task { await readingProvider.loadDay(date) }
    }

    /// Keeps the right pane highlight aligned with the `MassDay` actually shown.
    private func syncRightPaneLabelFromMassDay() {
        guard case .daily = leftSelection else { return }
        switch readingProvider.state {
        case .loaded(let d), .needsSync(let d), .offline(let d):
            let label = d.date.formatted(.dateTime.day().month(.wide))
            if selectedRightLabel != label {
                selectedRightLabel = label
            }
        default:
            break
        }
    }

    private func triggerLoadForChapter() {
        guard case .book(let name) = leftSelection,
              let chStr = selectedRightLabel,
              let chapter = Int(chStr) else { return }
        chapterProvider.load(bookName: name, chapter: chapter)
    }

    private func handleVisibleChapterChange(bookName: String, chapter: Int) {
        guard case .book(let currentBook) = leftSelection,
              currentBook == bookName else { return }
        let newLabel = "\(chapter)"
        if selectedRightLabel != newLabel {
            selectedRightLabel = newLabel
        }
    }

    private func dateFromSelectedLabel() -> Date? {
        guard let label = selectedRightLabel else { return nil }
        return DailyPaneCalendar.date(forLabel: label)
    }

    private func chapterItems(for book: String) -> [String] {
        let count = BibleCatalog.entry(forName: book)?.chapterCount ?? 30
        return (1...count).map { "\($0)" }
    }
}

#Preview { ContentView() }

// MARK: - Bottom navigation bar (liquid glass pill)

struct BottomBar: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    let primaryTitle: String
    let secondaryTitle: String?
    let bottomSafeArea: CGFloat
    let onOpenLeft: () -> Void
    let onOpenRight: () -> Void
    let onOpenThemeSettings: () -> Void

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        HStack(spacing: 0) {
            // Primary title → opens left pane
            Button(action: onOpenLeft) {
                HStack(spacing: 6) {
                    Text(primaryTitle)
                        .font(ThemeFont.buttonLarge)
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(.leading, 20)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 16)

            // Secondary title → opens left pane (chapter/date selection now there)
            if let sec = secondaryTitle {
                Button(action: onOpenRight) {
                    Text(sec)
                        .font(ThemeFont.buttonLarge)
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Paint palette → opens theme settings
            Button(action: onOpenThemeSettings) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 44, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(colors.border.opacity(0.4), lineWidth: 0.5))
        .shadow(color: .black.opacity(mode == .day ? 0.10 : 0.28), radius: 20, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, max(bottomSafeArea, 16))
    }
}
