//  BibleChapterView.swift
//  BibleApp
//
//  Displays a Bible book as a stack of chapter pages. Each chapter renders
//  in its own ScrollView with native rubber-band, so the user sees the
//  scroll halt at the chapter's top and bottom. Pulling past the boundary
//  triggers a slide transition to the adjacent chapter.
//
//  Verse numbers appear inline before each verse in the accent colour.
//  Verses marked with p:true in the data start a new visible paragraph.

import SwiftUI
import UIKit

// MARK: - LoadedChapter

struct LoadedChapter: Identifiable, Equatable {
    let id: String           // "<bookName>-<chapter>"
    let bookSlug: String
    let bookName: String
    let chapter: Int
    let verses: [BibleVerse]

    static func == (lhs: LoadedChapter, rhs: LoadedChapter) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BibleChapterView

struct BibleChapterView: View {
    @Environment(\.appTheme)    private var theme
    @Environment(\.appMode)     private var mode
    @Environment(\.appTextSize) private var textSize
    @Environment(BibleChapterProvider.self) private var provider

    @Binding var isReadingState: Bool
    var topContentInset: CGFloat
    var onTap: () -> Void = {}
    var onChapterChange: (String, Int) -> Void = { _, _ in }

    @State private var bookChapters: [LoadedChapter] = []
    @State private var currentIndex: Int = 0
    @State private var loadedBookSlug: String? = nil
    @State private var transitionEdge: Edge = .bottom
    @State private var lastScrollOffset: CGFloat = 0
    @State private var nextStartAtBottom: Bool = false

    init(isReadingState: Binding<Bool>, topContentInset: CGFloat,
         onTap: @escaping () -> Void = {},
         onChapterChange: @escaping (String, Int) -> Void = { _, _ in }) {
        _isReadingState = isReadingState
        self.topContentInset = topContentInset
        self.onTap = onTap
        self.onChapterChange = onChapterChange
    }

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        ZStack {
            if let current = currentChapter {
                ChapterPageView(
                    chapter: current,
                    topContentInset: topContentInset,
                    startAtBottom: nextStartAtBottom,
                    onTap: onTap,
                    onScrollOffsetChange: { offset in
                        lastScrollOffset = offset
                        updateReadingState(scrollOffset: offset)
                    },
                    onOverscrollBottom: goNext,
                    onOverscrollTop: goPrev
                )
                .id(current.id)
                .transition(transitionForEdge(transitionEdge))
            } else {
                unavailableView(colors: colors)
            }
        }
        .background(colors.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { syncWithProvider() }
        .onChange(of: providerStateKey) { _, _ in syncWithProvider() }
    }

    private var currentChapter: LoadedChapter? {
        guard !bookChapters.isEmpty,
              currentIndex >= 0,
              currentIndex < bookChapters.count else { return nil }
        return bookChapters[currentIndex]
    }

    private func transitionForEdge(_ edge: Edge) -> AnyTransition {
        let opposite: Edge = (edge == .bottom) ? .top : .bottom
        return .asymmetric(
            insertion: .move(edge: edge),
            removal:   .move(edge: opposite)
        )
    }

    @ViewBuilder
    private func unavailableView(colors: ThemeColors) -> some View {
        switch provider.state {
        case .empty(let bookName, let chapter):
            VStack(spacing: 24) {
                ChapterHeaderView(bookName: bookName, chapter: chapter, screenHeight: 0)
                    .padding(.horizontal, hPageMargin)
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.accent)
                    Text("Teks belum tersedia. Sinkronkan Alkitab melalui Pengaturan › Admin.")
                        .font(.system(size: 13))
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(colors.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(colors.border, lineWidth: 1))
                .padding(.horizontal, hPageMargin)
                Spacer()
            }
        default:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Navigation

    private func goNext() {
        guard currentIndex + 1 < bookChapters.count else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        transitionEdge = .bottom
        nextStartAtBottom = false
        withAnimation(.easeInOut(duration: 0.4)) {
            currentIndex += 1
        }
        notifyChapterChange()
    }

    private func goPrev() {
        guard currentIndex > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        transitionEdge = .top
        nextStartAtBottom = true
        withAnimation(.easeInOut(duration: 0.4)) {
            currentIndex -= 1
        }
        notifyChapterChange()
    }

    private func notifyChapterChange() {
        if let current = currentChapter {
            onChapterChange(current.bookName, current.chapter)
        }
    }

    // MARK: - State sync

    private var providerStateKey: String {
        switch provider.state {
        case .loaded(let n, let c, _): return "loaded-\(n)-\(c)"
        case .empty(let n, let c):     return "empty-\(n)-\(c)"
        case .idle:                    return "idle"
        }
    }

    private func syncWithProvider() {
        let (bookName, chapter): (String, Int) = {
            switch provider.state {
            case .loaded(let n, let c, _): return (n, c)
            case .empty(let n, let c):     return (n, c)
            case .idle:                    return ("", 0)
            }
        }()

        guard !bookName.isEmpty,
              let entry = BibleCatalog.entry(forName: bookName) else { return }

        // Load all chapters of the book once per book selection.
        if loadedBookSlug != entry.slug {
            loadedBookSlug = entry.slug
            bookChapters = loadAllChapters(slug: entry.slug)
            currentIndex = bookChapters.firstIndex(where: { $0.chapter == chapter }) ?? 0
            return
        }

        // Same book — animate to the externally-selected chapter if different.
        // External selections always start at the top of the chapter.
        if let idx = bookChapters.firstIndex(where: { $0.chapter == chapter }),
           idx != currentIndex {
            transitionEdge = idx > currentIndex ? .bottom : .top
            nextStartAtBottom = false
            withAnimation(.easeInOut(duration: 0.4)) {
                currentIndex = idx
            }
        }
    }

    private func loadAllChapters(slug: String) -> [LoadedChapter] {
        guard let entry = BibleCatalog.entry(forSlug: slug) else { return [] }
        var chapters: [LoadedChapter] = []
        for ch in 1...entry.chapterCount {
            if let verses = BibleDatabase.shared.verses(bookSlug: slug, chapter: ch),
               !verses.isEmpty {
                chapters.append(LoadedChapter(
                    id: "\(entry.name)-\(ch)",
                    bookSlug: slug,
                    bookName: entry.name,
                    chapter: ch,
                    verses: verses
                ))
            }
        }
        return chapters
    }

    private func updateReadingState(scrollOffset: CGFloat) {
        let nearTop = scrollOffset <= 2
        let next: Bool = !nearTop
        if next != isReadingState {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isReadingState = next
            }
        }
    }
}

// MARK: - ChapterPageView

private struct ChapterPageView: View {
    @Environment(\.appTheme)    private var theme
    @Environment(\.appMode)     private var mode

    let chapter: LoadedChapter
    let topContentInset: CGFloat
    let startAtBottom: Bool
    let onTap: () -> Void
    let onScrollOffsetChange: (CGFloat) -> Void
    let onOverscrollBottom: () -> Void
    let onOverscrollTop: () -> Void

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        GeometryReader { scrollGeo in
            ScrollView {
                // Hidden anchor finds the parent UIScrollView and observes
                // its contentOffset for rubber-band overscroll detection.
                // When startAtBottom is true, also positions initial offset
                // at the bottom of the content as soon as contentSize is known.
                Color.clear.frame(height: 0).background(
                    ScrollOverscrollObserver(
                        onOverscrollBottom: onOverscrollBottom,
                        onOverscrollTop: onOverscrollTop,
                        startAtBottom: startAtBottom
                    )
                )

                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: topContentInset)

                    ChapterHeaderView(
                        bookName: chapter.bookName,
                        chapter: chapter.chapter,
                        screenHeight: scrollGeo.size.height
                    )
                    .padding(.horizontal, hPageMargin)

                    ChapterVersesView(verses: chapter.verses)
                        .padding(.horizontal, hPageMargin)

                    Spacer().frame(height: 100)
                }
                .frame(maxWidth: .infinity, minHeight: scrollGeo.size.height, alignment: .topLeading)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ChapterScrollOffsetKey.self,
                            value: -geo.frame(in: .named("chapterPage")).minY
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "chapterPage")
        .onPreferenceChange(ChapterScrollOffsetKey.self) { onScrollOffsetChange($0) }
        .simultaneousGesture(TapGesture().onEnded { onTap() })
        .background(colors.background)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - ChapterHeaderView

private struct ChapterHeaderView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.appTextSize) private var textSize

    let bookName: String
    let chapter: Int
    var screenHeight: CGFloat = 0

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        VStack(spacing: 32) {
            Spacer(minLength: 0)
            Text("\(bookName) \(chapter)")
                .font(ThemeFont.titleDefault(theme, textSize))
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            Rectangle()
                .fill(colors.accent)
                .frame(height: 1)
                .frame(width: 72)

            Spacer(minLength: 40)
        }
        .frame(minHeight: screenHeight > 0 ? screenHeight * 0.44 : 220)
    }
}

// MARK: - Verse sections (optional `h` on BibleVerse)

private struct BibleVerseSection {
    var heading: String?
    var verses: [BibleVerse]
}

private func bibleVerseSections(from verses: [BibleVerse]) -> [BibleVerseSection] {
    var sections: [BibleVerseSection] = []
    var currentHeading: String?
    var currentVerses: [BibleVerse] = []

    for verse in verses {
        if let h = verse.h?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            if !currentVerses.isEmpty {
                sections.append(BibleVerseSection(heading: currentHeading, verses: currentVerses))
                currentVerses = []
            }
            currentHeading = h
            currentVerses = [verse]
        } else {
            currentVerses.append(verse)
        }
    }
    if !currentVerses.isEmpty {
        sections.append(BibleVerseSection(heading: currentHeading, verses: currentVerses))
    }
    return sections
}

// MARK: - Verse paragraphs (optional `p` on BibleVerse)

private struct VerseParagraph {
    var verses: [BibleVerse]
}

private func verseParagraphs(from verses: [BibleVerse]) -> [VerseParagraph] {
    var paragraphs: [VerseParagraph] = []
    var current: [BibleVerse] = []
    for verse in verses {
        if verse.p == true && !current.isEmpty {
            paragraphs.append(VerseParagraph(verses: current))
            current = []
        }
        current.append(verse)
    }
    if !current.isEmpty {
        paragraphs.append(VerseParagraph(verses: current))
    }
    return paragraphs
}

// MARK: - Chapter section heading

private struct ChapterSectionHeadingView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.appTextSize) private var textSize

    let text: String
    /// Extra space after chapter title row; first subheading only.
    var isFirstInChapter: Bool

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        Text(text)
            .font(ThemeFont.chapterSectionHeading(theme, textSize))
            .foregroundStyle(colors.textPrimary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isFirstInChapter ? 20 : 36)
            .padding(.bottom, 12)
    }
}

// MARK: - ChapterVersesView

private struct ChapterVersesView: View {
    @Environment(\.appTheme)    private var theme
    @Environment(\.appMode)     private var mode
    @Environment(\.appTextSize) private var textSize
    @Environment(\.appSpacing)  private var spacing

    let verses: [BibleVerse]

    private var sections: [BibleVerseSection] {
        bibleVerseSections(from: verses)
    }

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        let firstHeadingIndex = sections.firstIndex { sec in
            guard let h = sec.heading?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !h.isEmpty
        }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { secIdx, section in
                if let heading = section.heading?.trimmingCharacters(in: .whitespacesAndNewlines), !heading.isEmpty {
                    ChapterSectionHeadingView(
                        text: heading,
                        isFirstInChapter: firstHeadingIndex == secIdx
                    )
                }

                let paragraphs = verseParagraphs(from: section.verses)

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                    let prose = attributedVerseParagraph(para.verses, colors: colors)
                    let laidOut = textSize.applyingChapterParagraphLayout(prose, spacing: spacing)
                    Text(laidOut)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// One typography paragraph (`p` block): verse numerals styled; line spacing handled by `applyingChapterParagraphLayout`.
    private func attributedVerseParagraph(_ paraVerses: [BibleVerse], colors: ThemeColors) -> AttributedString {
        var combined = AttributedString("")
        let bodyFont = ThemeFont.bodyDefault(theme, textSize)
        let verseFont = ThemeFont.verseNumber(theme, textSize)
        let verseBaseline = ThemeFont.verseNumberBaselineOffset(textSize)

        for verse in paraVerses {
            let spacer = verse.v == paraVerses.last?.v ? "" : "  "
            let token = "\(verse.v)"

            var numChunk = AttributedString(token)
            numChunk.font = verseFont
            numChunk.foregroundColor = colors.accent
            combined.append(numChunk)
            let numChars = token.count
            let startIndex = combined.index(combined.endIndex, offsetByCharacters: -numChars)
            combined[startIndex..<combined.endIndex].baselineOffset = verseBaseline

            var spaceAfterNum = AttributedString(" ")
            spaceAfterNum.font = bodyFont
            spaceAfterNum.foregroundColor = colors.textPrimary
            combined.append(spaceAfterNum)

            var bodyChunk = AttributedString(verse.t + spacer)
            bodyChunk.font = bodyFont
            bodyChunk.foregroundColor = colors.textPrimary
            combined.append(bodyChunk)
        }
        return combined
    }
}

// MARK: - Scroll offset preference key

private struct ChapterScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Scroll overscroll observer
//
// Observes the underlying UIScrollView's contentOffset via KVO. Fires the
// matching callback once per "pull session" when the rubber-band overscroll
// at top or bottom exceeds the threshold.

private struct ScrollOverscrollObserver: UIViewRepresentable {
    let onOverscrollBottom: () -> Void
    let onOverscrollTop: () -> Void
    let startAtBottom: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        DispatchQueue.main.async {
            context.coordinator.attach(from: view, startAtBottom: startAtBottom)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onOverscrollBottom = onOverscrollBottom
        context.coordinator.onOverscrollTop = onOverscrollTop
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOverscrollBottom: onOverscrollBottom,
            onOverscrollTop: onOverscrollTop
        )
    }

    final class Coordinator: NSObject {
        var onOverscrollBottom: () -> Void
        var onOverscrollTop: () -> Void
        private var offsetObservation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?
        private var hasTriggered = false
        private var didPositionAtBottom = false

        init(onOverscrollBottom: @escaping () -> Void,
             onOverscrollTop: @escaping () -> Void) {
            self.onOverscrollBottom = onOverscrollBottom
            self.onOverscrollTop = onOverscrollTop
        }

        func attach(from view: UIView, startAtBottom: Bool) {
            var v: UIView? = view.superview
            while let current = v {
                if let scrollView = current as? UIScrollView {
                    if startAtBottom {
                        positionAtBottom(scrollView: scrollView)
                    }
                    offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                        guard let self = self else { return }
                        // Suppress overscroll triggers until initial bottom positioning is settled
                        if startAtBottom && !self.didPositionAtBottom { return }
                        guard !self.hasTriggered else { return }
                        let maxOffset = max(sv.contentSize.height - sv.bounds.height, 0)
                        let bottomOverscroll = sv.contentOffset.y - maxOffset
                        let topOverscroll    = -sv.contentOffset.y

                        if bottomOverscroll > 60 {
                            self.hasTriggered = true
                            self.onOverscrollBottom()
                        } else if topOverscroll > 60 {
                            self.hasTriggered = true
                            self.onOverscrollTop()
                        } else if bottomOverscroll < 10 && topOverscroll < 10 {
                            self.hasTriggered = false
                        }
                    }
                    return
                }
                v = current.superview
            }
        }

        private func positionAtBottom(scrollView: UIScrollView) {
            // Snap to bottom now if content is already laid out, otherwise
            // observe contentSize and snap as soon as it is.
            let maxY = scrollView.contentSize.height - scrollView.bounds.height
            if maxY > 0 {
                scrollView.setContentOffset(CGPoint(x: 0, y: maxY), animated: false)
                didPositionAtBottom = true
                return
            }
            sizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] sv, _ in
                guard let self = self, !self.didPositionAtBottom else { return }
                let m = sv.contentSize.height - sv.bounds.height
                if m > 0 {
                    sv.setContentOffset(CGPoint(x: 0, y: m), animated: false)
                    self.didPositionAtBottom = true
                    self.sizeObservation?.invalidate()
                    self.sizeObservation = nil
                }
            }
        }
    }
}
