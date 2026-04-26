import SwiftUI
import UIKit

enum Pane { case left, center }

enum LeftSelection: Equatable {
    case daily
    case book(String)
}

struct ContentView: View {
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.purba.rawValue
    @AppStorage("appColorScheme") private var appColorSchemeRaw: String = AppColorScheme.light.rawValue
    @AppStorage("appTextSize") private var appTextSizeRaw: String = AppTextSize.pt20.rawValue
    @AppStorage("appSpacing") private var appSpacingRaw: String = AppSpacing.normal.rawValue

    @AppStorage("bibleSource") private var bibleSourceRaw: String = BibleSource.alkitab.rawValue
    @AppStorage("lectionaryRegion") private var lectionaryRegion: String = "ID"

    @State private var currentPane: Pane = .center
    @State private var leftSelection: LeftSelection = .daily
    @State private var selectedRightLabel: String? = Calendar.current.startOfDay(for: Date())
        .formatted(.dateTime.day().month(.wide))

    @State private var showPreferences = false
    @State private var showAppSettings = false
    /// True while reading (scroll down or tap); hides bottom bar and status bar.
    @State private var isReadingState = false
    @State private var isListenState = false
    @State private var dragDx: CGFloat = 0
    @State private var isDraggingPane = false

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
            // Fixed left pane width.
            let leftW = W * 0.88

            let colors = Colors.theme(currentTheme, mode: resolvedMode)
            let drag = effectiveDragDx(leftW: leftW)
            let centerX = centerPaneX(leftW: leftW, dragDx: drag)
            let overlayOpacity = mainContentOverlayOpacity(leftW: leftW, dragDx: drag)
            let leftPaneParallaxX = leftPaneParallaxOffset(leftW: leftW, centerPaneX: centerX)
            let leftPaneParallaxScale = leftPaneParallaxScale(leftW: leftW, centerPaneX: centerX)
            let bottomSafeArea = geo.safeAreaInsets.bottom
            // Content always starts at y=0; the status bar floats over it (no layout shift on state change).
            let topContentInset: CGFloat = 0

            ZStack {
                // Full-screen base. No special top safe-area band is painted.
                colors.background.ignoresSafeArea()

                // Left-pane underlay to avoid bright gaps during parallax/scale.
                HStack(spacing: 0) {
                    colors.surface
                        .frame(width: leftW + 40)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Left pane (behind).
                HStack(spacing: 0) {
                    LeftPaneView(
                        selection: $leftSelection,
                        selectedLabel: $selectedRightLabel,
                        topSafeArea: topSafeArea,
                        bottomSafeArea: bottomSafeArea,
                        onOpenAppSettings: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                currentPane = .center
                                dragDx = 0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showAppSettings = true
                            }
                        },
                        onClose: { dismissPaneToCenter() }
                    )
                        .frame(width: leftW)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: leftPaneParallaxX)
                .scaleEffect(leftPaneParallaxScale, anchor: .leading)
                .environment(\.appTheme, currentTheme)
                .environment(\.appMode,  resolvedMode)
                .environment(\.appTextSize, textSize)

                // Front surface: full-screen, slides under the status bar.
                ZStack(alignment: .top) {
                    Group {
                        switch leftSelection {
                        case .daily:
                            DailyMassView(
                                isReadingState: $isReadingState,
                                isListenState: $isListenState,
                                topContentInset: topContentInset,
                                onTap: { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isReadingState.toggle() } }
                            )
                            .environment(readingProvider)
                        case .book:
                            BibleChapterView(
                                isReadingState: $isReadingState,
                                topContentInset: topContentInset,
                                onTap: { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isReadingState.toggle() } }
                            )
                            .environment(chapterProvider)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .environment(\.appTheme, currentTheme)
                    .environment(\.appMode,  resolvedMode)
                    .environment(\.appTextSize, textSize)
                    .environment(\.appSpacing, spacing)
                    .overlay {
                        if overlayOpacity > 0.001 {
                            Rectangle()
                                .fill(colors.background.opacity(overlayOpacity))
                                .contentShape(Rectangle())
                                .onTapGesture { dismissPaneToCenter() }
                        }
                    }

                    // Bottom navigation bar — slides with the front surface, hidden in reading state.
                    if !isReadingState {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            BottomBar(
                                primaryTitle: topBarPrimaryTitle,
                                secondaryTitle: topBarSecondaryTitle,
                                bottomSafeArea: bottomSafeArea,
                                isListenState: isListenState,
                                showListenButton: leftSelection == .daily,
                                onOpenLeft: { togglePane(.left) },
                                onOpenRight: { togglePane(.left) },
                                onOpenThemeSettings: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                        showPreferences = true
                                    }
                                },
                                onToggleListen: { isListenState.toggle() }
                            )
                            .environment(\.appTheme, currentTheme)
                            .environment(\.appMode,  resolvedMode)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: showPreferences ? -96 : 0)
                .offset(x: centerX)

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
                if case .book = new { isListenState = false }

                if case .book(let newBook) = new {
                    // Always reset chapter to the first chapter when switching books.
                    let switchedBooks: Bool = {
                        if case .book(let oldBook) = old { return oldBook != newBook }
                        return true
                    }()
                    if switchedBooks {
                        selectedRightLabel = chapterItems(for: newBook).first
                    }
                }

                ensureDefaultRightSelection()
                if currentPane == .left { dismissPaneToCenter() }
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
            .onChange(of: currentPane) { oldValue, newValue in
                guard oldValue != newValue else { return }
                if newValue == .left {
                    playPaneOpenHaptic()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        isDraggingPane = true
                        withTransaction(Transaction(animation: nil)) { dragDx = value.translation.width }
                    }
                    .onEnded { value in
                        defer { isDraggingPane = false }
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { dragDx = 0 }
                            return
                        }

                        let dx = value.translation.width
                            + (value.predictedEndTranslation.width - value.translation.width) * 0.3
                        let threshold = leftW * 0.35

                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            switch currentPane {
                            case .center:
                                if dx > threshold { currentPane = .left }
                            case .left:
                                if dx < -threshold { currentPane = .center }
                            }
                            dragDx = 0
                        }
                    }
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showPreferences)
            .sheet(isPresented: $showAppSettings) {
                AcknowledgementsView()
                    .environment(\.appTheme, currentTheme)
                    .environment(\.appMode,  resolvedMode)
            }
            .onChange(of: lectionaryRegion) { _, _ in
                // Region changed — clear cache so today's reading reloads with the new region
                readingProvider.clearCache()
                Task { await readingProvider.loadDay(readingProvider.selectedDate) }
            }
            // ignoresSafeArea on the ZStack (not on GeometryReader) so that
            // geo.safeAreaInsets.top above correctly reports the real device
            // inset instead of returning 0.
            .ignoresSafeArea(.all)
        }
        .preferredColorScheme(preferredInterfaceScheme)
        .statusBarHidden(isReadingState)
    }

    // MARK: - Motion helpers

    private func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(x, lo), hi) }

    private func effectiveDragDx(leftW: CGFloat) -> CGFloat {
        guard isDraggingPane else { return 0 }
        switch currentPane {
        case .center:
            if dragDx > 0 { return clamp(dragDx, 0, leftW) }
            return 0
        case .left:
            return clamp(min(dragDx, 0), -leftW, 0)
        }
    }

    private func centerPaneX(leftW: CGFloat, dragDx: CGFloat) -> CGFloat {
        switch currentPane {
        case .center: return dragDx
        case .left:   return leftW + dragDx
        }
    }

    private func leftPaneParallaxOffset(leftW: CGFloat, centerPaneX: CGFloat) -> CGFloat {
        let closedOffset: CGFloat = 22
        let progress = clamp(centerPaneX / leftW, 0, 1)
        return closedOffset * (1 - progress)
    }

    private func leftPaneParallaxScale(leftW: CGFloat, centerPaneX: CGFloat) -> CGFloat {
        let closedScale: CGFloat = 0.982
        let progress = clamp(centerPaneX / leftW, 0, 1)
        return closedScale + (1 - closedScale) * progress
    }

    // MARK: - Dimming

    private func mainContentOverlayOpacity(leftW: CGFloat, dragDx: CGFloat) -> Double {
        let maxDim = 0.70
        switch currentPane {
        case .center:
            if dragDx == 0 { return 0 }
            return min(Double(abs(dragDx) / leftW) * maxDim, maxDim)
        case .left:
            return Double(1 - abs(dragDx) / leftW) * maxDim
        }
    }

    private func dismissPaneToCenter() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            currentPane = .center
            dragDx = 0
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

    private func togglePane(_ pane: Pane) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            currentPane = (currentPane == pane) ? .center : pane
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
    var isListenState: Bool = false
    var showListenButton: Bool = false
    let onOpenLeft: () -> Void
    let onOpenRight: () -> Void
    let onOpenThemeSettings: () -> Void
    var onToggleListen: (() -> Void)? = nil

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

            // Listen button — only shown on the Daily Mass reading view
            if showListenButton {
                Button(action: { onToggleListen?() }) {
                    Image(systemName: "ear.badge.waveform")
                        .font(.system(size: 17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isListenState ? colors.accent : colors.textSecondary)
                        .frame(width: 44, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isListenState)
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
