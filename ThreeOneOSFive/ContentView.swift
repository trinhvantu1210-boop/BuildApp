import SwiftUI
import UIKit

// MARK: - ContentView: Giao diện chính duy nhất tập trung vào Tab Hack Game
//
// Màn hình hiển thị 2 phiên bản Free Fire (Free Fire & Free Fire MAX).
// Khi bấm vào mỗi game sẽ mở ra 3 tab nhỏ: Aim / Mod / Định Vị kèm Anti-Ban Cực Cao.

struct ContentView: View {
    var body: some View {
        PatchProjectsView()
            .tint(AppTheme.accent)
    }
}
