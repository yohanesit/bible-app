//  DailyMassView.swift
//  BibleApp
//
//  Created by Yohanes Sitanggang on 08/04/26.
//

import SwiftUI

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - DailyMassView

struct DailyMassView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.appTextSize) private var textSize
    @Environment(DailyReadingProvider.self) private var provider

    @Binding var isReadingState: Bool
    @Binding var isListenState: Bool
    var topContentInset: CGFloat
    var onTap: () -> Void = {}

    @State private var lastScrollOffset: CGFloat = 0
    @State private var syncCoordinator = SyncEngineCoordinator()

    init(
        isReadingState: Binding<Bool>,
        isListenState: Binding<Bool>,
        topContentInset: CGFloat,
        onTap: @escaping () -> Void = {}
    ) {
        _isReadingState = isReadingState
        _isListenState = isListenState
        self.topContentInset = topContentInset
        self.onTap = onTap
    }

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        let massDay = provider.state.massDay

        GeometryReader { scrollGeo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: topContentInset)

                    switch provider.state {
                    case .loading:
                        LoadingView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)

                    case .error(let message):
                        ErrorBannerView(message: message)
                            .padding(.horizontal, 24)
                            .padding(.top, 40)

                    default:
                        if let day = massDay {
                            // ── Celebration header ───────────────────────────
                            VStack(spacing: 32) {
                                Spacer(minLength: 0)
                                Text(day.celebrationName)
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
                            .frame(minHeight: scrollGeo.size.height * 0.44)
                            .padding(.horizontal, 24)

                            // ── Sync needed banner (overlay, non-blocking) ───
                            if case .needsSync = provider.state {
                                SyncNeededBannerView()
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 24)
                            }

                            // ── Offline indicator ────────────────────────────
                            if case .offline = provider.state {
                                OfflineBannerView()
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 24)
                            }

                            // ── Readings ─────────────────────────────────────
                            ForEach(Array(day.readings.enumerated()), id: \.element.id) { index, reading in
                                let lagumisaRefrain: String? = {
                                    guard reading.type == .psalm,
                                          let slug = LagumisaSlugDeriver.slug(
                                              for: day.celebrationName, on: day.date)
                                    else { return nil }
                                    return LagumisaRefrainStore.shared.refrain(for: slug)
                                }()

                                if isListenState && !reading.verses.isEmpty {
                                    // Sync-mode: verse-by-verse highlighting
                                    VStack(alignment: .leading, spacing: 0) {
                                        ReadingHeaderView(reading: reading)
                                            .padding(.horizontal, 24)
                                            .padding(.top, 32)
                                            .padding(.bottom, 12)
                                        VerseListView(
                                            reading: reading,
                                            readingIndex: index,
                                            coordinator: syncCoordinator
                                        )
                                        .padding(.bottom, 8)
                                        ReadingFooterView(reading: reading)
                                            .padding(.horizontal, 24)
                                            .padding(.bottom, 32)
                                    }
                                } else {
                                    // Standard mode: full body text
                                    ReadingView(reading: reading, lagumisaRefrain: lagumisaRefrain)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 32)
                                }

                                if reading.id != day.readings.last?.id {
                                    Divider()
                                        .overlay(colors.border)
                                        .padding(.horizontal, 24)
                                }
                            }
                        }
                    }

                    Spacer().frame(height: 100)
                }
                .frame(maxWidth: .infinity, minHeight: scrollGeo.size.height, alignment: .topLeading)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: -geo.frame(in: .named("massScroll")).minY
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "massScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            updateReadingState(scrollOffset: offset)
        }
        .simultaneousGesture(TapGesture().onEnded { onTap() })
        .background(colors.background)
        .scrollContentBackground(.hidden)
        .onChange(of: isListenState) { _, listening in
            if listening {
                Task { await syncCoordinator.beginMass(readings: massDay?.readings ?? []) }
            } else {
                syncCoordinator.endMass()
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

// MARK: - State banners

private struct LoadingView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        VStack(spacing: 16) {
            ProgressView()
                .tint(colors.accent)
            Text("Memuat bacaan…")
                .font(.system(size: 14))
                .foregroundStyle(colors.textSecondary)
        }
    }
}

private struct SyncNeededBannerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundStyle(colors.accent)
            Text("Sinkronkan Alkitab untuk membaca teks lengkap. Buka Pengaturan › Admin.")
                .font(.system(size: 13))
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

private struct OfflineBannerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14))
                .foregroundStyle(colors.textSecondary)
            Text("Menampilkan bacaan tersimpan. Sambungkan internet untuk memperbarui.")
                .font(.system(size: 13))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(colors.border, lineWidth: 1)
        )
    }
}

private struct ErrorBannerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    let message: String

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(.red.opacity(0.8))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.red.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - ReadingView

struct ReadingView: View {
    @Environment(\.appTheme)    private var theme
    @Environment(\.appMode)     private var mode
    @Environment(\.appTextSize) private var textSize
    @Environment(\.appSpacing)  private var spacing

    let reading: MassReading
    var lagumisaRefrain: String? = nil

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.type.rawValue)
                    .font(ThemeFont.chapterSectionHeading(theme, textSize))
                    .foregroundStyle(colors.textPrimary)

                Text(reading.reference)
                    .font(ThemeFont.bodyDefaultItalic(theme, textSize))
                    .foregroundStyle(colors.textSecondary)
            }

            if let refrain = lagumisaRefrain {
                Text("Ulangan: \"\(refrain)\"")
                    .font(ThemeFont.bodyDefaultItalic(theme, textSize))
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(reading.bodyText)
                .font(ThemeFont.bodyDefault(theme, textSize))
                .lineSpacing(spacing.bodyLineSpacing)
                .foregroundStyle(colors.textPrimary)

        }
    }
}

// MARK: - Reading Header (sync mode)

/// Shows reading type, reference, and intro rubric — displayed above VerseListView in Mass mode.
struct ReadingHeaderView: View {
    @Environment(\.appTheme)    private var theme
    @Environment(\.appMode)     private var mode
    @Environment(\.appTextSize) private var textSize

    let reading: MassReading

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        VStack(alignment: .leading, spacing: 4) {
            Text(reading.type.rawValue)
                .font(ThemeFont.chapterSectionHeading(theme, textSize))
                .foregroundStyle(colors.textPrimary)

            Text(reading.reference)
                .font(ThemeFont.bodyDefaultItalic(theme, textSize))
                .foregroundStyle(colors.textSecondary)

            if !reading.introRubric.isEmpty {
                Text(reading.introRubric)
                    .font(ThemeFont.bodyDefaultItalic(theme, textSize))
                    .foregroundStyle(SemanticColors.Liturgical.rubric(mode: mode))
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Reading Footer (sync mode)

/// Shows response rubric and congregation response — displayed below VerseListView in Mass mode.
struct ReadingFooterView: View {
    @Environment(\.appTheme)    private var theme
    @Environment(\.appMode)     private var mode
    @Environment(\.appTextSize) private var textSize

    let reading: MassReading

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        VStack(alignment: .leading, spacing: 6) {
            if let rubric = reading.responseRubric {
                Text(rubric)
                    .font(ThemeFont.bodyDefaultItalic(theme, textSize))
                    .foregroundStyle(SemanticColors.Liturgical.rubric(mode: mode))
            }
            if let response = reading.congregationResponse {
                Text(response)
                    .font(ThemeFont.bodyDefault(theme, textSize))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
