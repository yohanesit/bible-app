//  LeftPaneView.swift
//  BibleApp
//
//  Navigation sidebar: "Hari ini" + all 73 Catholic Bible books.
//  Both expand inline via accordions; right pane removed.

import SwiftUI

private enum ExpandedItem: Equatable {
    case daily
    case book(String)
}

struct LeftPaneView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.appTextSize) private var textSize

    @Binding var selection: LeftSelection
    @Binding var selectedLabel: String?

    var topSafeArea: CGFloat
    var bottomSafeArea: CGFloat
    var onOpenAppSettings: () -> Void
    var onClose: () -> Void = {}

    @State private var expanded: ExpandedItem? = nil

    private var dailyRowSubtitle: String {
        switch selection {
        case .daily:
            return DailyPaneCalendar.longDisplayDate(forLabel: selectedLabel)
        case .book:
            return DailyPaneCalendar.longDisplayDate(forLabel: DailyPaneCalendar.todayFormattedLabel)
        }
    }

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    Image(ThemeAssetIcon.sidebarLogo)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .accessibilityLabel("Lectio")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 32)
                .padding(.top, topSafeArea + 12)
                .padding(.bottom, 22)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        BookRowView(
                            title: "Lectionary",
                            subtitle: dailyRowSubtitle,
                            isSelected: selection == .daily
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                expanded = (expanded == .daily) ? nil : .daily
                            }
                        }

                        if expanded == .daily {
                            DailyDateGridView(
                                selectedLabel: selectedLabel,
                                onSelectLabel: { label in
                                    selectedLabel = label
                                    selection = .daily
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                        expanded = nil
                                    }
                                    onClose()
                                }
                            )
                            .transition(.opacity)
                        }

                        ForEach(BibleCatalog.books) { book in
                            BookRowView(
                                title: book.name,
                                subtitle: "\(book.chapterCount) Chapters",
                                isSelected: selection == .book(book.name)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    expanded = (expanded == .book(book.name)) ? nil : .book(book.name)
                                }
                            }

                            if expanded == .book(book.name) {
                                ChapterGridView(
                                    book: book,
                                    selectedLabel: selectedLabel,
                                    isBookActive: selection == .book(book.name)
                                ) { chapterStr in
                                    selectedLabel = chapterStr
                                    selection = .book(book.name)
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                        expanded = nil
                                    }
                                    onClose()
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    .padding(.bottom, 96)
                }
            }

            FloatingSettingsButton(colors: colors, action: onOpenAppSettings)
                .padding(.trailing, 20)
                .padding(.bottom, bottomSafeArea + 12)
                .accessibilityLabel("App settings")
        }
        .background(colors.surface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(colors.border.opacity(0.85))
                .frame(width: 1)
        }
    }
}

private struct BookRowView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.appTextSize) private var textSize

    let title: String
    let subtitle: String?
    let isSelected: Bool

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ThemeFont.sidebarRowPrimary(theme, textSize))
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(colors.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(ThemeFont.sidebarRowSubtitle(theme, textSize))
                    .foregroundStyle(colors.textSecondary.opacity(0.88))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .padding(.leading, 32)
        .padding(.trailing, 20)
    }
}

private struct DailyDateGridView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.appTextSize) private var textSize

    let selectedLabel: String?
    let onSelectLabel: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        let selectedTint = SemanticColors.Liturgical.rubric(mode: mode)

        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DailyPaneCalendar.dayRangeEntries(), id: \.label) { entry in
                let isSelected = selectedLabel == entry.label
                let dayNum = Calendar.current.component(.day, from: entry.date)

                Button { onSelectLabel(entry.label) } label: {
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(selectedTint)
                                .frame(width: 34, height: 34)
                        }

                        Text("\(dayNum)")
                            .font(ThemeFont.sidebarGridCell(theme, textSize))
                            .foregroundStyle(isSelected ? Color.white : colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.background.opacity(mode == .day ? 0.55 : 0.4))
        )
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }
}

private struct ChapterGridView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.appTextSize) private var textSize

    let book: BibleBookEntry
    let selectedLabel: String?
    let isBookActive: Bool
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        let selectedTint = SemanticColors.Liturgical.rubric(mode: mode)

        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(1...book.chapterCount, id: \.self) { ch in
                let label = "\(ch)"
                let isSelected = isBookActive && selectedLabel == label

                Button { onSelect(label) } label: {
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(selectedTint)
                                .frame(width: 34, height: 34)
                        }

                        Text(label)
                            .font(ThemeFont.sidebarChapterGridCell(theme, textSize))
                            .foregroundStyle(isSelected ? Color.white : colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.background.opacity(mode == .day ? 0.55 : 0.4))
        )
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - AccordionRevealer
//
// Animates the container's height between 0 and the natural height of its
// content. The inner content is always rendered at its intrinsic vertical
// size (via fixedSize), measured with a GeometryReader, and clipped by the
// outer frame. When isExpanded toggles inside withAnimation, SwiftUI
// interpolates the frame's height, giving a smooth "curtain" reveal.

private struct AccordionRevealer<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        // Match the "outer animates, inner measures" pattern:
        // - The *inner* content is rendered at natural height and measured.
        // - The *outer* container animates/clips its height.
        ZStack(alignment: .top) {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .allowsHitTesting(false)
                            .preference(key: AccordionHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .frame(height: isExpanded ? measuredHeight : 0, alignment: .top)
        .clipped()
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .onPreferenceChange(AccordionHeightKey.self) { newValue in
            if newValue > 0 { measuredHeight = newValue }
        }
    }
}

private struct AccordionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FloatingSettingsButton: View {
    let colors: ThemeColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(colors.textPrimary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(colors.background))
                .overlay(
                    Circle()
                        .strokeBorder(colors.border.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var selection: LeftSelection = .daily
    @Previewable @State var selectedLabel: String? = nil
    LeftPaneView(
        selection: $selection,
        selectedLabel: $selectedLabel,
        topSafeArea: 59,
        bottomSafeArea: 34,
        onOpenAppSettings: {}
    )
    .environment(\.appTheme, .purba)
    .environment(\.appMode, .day)
    .environment(\.appTextSize, .pt20)
}
