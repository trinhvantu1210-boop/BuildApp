import SwiftUI
import UIKit
import CryptoKit
import CommonCrypto

// MARK: - Aim catalog (loaded from BundledPatches folder in the app bundle)

enum AimGameKind: Hashable, CaseIterable {
    case freeFire
    case freeFireMax

    var title: String {
        self == .freeFire ? SStr.s("g1") : SStr.s("g0")
    }

    var bundleID: String {
        self == .freeFire ? "com.dts.freefireth" : "com.dts.freefiremax"
    }

    var targetGame: FFAntiBanService.TargetGame {
        self == .freeFire ? .freeFire : .freeFireMax
    }

    var builder: String {
        self == .freeFire ? SStr.s("g3") : SStr.s("g2")
    }

    var iconAssetName: String {
        self == .freeFire ? "FreeFireIcon" : "FreeFireMaxIcon"
    }

    var iconPlaceholder: String {
        self == .freeFire ? "FF" : "MAX"
    }
}

struct BundledAim: Identifiable {
    let id: UUID
    let displayName: String
    let game: AimGameKind
    let entries: [Entry]

    struct Entry {
        let relativePath: String
        let bundleID: String
        let fileID: String
    }

    var targetKeys: Set<String> {
        Set(entries.map { $0.bundleID + "|" + $0.relativePath })
    }
}

// Bảng chuỗi hiển thị mã hoá (gd/str.bin)
enum SStr {
    private static var cache: [String: String] = [:]

    static func s(_ key: String) -> String {
        if cache.isEmpty { load() }
        return cache[key] ?? key
    }

    private static func load() {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "gd", withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent("gd", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("gd", isDirectory: true)
        ]
        for candidate in candidates {
            guard let pack = candidate,
                  let encrypted = try? Data(contentsOf: pack.appendingPathComponent("str.bin")),
                  let plain = UIStringVault.decrypt(encrypted),
                  let table = try? JSONDecoder().decode([String: String].self, from: plain) else {
                continue
            }
            cache = table
            break
        }
    }
}

private struct VaultIndex: Decodable {
    struct Aim: Decodable {
        let n: String
        let g: Int
        let o: Int
        let e: [Entry]
    }
    struct Entry: Decodable {
        let p: String
        let b: String
        let f: String
    }
    let aims: [Aim]
}

struct PatchCatalogConfig {
    let packName: String
    let seedPrefix: String
    let unitLabel: String
    var supportsRestoreAll = false

    func load() -> [AimGameKind: [BundledAim]] {
        guard LicenseGate.admit(1) else { return [:] }
        guard let pack = packURL(),
              let encrypted = try? Data(contentsOf: pack.appendingPathComponent("i.bin")),
              let plain = PackVault.decrypt(encrypted),
              let index = try? JSONDecoder().decode(VaultIndex.self, from: plain) else {
            return [:]
        }

        var byGame: [AimGameKind: [BundledAim]] = [:]
        for (position, aim) in index.aims.enumerated() {
            let game: AimGameKind = aim.g == 1 ? .freeFireMax : .freeFire
            byGame[game, default: []].append(
                BundledAim(
                    id: deterministicUUID("\(seedPrefix)-\(position)-\(aim.o)"),
                    displayName: aim.n,
                    game: game,
                    entries: aim.e.map {
                        BundledAim.Entry(relativePath: $0.p, bundleID: $0.b, fileID: $0.f)
                    }
                )
            )
        }
        return byGame
    }

    func buildProject(for aim: BundledAim) throws -> PatchProject {
        guard LicenseGate.admit(2) else {
            throw PatchPackageError.applyFailed
        }
        guard let pack = packURL() else {
            throw PatchPackageError.applyFailed
        }
        let rules = try aim.entries.enumerated().map { index, entry -> PatchRule in
            let encrypted = try Data(contentsOf: pack.appendingPathComponent(entry.fileID + ".bin"))
            guard let plain = PackVault.decrypt(encrypted), !plain.isEmpty else {
                throw PatchPackageError.applyFailed
            }
            return PatchRule(
                id: deterministicUUID("\(aim.id.uuidString)-rule-\(index)"),
                bundleID: entry.bundleID,
                relativePath: entry.relativePath,
                replacementFilename: entry.fileID + ".bin",
                replacementData: plain
            )
        }
        return PatchProject(id: aim.id, name: aim.displayName, rules: rules)
    }

    func isApplied(_ aim: BundledAim) -> Bool {
        DevicePatchService.latestReceipt(projectID: aim.id) != nil
    }

    func restoreReceipt(for aim: BundledAim) -> PatchTransactionReceipt? {
        DevicePatchService.latestReceipt(projectID: aim.id)
    }

    func deterministicUUID(_ seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        var formatted = hex
        for offset in [23, 18, 13, 8] {
            formatted.insert("-", at: formatted.index(formatted.startIndex, offsetBy: offset))
        }
        return UUID(uuidString: formatted) ?? UUID()
    }

    private func packURL() -> URL? {
        if let url = Bundle.main.url(forResource: packName, withExtension: nil) {
            return url
        }
        if let res = Bundle.main.resourceURL?.appendingPathComponent(packName, isDirectory: true),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        let bundlePath = Bundle.main.bundleURL.appendingPathComponent(packName, isDirectory: true)
        if FileManager.default.fileExists(atPath: bundlePath.path) {
            return bundlePath
        }
        return Bundle.main.resourceURL?.appendingPathComponent(packName, isDirectory: true)
    }
}

enum AimCatalog {
    static let config = PatchCatalogConfig(packName: "gd", seedPrefix: "zrx-aim", unitLabel: SStr.s("t2"))
}

enum SkinCatalog {
    static let config = PatchCatalogConfig(packName: "sk", seedPrefix: "zrx-skin", unitLabel: SStr.s("t3"))
}

enum DinhViCatalog {
    static let config = PatchCatalogConfig(
        packName: "dv",
        seedPrefix: "zrx-dv",
        unitLabel: SStr.s("t5"),
        supportsRestoreAll: true
    )
}

// MARK: - 3 Sub-Tabs cho từng Game: Aim / Mod / Định Vị

enum HackSubCategory: String, CaseIterable, Identifiable {
    case aim = "Aim"
    case skins = "Mod"
    case dinhVi = "Định vị"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aim: return "Aim"
        case .skins: return "Mod (Skin)"
        case .dinhVi: return "Định vị"
        }
    }

    var icon: String {
        switch self {
        case .aim: return "scope"
        case .skins: return "tshirt.fill"
        case .dinhVi: return "location.fill"
        }
    }

    var config: PatchCatalogConfig {
        switch self {
        case .aim: return AimCatalog.config
        case .skins: return SkinCatalog.config
        case .dinhVi: return DinhViCatalog.config
        }
    }
}

// MARK: - Màn hình chính Hack Tab: Chọn Free Fire hoặc Free Fire MAX

struct PatchProjectsView: View {
    @State private var installedGames: [String: Bool] = [:]
    @State private var showSettings = false
    @State private var showProfileSheet = false
    @ObservedObject private var antiBanService = FFAntiBanService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Banner
                    headerCard

                    // Card Cấu hình DNS Anti-Ban HZZ Profile (.mobileconfig)
                    profileConfigCard

                    // Danh sách 2 Game: Free Fire & Free Fire MAX
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CHỌN PHIÊN BẢN GAME")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .kerning(1.2)
                            .padding(.leading, 4)

                        ForEach(AimGameKind.allCases, id: \.self) { game in
                            NavigationLink {
                                GameUnifiedHackDetailView(game: game)
                            } label: {
                                UnifiedGameCard(
                                    game: game,
                                    installed: installedGames[game.bundleID] ?? false,
                                    isAntiBanRunning: antiBanService.isRunning(game.targetGame),
                                    antiBanTime: antiBanService.elapsedTimeString(for: game.targetGame)
                                )
                            }
                            .buttonStyle(AimPressStyle())
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageInset)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("PrMods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileInstallSheetView()
            }
            .onAppear {
                checkInstalledGames()
            }
        }
    }

    private var profileConfigCard: some View {
        let isRunning = antiBanService.isAnyRunning
        let timeStr = antiBanService.maxRunningTimeString

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isRunning
                                ? [Color(red: 0.05, green: 0.85, blue: 0.45), Color(red: 0.02, green: 0.55, blue: 0.28)]
                                : [Color(red: 0.1, green: 0.55, blue: 0.95), Color(red: 0.05, green: 0.28, blue: 0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: isRunning ? "shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("AntiBan AimLock HZZ")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text(isRunning ? "ACTIVE" : "DIRECT")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isRunning ? Color.green : Color.blue))
                }

                if isRunning {
                    Text("🟢 Đang bảo vệ trực tiếp (\(timeStr))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.green)
                        .lineLimit(1)
                } else {
                    Text("Chặn file log báo cáo & chuẩn hóa mốc giờ trực tiếp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Nút mở bảng hướng dẫn / profile mobileconfig (Tùy chọn)
            Button {
                showProfileSheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)

            // Nút gạt BẬT/TẮT trực tiếp trong app
            Toggle("", isOn: Binding(
                get: { antiBanService.isAnyRunning },
                set: { _ in
                    antiBanService.toggleAllInstalledGames()
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            ))
            .labelsHidden()
            .tint(.green)
            .scaleEffect(0.9)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isRunning ? Color.green.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var headerCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.44, blue: 0.96),
                            Color(red: 0.00, green: 0.72, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 14, weight: .bold))
                    Text("PRMODS PRO")
                        .font(.caption2.weight(.heavy))
                        .kerning(1.5)
                }
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.18)))

                Text("Menu Hack & Anti-Ban")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Hỗ trợ Aim, Mod Skin và Định Vị cho Free Fire & Free Fire MAX kèm Anti-Ban cực cao.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
            }
            .padding(20)
        }
    }

    private func checkInstalledGames() {
        for game in AimGameKind.allCases {
            let id = game.bundleID
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = ContainerStore.resolveAppContainerPath(bundleID: id) != nil
                DispatchQueue.main.async {
                    self.installedGames[id] = ok
                }
            }
        }
    }
}

// MARK: - Game Card hiển thị ở Menu chính

private struct UnifiedGameCard: View {
    let game: AimGameKind
    let installed: Bool
    let isAntiBanRunning: Bool
    let antiBanTime: String

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                AimGameIcon(
                    assetName: game.iconAssetName,
                    placeholder: game.iconPlaceholder,
                    size: 64
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(game.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        if installed {
                            Text("Đã cài")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.12), in: Capsule())
                        } else {
                            Text("Chưa cài")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(game.builder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isAntiBanRunning {
                        HStack(spacing: 5) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("Anti-Ban: \(antiBanTime)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.green)
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            // 3 Badges tính năng: Aim, Mod, Định vị
            HStack(spacing: 8) {
                badgeView(icon: "scope", label: "Aim")
                badgeView(icon: "tshirt.fill", label: "Mod")
                badgeView(icon: "location.fill", label: "Định vị")
                Spacer()
                Text("Chi tiết")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func badgeView(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.accent.opacity(0.10), in: Capsule())
    }
}

// MARK: - Chi tiết Game với 3 Tab nhỏ: Aim / Mod / Định Vị + Anti-Ban

struct GameUnifiedHackDetailView: View {
    let game: AimGameKind

    @State private var selectedSubTab: HackSubCategory = .aim
    @ObservedObject private var antiBanService = FFAntiBanService.shared
    @AppStorage("floating_overlay_enabled") private var isOverlayEnabled = true

    // Data catalogs for each sub-tab
    @State private var aimsByCategory: [HackSubCategory: [BundledAim]] = [:]
    @State private var appliedAimIDs: Set<UUID> = []
    @State private var workingAimIDs: Set<UUID> = []
    @State private var isRestoringAll = false
    @State private var activeError: String?
    @State private var isInstalled = false
    
    // State cho Floating Button
    @State private var showFloatingMenu = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 1. Anti-Ban Banner riêng cho game này
                    antiBanSection

                    // 2. Banner bật/tắt Nút Menu Nổi (Overlay) có thể kéo thả
                    overlayToggleSection

                    // 3. Thanh gạt 3 Sub-Tabs: Aim / Mod / Định Vị
                    subTabBar

                    // 4. Danh sách tính năng của Sub-Tab đang chọn
                    featureListSection
                }
                .padding(.horizontal, AppTheme.pageInset)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle(game.title)
            .navigationBarTitleDisplayMode(.inline)
            
            // Nút tròn nổi mượt
            if isOverlayEnabled {
                SmoothFloatingButton(
                    game: game,
                    isAntiBanOn: antiBanService.isRunning(game.targetGame),
                    hasActiveHack: !appliedAimIDs.isEmpty,
                    activeHackCount: appliedAimIDs.count,
                    onTap: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            showFloatingMenu.toggle()
                        }
                    }
                )
                .zIndex(999)
            }
            
            // Menu overlay khi bấm vào nút tròn
            if showFloatingMenu {
                FloatingMenuOverlay(
                    game: game,
                    aimsByCategory: aimsByCategory,
                    appliedAimIDs: appliedAimIDs,
                    workingAimIDs: workingAimIDs,
                    selectedTab: selectedSubTab,
                    isRestoringAll: isRestoringAll,
                    antiBanService: antiBanService,
                    onToggleAim: { aim, on, config in
                        toggleAim(aim, on: on, config: config)
                    },
                    onRestoreCategory: {
                        restoreCurrentCategory()
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            showFloatingMenu = false
                        }
                    }
                )
                .zIndex(1000)
            }
        }
        .onAppear {
            isInstalled = ContainerStore.resolveAppContainerPath(bundleID: game.bundleID) != nil
            loadAllCatalogs()
        }
        .alert(isPresented: Binding(get: { activeError != nil }, set: { if !$0 { activeError = nil } })) {
            Alert(
                title: Text("Thông báo"),
                message: Text(activeError ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // Banner Bật / Tắt Nút Tròn Nổi Overlay Kéo Thả
    private var overlayToggleSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isOverlayEnabled ? AppTheme.accent.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: isOverlayEnabled ? "scope" : "circle.dashed")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isOverlayEnabled ? AppTheme.accent : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Nút Tròn Nổi")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if isOverlayEnabled {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    }
                }

                Text(isOverlayEnabled ? "Đang hiện nút tròn kéo thả trên màn hình" : "Bật để hiện nút chức năng di chuyển tự do")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOverlayEnabled.animation(.spring(response: 0.35, dampingFraction: 0.75)))
                .labelsHidden()
                .tint(AppTheme.accent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isOverlayEnabled ? AppTheme.accent.opacity(0.4) : AppTheme.accent.opacity(0.12), lineWidth: 1)
        )
    }

    // Banner Anti-Ban Cực Cao
    private var antiBanSection: some View {
        let isRunning = antiBanService.isRunning(game.targetGame)
        let timeStr = antiBanService.elapsedTimeString(for: game.targetGame)

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isRunning ? Color.green.opacity(0.18) : AppTheme.accent.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: isRunning ? "shield.fill" : "shield.slash")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isRunning ? Color.green : AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Anti-Ban Cực Cao")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if isRunning {
                    Text("Đang chạy: \(timeStr)")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color.green)
                } else if let lastResult = antiBanService.resultText(for: game.targetGame) {
                    Text(lastResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(isInstalled ? "Sẵn sàng chạy ngầm" : "Game chưa cài")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                antiBanService.toggle(for: game.targetGame)
            } label: {
                Text(isRunning ? "TẮT" : "BẬT")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isRunning ? Color.red : (isInstalled ? AppTheme.accent : Color.gray.opacity(0.4)))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isInstalled)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isRunning ? Color.green.opacity(0.4) : AppTheme.accent.opacity(0.15), lineWidth: 1)
        )
    }

    // 3 Tab Nhỏ: Aim / Mod / Định Vị
    private var subTabBar: some View {
        HStack(spacing: 8) {
            ForEach(HackSubCategory.allCases) { cat in
                let isSelected = selectedSubTab == cat
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selectedSubTab = cat
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(cat.displayName)
                            .font(.system(size: 14, weight: isSelected ? .bold : .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? AppTheme.accent : Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Color.clear : AppTheme.accent.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    // Danh sách tính năng tương ứng theo Sub-Tab đã chọn
    @ViewBuilder
    private var featureListSection: some View {
        let currentItems = aimsByCategory[selectedSubTab] ?? []

        VStack(spacing: 12) {
            if currentItems.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                        .padding(.top, 24)
                    Text("Đang tải dữ liệu \(selectedSubTab.displayName)…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(currentItems) { aim in
                    AimToggleRow(
                        title: aim.displayName,
                        isApplied: appliedAimIDs.contains(aim.id),
                        isWorking: workingAimIDs.contains(aim.id)
                    ) { on in
                        toggleAim(aim, on: on, config: selectedSubTab.config)
                    }
                }

                // Nút khôi phục tất cả
                Button(action: restoreCurrentCategory) {
                    HStack(spacing: 8) {
                        if isRestoringAll {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        Text("Khôi phục tất cả \(selectedSubTab.displayName)")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(isRestoringAll)
                .padding(.top, 10)
            }
        }
    }

    private func loadAllCatalogs() {
        Task {
            for cat in HackSubCategory.allCases {
                let dict = cat.config.load()
                let items = dict[game] ?? []
                await MainActor.run {
                    self.aimsByCategory[cat] = items
                }
            }
            refreshAppliedState()
        }
    }

    private func refreshAppliedState() {
        let allItems = aimsByCategory.values.flatMap { $0 }
        appliedAimIDs = Set(allItems.filter { aim in
            DevicePatchService.latestReceipt(projectID: aim.id) != nil
        }.map(\.id))
    }

    private func toggleAim(_ aim: BundledAim, on: Bool, config: PatchCatalogConfig) {
        guard !workingAimIDs.contains(aim.id) else { return }
        workingAimIDs.insert(aim.id)
        UISelectionFeedbackGenerator().selectionChanged()

        let currentCategoryItems = aimsByCategory[selectedSubTab] ?? []
        let snapshotApplied = appliedAimIDs

        Task.detached(priority: .userInitiated) {
            do {
                if on {
                    for other in currentCategoryItems where other.id != aim.id && other.game == aim.game {
                        guard !other.targetKeys.isDisjoint(with: aim.targetKeys),
                              snapshotApplied.contains(other.id),
                              let receipt = config.restoreReceipt(for: other) else { continue }
                        try? DevicePatchService.restore(receipt: receipt)
                    }
                    let project = try config.buildProject(for: aim)
                    _ = try DevicePatchService.apply(project: project)
                } else {
                    guard let receipt = config.restoreReceipt(for: aim) else {
                        throw PatchPackageError.restoreFailed
                    }
                    try DevicePatchService.restore(receipt: receipt)
                }
                await MainActor.run {
                    workingAimIDs.remove(aim.id)
                    refreshAppliedState()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    workingAimIDs.remove(aim.id)
                    refreshAppliedState()
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    activeError = "Không thể áp dụng trên \(game.title). Hãy chắc chắn game đã cài và mở lại quyền exploit."
                }
            }
        }
    }

    private func restoreCurrentCategory() {
        guard !isRestoringAll else { return }
        isRestoringAll = true
        UISelectionFeedbackGenerator().selectionChanged()

        let snapshot = aimsByCategory[selectedSubTab] ?? []
        let config = selectedSubTab.config

        Task.detached(priority: .userInitiated) {
            var failures = 0
            for aim in snapshot {
                do {
                    let receipt: PatchTransactionReceipt
                    if let existing = DevicePatchService.latestReceipt(projectID: aim.id) {
                        receipt = existing
                    } else {
                        let project = try config.buildProject(for: aim)
                        receipt = try DevicePatchService.backupOriginal(project: project)
                    }
                    try DevicePatchService.restore(receipt: receipt)
                } catch {
                    failures += 1
                }
            }
            await MainActor.run {
                isRestoringAll = false
                refreshAppliedState()
                UINotificationFeedbackGenerator().notificationOccurred(failures == 0 ? .success : .warning)
            }
        }
    }
}

// MARK: - Tương thích ngược: SkinsView, DinhViView

struct SkinsView: View {
    var body: some View {
        PatchProjectsView()
    }
}

struct DinhViView: View {
    var body: some View {
        PatchProjectsView()
    }
}

// MARK: - Game Icon Component

private struct AimGameIcon: View {
    let assetName: String
    let placeholder: String
    let size: CGFloat

    var body: some View {
        let cornerRadius = size * 0.26
        return Group {
            if let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.48, blue: 0.31),
                                    Color(red: 0.94, green: 0.29, blue: 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(placeholder)
                        .font(.system(
                            size: size * (placeholder.count > 2 ? 0.26 : 0.34),
                            weight: .heavy,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.95))
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Aim List Toggle Row

private struct AimToggleRow: View {
    let title: String
    let isApplied: Bool
    let isWorking: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isApplied },
            set: { on in onToggle(on) }
        )) {
            HStack(spacing: 10) {
                if isApplied && !isWorking {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    statusView
                }
            }
        }
        .tint(AppTheme.accent)
        .disabled(isWorking)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isApplied ? Color.green.opacity(0.45) : AppTheme.accent.opacity(0.14),
                    lineWidth: isApplied ? 1.5 : 1
                )
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isApplied)
        .animation(.easeInOut(duration: 0.2), value: isWorking)
    }

    @ViewBuilder
    private var statusView: some View {
        if isWorking {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Đang xử lý…")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .transition(.opacity)
        } else if isApplied {
            Text("Đã kích hoạt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Text("Chưa áp dụng")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }
}

// Panel nhấn xuống co nhẹ lại như nút thật.
private struct AimPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}