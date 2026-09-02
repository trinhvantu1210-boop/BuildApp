import SwiftUI

// MARK: - Giao diện Hướng dẫn & Cài đặt Hồ sơ AntiBan AimLock HZZ

struct ProfileInstallSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var installer = ProfileInstallerService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Banner trên cùng
                    topBannerCard

                    // Các bước hướng dẫn kích hoạt
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CÁC BƯỚC KÍCH HOẠT (3 BƯỚC)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .kerning(1.2)
                            .padding(.leading, 4)

                        stepCard(
                            stepNumber: "1",
                            title: "Tải về hồ sơ cấu hình",
                            desc: "Bấm nút 'Tải Hồ Sơ', Safari sẽ tự động mở và hiện thông báo yêu cầu cho phép tải hồ sơ cấu hình về máy.",
                            buttonTitle: "1. Bấm Tải Hồ Sơ",
                            buttonIcon: "arrow.down.doc.fill",
                            buttonColor: AppTheme.accent,
                            action: {
                                installer.startAndInstall()
                            }
                        )

                        stepCard(
                            stepNumber: "2",
                            title: "Mở Cài đặt trên iPhone",
                            desc: "Sau khi bấm 'Cho phép' trên Safari, mở Cài đặt > chọn mục 'Đã tải về hồ sơ' (hoặc Cài đặt chung > Quản lý VPN & Thiết bị).",
                            buttonTitle: "2. Mở Cài Đặt iOS",
                            buttonIcon: "gearshape.fill",
                            buttonColor: Color.blue,
                            action: {
                                installer.openSettingsProfile()
                            }
                        )

                        stepCard(
                            stepNumber: "3",
                            title: "Xác nhận & Cài đặt",
                            desc: "Bấm nút 'Cài đặt' ở góc trên bên phải, nhập mật mã khóa màn hình của bạn để hoàn tất kích hoạt DNS AntiBan.",
                            buttonTitle: nil,
                            buttonIcon: nil,
                            buttonColor: nil,
                            action: nil
                        )
                    }

                    // Tùy chọn xuất file thủ công
                    VStack(spacing: 12) {
                        Button {
                            installer.exportProfileFile()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Chia sẻ hoặc Lưu file .mobileconfig")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, AppTheme.pageInset)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("Hồ Sơ AntiBan AimLock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    // Banner giới thiệu cấu hình
    private var topBannerCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.58, blue: 0.95),
                            Color(red: 0.05, green: 0.28, blue: 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 14, weight: .bold))
                    Text("ENCRYPTED DNS / DoH")
                        .font(.caption2.weight(.heavy))
                        .kerning(1.2)
                }
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.2)))

                Text("AntiBan AimLock HZZ")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Cấu hình DNS mã hóa NextDNS chuyên dụng chặn server quét gian lận và hỗ trợ tối ưu kết nối WiFi / 4G / 5G.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineSpacing(2)

                if let err = installer.lastErrorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.yellow)
                        .padding(.top, 2)
                }
            }
            .padding(20)
        }
    }

    // Khung từng bước hướng dẫn
    private func stepCard(
        stepNumber: String,
        title: String,
        desc: String,
        buttonTitle: String?,
        buttonIcon: String?,
        buttonColor: Color?,
        action: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Text(stepNumber)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Text(desc)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            if let btnTitle = buttonTitle, let btnColor = buttonColor, let act = action {
                Button(action: act) {
                    HStack(spacing: 8) {
                        if let icon = buttonIcon {
                            Image(systemName: icon)
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(btnTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(btnColor)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
