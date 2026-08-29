import Foundation
import Combine

// MARK: - Anti-Ban Free Fire / Free Fire MAX Cực Cao: Chạy ngầm liên tục, tự lưu trạng thái khi tắt app
//
// Dịch vụ này chuẩn hóa mốc thời gian chuyên sâu (deep timestamp normalization) trên toàn bộ container game:
// - Quét và chuẩn hóa toàn bộ Documents, contentcache, Library/Caches, tmp về mốc ngày cài/cũ nhất.
// - Tự động lưu trạng thái vào UserDefaults: khi tắt/vuốt đóng app và mở lại, Anti-Ban vẫn tiếp tục chạy ngầm
//   và bộ đếm thời gian vẫn đếm chính xác mà KHÔNG bị reset/tắt cho đến khi người dùng bấm nút TẮT.

@MainActor
final class FFAntiBanService: ObservableObject {

    static let shared = FFAntiBanService()

    struct Result: Equatable, Sendable {
        let filesNormalized: Int
        let directoriesNormalized: Int
        let referenceDate: Date
    }

    enum TargetGame: String, CaseIterable, Identifiable, Sendable {
        case freeFire = "com.dts.freefireth"
        case freeFireMax = "com.dts.freefiremax"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .freeFire: return "Free Fire"
            case .freeFireMax: return "Free Fire MAX"
            }
        }
    }

    enum AntiBanError: LocalizedError, Sendable {
        case containerNotFound(String)
        case contentCacheMissing(String)

        var errorDescription: String? {
            switch self {
            case .containerNotFound(let name):
                return "Không tìm thấy dữ liệu \(name) trên máy. Hãy chắc chắn game đã cài và quyền exploit đã mở."
            case .contentCacheMissing(let name):
                return "\(name) thiếu thư mục dữ liệu — không có gì để xử lý."
            }
        }
    }

    nonisolated static let antiBanBundleID = TargetGame.freeFire.rawValue
    nonisolated static let freeFireBundleID = TargetGame.freeFire.rawValue
    nonisolated static let freeFireMaxBundleID = TargetGame.freeFireMax.rawValue

    @Published public private(set) var runningGames: Set<TargetGame> = []
    @Published public private(set) var elapsedSeconds: [TargetGame: Int] = [:]
    @Published public private(set) var resultTexts: [TargetGame: String] = [:]
    @Published public private(set) var errorTexts: [TargetGame: String] = [:]

    private var tasks: [TargetGame: Task<Void, Never>] = [:]
    private var startTimes: [TargetGame: Date] = [:]

    private init() {
        restoreRunningState()
    }

    private func defaultsKeyRunning(_ game: TargetGame) -> String {
        "antiban.running.\(game.rawValue)"
    }

    private func defaultsKeyStartTime(_ game: TargetGame) -> String {
        "antiban.start_time.\(game.rawValue)"
    }

    // Khôi phục trạng thái chạy ngầm khi mở lại app
    private func restoreRunningState() {
        for game in TargetGame.allCases {
            let isSavedRunning = UserDefaults.standard.bool(forKey: defaultsKeyRunning(game))
            if isSavedRunning {
                let savedTimestamp = UserDefaults.standard.double(forKey: defaultsKeyStartTime(game))
                let startDate = savedTimestamp > 0 ? Date(timeIntervalSince1970: savedTimestamp) : Date()
                resumeBackgroundAntiBan(for: game, initialStartDate: startDate)
            }
        }
    }

    func isRunning(_ game: TargetGame) -> Bool {
        runningGames.contains(game)
    }

    func elapsedTimeString(for game: TargetGame) -> String {
        formattedTime(elapsedSeconds[game] ?? 0)
    }

    func resultText(for game: TargetGame) -> String? {
        resultTexts[game]
    }

    func errorText(for game: TargetGame) -> String? {
        errorTexts[game]
    }

    nonisolated static func isInstalled(bundleID: String = antiBanBundleID) -> Bool {
        ContainerStore.resolveAppContainerPath(bundleID: bundleID) != nil
    }

    // Chuẩn hóa mốc thời gian cực cao (Deep Normalization trên toàn bộ Documents, contentcache, Library/Caches, tmp)
    @discardableResult
    nonisolated static func normalizeTimestamps(bundleID: String = antiBanBundleID) throws -> Result {
        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
            let gameName = bundleID == freeFireMaxBundleID ? "Free Fire MAX" : "Free Fire"
            throw AntiBanError.containerNotFound(gameName)
        }

        let containerURL = URL(fileURLWithPath: containerPath, isDirectory: true)
        let fm = FileManager.default

        let targets: [URL] = [
            containerURL.appendingPathComponent("Documents", isDirectory: true),
            containerURL.appendingPathComponent("Library/Caches", isDirectory: true),
            containerURL.appendingPathComponent("tmp", isDirectory: true)
        ]

        var fileURLs: [URL] = []
        var dirURLs: [URL] = []
        var oldest: Date?

        for target in targets {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let enumerator = fm.enumerator(
                at: target,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [],
                errorHandler: nil
            )

            while let item = enumerator?.nextObject() as? URL {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let isDirectory = values?.isDirectory ?? false
                if isDirectory {
                    dirURLs.append(item)
                } else {
                    fileURLs.append(item)
                }
                if let date = values?.contentModificationDate {
                    if oldest == nil || date < oldest! {
                        oldest = date
                    }
                }
            }
        }

        guard let reference = oldest else {
            let gameName = bundleID == freeFireMaxBundleID ? "Free Fire MAX" : "Free Fire"
            throw AntiBanError.contentCacheMissing(gameName)
        }

        let attrs: [FileAttributeKey: Any] = [
            .modificationDate: reference,
            .creationDate: reference
        ]

        var filesDone = 0
        for url in fileURLs where (try? fm.setAttributes(attrs, ofItemAtPath: url.path)) != nil {
            filesDone += 1
        }

        var directoriesDone = 0
        for url in dirURLs.sorted(by: { $0.path.count > $1.path.count })
        where (try? fm.setAttributes(attrs, ofItemAtPath: url.path)) != nil {
            directoriesDone += 1
        }

        for target in targets {
            try? fm.setAttributes(attrs, ofItemAtPath: target.path)
        }

        return Result(
            filesNormalized: filesDone,
            directoriesNormalized: directoriesDone,
            referenceDate: reference
        )
    }

    // Khởi chạy ngầm và lưu vào UserDefaults
    func startBackgroundAntiBan(for game: TargetGame, intervalSeconds: TimeInterval = 5.0) {
        guard !runningGames.contains(game) else { return }
        let now = Date()
        UserDefaults.standard.set(true, forKey: defaultsKeyRunning(game))
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: defaultsKeyStartTime(game))
        resumeBackgroundAntiBan(for: game, initialStartDate: now, intervalSeconds: intervalSeconds)
    }

    private func resumeBackgroundAntiBan(for game: TargetGame, initialStartDate: Date, intervalSeconds: TimeInterval = 5.0) {
        runningGames.insert(game)
        startTimes[game] = initialStartDate
        elapsedSeconds[game] = max(0, Int(Date().timeIntervalSince(initialStartDate)))
        errorTexts[game] = nil
        resultTexts[game] = "Đang chạy ngầm Anti-Ban Cực Cao (\(game.displayName))…"

        let bundleID = game.rawValue

        tasks[game]?.cancel()
        tasks[game] = Task { [weak self] in
            var lastNormalizedTime: Date = Date.distantPast
            while !Task.isCancelled {
                guard let self = self, self.runningGames.contains(game) else { break }

                if let start = self.startTimes[game] {
                    self.elapsedSeconds[game] = max(0, Int(Date().timeIntervalSince(start)))
                }

                if Date().timeIntervalSince(lastNormalizedTime) >= intervalSeconds {
                    lastNormalizedTime = Date()
                    let resultOrError: Swift.Result<Result, Error> = await Task.detached(priority: .userInitiated) {
                        Swift.Result {
                            try FFAntiBanService.normalizeTimestamps(bundleID: bundleID)
                        }
                    }.value

                    guard !Task.isCancelled, self.runningGames.contains(game) else { break }
                    switch resultOrError {
                    case .success(let result):
                        self.resultTexts[game] = "Đã quét & chuẩn hóa \(result.filesNormalized) file"
                    case .failure(let error):
                        self.errorTexts[game] = error.localizedDescription
                    }
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // Dừng chạy ngầm và xóa khỏi UserDefaults
    func stopBackgroundAntiBan(for game: TargetGame) {
        guard runningGames.contains(game) else { return }
        runningGames.remove(game)
        UserDefaults.standard.set(false, forKey: defaultsKeyRunning(game))
        UserDefaults.standard.removeObject(forKey: defaultsKeyStartTime(game))
        tasks[game]?.cancel()
        tasks[game] = nil
        let timeStr = formattedTime(elapsedSeconds[game] ?? 0)
        resultTexts[game] = "Đã dừng Anti-Ban (\(timeStr))"
    }

    func toggle(for game: TargetGame) {
        if isRunning(game) {
            stopBackgroundAntiBan(for: game)
        } else {
            startBackgroundAntiBan(for: game)
        }
    }

    func formattedTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
