//  BibleChapterView.swift
//  BibleApp
//
//  Displays a single Bible chapter loaded by BibleChapterProvider.
//  Verse numbers appear inline before each verse in the accent colour.
//  Verses marked with p:true in the data start a new visible paragraph.

import SwiftUI

struct BibleChapterView: View {
    @Environment(\.appTheme)    private var theme
    @Environment(\.appMode)     private var mode
    @Environment(\.appTextSize) private var textSize
    @Environment(BibleChapterProvider.self) private var provider

    @Binding var isReadingState: Bool
    var topContentInset: CGFloat
    var onTap: () -> Void = {}

    @State private var lastScrollOffset: CGFloat = 0

    init(isReadingState: Binding<Bool>, topContentInset: CGFloat, onTap: @escaping () -> Void = {}) {
        _isReadingState = isReadingState
        self.topContentInset = topContentInset
        self.onTap = onTap
    }

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        GeometryReader { scrollGeo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: topContentInset)

                    switch provider.state {

                    // ── Not yet loaded ───────────────────────────────────────
                    case .idle:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)

                    // ── Book loaded successfully ─────────────────────────────
                    case .loaded(let bookName, let chapter, let verses):
                        ChapterHeaderView(bookName: bookName, chapter: chapter,
                                          screenHeight: scrollGeo.size.height)
                            .padding(.horizontal, 24)

                        ChapterVersesView(verses: verses)
                            .padding(.horizontal, 24)

                    // ── Book not in DB (needs sync) ──────────────────────────
                    case .empty(let bookName, let chapter):
                        ChapterHeaderView(bookName: bookName, chapter: chapter,
                                          screenHeight: scrollGeo.size.height)
                            .padding(.horizontal, 24)

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
                        .padding(.horizontal, 24)
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
        }
        .id(chapterScrollResetKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "chapterScroll")
        .onPreferenceChange(ChapterScrollOffsetKey.self) { offset in
            updateReadingState(scrollOffset: offset)
        }
        .simultaneousGesture(TapGesture().onEnded { onTap() })
        .background(colors.background)
        .scrollContentBackground(.hidden)
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

    private var chapterScrollResetKey: String {
        switch provider.state {
        case .loaded(let bookName, let chapter, _):
            return "loaded-\(bookName)-\(chapter)"
        case .empty(let bookName, let chapter):
            return "empty-\(bookName)-\(chapter)"
        case .idle:
            return "idle"
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

// MARK: - Scroll offset preference key

private struct ChapterScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
