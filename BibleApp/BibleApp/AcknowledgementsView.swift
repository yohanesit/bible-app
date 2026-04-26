//  AcknowledgementsView.swift
//  BibleApp
//
//  Credits and license notices for third-party content used by the app.
//  Required by LAI license terms and App Store guidelines.

import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    @AppStorage("lectionaryRegion") private var lectionaryRegion: String = "ID"

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Capsule()
                    .fill(colors.accent.opacity(0.55))
                    .frame(width: 51, height: 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)

                Text("Settings")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                    .padding(.horizontal, 2)

                VStack(spacing: 0) {
                    // Lectionary region picker — tapping opens a menu of available regions
                    let regions = BundledLectionaryStore.shared.availableRegions
                    let currentRegion = regions[lectionaryRegion]
                    Menu {
                        ForEach(regions.keys.sorted(), id: \.self) { code in
                            Button {
                                lectionaryRegion = code
                            } label: {
                                let info = regions[code]
                                if lectionaryRegion == code {
                                    Label("\(info?.flag ?? "") \(info?.name ?? code)", systemImage: "checkmark")
                                } else {
                                    Text("\(info?.flag ?? "") \(info?.name ?? code)")
                                }
                            }
                        }
                    } label: {
                        SettingRow(
                            label: "Lectionary Region",
                            value: currentRegion.map { "\($0.flag) \($0.name)" } ?? lectionaryRegion,
                            colors: colors
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(colors.border)
                    SettingRow(label: "Bible Version", value: "TB", colors: colors)
                    Divider().overlay(colors.border)
                    SettingRow(label: "Privacy Policy", value: nil, colors: colors)
                }
                .background(Color.white.opacity(mode == .day ? 1 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Text("Acknowledgements")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Tunduk, Setia & Taat pada Hierarki\n\nInformasi diambil dari imankatolik.or.id")
                    Divider().overlay(colors.border)
                    Text(
                        """
                        Alkitab Terjemahan Baru (TB) - 1974

                        Teks Alkitab Terjemahan Baru Indonesia © LAI 1974

                        Copyright Lembaga Alkitab Indonesia (Indonesian Bible Society), 1994.
                        Released for non-profit scholarly and personal use. Not to be sold for profit.
                        When making formal public reference to the materials, please acknowledge The Indonesian Bible Society (Lembaga Alkitab Indonesia) as the copyright holder.
                        """
                    )
                }
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(colors.textPrimary)
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .background(Color.white.opacity(mode == .day ? 1 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(colors.surface)
        .presentationBackground(colors.surface)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(16)
    }
}

private struct SettingRow: View {
    let label: String
    let value: String?
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(colors.textPrimary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

// MARK: - Preview

#Preview {
    AcknowledgementsView()
        .environment(\.appTheme, .purba)
        .environment(\.appMode,  .day)
}
