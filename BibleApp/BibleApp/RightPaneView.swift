//  RightPaneView.swift
//  BibleApp
//
//  Created by Yohanes Sitanggang on 08/04/26.
//

import SwiftUI

// MARK: - Data

private struct DateEntry: Identifiable {
    let date: Date
    let label: String
    var id: Date { date }
}

// MARK: - RightPaneView

struct RightPaneView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    private var dates: [DateEntry] {
        DailyPaneCalendar.dayRangeEntries().map { DateEntry(date: $0.date, label: $0.label) }
    }

    private var todayStr: String { DailyPaneCalendar.todayFormattedLabel }
    let selection: LeftSelection
    @Binding var selectedLabel: String?
    let isActive: Bool
    let topSafeArea: CGFloat

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        VStack(alignment: .trailing, spacing: 0) {
            Spacer()
                .frame(height: topSafeArea)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .trailing, spacing: 0) {
                        switch selection {
                        case .daily:
                            ForEach(dates) { entry in
                                PaneRowView(
                                    label: entry.label,
                                    isSelected: labelsMatch(selectedLabel, entry.label),
                                    alignment: .trailing
                                )
                                .id(entry.label)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedLabel = entry.label }
                            }
                        case .book(let book):
                            ForEach(chapterItems(for: book), id: \.self) { item in
                                PaneRowView(
                                    label: item,
                                    isSelected: labelsMatch(selectedLabel, item),
                                    alignment: .trailing
                                )
                                .id(item)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedLabel = item }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .onAppear {
                    ensureDefaultSelection()
                    scrollToSelection(using: proxy)
                }
                .onChange(of: isActive) { _, newValue in
                    guard newValue else { return }
                    ensureDefaultSelection()
                    scrollToSelection(using: proxy)
                }
            }
        }
        .background(colors.surface)
        // Vertical border on left edge
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(colors.border)
                .frame(width: 1)
        }
    }

    private func scrollToSelection(using proxy: ScrollViewProxy) {
        let target: String? = {
            if let selectedLabel { return selectedLabel }
            switch selection {
            case .daily:
                return todayStr
            case .book(let book):
                return chapterItems(for: book).first
            }
        }()

        guard let target else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    private func ensureDefaultSelection() {
        let validLabels: [String] = {
            switch selection {
            case .daily:
                return DailyPaneCalendar.dayRangeEntries().map(\.label)
            case .book(let book):
                return chapterItems(for: book)
            }
        }()

        if let selectedLabel, validLabels.contains(where: { labelsMatch(selectedLabel, $0) }) {
            return
        }

        switch selection {
        case .daily:
            selectedLabel = todayStr
        case .book(let book):
            selectedLabel = chapterItems(for: book).first
        }
    }
}

private func chapterItems(for book: String) -> [String] {
    let count = BibleCatalog.entry(forName: book)?.chapterCount ?? 30
    return (1...count).map { "\($0)" }
}

private func labelsMatch(_ selected: String?, _ row: String) -> Bool {
    guard let selected else { return false }
    return selected.trimmingCharacters(in: .whitespacesAndNewlines)
        == row.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - PaneRowView

private struct PaneRowView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    let label: String
    let isSelected: Bool
    let alignment: Alignment

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        Text(label)
            .font(isSelected ? ThemeFont.buttonLarge : ThemeFont.buttonLargeRegular)
            .foregroundStyle(isSelected ? colors.textPrimary : colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .padding(.leading, 4)
            .padding(.trailing, 24)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selection: LeftSelection = .daily
    @Previewable @State var selectedLabel: String? = Date().formatted(.dateTime.day().month(.wide))
    RightPaneView(selection: selection, selectedLabel: $selectedLabel, isActive: true, topSafeArea: 59)
        .environment(\.appTheme, .purba)
        .environment(\.appMode, .day)
}
