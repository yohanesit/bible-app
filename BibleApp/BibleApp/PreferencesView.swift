//  PreferencesView.swift
//  BibleApp

import SwiftUI

// MARK: - Layout constants

private enum PrefLayout {
    static let horizontalInset: CGFloat = 20
    static let headerTop: CGFloat       = 8
    static let headerBottom: CGFloat    = 8
    static let sectionSpacing: CGFloat  = 0   // dividers provide visual separation
    static let rowVerticalPad: CGFloat  = 16
    static let controlCorner: CGFloat   = 10
    static let controlHeight: CGFloat   = 40
    static let stopDotSize: CGFloat     = 5
    static let stopDotSpacing: CGFloat  = 7
    static let stepperButtonWidth: CGFloat = 56
    static let stepperSpacing: CGFloat     = 8
    static let stepperGroupWidth: CGFloat  = 120   // 56 + 8 + 56
}

// MARK: - AppColorScheme cycle helpers (UI-only)

extension AppColorScheme {
    var next: AppColorScheme {
        switch self {
        case .system: return .dark
        case .dark:   return .light
        case .light:  return .system
        }
    }

    var cycleLabel: String {
        switch self {
        case .system: return "System"
        case .dark:   return "Dark"
        case .light:  return "Light"
        }
    }

    var cycleIcon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark:   return "moon.fill"
        case .light:  return "sun.max.fill"
        }
    }
}

// MARK: - PreferencesView

struct PreferencesView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var appMode

    @Binding var colorSchemePreference: AppColorScheme
    @Binding var currentTheme: AppTheme
    @Binding var textSize: AppTextSize
    @Binding var spacing: AppSpacing

    var onClose: () -> Void = {}

    @State private var showTextSizeStops = false
    @State private var showSpacingStops = false
    @State private var textSizeHideWorkItem: DispatchWorkItem?
    @State private var spacingHideWorkItem: DispatchWorkItem?

    var body: some View {
        let colors = Colors.theme(theme, mode: appMode)

        VStack(alignment: .leading, spacing: 0) {

            // ── Grab bar ─────────────────────────────────────────────────
            RoundedRectangle(cornerRadius: 2.5)
                .fill(colors.border)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 8)

            // ── Theme section ────────────────────────────────────────────
            HStack(alignment: .center) {
                Text("Theme")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Button {
                    colorSchemePreference = colorSchemePreference.next
                } label: {
                    HStack(spacing: 6) {
                        Text(colorSchemePreference.cycleLabel)
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: colorSchemePreference.cycleIcon)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(colors.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: PrefLayout.controlHeight)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: PrefLayout.controlCorner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PrefLayout.controlCorner, style: .continuous)
                            .strokeBorder(colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, PrefLayout.horizontalInset)
            .padding(.vertical, PrefLayout.rowVerticalPad)

            // Row 2: theme-type buttons
            HStack(spacing: 8) {
                ForEach(AppTheme.allCases.filter { $0 != .system }, id: \.self) { t in
                    ThemeTypeButton(appTheme: t, isSelected: currentTheme == t) {
                        currentTheme = t
                    }
                }
            }
            .padding(.horizontal, PrefLayout.horizontalInset)
            .padding(.bottom, PrefLayout.rowVerticalPad)

            Divider().overlay(colors.border)

            // ── Font Size section ─────────────────────────────────────────
            HStack(alignment: .center) {
                Text("Font Size")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    StepperButton(enabled: textSize.previous != nil) {
                        if let prev = textSize.previous { textSize = prev }
                        revealTextSizeStops()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("A")
                            .font(.system(size: 14, weight: .medium))
                    }
                    StepperButton(enabled: textSize.next != nil) {
                        if let next = textSize.next { textSize = next }
                        revealTextSizeStops()
                    } label: {
                        Text("A")
                            .font(.system(size: 18, weight: .medium))
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
            .padding(.horizontal, PrefLayout.horizontalInset)
            .padding(.vertical, PrefLayout.rowVerticalPad)

            HStack {
                Spacer()
                ValueStopsIndicator(
                    count: AppTextSize.allCases.count,
                    selectedIndex: AppTextSize.allCases.firstIndex(of: textSize) ?? 0
                )
                .frame(width: PrefLayout.stepperGroupWidth)
                .padding(.trailing, PrefLayout.horizontalInset)
            }
            .opacity(showTextSizeStops ? 1 : 0)
            .padding(.bottom, PrefLayout.rowVerticalPad)
            .animation(.easeInOut(duration: 0.2), value: showTextSizeStops)

            // ── Spacing section ───────────────────────────────────────────
            HStack(alignment: .center) {
                Text("Spacing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    StepperButton(enabled: spacing.previous != nil) {
                        if let prev = spacing.previous { spacing = prev }
                        revealSpacingStops()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .medium))
                    }
                    StepperButton(enabled: spacing.next != nil) {
                        if let next = spacing.next { spacing = next }
                        revealSpacingStops()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
            .padding(.horizontal, PrefLayout.horizontalInset)
            .padding(.vertical, PrefLayout.rowVerticalPad)

            HStack {
                Spacer()
                ValueStopsIndicator(
                    count: AppSpacing.allCases.count,
                    selectedIndex: AppSpacing.allCases.firstIndex(of: spacing) ?? 0
                )
                .frame(width: PrefLayout.stepperGroupWidth)
                .padding(.trailing, PrefLayout.horizontalInset)
            }
            .opacity(showSpacingStops ? 1 : 0)
            .padding(.bottom, PrefLayout.rowVerticalPad)
            .animation(.easeInOut(duration: 0.2), value: showSpacingStops)

            Divider().overlay(colors.border)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colors.border)
                .frame(height: 1)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 60 {
                        onClose()
                    }
                }
        )
        .onDisappear {
            textSizeHideWorkItem?.cancel()
            spacingHideWorkItem?.cancel()
        }
    }

    private func revealTextSizeStops() {
        textSizeHideWorkItem?.cancel()
        withAnimation(.easeIn(duration: 0.15)) {
            showTextSizeStops = true
        }

        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) {
                showTextSizeStops = false
            }
        }
        textSizeHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private func revealSpacingStops() {
        spacingHideWorkItem?.cancel()
        withAnimation(.easeIn(duration: 0.15)) {
            showSpacingStops = true
        }

        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) {
                showSpacingStops = false
            }
        }
        spacingHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }
}

// MARK: - Theme type button

private struct ThemeTypeButton: View {
    @Environment(\.appTheme) private var uiTheme
    @Environment(\.appMode)  private var appMode

    let appTheme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let ui   = Colors.theme(uiTheme, mode: appMode)
        let card = Colors.theme(appTheme, mode: appMode)

        Button(action: action) {
            VStack(spacing: 4) {
                Text(appTheme.displayName)
                    .font(ThemeFont.bodyDefault(appTheme, .pt16))
                    .foregroundStyle(card.textPrimary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: PrefLayout.controlCorner, style: .continuous)
                    .fill(card.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PrefLayout.controlCorner, style: .continuous)
                    .strokeBorder(
                        isSelected ? ui.accent : ui.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stepper button

private struct StepperButton<Label: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var appMode

    let enabled: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        let colors = Colors.theme(theme, mode: appMode)
        Button(action: action) {
            HStack(spacing: 4) { label }
                .foregroundStyle(enabled ? colors.textPrimary : colors.textSecondary.opacity(0.4))
                .frame(width: 56, height: PrefLayout.controlHeight)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: PrefLayout.controlCorner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PrefLayout.controlCorner, style: .continuous)
                        .strokeBorder(colors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct ValueStopsIndicator: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var appMode

    let count: Int
    let selectedIndex: Int

    var body: some View {
        let colors = Colors.theme(theme, mode: appMode)
        HStack(spacing: PrefLayout.stopDotSpacing) {
            ForEach(0..<count, id: \.self) { idx in
                Circle()
                    .fill(idx == selectedIndex ? colors.accent : colors.border.opacity(0.9))
                    .frame(width: PrefLayout.stopDotSize, height: PrefLayout.stopDotSize)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var scheme: AppColorScheme = .light
    @Previewable @State var appTheme: AppTheme = .purba
    @Previewable @State var textSize: AppTextSize = .pt20
    @Previewable @State var spacing: AppSpacing = .normal

    PreferencesView(
        colorSchemePreference: $scheme,
        currentTheme: $appTheme,
        textSize: $textSize,
        spacing: $spacing
    )
    .environment(\.appTheme, appTheme)
    .environment(\.appMode, .day)
}
