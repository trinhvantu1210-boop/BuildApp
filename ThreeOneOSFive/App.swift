import SwiftUI
import UIKit
import CryptoKit
import CommonCrypto
import Darwin

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.vietnamese.rawValue
    @AppStorage(KV.loggedIn) private var loggedIn = false
    @AppStorage(KV.blockedVersion) private var blockedVersion = ""
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var announcementDismissed = false
    @State private var creditsDismissed = false
    @State private var remoteConfig = SignedConfigService.cached() ?? SignedAppConfig.default
    @State private var lastConfigCheck = Date.distantPast
    @State private var showAttribution = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        UserDefaults.standard.removeObject(forKey: KV.blockedVersion)
        log("app: launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .vietnamese
    }

    private func checkForcedUpdate() async {
        UserDefaults.standard.removeObject(forKey: KV.blockedVersion)
        await MainActor.run {
            blockedVersion = ""
        }
    }

    private var isVersionBlocked: Bool {
        false
    }

    // Thông báo hướng dẫn + changelog hiện 1 lần sau mỗi version.
    // Thông báo hiện lại mỗi lần mở app (chỉ tắt trong phiên hiện tại).
    private var shouldShowAnnouncement: Bool {
        !showOnboarding && !announcementDismissed
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isVersionBlocked {
                    ForceUpdateView(
                        newVersion: blockedVersion,
                        onRetry: {
                            Task { await checkForcedUpdate() }
                        }
                    )
                    .zIndex(3)
                } else if remoteConfig.maintenance {
                    MaintenanceView(onRetry: {
                        Task { await refreshRemoteConfig(force: true) }
                    })
                    .zIndex(3)
                    .transition(.opacity)
                } else if loggedIn || !remoteConfig.requireAuth {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(patchDraftCoordinator)
                        .environmentObject(fileOperationCoordinator)
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .opacity(showOnboarding ? 0 : 1)
                        .allowsHitTesting(!showOnboarding)

                    if showOnboarding {
                        OnboardingView {
                            OnboardingStore.markCompleted()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                showOnboarding = false
                            }
                            appState.detectSupport()
                            Task { await checkForcedUpdate() }
                        }
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(1)
                    }

                    if shouldShowAnnouncement {
                        AnnouncementView(onClose: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                announcementDismissed = true
                            }
                        })
                        .zIndex(2)
                        .transition(.opacity)
                    }

                    // Ghi công đội ngũ — hiện sau khi đóng thông báo admin
                    // (hoặc ngay khi vào app nếu không có thông báo).
                    if !creditsDismissed && !shouldShowAnnouncement {
                        TeamCreditsView(onClose: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                creditsDismissed = true
                            }
                        })
                        .zIndex(2)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                } else {
                    LoginView(onSuccess: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            loggedIn = true
                        }
                    })
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: shouldShowAnnouncement)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .onAppear {
                if !showOnboarding {
                    appState.detectSupport()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showOnboarding else { return }
                appState.detectSupport()
                Task {
                    await refreshRemoteConfig(force: false)
                    await Task.detached(priority: .userInitiated) {
                        GuardContext.shared.pulse(force: true)
                    }.value
                    await checkForcedUpdate()
                }
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
            .task {
                await refreshRemoteConfig(force: true)
                await Task.detached(priority: .userInitiated) {
                    GuardContext.shared.pulse(force: true)
                }.value
                await checkForcedUpdate()
                await revalidateLicense()
            }
        }
    }

    // Admin điều khiển từ xa qua cfg.json (ký HMAC): bảo trì + bật/tắt bắt đăng nhập + ép cập nhật.
    private func refreshRemoteConfig(force: Bool) async {
        if !force, Date().timeIntervalSince(lastConfigCheck) < 60 { return }
        lastConfigCheck = Date()
        if let config = await SignedConfigService.fetch() {
            remoteConfig = config
            // Cập nhật ngay trạng thái guard (cfg mới có thể đổi min_version/hash).
            await Task.detached(priority: .userInitiated) {
                GuardContext.shared.pulse(force: true)
            }.value
        }
    }

    // Xác thực lại key mỗi lần mở app; lỗi mạng thì giữ phiên, key sai/hết hạn thì bắt đăng nhập lại.
    private func revalidateLicense() async {
        guard loggedIn else { return }
        // Chống flip cờ: phiên phải kèm chữ ký hợp lệ.
        guard LicenseAuthService.storedSessionIsValid() else {
            LicenseAuthService.clearSession()
            loggedIn = false
            return
        }
        guard let key = UserDefaults.standard.string(forKey: KV.licenseKey),
              !key.isEmpty else { return }
        do {
            let session = try await LicenseAuthService.validate(key: key)
            UserDefaults.standard.set(session.remainingText, forKey: KV.licenseRemaining)
            UserDefaults.standard.set(session.statusText, forKey: KV.licenseStatus)
            UserDefaults.standard.set(session.expiresAt, forKey: KV.licenseExpires)
        } catch LicenseError.rejected {
            LicenseAuthService.clearSession()
            loggedIn = false
        } catch {
            // Không có mạng / server không phản hồi: giữ nguyên phiên đăng nhập.
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}

// MARK: - KeyAuth.cc License Configuration

enum LicenseConfig {
    // ⚙️ CẤU HÌNH KEYAUTH (keyauth.cc / keyauth.win)
    static var appName: String = "tungo"          // Tên Application trên KeyAuth Dashboard
    static var ownerId: String = "ir3DIj1Kx1"          // Owner ID (10 ký tự trên KeyAuth Dashboard)
    static var appSecret: String = "ef187e5a2b466af7323f65af6592db8abbcf6a83cd5e31a0d868c784a1509279" // Application Secret (64 ký tự)
    static var version: String = "1.0"                 // Application Version trên KeyAuth
    static var apiURL: String = "https://keyauth.win/api/1.3/" // KeyAuth API Endpoint (hoặc https://keyauth.cc/api/1.2/)

    static var discordURL: String { SStr.s("u1") }
    static var supportURL: URL { URL(string: SStr.s("u2")) ?? URL(string: "https://discord.gg")! }
    static var getKeyStep1URL: URL { shortenedLink(SStr.s("u7")) }
    static var getKeyStep2URL: URL { shortenedLink(SStr.s("u8")) }
    static var adminContactURL: URL? {
        let raw = SStr.s("u10")
        guard raw.hasPrefix("https://"), !raw.contains("PLACEHOLDER") else { return nil }
        return URL(string: raw)
    }

    private static func shortenedLink(_ raw: String) -> URL {
        if let url = URL(string: raw), !raw.contains("PLACEHOLDER") {
            return url
        }
        return URL(string: SStr.s("u1")) ?? URL(string: "https://discord.gg")!
    }
}

// MARK: - Get Key miễn phí: vượt 2 link Link4M → key dùng thử 1 ngày

enum FreeKeyService {

    static let stepWaitSeconds = 15
    private static let probeDelayNanos: UInt64 = 250_000_000

    static func claimFreeKey(progress: ((Int, Int) -> Void)? = nil) async throws -> String {
        let pool = keyPool()
        guard !pool.isEmpty else {
            throw LicenseError.network("Danh sách key chưa sẵn sàng, thử lại sau.")
        }

        let day = UInt64(Date().timeIntervalSince1970 / 86_400)
        let start = Int((day &+ stableHash(LicenseAuthService.hardwareID())) % UInt64(pool.count))

        for offset in 0..<pool.count {
            progress?(offset + 1, pool.count)
            let candidate = pool[(start + offset) % pool.count]
            do {
                _ = try await LicenseAuthService.validate(key: candidate)
                return candidate
            } catch LicenseError.rejected {
                if offset < pool.count - 1 {
                    try? await Task.sleep(nanoseconds: probeDelayNanos)
                }
            }
        }
        throw LicenseError.rejected("Hôm nay đã hết key miễn phí, hãy quay lại vào ngày mai.")
    }

    static func keyPool() -> [String] {
        var pool: [String] = []
        for index in 0..<50 {
            let keyID = String(format: "k%02d", index)
            let value = SStr.s(keyID)
            if !value.isEmpty && value != keyID {
                pool.append(value)
            }
        }
        return pool
    }

    static func todayCode() -> String {
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data("getkey|\(day)".utf8),
            using: SymmetricKey(data: Data(LicenseConfig.appSecret.utf8))
        )
        return mac.prefix(4).map { String(format: "%02X", $0) }.joined()
    }

    static func normalizedCode(_ raw: String) -> String {
        let cleaned = raw.uppercased().filter(\.isHexDigit)
        return cleaned.count == 8 ? cleaned : ""
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603 // FNV-1a 64-bit offset
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211 // FNV prime
        }
        return hash
    }
}

enum LicenseError: Error {
    case network(String)
    case rejected(String)
}

struct LicenseSession {
    var licenseKey: String
    var statusText: String
    var remainingText: String
    var expiresAt: String
}

enum LicenseAuthService {

    static func clearSession() {
        UserDefaults.standard.removeObject(forKey: KV.licenseKey)
        UserDefaults.standard.removeObject(forKey: KV.licenseRemaining)
        UserDefaults.standard.removeObject(forKey: KV.licenseStatus)
        UserDefaults.standard.removeObject(forKey: KV.licenseExpires)
        UserDefaults.standard.removeObject(forKey: KV.sessionSig)
        UserDefaults.standard.removeObject(forKey: KV.loggedIn)
    }

    static func sessionSignature(for key: String) -> String {
        let digest = SHA256.hash(data: Data("\(key)|\(hardwareID())|\(LicenseConfig.appSecret)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func storedSessionIsValid() -> Bool {
        guard let key = UserDefaults.standard.string(forKey: KV.licenseKey), !key.isEmpty else {
            return false
        }
        return UserDefaults.standard.string(forKey: KV.sessionSig) == sessionSignature(for: key)
    }

    // Helper gửi POST request tới KeyAuth API (1.2 / 1.3)
    private static func postKeyAuth(params: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: LicenseConfig.apiURL) else {
            throw LicenseError.network("URL máy chủ KeyAuth không hợp lệ.")
        }

        let bodyString = params
            .map { "\($0.key)=\(escape($0.value))" }
            .joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("KeyAuth", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = bodyString.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.network("Không kết nối được tới máy chủ KeyAuth. Vui lòng kiểm tra mạng và thử lại.")
        }
        _ = response

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if let text = String(data: data, encoding: .utf8), text.contains("error") {
                throw LicenseError.rejected(text)
            }
            throw LicenseError.network("Máy chủ KeyAuth phản hồi không hợp lệ.")
        }

        return json
    }

    // Xác thực License Key theo chuẩn KeyAuth.cc
    static func validate(key: String) async throws -> LicenseSession {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LicenseError.rejected("Vui lòng nhập license key.")
        }

        // BƯỚC 1: KeyAuth Init (Khởi tạo kết nối lấy Session ID)
        let initParams: [String: String] = [
            "type": "init",
            "name": LicenseConfig.appName,
            "ownerid": LicenseConfig.ownerId,
            "secret": LicenseConfig.appSecret,
            "version": LicenseConfig.version
        ]

        let initJson = try await postKeyAuth(params: initParams)
        let initSuccess = initJson["success"] as? Bool ?? false
        let initMessage = initJson["message"] as? String ?? ""

        guard initSuccess, let sessionId = initJson["sessionid"] as? String, !sessionId.isEmpty else {
            let err = initMessage.isEmpty ? "Khởi tạo kết nối KeyAuth thất bại. Vui lòng kiểm tra App Name, OwnerID hoặc Secret." : initMessage
            throw LicenseError.rejected(err)
        }

        // BƯỚC 2: KeyAuth License Login (Kiểm tra License Key + HWID)
        let licenseParams: [String: String] = [
            "type": "license",
            "key": trimmed,
            "hwid": hardwareID(),
            "sessionid": sessionId,
            "name": LicenseConfig.appName,
            "ownerid": LicenseConfig.ownerId
        ]

        let loginJson = try await postKeyAuth(params: licenseParams)
        let loginSuccess = loginJson["success"] as? Bool ?? false
        let loginMessage = loginJson["message"] as? String ?? ""

        guard loginSuccess else {
            throw LicenseError.rejected(loginMessage.isEmpty ? "License key không hợp lệ hoặc đã hết hạn." : loginMessage)
        }

        // BƯỚC 3: Trích xuất thông tin hạn dùng từ KeyAuth info
        var statusText = "Active"
        var remainingText = "Đang hoạt động"
        var expiresAtFormatted = ""

        if let info = loginJson["info"] as? [String: Any] {
            if let subs = info["subscriptions"] as? [[String: Any]], let firstSub = subs.first {
                if let subName = firstSub["subscription"] as? String, !subName.isEmpty {
                    statusText = subName
                }

                let expiryRaw = firstSub["expiry"]
                var expiryTimestamp: Double? = nil
                if let num = expiryRaw as? Double { expiryTimestamp = num }
                else if let num = expiryRaw as? Int { expiryTimestamp = Double(num) }
                else if let str = expiryRaw as? String, let num = Double(str) { expiryTimestamp = num }

                if let exp = expiryTimestamp {
                    if exp > 2000000000 || exp <= 0 {
                        remainingText = "Vĩnh viễn (Lifetime)"
                        expiresAtFormatted = "Lifetime"
                    } else {
                        let date = Date(timeIntervalSince1970: exp)
                        let formatter = DateFormatter()
                        formatter.dateFormat = "dd/MM/yyyy HH:mm"
                        formatter.locale = Locale(identifier: "vi_VN")
                        expiresAtFormatted = formatter.string(from: date)

                        let now = Date().timeIntervalSince1970
                        let timeLeft = exp - now
                        if timeLeft <= 0 {
                            remainingText = "Đã hết hạn"
                        } else {
                            let days = Int(timeLeft / 86400)
                            let hours = Int((timeLeft.truncatingRemainder(dividingBy: 86400)) / 3600)
                            if days > 0 {
                                remainingText = "Còn \(days) ngày \(hours) giờ"
                            } else {
                                let mins = max(1, Int((timeLeft.truncatingRemainder(dividingBy: 3600)) / 60))
                                remainingText = "Còn \(hours) giờ \(mins) phút"
                            }
                        }
                    }
                } else if let timeleft = firstSub["timeleft"] as? Int {
                    if timeleft >= 315360000 {
                        remainingText = "Vĩnh viễn (Lifetime)"
                        expiresAtFormatted = "Lifetime"
                    } else if timeleft > 0 {
                        let days = timeleft / 86400
                        let hours = (timeleft % 86400) / 3600
                        if days > 0 {
                            remainingText = "Còn \(days) ngày \(hours) giờ"
                        } else {
                            let mins = max(1, (timeleft % 3600) / 60)
                            remainingText = "Còn \(hours) giờ \(mins) phút"
                        }
                    } else {
                        remainingText = "Đã hết hạn"
                    }
                }
            } else if let expiry = info["expiry"] as? String, let expiryTimestamp = Double(expiry) {
                let date = Date(timeIntervalSince1970: expiryTimestamp)
                let formatter = DateFormatter()
                formatter.dateFormat = "dd/MM/yyyy HH:mm"
                expiresAtFormatted = formatter.string(from: date)
            }
        }

        return LicenseSession(
            licenseKey: trimmed,
            statusText: statusText,
            remainingText: remainingText,
            expiresAt: expiresAtFormatted
        )
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    static func hardwareID() -> String {
        if let vendor = UIDevice.current.identifierForVendor?.uuidString {
            return vendor
        }
        let fallbackKey = KV.hwidFallback
        if let stored = UserDefaults.standard.string(forKey: fallbackKey) {
            return stored
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: fallbackKey)
        return generated
    }
}

// MARK: - Thông báo sau đăng nhập: hướng dẫn an toàn + changelog

private struct AnnouncementView: View {
    var onClose: () -> Void

    private let safetyTips = [
        SStr.s("s0"),
        SStr.s("s1"),
        SStr.s("s2"),
        SStr.s("s3"),
        SStr.s("s4")
    ]

    private let changelog: [String] = [
        SStr.s("c8"),
        SStr.s("c6"),
        SStr.s("c7"),
        SStr.s("c5"),
        SStr.s("c0")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)

            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.top, 8)

                    Text(SStr.s("l6"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader(SStr.s("l8"), icon: "shield.lefthalf.filled")
                        ForEach(safetyTips, id: \.self) { tip in
                            bulletRow(tip)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(sectionBackground)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader(SStr.s("l9"), icon: "sparkles")
                        ForEach(changelog, id: \.self) { item in
                            bulletRow(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(sectionBackground)

                    Button(SStr.s("l7"), action: onClose)
                        .buttonStyle(SquaredProminentButtonStyle(cornerRadius: 14))
                }
                .padding(20)
            }
            .frame(maxWidth: 340, maxHeight: 520)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
            .padding(.horizontal, 30)
        }
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground))
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.accent)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.accent)
                .padding(.top, 2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Ghi công đội ngũ phát triển (hiện mỗi lần mở app)

private struct TeamCreditsView: View {
    var onClose: () -> Void

    private struct Member {
        let rank: Int
        let name: String
        let icon: String
    }

    private let members: [Member] = [
        Member(rank: 1, name: "Trịnh Tú (Admin)", icon: "crown.fill"),
        Member(rank: 2, name: "PrMods Developer", icon: "wrench.and.screwdriver.fill"),
        Member(rank: 3, name: "PrMods Coder", icon: "lightbulb.fill"),
        Member(rank: 4, name: "PrMods VIP", icon: "memorychip")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 14) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.yellow)
                    .padding(.top, 8)

                VStack(spacing: 5) {
                    Text("ĐỘI NGŨ PHÁT TRIỂN")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Bản quyền phát triển bởi Trịnh Tú & PrMods Team")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    ForEach(members, id: \.rank) { member in
                        memberRow(member)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                Button("Vào Ứng Dụng", action: onClose)
                    .buttonStyle(SquaredProminentButtonStyle(cornerRadius: 14))
            }
            .padding(20)
            .frame(maxWidth: 330)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
            .padding(.horizontal, 30)
        }
    }

    private func memberRow(_ member: Member) -> some View {
        let isTop = member.rank == 1
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        isTop
                            ? AnyShapeStyle(Color.yellow.opacity(0.18))
                            : AnyShapeStyle(AppTheme.accent.opacity(0.12))
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: member.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isTop ? .yellow : AppTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text("#\(member.rank)")
                .font(.system(.footnote, design: .rounded).weight(.heavy))
                .foregroundStyle(isTop ? .yellow : AppTheme.accent.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTop ? Color.yellow.opacity(0.08) : Color.clear)
        )
    }
}

// MARK: - Màn bảo trì (admin bật từ xa)

private struct MaintenanceView: View {
    var onRetry: () -> Void

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 24)

                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(AppTheme.accent)

                VStack(spacing: 8) {
                    Text(SStr.s("m0"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(SStr.s("m1"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(SStr.s("f2")) { onRetry() }
                    .buttonStyle(SquaredBorderedButtonStyle(cornerRadius: 14))

                if let discordURL = URL(string: LicenseConfig.discordURL) {
                    Link(destination: discordURL) {
                        Text(SStr.s("f5"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .underline()
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        }
        .tint(AppTheme.accent)
    }
}

// MARK: - Cổng ép cập nhật: bản cũ bị khóa, phải cài bản mới

private struct ForceUpdateView: View {
    let newVersion: String
    var onRetry: () -> Void

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 24)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppTheme.accent)

                VStack(spacing: 8) {
                    Text(SStr.s("f0"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Phiên bản \(AppUpdateChecker.currentVersion) đã cũ và không còn được hỗ trợ. Hãy cài phiên bản \(newVersion) để tiếp tục sử dụng.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    infoRow(label: SStr.s("f3"), value: newVersion)
                    infoRow(label: SStr.s("f4"), value: AppUpdateChecker.currentVersion)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                Button {
                    UIApplication.shared.open(AppUpdateChecker.installURL)
                } label: {
                    Label(SStr.s("f1"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SquaredProminentButtonStyle(cornerRadius: 14))

                Button(SStr.s("f2")) { onRetry() }
                    .font(.subheadline.weight(.medium))

                if let discordURL = URL(string: LicenseConfig.discordURL) {
                    Link(destination: discordURL) {
                        Text(SStr.s("f5"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .underline()
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        }
        .tint(AppTheme.accent)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct LoginView: View {
    var onSuccess: () -> Void

    @State private var licenseKey = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var successSession: LicenseSession?
    @State private var showingGetKey = false
    @State private var animateAmbient = false
    @State private var appeared = false
    @FocusState private var isFieldFocused: Bool

    // Bảng màu Trắng - Xanh nhạt Hiện đại (Light Cyan / Sky Blue Glassmorphism)
    private let bgTop = Color(red: 0.93, green: 0.96, blue: 1.00)       // #EEF5FF
    private let bgBottom = Color(red: 0.98, green: 0.99, blue: 1.00)    // #FAFCFF
    private let glowBlue = Color(red: 0.05, green: 0.48, blue: 0.98)    // #0C7BFA
    private let glowCyan = Color(red: 0.00, green: 0.75, blue: 0.95)    // #00BFF2
    private let textPrimary = Color(red: 0.08, green: 0.15, blue: 0.28) // Deep Navy
    private let textSecondary = Color(red: 0.40, green: 0.48, blue: 0.58)
    private let cardFill = Color.white.opacity(0.92)
    private let cardStroke = Color(red: 0.86, green: 0.92, blue: 0.98)
    private let fieldFill = Color(red: 0.95, green: 0.97, blue: 1.00)

    var body: some View {
        ZStack {
            backgroundLayers
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 32)

                    headerBlock
                        .offset(y: appeared ? 0 : -20)
                        .opacity(appeared ? 1 : 0)

                    keyCard
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)

                    signInButton
                        .offset(y: appeared ? 0 : 25)
                        .opacity(appeared ? 1 : 0)

                    actionRow
                        .offset(y: appeared ? 0 : 30)
                        .opacity(appeared ? 1 : 0)

                    versionFootnote
                        .opacity(appeared ? 1 : 0)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)

            if let session = successSession {
                successOverlay(session)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .sheet(isPresented: $showingGetKey) {
            GetKeySheet()
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                animateAmbient = true
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78, blendDuration: 0.2)) {
                appeared = true
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: successSession != nil)
    }

    // Nền trắng xanh nhạt chuyển màu + hiệu ứng quầng sáng xanh dịu
    private var backgroundLayers: some View {
        ZStack {
            LinearGradient(
                colors: [bgTop, bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geo in
                // Quầng sáng trên bên trái
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowBlue.opacity(0.18), glowCyan.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 280
                        )
                    )
                    .frame(width: 480, height: 480)
                    .position(
                        x: animateAmbient ? 40 : -40,
                        y: animateAmbient ? 160 : 100
                    )
                    .blur(radius: 30)

                // Quầng sáng dưới bên phải
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowCyan.opacity(0.20), glowBlue.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 260
                        )
                    )
                    .frame(width: 440, height: 440)
                    .position(
                        x: animateAmbient ? geo.size.width - 10 : geo.size.width + 50,
                        y: animateAmbient ? geo.size.height - 160 : geo.size.height - 100
                    )
                    .blur(radius: 30)
            }
            .allowsHitTesting(false)
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 14) {
            AppLogo(size: 88)

            VStack(spacing: 6) {
                Text("PrMods")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(textPrimary)

                Text("Bản Quyền iOS VIP")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(textSecondary)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [glowBlue, glowCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 52, height: 4)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LICENSE KEY")
                    .font(.caption2.weight(.bold))
                    .kerning(2.0)
                    .foregroundStyle(isFieldFocused ? glowBlue : textSecondary)
                    .animation(.easeInOut(duration: 0.2), value: isFieldFocused)

                Spacer()

                if !licenseKey.isEmpty {
                    Text("\(licenseKey.count) ký tự")
                        .font(.caption2.monospaced())
                        .foregroundStyle(textSecondary.opacity(0.7))
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isFieldFocused ? glowBlue : textSecondary.opacity(0.8))
                    .scaleEffect(isFieldFocused ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFieldFocused)

                TextField("Nhập License Key…", text: $licenseKey)
                    .focused($isFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .foregroundStyle(textPrimary)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .onSubmit(of: .text) { activate() }

                if !licenseKey.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            licenseKey = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: pasteFromClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                            Text(SStr.s("l1"))
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(glowBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(glowBlue.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFieldFocused
                            ? LinearGradient(colors: [glowBlue, glowCyan], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [cardStroke, cardStroke.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                        lineWidth: isFieldFocused ? 1.5 : 1.0
                    )
            )
            .shadow(color: isFieldFocused ? glowBlue.opacity(0.15) : .clear, radius: 8, y: 2)
            .animation(.easeInOut(duration: 0.22), value: isFieldFocused)

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 16, y: 8)
    }

    private var signInButton: some View {
        Button(action: activate) {
            HStack(spacing: 10) {
                if isWorking {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                }
                Text("ĐĂNG NHẬP")
                    .font(.body.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [glowBlue, glowCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: glowBlue.opacity(isWorking ? 0.20 : 0.40), radius: isWorking ? 6 : 14, y: 5)
        }
        .buttonStyle(SpringPressStyle(scale: 0.97))
        .disabled(isWorking)
        .padding(.top, 4)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                UIApplication.shared.open(LicenseConfig.supportURL)
            } label: {
                Label("Mua Key", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .foregroundStyle(textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(cardStroke, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
            }
            .buttonStyle(SpringPressStyle(scale: 0.96))

            Button {
                showingGetKey = true
            } label: {
                Label("Get Key Miễn Phí", systemImage: "gift.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .foregroundStyle(glowBlue)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(glowCyan.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(glowBlue.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(SpringPressStyle(scale: 0.96))
        }
    }

    private var versionFootnote: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("v\(AppUpdateChecker.currentVersion) · Online Secure")
                .font(.caption2.weight(.medium))
                .foregroundStyle(textSecondary.opacity(0.75))
        }
        .padding(.top, 4)
    }

    private func pasteFromClipboard() {
        guard let copied = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines), !copied.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            licenseKey = copied
        }
    }

    private func successOverlay(_ session: LicenseSession) -> some View {
        ZStack {
            Color.black.opacity(0.40)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(glowCyan.opacity(0.20))
                        .frame(width: 80, height: 80)
                        .blur(radius: 10)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [glowBlue, glowCyan],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: glowCyan.opacity(0.4), radius: 10, y: 3)
                }

                Text(SStr.s("l5"))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(textPrimary)

                VStack(alignment: .leading, spacing: 10) {
                    infoRow(label: "License key", value: maskedKey(session.licenseKey), monospaced: true)
                    infoRow(label: "Trạng thái", value: session.statusText)
                    infoRow(label: "Còn lại", value: session.remainingText)
                    if !session.expiresAt.isEmpty, session.remainingText != "Lifetime" {
                        infoRow(label: "Hết hạn", value: session.expiresAt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(cardStroke, lineWidth: 1)
                )

                Text("Đang vào ứng dụng…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(glowBlue)
                    .padding(.top, 4)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)
            .padding(.horizontal, 28)
        }
    }

    private func infoRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(textSecondary)
            Spacer()
            Text(value)
                .font(monospaced ? .footnote.monospaced().weight(.semibold) : .footnote.weight(.semibold))
                .foregroundStyle(textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return "••••" }
        return "\(key.prefix(4))••••\(key.suffix(4))"
    }

    private func activate() {
        guard !isWorking else { return }
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Vui lòng nhập license key."
            return
        }
        errorMessage = nil
        isWorking = true
        Task {
            do {
                let session = try await LicenseAuthService.validate(key: key)
                UserDefaults.standard.set(session.licenseKey, forKey: KV.licenseKey)
                UserDefaults.standard.set(session.remainingText, forKey: KV.licenseRemaining)
                UserDefaults.standard.set(session.statusText, forKey: KV.licenseStatus)
                UserDefaults.standard.set(session.expiresAt, forKey: KV.licenseExpires)
                UserDefaults.standard.set(
                    LicenseAuthService.sessionSignature(for: session.licenseKey),
                    forKey: KV.sessionSig
                )
                UserDefaults.standard.set(true, forKey: KV.loggedIn)
                await MainActor.run {
                    isWorking = false
                    successSession = session
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        onSuccess()
                    }
                }
            } catch LicenseError.rejected(let message) {
                await MainActor.run {
                    isWorking = false
                    errorMessage = message
                }
            } catch LicenseError.network(let message) {
                await MainActor.run {
                    isWorking = false
                    errorMessage = message
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = "Đăng nhập thất bại. Thử lại sau."
                }
            }
        }
    }
}

// MARK: - Sheet Get Key: vượt 2 link Link4M → key dùng thử 1 ngày

private struct GetKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var completedStep = 0
    @State private var waitRemaining = 0
    @State private var copied = false
    @State private var waitTimer: Timer?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    stepRow(step: 1, title: "Vượt liên kết rút gọn thứ nhất", unlocked: true)
                    stepRow(
                        step: 2,
                        title: "Vượt liên kết rút gọn thứ hai",
                        unlocked: completedStep >= 1 && waitRemaining == 0
                    )
                    submitSection
                    Text("Key Admin cấp sẽ dán vào ô KEY ở màn hình đăng nhập.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .navigationTitle("Get Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
        .onDisappear { waitTimer?.invalidate() }
    }

    private var headerCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "gift.fill")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.accent)
            Text("Nhận key miễn phí")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Vượt đủ 2 liên kết rút gọn Link4M (nhớ bật quay màn hình từ đầu để làm bằng chứng), rồi gửi video cho Admin để nhận key dùng thử 1 ngày. Mỗi máy chỉ nhận 1 key mỗi ngày.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func stepRow(step: Int, title: String, unlocked: Bool) -> some View {
        let done = completedStep >= step
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.16) : Color(uiColor: .tertiarySystemFill))
                    .frame(width: 34, height: 34)
                Image(systemName: done ? "checkmark" : "\(step).circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(done ? Color.green : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Bước \(step)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            if done {
                Text("Xong")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            } else if unlocked {
                Button("Mở") { openLink(step) }
                    .buttonStyle(.bordered)
                    .font(.footnote.weight(.semibold))
            } else if waitRemaining > 0 {
                Text("Chờ \(waitRemaining)s…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Làm bước \(step - 1) trước")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // Bước 3: người dùng quay màn hình lúc vượt 2 link làm bằng chứng rồi gửi
    // cho Admin qua kênh liên hệ u10; Admin xem xong tự phát key thủ công.
    // Không còn đổi key tự động trong app — không có gì để lách bằng cách
    // bấm chờ hay đoán mã nữa.
    private var submitSection: some View {
        let ready = completedStep >= 2 && waitRemaining == 0
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(ready ? Color.green.opacity(0.16) : Color(uiColor: .tertiarySystemFill))
                        .frame(width: 34, height: 34)
                    Image(systemName: ready ? "checkmark" : "3.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ready ? Color.green : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bước 3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Gửi video chứng minh cho Admin")
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )

            Text("Bật quay màn hình TRƯỚC khi vượt link: vuốt xuống mở Trung Tâm Điều Khiển → chạm nút ⏺. Vượt đủ 2 link rồi quay lại đây, sao chép tin nhắn bên dưới, đính kèm video và gửi cho Admin iqv trên Discord.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = adminMessage
                copied = true
            } label: {
                Label(
                    copied ? "Đã sao chép tin nhắn" : "Sao Chép Tin Nhắn Gửi Admin",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
                .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Button {
                if let url = LicenseConfig.adminContactURL {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                    Text("Gửi Video Cho Admin iqv")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SquaredProminentButtonStyle(cornerRadius: 14))
            .disabled(!ready || LicenseConfig.adminContactURL == nil)

            if !ready {
                Text(completedStep < 2 ? "Hoàn tất cả 2 bước liên kết trước khi gửi video." : "Vui lòng đợi…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // Nội dung tin nhắn mẫu — Admin iqv dựa vào MÃ MÁY để tra máy, video để xác nhận vượt link.
    private var adminMessage: String {
        """
        XIN KEY MIỄN PHÍ - PrMods (gửi Admin TrinhTu)
        • Đã vượt đủ 2 link Get Key trong app
        • Video quay màn hình lúc vượt link: đính kèm
        • Mã máy: \(LicenseAuthService.hardwareID())
        Admin TrinhTu kiểm tra xong cho em xin key 1 ngày với ạ!
        """
    }

    private func openLink(_ step: Int) {
        guard completedStep >= step - 1 else { return }
        let url = step == 1 ? LicenseConfig.getKeyStep1URL : LicenseConfig.getKeyStep2URL
        UIApplication.shared.open(url)
        completedStep = max(completedStep, step)
        startWait(FreeKeyService.stepWaitSeconds)
    }

    private func startWait(_ seconds: Int) {
        waitTimer?.invalidate()
        waitRemaining = seconds
        waitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if waitRemaining > 0 {
                waitRemaining -= 1
            }
            if waitRemaining <= 0 {
                timer.invalidate()
            }
        }
    }
}
