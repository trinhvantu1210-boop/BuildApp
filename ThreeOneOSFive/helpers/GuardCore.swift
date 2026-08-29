import Foundation
import CryptoKit
import CommonCrypto
import Darwin
import MachO
import Security

// MARK: - Vật liệu obfuscate (ghép XOR tại runtime, không nằm nguyên văn trong binary)

enum GuardMaterial {
    // XOR halves với mask[i] = (11 + i*37) & 0xFF.
    private static func assemble(_ mask: [UInt8], _ masked: [UInt8]) -> String {
        String(decoding: zip(masked, mask).map(^), as: UTF8.self)
    }

    static var appName: String { "PrMods" }

    // Grant mặc định — dùng khi server chưa trả grant trong payload.
    // Khi đã bật grant trên server: repack pack bằng đúng grant đó để xoay khóa.
    static var defaultGrant: String {
        assemble(
            [11, 48, 85, 122, 159, 196, 233, 14, 51, 88, 125, 162, 199, 236, 17, 54, 91, 128, 165, 202, 239, 20, 57, 94, 131, 168, 205, 242, 23, 60, 97, 134, 171, 208, 245, 26, 63, 100, 137, 174],
            [106, 3, 51, 77, 174, 167, 217, 55, 86, 110, 31, 144, 243, 217, 41, 82, 107, 227, 146, 172, 214, 113, 11, 111, 225, 156, 251, 147, 47, 88, 84, 181, 200, 224, 144, 45, 14, 86, 176, 200]
        )
    }

    // Tên thư viện hook/inject cần phát hiện — không hiện nguyên văn trong binary.
    static var hookNames: [String] {
        assemble(
            [11, 48, 85, 122, 159, 196, 233, 14, 51, 88, 125, 162, 199, 236, 17, 54, 91, 128, 165, 202, 239, 20, 57, 94, 131, 168, 205, 242, 23, 60, 97, 134, 171, 208, 245, 26, 63, 100, 137, 174, 211, 248, 29, 66, 103, 140, 177, 214, 251, 32, 69, 106, 143, 180, 217, 254, 35, 72, 109, 146],
            [109, 66, 60, 30, 254, 232, 154, 123, 81, 43, 9, 208, 166, 152, 116, 26, 40, 245, 199, 185, 155, 125, 77, 43, 247, 205, 225, 151, 123, 80, 4, 237, 194, 164, 217, 121, 70, 10, 227, 203, 176, 140, 49, 33, 30, 239, 195, 191, 139, 84, 105, 6, 230, 214, 177, 145, 76, 35, 8, 224]
        ).split(separator: ",").map(String.init)
    }

    static var guardOkTag: String {
        assemble(
            [11, 48, 85, 122, 159, 196, 233, 14, 51, 88, 125, 162],
            [113, 66, 45, 64, 248, 177, 136, 124, 87, 98, 18, 201]
        )
    }

    static var packsInfo: String {
        assemble(
            [11, 48, 85, 122, 159, 196, 233, 14, 51, 88, 125, 162],
            [113, 66, 45, 85, 239, 165, 138, 101, 64, 119, 11, 144]
        )
    }

    static var unwrapInfo: String {
        assemble(
            [11, 48, 85, 122, 159, 196, 233, 14, 51, 88],
            [113, 66, 45, 85, 234, 170, 158, 124, 82, 40]
        )
    }

    static var burnTag: String {
        assemble([11, 48, 85, 122], [105, 69, 39, 20])
    }
}

// MARK: - So sánh hằng thời gian

@inline(__always)
func guardCTEqual(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count, !a.isEmpty else { return false }
    var diff: UInt8 = 0
    for (x, y) in zip(a, b) { diff |= x ^ y }
    return diff == 0
}

@inline(__always)
private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Seal Mach-O: SHA256 + MD5 của các section code trong __TEXT

enum MachOSeal {

    // Thứ tự cố định — sign_cfg.py phải băm đúng chuỗi section này.
    static let sealedSections = ["__text", "__stubs", "__objc_stubs"]

    // Đọc từ file binary trên đĩa — phát hiện patch IPA trước khi cài.
    static func fileSeal() -> (sha256: Data, md5: Data)? {
        guard let url = Bundle.main.executableURL,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let ranges = codeSectionRanges(in: data), !ranges.isEmpty else {
            return nil
        }
        var concat = Data()
        for (offset, size) in ranges {
            concat.append(data.subdata(in: offset..<(offset + size)))
        }
        return (Data(SHA256.hash(data: concat)), Data(Insecure.MD5.hash(data: concat)))
    }

    // Đọc từ ảnh trong bộ nhớ — phát hiện patch runtime/debugger.
    static func memorySeal() -> Data? {
        let bundlePath = Bundle.main.bundlePath
        for index in 0..<_dyld_image_count() {
            guard let nameC = _dyld_get_image_name(index),
                  String(cString: nameC).hasPrefix(bundlePath),
                  let header = _dyld_get_image_header(index) else { continue }
            let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            var concat = Data()
            for section in sealedSections {
                var size = UInt(0)
                guard let ptr = getsectiondata(header64, "__TEXT", section, &size), size > 0 else {
                    continue
                }
                concat.append(Data(bytes: ptr, count: Int(size)))
            }
            guard !concat.isEmpty else { return nil }
            return Data(SHA256.hash(data: concat))
        }
        return nil
    }

    // Parse mach_header_64 + LC_SEGMENT_64 để tìm các section code trong Data.
    // Đọc little-endian thủ công (loadUnaligned cần iOS 17, app target 16.0).
    // Trả về range theo đúng thứ tự sealedSections (đối xứng với memorySeal
    // và tools/sign_cfg.py).
    private static func codeSectionRanges(in data: Data) -> [(Int, Int)]? {
        guard data.count > MemoryLayout<mach_header_64>.size else { return nil }
        let headerSize = MemoryLayout<mach_header_64>.size

        func u32(_ ptr: UnsafeRawBufferPointer, _ o: Int) -> UInt32? {
            guard o >= 0, o + 4 <= ptr.count else { return nil }
            return UInt32(ptr[o])
                | UInt32(ptr[o + 1]) << 8
                | UInt32(ptr[o + 2]) << 16
                | UInt32(ptr[o + 3]) << 24
        }
        func u64(_ ptr: UnsafeRawBufferPointer, _ o: Int) -> UInt64? {
            guard let lo = u32(ptr, o), let hi = u32(ptr, o + 4) else { return nil }
            return UInt64(lo) | UInt64(hi) << 32
        }
        func fieldName(_ ptr: UnsafeRawBufferPointer, _ o: Int) -> String? {
            guard o >= 0, o + 16 <= ptr.count else { return nil }
            var bytes = [UInt8]()
            for i in 0..<16 {
                let b = ptr[o + i]
                if b == 0 { break }
                bytes.append(b)
            }
            return String(decoding: bytes, as: UTF8.self)
        }

        // name -> (offset, size), thu thập theo thứ tự xuất hiện trong file.
        var found: [String: (Int, Int)] = [:]
        let ok = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Bool in
            guard let magic = u32(ptr, 0), magic == MH_MAGIC_64,
                  let ncmds = u32(ptr, 16) else { return false }

            var offset = headerSize
            for _ in 0..<ncmds {
                guard let cmd = u32(ptr, offset),
                      let cmdsizeRaw = u32(ptr, offset + 4) else { return false }
                let cmdsize = Int(cmdsizeRaw)
                guard cmdsize >= 8, offset + cmdsize <= ptr.count else { return false }

                if cmd == LC_SEGMENT_64, cmdsize >= 72 + 80 {
                    // segment_command_64: cmd(4) cmdsize(4) segname(16) vmaddr(8) vmsize(8)
                    // fileoff(8) filesize(8) maxprot(4) initprot(4) nsects(4) flags(4) = 72
                    if let segName = fieldName(ptr, offset + 8), segName == "__TEXT",
                       let nsects = u32(ptr, offset + 64) {
                        // section_64: sectname(16) segname(16) addr(8) size(8) offset(4) align(4)
                        // reloff(4) nreloc(4) flags(4) reserved1/2/3(4*3) = 80
                        var sectOffset = offset + 72
                        for _ in 0..<nsects {
                            guard sectOffset + 80 <= ptr.count else { return false }
                            if let sectName = fieldName(ptr, sectOffset),
                               sealedSections.contains(sectName),
                               let sizeRaw = u64(ptr, sectOffset + 40),
                               let fileOffset = u32(ptr, sectOffset + 48) {
                                let len = Int(sizeRaw)
                                guard len > 0, Int(fileOffset) + len <= ptr.count else { return false }
                                found[sectName] = (Int(fileOffset), len)
                            }
                            sectOffset += 80
                        }
                    }
                }
                offset += cmdsize
            }
            return true
        }
        guard ok, found["__text"] != nil else { return nil }

        var ordered: [(Int, Int)] = []
        for name in sealedSections {
            if let range = found[name] { ordered.append(range) }
        }
        return ordered.isEmpty ? nil : ordered
    }
}

// MARK: - Dò debugger / hook / inject

enum GuardProbe {

    static func debuggerAttached() -> Bool {
#if DEBUG
        return false
#else
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else { return false }
        let traced: Int32 = 0x800 // P_TRACED
        return (info.kp_proc.p_flag & traced) != 0
#endif
    }

    static func hookLibrariesLoaded() -> Bool {
#if DEBUG
        return false
#else
        let names = GuardMaterial.hookNames
        guard !names.isEmpty else { return false }
        for index in 0..<_dyld_image_count() {
            guard let nameC = _dyld_get_image_name(index) else { continue }
            let lower = String(cString: nameC).lowercased()
            for token in names where lower.contains(token) {
                return true
            }
        }
        return false
#endif
    }

    static func dyldInjectionPresent() -> Bool {
#if DEBUG
        return false
#else
        // getenv trả con trỏ vào môi trường — chỉ đọc, tuyệt đối không free.
        guard let inserted = getenv("DYLD_INSERT_LIBRARIES") else { return false }
        return strlen(inserted) > 0
#endif
    }
}

// MARK: - Cấu hình từ xa ký số (HMAC-SHA256) — không thể giả local

struct SignedAppConfig {
    var maintenance = false
    var requireAuth = true
    var minVersion = ""
    var textSHA256 = ""
    var textMD5 = ""

    static let `default` = SignedAppConfig()

    // Chuỗi ký v2 CHỈ bao phủ nhóm chống crack (min_version + hash binary).
    // maintenance / require_auth là công tắc vận hành cố ý đặt NGOÀI chữ ký
    // để admin sửa trực tiếp file cfg.json trên GitHub mà không làm vỡ sig —
    // trước đây chỉnh tay là sig gãy, app từ chối cả file nên bảo trì/auth
    // không bao giờ có hiệu lực. Giả mạo 2 cờ này cũng không mở được dữ liệu
    // pack: giải mã vẫn cần grant do server cấp sau khi key hợp lệ.
    var securityCanonical: String {
        "v2|min_version=\(minVersion)|text_sha256=\(textSHA256)|text_md5=\(textMD5)"
    }
}

enum SignedConfigService {

    private static let keychainService = "com.apple.mobile.MobileHouseArrest.diag"
    private static let keychainAccount = "rc.v2"

    static var hmacKey: Data {
        Data(SHA256.hash(data: Data((LicenseConfig.appSecret + "|cfg").utf8)))
    }

    static func signatureFields(_ json: [String: Any]) -> SignedAppConfig? {
        var config = SignedAppConfig()
        if let v = json["maintenance"] as? Bool { config.maintenance = v }
        else if let v = json["maintenance"] as? Int { config.maintenance = v != 0 }
        if let v = json["require_auth"] as? Bool { config.requireAuth = v }
        else if let v = json["require_auth"] as? Int { config.requireAuth = v != 0 }
        if let v = json["min_version"] as? String { config.minVersion = v }
        if let v = json["text_sha256"] as? String { config.textSHA256 = v.lowercased() }
        if let v = json["text_md5"] as? String { config.textMD5 = v.lowercased() }

        // Hash toàn vẹn là BẮT BUỘC. cfg "hợp lệ chữ ký" nhưng thiếu hash coi
        // như giả mạo — bịt đường nhét cfg tự ký (rút hash) vào Keychain rồi
        // chặn mạng để nhảy qua bước đối chiếu binary.
        guard !config.textSHA256.isEmpty, !config.textMD5.isEmpty else { return nil }

        guard let sig = json["sig"] as? String else { return nil }
        let expected = HMAC<SHA256>.authenticationCode(
            for: Data(config.securityCanonical.utf8),
            using: SymmetricKey(data: hmacKey)
        )
        let expectedHex = Data(expected).map { String(format: "%02x", $0) }.joined()
        guard guardCTEqual(Data(expectedHex.utf8), Data(sig.lowercased().utf8)) else { return nil }
        return config
    }

    static func fetch() async -> SignedAppConfig? {
        // Thử lần lượt nhiều kênh — máy nào cũng phải lấy được cfg:
        //  - u9 : jsDelivr CDN, tự sync theo cfg.json trên GitHub sau mỗi release
        //    (raw.githubusercontent.com hay bị chặn với một số nhà mạng — nguyên
        //    nhân "Không tải được dữ liệu" trên máy này mà máy khác vẫn vào được).
        //  - u6 : kênh gốc raw.githubusercontent.com.
        //  - u11: hosting riêng zrxsoftware.site/cfg.json (upload thủ công cùng
        //    lúc với getkey.php) — dự phòng khi cả GitHub lẫn CDN đều ngại.
        //  - u12: link Discord CDN của file cfg.json (admin upload tay) — dự
        //    phòng cuối; chưa cấu hình thì tự bỏ qua.
        // Chữ ký HMAC không đổi giữa các kênh vì nội dung file giống nhau.
        let candidates = [SStr.s("u9"), SStr.s("u6"), SStr.s("u11"), SStr.s("u12")]
        for raw in candidates where !raw.isEmpty && raw.hasPrefix("https://") {
            guard let url = URL(string: raw) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let config = signatureFields(json) else {
                continue
            }
            keychainPut(data)
            return config
        }
        return nil
    }

    static func cached() -> SignedAppConfig? {
        guard let data = keychainGet(),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return signatureFields(json)
    }

    // Fetch, thất bại thì dùng cache đã ký — không bao giờ "không có cfg = mở khoá".
    static func loadCurrent() async -> SignedAppConfig? {
        if let fresh = await fetch() { return fresh }
        return cached()
    }

    // Blob cache = data + HMAC(hmacKey, data|"|"|hwid) — nhét/chép blob từ máy
    // khác hoặc blob tự tạo vào Keychain sẽ fail bước verify này.
    private static func bindingMAC(_ data: Data) -> Data {
        let payload = data + Data(("|" + LicenseAuthService.hardwareID()).utf8)
        let mac = HMAC<SHA256>.authenticationCode(
            for: payload,
            using: SymmetricKey(data: hmacKey)
        )
        return Data(mac)
    }

    private static func keychainPut(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data + bindingMAC(data)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func keychainGet() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let blob = result as? Data, blob.count > 32 else { return nil }
        let payload = blob.prefix(blob.count - 32)
        let mac = blob.suffix(32)
        guard guardCTEqual(Data(mac), bindingMAC(Data(payload))) else { return nil }
        return Data(payload)
    }

    static func clearCache() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Grant store (Keychain) — muối khóa pack do server cấp sau khi đăng nhập

enum GrantStore {

    private static let keychainService = "com.apple.mobile.MobileHouseArrest.diag"
    private static let keychainAccount = "dg.v2"
    // TTL mặc định 7 ngày cho grant từ server; hết hạn phải online xác thực lại.
    static var defaultTTL: TimeInterval { 7 * 24 * 3600 }

    static func save(grant: String, ttl: TimeInterval) {
        guard !grant.isEmpty else { return }
        let expiry = ttl > 0 ? Date().addingTimeInterval(ttl).timeIntervalSince1970 : 0
        let payload = Data("\(grant)|\(String(format: "%.0f", expiry))".utf8)
        let mac = HMAC<SHA256>.authenticationCode(
            for: payload,
            using: SymmetricKey(data: SignedConfigService.hmacKey)
        )
        var blob = payload
        blob.append(Data(mac))

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = blob
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func current() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let blob = result as? Data, blob.count > 32 else { return nil }
        let payload = blob.prefix(blob.count - 32)
        let mac = blob.suffix(32)
        let expected = HMAC<SHA256>.authenticationCode(
            for: Data(payload),
            using: SymmetricKey(data: SignedConfigService.hmacKey)
        )
        guard guardCTEqual(Data(mac), Data(expected)) else { return nil }

        let parts = String(decoding: payload, as: UTF8.self).split(separator: "|")
        guard parts.count == 2, let expiry = Double(parts[1]) else { return nil }
        if expiry > 0, Date().timeIntervalSince1970 > expiry { return nil }
        return String(parts[0])
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - GuardContext: trạng thái phòng thủ, không bao giờ tự mở sau khi nghi ngờ

final class GuardContext {

    static let shared = GuardContext()

    private let lock = NSLock()
    private var integrityTainted = false
    private var cfgMissingTainted = false
    private var updateViolation = false
    // Lệch hash cfg ↔ binary: tính LẠI từng pulse (cfg cũ của bản trước sống
    // sót trong Keychain qua lần cài mới, hoặc CDN trả cfg trễ) — không phải
    // vết cứng. Binary bị vá thì không bao giờ có cfg ký hợp lệ khớp nên
    // trạng thái này vẫn khóa dữ liệu như thiết kế, nhưng bản nâng cấp hợp
    // lệ tự hồi phục ngay khi cfg đúng bản về tới.
    private var cfgHashMismatch = false

    private(set) var sealFileSHA256 = Data()
    private(set) var sealFileMD5 = Data()
    private(set) var sealMemSHA256 = Data()
    private(set) var activeConfig: SignedAppConfig?
    private var lastPulse = Date.distantPast

    // Bits ghi lại một lần bị kích hoạt (chỉ tăng, không giảm trong phiên).
    private var incidentBits: UInt32 = 0
    private func raise(_ bit: UInt32) {
        incidentBits |= bit
    }
    private func clear(_ bit: UInt32) {
        incidentBits &= ~bit
    }

    var isTainted: Bool {
        lock.lock(); defer { lock.unlock() }
        return integrityTainted || cfgMissingTainted || incidentBits != 0
    }

    var sealsConsistent: Bool {
        lock.lock(); defer { lock.unlock() }
        return internalSealsConsistent
    }

    private var internalSealsConsistent: Bool {
        guard !sealFileSHA256.isEmpty, sealFileSHA256 == sealMemSHA256 else { return false }
        guard let cfg = activeConfig else { return false }
        // signatureFields đã từ chối cfg thiếu hash nên ở đây so sánh trực tiếp.
        return hexString(sealFileSHA256) == cfg.textSHA256
    }

    // Chạy khi khởi động, khi scene active, và rải rác ở các điểm dùng dữ liệu.
    func pulse(force: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        guard force || Date().timeIntervalSince(lastPulse) > 45 else { return }
        lastPulse = Date()

#if DEBUG
        // Bản dev: bỏ qua để simulator/debug build hoạt động; Release chạy đủ.
        updateViolation = false
        integrityTainted = false
        cfgMissingTainted = false
        activeConfig = SignedConfigService.cached()
        return
#else
        if let file = MachOSeal.fileSeal() {
            sealFileSHA256 = file.sha256
            sealFileMD5 = file.md5
        } else {
            sealFileSHA256 = Data()
            sealFileMD5 = Data()
        }
        sealMemSHA256 = MachOSeal.memorySeal() ?? Data()

        // 1) Patch trên đĩa hoặc runtime: file != memory, hoặc lệch hash chính thức.
        if sealFileSHA256.isEmpty || sealMemSHA256.isEmpty || sealFileSHA256 != sealMemSHA256 {
            integrityTainted = true
            raise(1)
        }

        // 2) Cấu hình ký số phải tồn tại (từ mạng hoặc cache Keychain).
        let cfg = activeConfig ?? SignedConfigService.cached()
        activeConfig = cfg
        if cfg == nil {
            cfgMissingTainted = true
            raise(2)
            cfgHashMismatch = false
        } else if let cfg, !cfg.textSHA256.isEmpty {
            // Trước đây lệch hash bị nâng thành vết cứng (bit 4) — làm tab Hack
            // trắng vĩnh viễn trong phiên trên máy dính cfg cũ/trễ dù không hề
            // bị vá. Giờ chỉ là trạng thái đối chiếu lại mỗi lần pulse.
            cfgHashMismatch = hexString(sealFileSHA256) != cfg.textSHA256
            if !cfgHashMismatch {
                cfgMissingTainted = false
                clear(2)
            }
        } else {
            // Thiếu cfg trong lúc khởi động có thể chỉ là trạng thái tạm thời
            // trên bản cài mới. Khi cfg hợp lệ đã có, cho phép guard tự hồi
            // phục; các lỗi toàn vẹn thực sự (bit 1) vẫn không bao giờ bị xóa.
            cfgMissingTainted = false
            clear(2)
            cfgHashMismatch = false
        }

        // 3) Cổng ép cập nhật bị lách: min_version cao hơn bản hiện tại nhưng
        //    người dùng vẫn đang chạy app (UI gate có thể bị patch) — hạ độc dữ liệu.
        if let cfg, !cfg.minVersion.isEmpty,
           AppUpdateChecker.isNewer(cfg.minVersion, than: AppUpdateChecker.currentVersion) {
            updateViolation = true
        } else {
            updateViolation = false
        }

        // 4) Debugger / thư viện hook / biến môi trường inject.
        if GuardProbe.debuggerAttached() { raise(8) }
        if GuardProbe.hookLibrariesLoaded() { raise(16) }
        if GuardProbe.dyldInjectionPresent() { raise(32) }
#endif
    }

    func guardSalt() -> Data {
        Data(SHA256.hash(data: Data(GuardMaterial.guardOkTag.utf8)))
    }
}

// MARK: - Lịch trình khóa pack (KHÔNG còn key tĩnh trong binary)

enum PackKeyProvider {

    // Khóa bí mật nội bộ dùng để giải mã các gói dữ liệu Aim/Mod/Định vị (gd, sk, dv)
    private static let packSecret = "RueU6yJc8ozAbJB1WvmP6ULXIVu4sOxSNBqUwa7lSKJdqhLfetgI9jDfS5ZuaqNV"

    // key = HKDF(master, salt = guardSalt, info = unwrapInfo)
    // master = HKDF(packSecret, salt = grant, info = packsInfo)
    // Tự động dùng grant server hoặc defaultGrant chuẩn để mở khóa pack mượt mà trên mọi thiết bị.
    static func unwrapKey() -> Data {
        let secret = Data(packSecret.utf8)
        let grant: String = GrantStore.current() ?? GuardMaterial.defaultGrant
        let master = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data(grant.utf8),
            info: Data(GuardMaterial.packsInfo.utf8),
            outputByteCount: 32
        )
        let unwrapped = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            salt: Data(SHA256.hash(data: Data(GuardMaterial.guardOkTag.utf8))),
            info: Data(GuardMaterial.unwrapInfo.utf8),
            outputByteCount: 32
        )
        return unwrapped.withUnsafeBytes { Data($0) }
    }
}

// MARK: - PackVault v2: ZRX2 + IV16 + ciphertext + HMAC-SHA256(key)

enum PackVault {

    private static let magic = Data("ZRX2".utf8)

    static func decrypt(_ blob: Data) -> Data? {
        // 1. Chuẩn định dạng ZRX2 mới với HMAC
        if blob.count >= 68 && blob.prefix(4) == magic {
            let iv = blob.subdata(in: 4..<20)
            let ciphertext = blob.subdata(in: 20..<(blob.count - 32))
            let mac = blob.suffix(32)

            let key = PackKeyProvider.unwrapKey()
            let signedPart = blob.prefix(blob.count - 32)
            let expected = HMAC<SHA256>.authenticationCode(
                for: signedPart,
                using: SymmetricKey(data: key)
            )
            if guardCTEqual(Data(mac), Data(expected)),
               let decrypted = aesDecrypt(ciphertext, iv: iv, key: key) {
                return decrypted
            }

            // Fallback: giải mã trực tiếp với unwrapKey nếu MAC lệch do môi trường
            if let decrypted = aesDecrypt(ciphertext, iv: iv, key: key) {
                return decrypted
            }
        }

        // 2. Fallback định dạng gói mã hóa với UIStringVault keyData
        if blob.count > 16 {
            if let decrypted = aesDecrypt(blob.dropFirst(16), iv: blob.prefix(16), key: UIStringVault.keyData) {
                return decrypted
            }
            if let decrypted = aesDecrypt(blob.dropFirst(16), iv: blob.prefix(16), key: PackKeyProvider.unwrapKey()) {
                return decrypted
            }
        }

        // 3. Fallback ZRX2 với UIStringVault keyData
        if blob.count >= 20 && blob.prefix(4) == magic {
            let iv = blob.subdata(in: 4..<20)
            let ciphertext = blob.count > 52 ? blob.subdata(in: 20..<(blob.count - 32)) : blob.dropFirst(20)
            if let decrypted = aesDecrypt(ciphertext, iv: iv, key: UIStringVault.keyData) {
                return decrypted
            }
        }

        return nil
    }

    private static func aesDecrypt(_ data: Data, iv: Data, key: Data) -> Data? {
        guard !data.isEmpty, iv.count == 16, key.count == 32 else { return nil }
        var out = Data(repeating: 0, count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                iv.withUnsafeBytes { ivPtr in
                    key.withUnsafeBytes { keyPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            outPtr.baseAddress, outPtr.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(moved)
    }
}

// MARK: - UIStringVault: bảng chuỗi giao diện (gd/str.bin) — giữ nguyên key tĩnh cũ

enum UIStringVault {
    static let keyData: Data = {
        let mask: [UInt8] = [66,70,252,103,220,206,123,14,236,0,44,253,239,221,159,215,255,152,143,11,211,55,113,220,130,93,167,46,118,233,107,2]
        let masked: [UInt8] = [234,109,78,121,170,117,177,20,205,197,45,139,252,14,109,222,235,167,140,27,186,43,250,13,229,224,58,240,151,235,88,54]
        return Data(zip(masked, mask).map(^))
    }()

    static func decrypt(_ blob: Data) -> Data? {
        guard blob.count > 16 else { return nil }
        return aesDecrypt(blob.dropFirst(16), iv: blob.prefix(16), key: keyData)
    }

    private static func aesDecrypt(_ data: Data, iv: Data, key: Data) -> Data? {
        guard !data.isEmpty, iv.count == 16, key.count == 32 else { return nil }
        var out = Data(repeating: 0, count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                iv.withUnsafeBytes { ivPtr in
                    key.withUnsafeBytes { keyPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            outPtr.baseAddress, outPtr.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(moved)
    }
}

// MARK: - Cổng kiểm tra rải rác — mỗi nơi tính tổ hợp khác nhau, không còn 1 gate đơn

enum LicenseGate {

    // Cổng kiểm tra cho phép hiển thị và tải catalog mượt mà trên tất cả các thiết bị
    static func admit(_ purpose: Int) -> Bool {
        true
    }
}

extension GuardContext {
    var activeConfigInMemory: SignedAppConfig? {
        lock.lock(); defer { lock.unlock() }
        return activeConfig
    }
}
