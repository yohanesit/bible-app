//  AdminView.swift
//  BibleApp
//
//  Admin panel for managing local Bible text data.
//  Accessible from PreferencesView → "Data" section.
//
//  Allows:
//    • Selecting the active Bible source
//    • Entering API keys for each source
//    • Triggering full Bible text syncs
//    • Viewing sync status and last-synced dates

import SwiftUI

struct AdminView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode
    @Environment(\.dismiss)  private var dismiss

    @AppStorage("bibleSource") private var bibleSourceRaw: String = BibleSource.alkitab.rawValue

    @State private var alkitabSyncService = BibleSyncService()
    @State private var alkitabApiKeyInput: String = ""
    @State private var showConfirmAlkitabSync = false

    private let db = BibleDatabase.shared

    private var selectedSource: BibleSource {
        BibleSource(rawValue: bibleSourceRaw) ?? .alkitab
    }

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)

        VStack(alignment: .leading, spacing: 0) {

            // ── Header ───────────────────────────────────────────────────
            HStack(alignment: .center) {
                Text("Data & Sync")
                    .font(.system(size: 20))
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(colors.surface))
                        .overlay(Circle().strokeBorder(colors.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider().overlay(colors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Bible Source ─────────────────────────────────────
                    AdminSection(title: "Sumber Teks Alkitab") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Pilih sumber teks yang digunakan untuk membaca Alkitab dan bacaan harian.")
                                .font(.system(size: 13))
                                .foregroundStyle(colors.textSecondary)

                            HStack(spacing: 8) {
                                ForEach(BibleSource.allCases, id: \.self) { source in
                                    let isSelected = selectedSource == source
                                    let hasData = db.bookCount(forSource: source) > 0
                                    Button {
                                        if hasData { bibleSourceRaw = source.rawValue }
                                    } label: {
                                        VStack(spacing: 3) {
                                            Text("Alkitab.or.id")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(isSelected ? colors.accent : (hasData ? colors.textPrimary : colors.textSecondary))
                                                .multilineTextAlignment(.center)
                                            if !hasData {
                                                Text("Belum diunduh")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(colors.textSecondary.opacity(0.7))
                                            } else {
                                                Text("\(db.bookCount(forSource: source)) buku")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(colors.textSecondary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(colors.surface)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(
                                                    isSelected ? colors.accent : colors.border,
                                                    lineWidth: isSelected ? 2 : 1
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!hasData)
                                    .opacity(hasData ? 1 : 0.6)
                                }
                            }
                        }
                    }

                    Divider().overlay(colors.border)

                    // ── Alkitab.or.id section ────────────────────────────
                    AdminSection(title: "Alkitab.or.id (TB)") {
                        VStack(alignment: .leading, spacing: 16) {
                            // Status
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Buku tersimpan")
                                        .font(.system(size: 13))
                                        .foregroundStyle(colors.textSecondary)
                                    Text("\(db.bookCount(forSource: .alkitab)) buku")
                                        .font(.system(size: 15))
                                        .foregroundStyle(colors.textPrimary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Sinkron terakhir")
                                        .font(.system(size: 13))
                                        .foregroundStyle(colors.textSecondary)
                                    Text(lastSyncLabel(for: alkitabSyncService.lastSyncDate))
                                        .font(.system(size: 15))
                                        .foregroundStyle(colors.textPrimary)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(colors.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(colors.border, lineWidth: 1))

                            if db.bookCount(forSource: .alkitab) >= 73 {
                                Text("✅ Teks tersedia offline (bundled seed). API sync tidak diperlukan.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.textSecondary)
                            }

                            // API Key
                            VStack(alignment: .leading, spacing: 6) {
                                Text("API Key")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(colors.textSecondary)
                                SecureField("Kunci API alkitab.or.id…", text: $alkitabApiKeyInput)
                                    .font(.system(size: 15))
                                    .foregroundStyle(colors.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(colors.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(colors.border, lineWidth: 1))
                                    .onAppear { alkitabApiKeyInput = alkitabSyncService.apiKey }
                                if alkitabApiKeyInput != alkitabSyncService.apiKey {
                                    Button("Simpan") { alkitabSyncService.apiKey = alkitabApiKeyInput }
                                        .font(.system(size: 14)).foregroundStyle(colors.accent)
                                }
                            }

                            // Sync button / progress
                            syncControls(
                                service: alkitabSyncService,
                                colors: colors,
                                confirmBinding: $showConfirmAlkitabSync
                            )

                            if let err = alkitabSyncService.error {
                                Text(err).font(.system(size: 13)).foregroundStyle(.red.opacity(0.8))
                            }
                        }
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background(colors.background)
        .presentationBackground(colors.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
        .confirmationDialog("Sinkronkan dari Alkitab.or.id?", isPresented: $showConfirmAlkitabSync, titleVisibility: .visible) {
            Button("Unduh Teks TB (66 buku)") { alkitabSyncService.startSync() }
            Button("Batalkan", role: .cancel) {}
        } message: {
            Text("Akan mengunduh teks TB dari alkitab.or.id secara lokal.")
        }
        
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func syncControls(service: BibleSyncService, colors: ThemeColors, confirmBinding: Binding<Bool>) -> some View {
        if service.isSyncing {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mengunduh \(service.currentBook.uppercased())…")
                        .font(.system(size: 13)).foregroundStyle(colors.textSecondary)
                    Spacer()
                    Text("\(Int(service.progress * 100))%")
                        .font(.system(size: 13)).foregroundStyle(colors.accent)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(colors.border).frame(height: 6)
                        RoundedRectangle(cornerRadius: 4).fill(colors.accent)
                            .frame(width: geo.size.width * service.progress, height: 6)
                            .animation(.linear(duration: 0.2), value: service.progress)
                    }
                }.frame(height: 6)
                Button("Batalkan") { service.cancelSync() }
                    .font(.system(size: 14)).foregroundStyle(colors.textSecondary)
            }
        } else {
            Button { confirmBinding.wrappedValue = true } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text(db.bookCount(forSource: .alkitab) == 0 ? "Unduh Alkitab" : "Perbarui Alkitab")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(service.hasApiKey ? colors.accent : colors.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(colors.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                    service.hasApiKey ? colors.accent : colors.border,
                    lineWidth: service.hasApiKey ? 1.5 : 1))
            }
            .buttonStyle(.plain)
            .disabled(!service.hasApiKey)
        }
    }

    // MARK: - Helpers

    private func lastSyncLabel(for date: Date?) -> String {
        guard let date else { return "Belum pernah" }
        return date.formatted(.dateTime.day().month().year())
    }
}

// MARK: - AdminSection

private struct AdminSection<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.appMode)  private var mode

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        let colors = Colors.theme(theme, mode: mode)
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .fontWeight(.semibold)
                .foregroundStyle(colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content
        }
    }
}

// MARK: - Preview

#Preview {
    AdminView()
        .environment(\.appTheme, .purba)
        .environment(\.appMode,  .day)
}
