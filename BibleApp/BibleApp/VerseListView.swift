//  VerseListView.swift
//  BibleApp
//
//  Displays a reading's verses with live sync highlighting, one clause/line at a time.
//  Observes SyncEngineCoordinator for current (verseIndex, lineIndex) and scrolls automatically.

import SwiftUI

// MARK: - Highlight state

enum VerseHighlightState {
    case current
    case previous
    case upcoming
    case normal
}

extension VerseHighlightState: Equatable {}

// MARK: - VerseListView

struct VerseListView: View {

    let reading: MassReading
    let readingIndex: Int

    @Environment(\.appTheme)    private var theme
    @Environment(\.appMode)     private var mode
    @Environment(\.appTextSize) private var textSize
    @Environment(\.appSpacing)  private var spacing

    @State private var coordinator: SyncEngineCoordinator

    init(reading: MassReading, readingIndex: Int, coordinator: SyncEngineCoordinator) {
        self.reading = reading
        self.readingIndex = readingIndex
        self._coordinator = State(wrappedValue: coordinator)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(reading.verses.enumerated()), id: \.element.id) { verseIdx, verse in
                        ForEach(Array(verse.lines.enumerated()), id: \.element.id) { lineIdx, line in
                            LineRow(
                                line: line,
                                verseNumber: lineIdx == 0 ? verse.number : nil,
                                highlightState: highlightState(verseIndex: verseIdx, lineIndex: lineIdx),
                                theme: theme,
                                mode: mode,
                                textSize: textSize,
                                spacing: spacing,
                                onLongPress: {
                                    coordinator.manualOverride(
                                        readingIndex: readingIndex,
                                        verseIndex: verseIdx,
                                        lineIndex: lineIdx
                                    )
                                }
                            )
                            .id(line.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: coordinator.currentLineIndex) { _, _ in scrollToCurrent(proxy: proxy) }
            .onChange(of: coordinator.currentVerseIndex) { _, _ in scrollToCurrent(proxy: proxy) }
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy) {
        guard coordinator.currentReadingIndex == readingIndex,
              let verse = reading.verses[safe: coordinator.currentVerseIndex],
              let line = verse.lines[safe: coordinator.currentLineIndex] else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            proxy.scrollTo(line.id, anchor: .center)
        }
    }

    private func highlightState(verseIndex: Int, lineIndex: Int) -> VerseHighlightState {
        guard coordinator.currentReadingIndex == readingIndex else { return .normal }
        let curVerse = coordinator.currentVerseIndex
        let curLine  = coordinator.currentLineIndex

        if verseIndex == curVerse && lineIndex == curLine { return .current }

        // Determine flat position relative to current for previous/upcoming
        let flatPos = flatIndex(verseIndex: verseIndex, lineIndex: lineIndex)
        let curFlat = flatIndex(verseIndex: curVerse, lineIndex: curLine)
        if flatPos == curFlat - 1 { return .previous }
        if flatPos == curFlat + 1 { return .upcoming }
        return .normal
    }

    /// Flat index across all lines in the reading for relative positioning.
    private func flatIndex(verseIndex: Int, lineIndex: Int) -> Int {
        var flat = 0
        for i in 0..<verseIndex {
            flat += reading.verses[safe: i]?.lines.count ?? 0
        }
        return flat + lineIndex
    }
}

// MARK: - LineRow

private struct LineRow: View {

    let line: LineSegment
    let verseNumber: Int?
    let highlightState: VerseHighlightState
    let theme: AppTheme
    let mode: AppMode
    let textSize: AppTextSize
    let spacing: AppSpacing
    let onLongPress: () -> Void

    private var colors: ThemeColors { Colors.theme(theme, mode: mode) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Verse number — only on first line of each verse
            Group {
                if let num = verseNumber {
                    Text("\(num)")
                        .font(ThemeFont.verseNumber(theme, textSize))
                        .baselineOffset(ThemeFont.verseNumberBaselineOffset(textSize))
                        .foregroundStyle(colors.accent.opacity(numberOpacity))
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 24, alignment: .trailing)
            .padding(.top, 1)

            // Line text
            Text(line.text)
                .font(ThemeFont.bodyDefault(theme, textSize))
                .fontWeight(fontWeight)
                .foregroundStyle(textColor)
                .lineSpacing(spacing.bodyLineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, 12)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        }
        .animation(.easeOut(duration: 0.4), value: highlightState == .current)
    }

    private var fontWeight: Font.Weight {
        highlightState == .current ? .semibold : .regular
    }

    private var textColor: Color {
        switch highlightState {
        case .current:  return colors.textPrimary
        case .previous: return colors.textPrimary.opacity(0.5)
        case .upcoming: return colors.textSecondary
        case .normal:   return colors.textPrimary
        }
    }

    private var background: Color {
        highlightState == .current
            ? SemanticColors.Liturgical.highlight(mode: mode)
            : .clear
    }

    private var numberOpacity: Double {
        switch highlightState {
        case .current:  return 1.0
        case .previous: return 0.4
        case .upcoming: return 0.5
        case .normal:   return 0.7
        }
    }

    private var verticalPadding: CGFloat {
        highlightState == .current ? 10 : 6
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
