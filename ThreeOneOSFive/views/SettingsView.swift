import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @AppStorage(KV.loggedIn) private var loggedIn = true
    @AppStorage(KV.licenseKey) private var licenseKey = ""
    @AppStorage(KV.licenseRemaining) private var licenseRemaining = ""
    @AppStorage(KV.licenseExpires) private var licenseExpires = ""

    var body: some View {
        NavigationStack {
            Form {
                // Tên app + phiên bản luôn ở trên cùng.
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text(SStr.s("b1")).font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.hardwareDisplayName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    HStack {
                        Text(language.text("settings.software"))
                        Spacer()
                        Text(appState.isSupported ? "Được hỗ trợ" : "Không được hỗ trợ")
                            .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                            .fontWeight(.semibold)
                    }
                }

                Section(language.text("settings.social_media")) {
                    creditsRow(name: SStr.s("d3"), role: SStr.s("d0"), url: SStr.s("u1"))
                    creditsRow(name: SStr.s("d2"), role: SStr.s("d1"), url: SStr.s("u2"))
                }

                Section(language.text("settings.credits")) {
                    creditRow(name: SStr.s("q7"))
                    creditRow(name: SStr.s("q8"))
                    creditRow(name: SStr.s("q9"))
                    creditRow(name: SStr.s("q10"))
                }

                // Tài khoản đặt ở dưới cùng.
                Section(language.text("settings.account")) {
                    HStack(spacing: 12) {
                        AppRowIcon(systemName: "key.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(maskedKey)
                                .font(.headline.monospaced())
                                .foregroundStyle(.primary)
                            if !licenseRemaining.isEmpty {
                                Text("Còn lại: \(licenseRemaining)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !licenseExpires.isEmpty, licenseRemaining != "Lifetime" {
                                Text("Hết hạn: \(licenseExpires)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(SStr.s("p6")) {
                            LicenseAuthService.clearSession()
                            GrantStore.clear()
                            loggedIn = false
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    }
                    .contentShape(Rectangle())
                }
            }
            .tint(AppTheme.accent)
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private var maskedKey: String {
        guard !licenseKey.isEmpty else { return "License" }
        guard licenseKey.count > 8 else { return "••••" }
        let first = licenseKey.prefix(4)
        let last = licenseKey.suffix(4)
        return "\(first)••••\(last)"
    }

    @ViewBuilder
    private func creditsRow(name: String, role: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(name)
        }
    }

    private func creditRow(name: String) -> some View {
        HStack(spacing: 12) {
            AppRowIcon(systemName: "person.crop.circle.fill")
            Text(name)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
