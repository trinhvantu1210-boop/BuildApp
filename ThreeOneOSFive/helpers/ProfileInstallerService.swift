import Foundation
import Network
import UIKit
import SwiftUI

// MARK: - Profile Installer Service (Cài đặt Hồ sơ Cấu hình DNS AntiBan HZZ)
//
// Dịch vụ khởi chạy Local Web Server nội bộ (sử dụng pure Network.framework NWListener)
// để phục vụ file .mobileconfig với MIME type chuẩn của Apple: `application/x-apple-aspen-config`.
// Khi người dùng bấm cài đặt, app tự động mở Safari tải hồ sơ và chuyển tiếp vào Cài đặt iOS.

@MainActor
final class ProfileInstallerService: ObservableObject {
    static let shared = ProfileInstallerService()

    @Published public private(set) var isServerRunning = false
    @Published public private(set) var lastErrorMessage: String? = nil
    @Published public var showGuideSheet: Bool = false
    @Published public private(set) var downloadTriggered: Bool = false

    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var stopTimerTask: Task<Void, Never>? = nil
    private let portNumber: UInt16 = 18888

    // Nội dung profile mặc định từ AntiBan AimLock HZZ
    static let defaultProfileXML: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>PayloadDescription</key>
        <string>By Hungzizc</string>
        <key>PayloadDisplayName</key>
        <string>AntiBan AimLock HZZ</string>
        <key>PayloadIdentifier</key>
        <string>com.jerrymod.antiban.d37388</string>
        <key>PayloadType</key>
        <string>Configuration</string>
        <key>PayloadUUID</key>
        <string>F1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
        <key>PayloadContent</key>
        <array>
            <dict>
                <key>PayloadDisplayName</key>
                <string>AntiBan AimLock HZZ (DNS)</string>
                <key>PayloadIdentifier</key>
                <string>com.jerrymod.antiban.d37388.dns</string>
                <key>PayloadType</key>
                <string>com.apple.dnsSettings.managed</string>
                <key>PayloadUUID</key>
                <string>23456789-ABCD-EF01-2345-6789ABCDEF02</string>
                <key>PayloadVersion</key>
                <integer>1</integer>
                <key>DNSSettings</key>
                <dict>
                    <key>DNSProtocol</key>
                    <string>HTTPS</string>
                    <key>ServerURL</key>
                    <string>https://dns.nextdns.io/d37388</string>
                </dict>
                <key>OnDemandRules</key>
                <array>
                    <dict>
                        <key>Action</key>
                        <string>Connect</string>
                        <key>InterfaceTypeMatch</key>
                        <string>Cellular</string>
                    </dict>
                    <dict>
                        <key>Action</key>
                        <string>Connect</string>
                        <key>InterfaceTypeMatch</key>
                        <string>WiFi</string>
                    </dict>
                </array>
            </dict>
        </array>
    </dict>
    </plist>
    """

    private init() {}

    // Lấy dữ liệu file .mobileconfig (ưu tiên file bundle hoặc dùng chuỗi nhúng)
    func getProfileData() -> Data {
        if let bundleURL = Bundle.main.url(forResource: "AntiBanAim", withExtension: "mobileconfig"),
           let data = try? Data(contentsOf: bundleURL) {
            return data
        }
        return Self.defaultProfileXML.data(using: .utf8) ?? Data()
    }

    // Khởi chạy server và kích hoạt cài đặt 1-chạm
    func startAndInstall() {
        lastErrorMessage = nil
        downloadTriggered = false
        showGuideSheet = true

        startLocalServer { [weak self] success in
            guard let self = self else { return }
            if success {
                self.openSafariForDownload()
            }
        }
    }

    // Mở Safari tới URL server nội bộ để kích hoạt tải cấu hình
    private func openSafariForDownload() {
        guard let url = URL(string: "http://127.0.0.1:\(portNumber)/AntiBan_AimLock_HZZ.mobileconfig") else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                if success {
                    self?.downloadTriggered = true
                } else {
                    self?.lastErrorMessage = "Không thể mở trình duyệt Safari. Hãy đảm bảo Safari không bị giới hạn."
                }
            }
        }
    }

    // Mở ứng dụng Cài đặt iOS để kích hoạt hồ sơ đã tải
    func openSettingsProfile() {
        // Cố gắng mở thẳng mục Quản lý cấu hình & VPN
        let prefsURLs = [
            "App-Prefs:root=General&path=ManagedConfigurationList",
            "App-prefs:root=General&path=ManagedConfigurationList",
            "prefs:root=General&path=ManagedConfigurationList",
            UIApplication.openSettingsURLString
        ]

        for path in prefsURLs {
            if let url = URL(string: path), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }

        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
        }
    }

    // Khởi động HTTP Server nội bộ với NWListener
    private func startLocalServer(completion: @escaping (Bool) -> Void) {
        stopServer()

        do {
            let tcpOptions = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true

            guard let nwPort = NWEndpoint.Port(rawValue: portNumber) else {
                lastErrorMessage = "Cổng kết nối không hợp lệ"
                completion(false)
                return
            }

            listener = try NWListener(using: params, on: nwPort)
        } catch {
            lastErrorMessage = "Không thể khởi tạo dịch vụ cấu hình: \(error.localizedDescription)"
            completion(false)
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isServerRunning = true
                    self.scheduleAutoStop()
                    completion(true)
                case .failed(let err):
                    self.isServerRunning = false
                    self.lastErrorMessage = "Lỗi dịch vụ mạng: \(err.localizedDescription)"
                    completion(false)
                case .cancelled:
                    self.isServerRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleIncomingConnection(connection)
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    // Xử lý Request HTTP từ Safari và trả về MIME type Apple profile
    private func handleIncomingConnection(_ connection: NWConnection) {
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state, let conn = connection {
                Task { @MainActor in
                    self?.activeConnections.removeAll { $0 === conn }
                }
            } else if case .cancelled = state, let conn = connection {
                Task { @MainActor in
                    self?.activeConnections.removeAll { $0 === conn }
                }
            }
        }

        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, isComplete, _ in
            guard let self = self, let conn = connection else { return }

            let profileData = self.getProfileData()
            let headers = [
                "HTTP/1.1 200 OK",
                "Content-Type: application/x-apple-aspen-config; charset=utf-8",
                "Content-Disposition: attachment; filename=\"AntiBan_AimLock_HZZ.mobileconfig\"",
                "Content-Length: \(profileData.count)",
                "Cache-Control: no-cache, no-store, must-revalidate",
                "Pragma: no-cache",
                "Expires: 0",
                "Connection: close",
                "\r\n"
            ].joined(separator: "\r\n")

            guard let headerData = headers.data(using: .utf8) else {
                conn.cancel()
                return
            }

            var fullResponse = Data()
            fullResponse.append(headerData)
            fullResponse.append(profileData)

            conn.send(content: fullResponse, completion: .contentProcessed { [weak conn] _ in
                conn?.cancel()
            })
        }
    }

    // Tự động tắt server sau 90 giây để tiết kiệm pin và tài nguyên
    private func scheduleAutoStop() {
        stopTimerTask?.cancel()
        stopTimerTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    self.stopServer()
                }
            }
        }
    }

    func stopServer() {
        stopTimerTask?.cancel()
        stopTimerTask = nil
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        listener?.cancel()
        listener = nil
        isServerRunning = false
    }

    // Chia sẻ file .mobileconfig ra ngoài qua Share Sheet (Files / AirDrop / Tin nhắn)
    func exportProfileFile(from viewController: UIViewController? = nil) {
        let profileData = getProfileData()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("AntiBan_AimLock_HZZ.mobileconfig")
        try? profileData.write(to: tempURL)

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        
        let rootVC = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController

        if let popover = activityVC.popoverPresentationController, let root = rootVC {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        rootVC?.present(activityVC, animated: true)
    }
}
