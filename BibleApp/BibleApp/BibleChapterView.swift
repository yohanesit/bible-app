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
        case .empty(let bookName, _):
            VStack(spacing: 24) {
                BookHeaderView(bookName: bookName, screenHeight: 0)
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

                    if chapter.chapter == 1 {
                        BookHeaderView(
                            bookName: chapter.bookName,
                            screenHeight: scrollGeo.size.height
                        )
                        .padding(.horizontal, hPageMargin)
                    }

                    ChapterVersesView(verses: chapter.verses, chapter: chapter.chapter)
                        .padding(.horizontal, hPageMargin)
                        .padding(.top, chapter.chapter == 1 ? 0 : topContentInset > 0 ? 0 : 24)

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

// MARK: - BookHeaderView
//
// Centered hero treatment shown only on the book opener (chapter 1). Subsequent
// chapters omit this view entirely so the page begins with the drop cap.

private struct BookHeaderView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.appTextSize) private var textSize

    let bookName: String
    var screenHeight: CGFloat = 0

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        VStack(spacing: 32) {
            Spacer(minLength: 0)
            Text(bookName)
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
    let chapter: Int

    private var sections: [BibleVerseSection] {
        bibleVerseSections(from: verses)
    }

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        let firstHeadingIndex = sections.firstIndex { sec in
            guard let h = sec.heading?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !h.isEmpty
        }
        // Paragraph break behaves like a regular line break: gap between `p`
        // blocks matches the within-paragraph line spacing. The first-line
        // indent on each paragraph is what visually distinguishes them.
        let paragraphGap = spacing.bodyLineSpacing

        // Address (sectionIdx, paragraphIdx) of the chapter's first prose paragraph; that paragraph renders via DropCapParagraphView.
        let firstParagraphAddress: (Int, Int)? = {
            for (sIdx, section) in sections.enumerated() {
                let paras = verseParagraphs(from: section.verses)
                if !paras.isEmpty { return (sIdx, 0) }
            }
            return nil
        }()

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
                    let isDropCapParagraph = firstParagraphAddress.map { $0.0 == secIdx && $0.1 == paraIdx } ?? false

                    if isDropCapParagraph {
                        let body = uiKitVerseParagraph(
                            para.verses,
                            colors: colors,
                            suppressFirstVerseNumber: true,
                            spacing: spacing
                        )
                        DropCapParagraphView(
                            dropCapText: "\(chapter)",
                            body: body,
                            theme: theme,
                            textSize: textSize,
                            spacing: spacing,
                            accent: colors.accent
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, paraIdx > 0 ? paragraphGap : 0)
                    } else {
                        let prose = attributedVerseParagraph(para.verses, colors: colors)
                        let laidOut = textSize.applyingChapterParagraphLayout(prose, spacing: spacing)
                        Text(laidOut)
                            .lineSpacing(spacing.bodyLineSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, paraIdx > 0 ? paragraphGap : 0)
                    }
                }
            }
        }
    }

    /// One typography paragraph (`p` block): verse numerals styled; `\u{00A0}` ties number + first two words so the numeral is not orphaned on its own line.
    /// When `suppressFirstVerseNumber` is true (drop-cap paragraph), the first verse's superscript numeral is omitted; the cap takes its place.
    private func attributedVerseParagraph(
        _ paraVerses: [BibleVerse],
        colors: ThemeColors,
        suppressFirstVerseNumber: Bool = false
    ) -> AttributedString {
        var combined = AttributedString("")
        let bodyFont = ThemeFont.bodyDefault(theme, textSize)
        let verseFont = ThemeFont.verseNumber(theme, textSize)
        let verseBaseline = ThemeFont.verseNumberBaselineOffset(textSize)
        let nbsp = "\u{00A0}"

        for (idx, verse) in paraVerses.enumerated() {
            let spacer = verse.v == paraVerses.last?.v ? "" : "  "
            let isFirstAndSuppressed = suppressFirstVerseNumber && idx == 0

            if !isFirstAndSuppressed {
                let token = "\(verse.v)"
                var numChunk = AttributedString(token)
                numChunk.font = verseFont
                numChunk.foregroundColor = colors.accent
                combined.append(numChunk)
                let numChars = token.count
                let startIndex = combined.index(combined.endIndex, offsetByCharacters: -numChars)
                combined[startIndex..<combined.endIndex].baselineOffset = verseBaseline
                appendNonBreakingGlue(&combined, nbsp, bodyFont: bodyFont, foreground: colors.textPrimary)
            }

            appendVerseTextWithLeadingWordTie(
                &combined,
                prose: verse.t,
                bodyFont: bodyFont,
                foreground: colors.textPrimary,
                nbsp: nbsp
            )

            if !spacer.isEmpty {
                var between = AttributedString(spacer)
                between.font = bodyFont
                between.foregroundColor = colors.textPrimary
                combined.append(between)
            }
        }
        return combined
    }

    /// UIKit-flavored attributed string for the drop-cap paragraph. Uses `UIFont` and `UIColor` directly so `UITextView`/TextKit honors the active theme face and the line metrics we use to size the cap exclusion rect. SwiftUI's `Font` does not bridge reliably to `NSAttributedString` (UITextView falls back to a default font), which is why this path is duplicated rather than shared with `attributedVerseParagraph`.
    private func uiKitVerseParagraph(
        _ paraVerses: [BibleVerse],
        colors: ThemeColors,
        suppressFirstVerseNumber: Bool,
        spacing: AppSpacing
    ) -> NSAttributedString {
        let combined = NSMutableAttributedString()
        let bodyFont = ThemeFont.bodyDefaultUIFont(theme, textSize)
        let verseFont = ThemeFont.verseNumberUIFont(theme, textSize)
        let verseBaseline = ThemeFont.verseNumberBaselineOffset(textSize)
        let textColor = UIColor(colors.textPrimary)
        let accentColor = UIColor(colors.accent)
        let nbsp = "\u{00A0}"

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: textColor
        ]
        let verseAttrs: [NSAttributedString.Key: Any] = [
            .font: verseFont,
            .foregroundColor: accentColor,
            .baselineOffset: verseBaseline
        ]

        func appendBody(_ s: String) {
            guard !s.isEmpty else { return }
            combined.append(NSAttributedString(string: s, attributes: bodyAttrs))
        }

        for (idx, verse) in paraVerses.enumerated() {
            let isFirstAndSuppressed = suppressFirstVerseNumber && idx == 0
            let spacer = verse.v == paraVerses.last?.v ? "" : "  "

            if !isFirstAndSuppressed {
                combined.append(NSAttributedString(string: "\(verse.v)", attributes: verseAttrs))
                appendBody(nbsp)
            }

            let trimmed = verse.t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
                let w1 = parts[0]
                let w2 = parts.count > 1 ? parts[1] : ""
                let tail: String = parts.count > 2 ? " " + parts[2] : ""

                appendBody(w1)
                if !w2.isEmpty {
                    appendBody(nbsp)
                    appendBody(w2)
                }
                appendBody(tail)
            }

            appendBody(spacer)
        }

        // Apply paragraph style after content is built so the whole range receives lineSpacing (no firstLineHeadIndent — the cap takes that role).
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = 0
        ps.headIndent = 0
        ps.lineSpacing = spacing.bodyLineSpacing
        if combined.length > 0 {
            combined.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: combined.length))
        }
        return combined
    }

    private func appendNonBreakingGlue(_ combined: inout AttributedString, _ nbsp: String, bodyFont: Font, foreground: Color) {
        var glue = AttributedString(nbsp)
        glue.font = bodyFont
        glue.foregroundColor = foreground
        combined.append(glue)
    }

    /// First two words separated by NBSP from each other and from the preceding verse number; remainder uses normal breaks.
    private func appendVerseTextWithLeadingWordTie(
        _ combined: inout AttributedString,
        prose: String,
        bodyFont: Font,
        foreground: Color,
        nbsp: String
    ) {
        let trimmed = prose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        let w1 = parts[0]
        let w2 = parts.count > 1 ? parts[1] : ""
        let tail: String = parts.count > 2 ? " " + parts[2] : ""

        func appendPlain(_ chunk: String) {
            guard !chunk.isEmpty else { return }
            var a = AttributedString(chunk)
            a.font = bodyFont
            a.foregroundColor = foreground
            combined.append(a)
        }

        appendPlain(w1)
        if !w2.isEmpty {
            appendNonBreakingGlue(&combined, nbsp, bodyFont: bodyFont, foreground: foreground)
            appendPlain(w2)
        }
        appendPlain(tail)
    }
}

// MARK: - Scroll offset preference key

private struct ChapterScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - DropCapParagraphView
//
// Renders the chapter's first prose paragraph with a 2-line drop cap. The cap
// glyph is a `UILabel` overlaid on the upper-left of the host view; the
// embedded non-scrolling `UITextView` carves out a rect of height = 2 lines
// via `textContainer.exclusionPaths` so the prose wraps to the right of the
// cap for the first 2 lines, then falls back to the left margin underneath.

private struct DropCapParagraphView: UIViewRepresentable {

    let dropCapText: String
    let body: NSAttributedString
    let theme: AppTheme
    let textSize: AppTextSize
    let spacing: AppSpacing
    let accent: Color

    func makeUIView(context: Context) -> DropCapHostView {
        let host = DropCapHostView()
        host.backgroundColor = .clear
        configure(host: host)
        return host
    }

    func updateUIView(_ uiView: DropCapHostView, context: Context) {
        configure(host: uiView)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DropCapHostView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        return uiView.preferredSize(forWidth: width)
    }

    private func configure(host: DropCapHostView) {
        let bodyFont = ThemeFont.bodyDefaultUIFont(theme, textSize)
        let lineHeight = textSize.chapterBodyLineHeight(theme: theme, spacing: spacing)

        // Pick the cap font size from body metrics so the glyph's cap-top
        // aligns with body line-1 cap-top AND the baseline aligns with line-2
        // baseline simultaneously. Both constraints reduce to:
        //   capFont.capHeight == bodyFont.capHeight + lineHeight
        // We sample the title face once at a reference size to recover its
        // cap-height-per-point ratio, then scale.
        let desiredCapHeight = bodyFont.capHeight + lineHeight
        let probe = ThemeFont.chapterDropCapUIFont(pointSize: 100)
        let capHeightPerPoint = probe.capHeight > 0 ? probe.capHeight / 100 : 0.7
        let capPointSize = desiredCapHeight / capHeightPerPoint
        let capFont = ThemeFont.chapterDropCapUIFont(pointSize: capPointSize)

        host.apply(
            dropCapText: dropCapText,
            dropCapFont: capFont,
            dropCapColor: UIColor(accent),
            body: body,
            bodyFont: bodyFont,
            lineHeight: lineHeight
        )
    }
}

private final class DropCapHostView: UIView {

    private let textView: UITextView = {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.isEditable = false
        tv.isSelectable = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = false
        return tv
    }()

    private let capLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.backgroundColor = .clear
        label.adjustsFontForContentSizeCategory = false
        return label
    }()

    private var bodyFont: UIFont = .systemFont(ofSize: 17)
    private var lineHeight: CGFloat = 24
    private var dropCapWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(textView)
        addSubview(capLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(
        dropCapText: String,
        dropCapFont: UIFont,
        dropCapColor: UIColor,
        body: NSAttributedString,
        bodyFont: UIFont,
        lineHeight: CGFloat
    ) {
        self.bodyFont = bodyFont
        self.lineHeight = lineHeight

        capLabel.text = dropCapText
        capLabel.font = dropCapFont
        capLabel.textColor = dropCapColor
        capLabel.sizeToFit()

        textView.attributedText = body

        let gap = max(4, bodyFont.pointSize * 0.25)
        dropCapWidth = ceil(capLabel.bounds.width + gap)

        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Glue between body line metrics and label metrics:
        //   bodyInternalTopOffset = how far the body's ascender sits above its capHeight.
        //   capInternalTopOffset  = same for the drop-cap font, where ascender > capHeight is typical.
        //
        // We want the cap glyph's cap-top to sit at body line-1 cap-top in view-space.
        // If we just placed labelOriginY = bodyLine1CapTopY - capInternalTopOffset, the
        // resulting value would often be negative (the label's frame extends above the
        // host view because the cap's full ascender region is taller than the small body
        // ascender region). Instead we shift the body text down by a matching `topInset`
        // so labelOriginY stays >= 0 and both cap-top + line-2 baseline alignments hold.
        let capFont = capLabel.font ?? bodyFont
        let bodyInternalTopOffset = max(0, bodyFont.ascender - bodyFont.capHeight)
        let capInternalTopOffset = max(0, capFont.ascender - capFont.capHeight)
        let topInset = max(0, capInternalTopOffset - bodyInternalTopOffset)

        textView.textContainerInset = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)

        let exclusionRect = CGRect(x: 0, y: 0, width: dropCapWidth, height: 2 * lineHeight)
        textView.textContainer.exclusionPaths = [UIBezierPath(rect: exclusionRect)]
        textView.frame = bounds

        // labelOriginY + capInternalTopOffset == topInset + bodyInternalTopOffset
        //   (so the cap glyph cap-top lands on body line-1 cap-top). Combined with
        // capFont.capHeight == bodyFont.capHeight + lineHeight (set in `configure`),
        // this also makes the cap baseline land exactly on body line-2 baseline.
        let labelOriginY = topInset + bodyInternalTopOffset - capInternalTopOffset
        capLabel.frame = CGRect(
            x: 0,
            y: floor(labelOriginY),
            width: capLabel.bounds.width,
            height: capLabel.bounds.height
        )
    }

    override var intrinsicContentSize: CGSize {
        preferredSize(forWidth: bounds.width > 0 ? bounds.width : UIView.noIntrinsicMetric)
    }

    func preferredSize(forWidth width: CGFloat) -> CGSize {
        guard width > 0 && width != UIView.noIntrinsicMetric else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        let capFont = capLabel.font ?? bodyFont
        let bodyInternalTopOffset = max(0, bodyFont.ascender - bodyFont.capHeight)
        let capInternalTopOffset = max(0, capFont.ascender - capFont.capHeight)
        let topInset = max(0, capInternalTopOffset - bodyInternalTopOffset)

        textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        textView.textContainer.exclusionPaths = [UIBezierPath(rect: CGRect(x: 0, y: 0, width: dropCapWidth, height: 2 * lineHeight))]
        textView.textContainerInset = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        let fit = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let minHeight = 2 * lineHeight + topInset
        return CGSize(width: width, height: ceil(max(fit.height, minHeight)))
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
