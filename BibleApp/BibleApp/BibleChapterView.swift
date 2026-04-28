//  BibleChapterView.swift
//  BibleApp
//
//  Displays a Bible book as a continuous, scrollable stream of chapters.
//  All chapters of the active book are loaded upfront from BibleDatabase
//  and rendered in a single ScrollView so the user can scroll seamlessly
//  forward and backward between chapters. Native rubber-band remains at
//  the book's first and last chapters.
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
    var onVisibleChapterChange: (String, Int) -> Void = { _, _ in }

    @State private var bookChapters: [LoadedChapter] = []
    @State private var loadedBookSlug: String? = nil
    @State private var visibleChapterID: String? = nil
    @State private var lastScrollOffset: CGFloat = 0
    @State private var pendingScrollTarget: String? = nil
    @State private var hasInitiallyLoaded = false

    init(isReadingState: Binding<Bool>, topContentInset: CGFloat,
         onTap: @escaping () -> Void = {},
         onVisibleChapterChange: @escaping (String, Int) -> Void = { _, _ in }) {
        _isReadingState = isReadingState
        self.topContentInset = topContentInset
        self.onTap = onTap
        self.onVisibleChapterChange = onVisibleChapterChange
    }

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        GeometryReader { scrollGeo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: topContentInset)

                        if !bookChapters.isEmpty {
                            ForEach(bookChapters) { chapter in
                                chapterContent(chapter: chapter, screenHeight: scrollGeo.size.height)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: ChapterTopsKey.self,
                                                value: [chapter.id: geo.frame(in: .named("chapterScroll")).minY]
                                            )
                                        }
                                    )
                                    .id(chapter.id)
                            }
                        } else {
                            unavailableView(scrollGeo: scrollGeo, colors: colors)
                        }

                        Spacer().frame(height: 100)
                    }
                    .frame(maxWidth: .infinity, minHeight: scrollGeo.size.height, alignment: .topLeading)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ChapterScrollOffsetKey.self,
                                value: -geo.frame(in: .named("chapterScroll")).minY
                            )
                        }
                    )
                }
                .onChange(of: pendingScrollTarget) { _, target in
                    guard let target = target else { return }
                    if hasInitiallyLoaded {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    } else {
                        proxy.scrollTo(target, anchor: .top)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            hasInitiallyLoaded = true
                        }
                    }
                    pendingScrollTarget = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "chapterScroll")
        .onPreferenceChange(ChapterScrollOffsetKey.self) { offset in
            updateReadingState(scrollOffset: offset)
        }
        .onPreferenceChange(ChapterTopsKey.self) { tops in
            updateVisibleChapter(tops: tops)
        }
        .simultaneousGesture(TapGesture().onEnded { onTap() })
        .background(colors.background)
        .scrollContentBackground(.hidden)
        .onAppear { syncWithProvider() }
        .onChange(of: providerStateKey) { _, _ in syncWithProvider() }
    }

    // MARK: - Chapter rendering

    @ViewBuilder
    private func chapterContent(chapter: LoadedChapter, screenHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ChapterHeaderView(
                bookName: chapter.bookName,
                chapter: chapter.chapter,
                screenHeight: screenHeight
            )
            .padding(.horizontal, hPageMargin)

            ChapterVersesView(verses: chapter.verses)
                .padding(.horizontal, hPageMargin)
        }
    }

    @ViewBuilder
    private func unavailableView(scrollGeo: GeometryProxy, colors: ThemeColors) -> some View {
        switch provider.state {
        case .empty(let bookName, let chapter):
            ChapterHeaderView(bookName: bookName, chapter: chapter,
                              screenHeight: scrollGeo.size.height)
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
        default:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    // MARK: - State sync

    private var providerStateKey: String {
        switch provider.state {
        case .loaded(let bookName, let chapter, _):
            return "loaded-\(bookName)-\(chapter)"
        case .empty(let bookName, let chapter):
            return "empty-\(bookName)-\(chapter)"
        case .idle:
            return "idle"
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

        let targetID = "\(bookName)-\(chapter)"

        if loadedBookSlug != entry.slug {
            // New book — reload all chapters
            loadedBookSlug = entry.slug
            bookChapters = loadAllChapters(slug: entry.slug)
            visibleChapterID = nil
            hasInitiallyLoaded = false
            if !bookChapters.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    pendingScrollTarget = targetID
                }
            }
        } else {
            // Same book — scroll to chapter only if not already there
            if visibleChapterID != targetID {
                pendingScrollTarget = targetID
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

    // MARK: - Visibility detection

    private func updateVisibleChapter(tops: [String: CGFloat]) {
        // The "current" chapter is the one whose top has scrolled to (or just past)
        // the reading line near the top of the viewport.
        let threshold = topContentInset + 120
        let candidates = tops
            .filter { $0.value <= threshold }
            .sorted { $0.value > $1.value }

        guard let visible = candidates.first else { return }

        if visibleChapterID != visible.key {
            visibleChapterID = visible.key
            if let chapter = bookChapters.first(where: { $0.id == visible.key }) {
                onVisibleChapterChange(chapter.bookName, chapter.chapter)
            }
        }
    }

    private func updateReadingState(scrollOffset: CGFloat) {
        lastScrollOffset = scrollOffset
        let nearTop = scrollOffset <= 2
        let next: Bool = !nearTop
        if next != isReadingState {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isReadingState = next
            }
        }
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
            .padding(.bottom, 24)
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
        // Extra top spacing between paragraphs (half a body line height)
        let paragraphGap = textSize.bodyPointSize * 0.5 + spacing.bodyLineSpacing

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { secIdx, section in
                if let heading = section.heading?.trimmingCharacters(in: .whitespacesAndNewlines), !heading.isEmpty {
                    ChapterSectionHeadingView(
                        text: heading,
                        isFirstInChapter: firstHeadingIndex == secIdx
                    )
                }

                let paragraphs = verseParagraphs(from: section.verses)

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { paraIdx, para in
                    inlineVersesText(para.verses, colors: colors)
                        .lineSpacing(spacing.bodyLineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, paraIdx > 0 ? paragraphGap : 0)
                }
            }
        }
    }

    /// Flowing inline verses within one paragraph.
    private func inlineVersesText(_ paraVerses: [BibleVerse], colors: ThemeColors) -> Text {
        paraVerses.reduce(Text("")) { result, verse in
            let numText = Text("\(verse.v)  ")
                .font(ThemeFont.verseNumber(theme, textSize))
                .foregroundStyle(colors.accent)
                .baselineOffset(ThemeFont.verseNumberBaselineOffset(textSize))
            let bodyText = Text(verse.v == paraVerses.last?.v ? verse.t : verse.t + "  ")
                .font(ThemeFont.bodyDefault(theme, textSize))
                .foregroundStyle(colors.textPrimary)
            return result + numText + bodyText
        }
    }
}

// MARK: - Preference keys

private struct ChapterScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChapterTopsKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
