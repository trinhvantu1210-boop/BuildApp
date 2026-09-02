import SwiftUI
import UIKit

// MARK: - Floating Draggable Overlay Menu Component (Zero-Lag AssistiveTouch)
//
// Nút Tròn Nổi với cơ chế vật lý AssistiveTouch phản hồi tức thì 0ms:
// - Bỏ Button wrapper gây delay/xung đột gesture trong SwiftUI
// - Sử dụng DragGesture(minimumDistance: 0) để bám ngón tay lập tức ngay khi chạm
// - Tự động nhận diện Chạm (Tap) để mở Menu và Vuốt (Drag) để di chuyển hít mép
// - Quán tính lực vuốt (Velocity inertia) hít sát mép trái/phải màn hình
// - Tự động làm mờ khi nghỉ (Idle Dimming) sau 3 giây

struct FloatingOverlayMenuView: View {
    let game: AimGameKind
    @Binding var isEnabled: Bool
    
    // Catalogs & data passed from detail view or shared
    let aimsByCategory: [HackSubCategory: [BundledAim]]
    let appliedAimIDs: Set<UUID>
    let workingAimIDs: Set<UUID>
    let onToggleAim: (BundledAim, Bool, PatchCatalogConfig) -> Void
    let onRestoreCategory: () -> Void
    let isRestoringAll: Bool
    
    @ObservedObject private var antiBanService = FFAntiBanService.shared
    @ObservedObject private var profileInstaller = ProfileInstallerService.shared
    
    @State private var isExpanded: Bool = false
    @State private var selectedTab: HackSubCategory = .aim
    
    // AssistiveTouch drag & position state
    @State private var position: CGPoint = CGPoint(
        x: max(350, UIScreen.main.bounds.width - 32),
        y: UIScreen.main.bounds.height * 0.42
    )
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var dragStartTime: Date? = nil
    @State private var isIdle: Bool = false
    @State private var idleTimerTask: Task<Void, Never>? = nil
    
    private let buttonSize: CGFloat = 54
    private let edgePadding: CGFloat = 6
    private let topSafeAreaMargin: CGFloat = 60
    private let bottomSafeAreaMargin: CGFloat = 85
    
    var body: some View {
        if isEnabled {
            GeometryReader { geo in
                ZStack {
                    // Dimmed backdrop khi mở rộng bảng menu
                    if isExpanded {
                        Color.black.opacity(0.48)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                closeMenu()
                            }
                        
                        // Bảng Menu Mini Overlay khi mở rộng
                        expandedMenuCard(screenSize: geo.size)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.88, anchor: .center).combined(with: .opacity),
                                removal: .scale(scale: 0.88, anchor: .center).combined(with: .opacity)
                            ))
                    } else {
                        // Nút Tròn Nổi chuẩn AssistiveTouch (Không bị bao bọc bởi Button gây delay)
                        floatingAssistiveBall(screenSize: geo.size)
                            .position(
                                x: clampedX(position.x + dragOffset.width, in: geo.size),
                                y: clampedY(position.y + dragOffset.height, in: geo.size)
                            )
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if dragStartTime == nil {
                                            dragStartTime = Date()
                                        }
                                        isDragging = true
                                        dragOffset = value.translation
                                        resetIdleTimer(isInteracting: true)
                                    }
                                    .onEnded { value in
                                        let translationDistance = hypot(value.translation.width, value.translation.height)
                                        let elapsed = Date().timeIntervalSince(dragStartTime ?? Date())
                                        dragStartTime = nil
                                        
                                        if translationDistance < 8 && elapsed < 0.4 {
                                            // Chạm nhẹ (Tap) -> Mở Menu tức thì
                                            dragOffset = .zero
                                            isDragging = false
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                                isExpanded = true
                                            }
                                        } else {
                                            // Kéo thả (Drag) -> Hít vào mép màn hình
                                            handleDragEnd(value: value, in: geo.size)
                                        }
                                    }
                            )
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // Căn chỉnh vị trí mặc định nằm sát mép phải màn hình
                    let initialX = geo.size.width > 0 ? (geo.size.width - buttonSize / 2 - edgePadding) : (UIScreen.main.bounds.width - buttonSize / 2 - edgePadding)
                    let initialY = geo.size.height > 0 ? (geo.size.height * 0.42) : (UIScreen.main.bounds.height * 0.42)
                    position = CGPoint(x: initialX, y: initialY)
                    resetIdleTimer()
                }
                .onChange(of: geo.size) { newSize in
                    // Cập nhật vị trí khi màn hình thay đổi
                    clampPosition(in: newSize)
                }
            }
            .sheet(isPresented: $profileInstaller.showGuideSheet) {
                ProfileInstallSheetView()
            }
        }
    }
    
    // MARK: - Nút Tròn Nổi Kiểu AssistiveTouch (Pure View, Zero Touch Lag)
    private func floatingAssistiveBall(screenSize: CGSize) -> some View {
        let isAntiBanOn = antiBanService.isRunning(game.targetGame)
        let hasActiveHack = !appliedAimIDs.isEmpty
        let activeHackCount = appliedAimIDs.count
        
        return ZStack {
            // Vòng sáng Glow bên ngoài khi đang hoạt động
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            isAntiBanOn ? Color.green.opacity(0.6) : AppTheme.accent.opacity(0.6),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 14,
                        endRadius: 36
                    )
                )
                .frame(width: buttonSize + 18, height: buttonSize + 18)
                .opacity(isDragging ? 1.0 : (isIdle ? 0.3 : 0.85))
            
            // Vỏ ngoài AssistiveTouch mờ ảo
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.65))
                        .blur(radius: 2)
                )
            
            // Lõi nút tròn chuyển màu
            Circle()
                .fill(
                    LinearGradient(
                        colors: isAntiBanOn
                            ? [Color(red: 0.12, green: 0.88, blue: 0.50), Color(red: 0.04, green: 0.62, blue: 0.32)]
                            : hasActiveHack
                                ? [Color(red: 1.0, green: 0.6, blue: 0.1), Color(red: 0.9, green: 0.3, blue: 0.05)]
                                : [AppTheme.gradientStart, AppTheme.gradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: buttonSize - 10, height: buttonSize - 10)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.2)
                )
                .shadow(color: (isAntiBanOn ? Color.green : AppTheme.accent).opacity(0.6), radius: 8, y: 3)
            
            // Icon bên trong
            VStack(spacing: 2) {
                Image(systemName: "scope")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(.white)
                
                if isAntiBanOn {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                }
            }
            
            // Badge số lượng hack
            if hasActiveHack && !isDragging && activeHackCount > 0 {
                Text("\(activeHackCount)")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.red)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                            )
                    )
                    .offset(x: 20, y: -20)
                    .scaleEffect(isIdle ? 0.5 : 1)
                    .opacity(isIdle ? 0 : 1)
            }
        }
        .contentShape(Circle())
        .opacity(isDragging ? 1.0 : (isIdle ? 0.48 : 0.96))
        .scaleEffect(isDragging ? 1.12 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isDragging)
        .animation(.easeInOut(duration: 0.35), value: isIdle)
    }
    
    // MARK: - Xử lý vật lý nhả tay và hít mép (AssistiveTouch Edge Snapping)
    private func handleDragEnd(value: DragGesture.Value, in size: CGSize) {
        let currentTargetX = position.x + value.translation.width
        let currentTargetY = position.y + value.translation.height
        
        // Quán tính lực vuốt (Inertia based on predicted velocity)
        let predictedX = position.x + value.predictedEndTranslation.width
        let snapToLeft = predictedX < size.width / 2
        
        let targetX: CGFloat = snapToLeft
            ? (buttonSize / 2 + edgePadding)
            : (size.width - buttonSize / 2 - edgePadding)
        
        let finalY = clampedY(currentTargetY + (value.predictedEndTranslation.height - value.translation.height) * 0.2, in: size)
        
        UISelectionFeedbackGenerator().selectionChanged()
        
        withAnimation(.spring(response: 0.36, dampingFraction: 0.74, blendDuration: 0.05)) {
            position = CGPoint(x: targetX, y: finalY)
            dragOffset = .zero
            isDragging = false
        }
        
        resetIdleTimer()
    }
    
    // Đếm thời gian tự làm mờ nút khi không dùng (Idle Dimming)
    private func resetIdleTimer(isInteracting: Bool = false) {
        idleTimerTask?.cancel()
        if isInteracting {
            isIdle = false
            return
        }
        isIdle = false
        idleTimerTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 giây
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        isIdle = true
                    }
                }
            }
        }
    }
    
    private func closeMenu() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            isExpanded = false
        }
        resetIdleTimer()
    }
    
    private func clampPosition(in size: CGSize) {
        position = CGPoint(
            x: clampedX(position.x, in: size),
            y: clampedY(position.y, in: size)
        )
    }
    
    // MARK: - Bảng Menu Mini Overlay
    private func expandedMenuCard(screenSize: CGSize) -> some View {
        let isAntiBanOn = antiBanService.isRunning(game.targetGame)
        let currentItems = aimsByCategory[selectedTab] ?? []
        
        return VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overlay Menu")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(game.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Nút thu nhỏ / đóng overlay
                Button {
                    closeMenu()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // Thanh gạt nhanh Anti-Ban trong Overlay
            HStack(spacing: 12) {
                Image(systemName: isAntiBanOn ? "shield.fill" : "shield.slash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isAntiBanOn ? Color.green : Color.white.opacity(0.6))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Anti-Ban Cực Cao")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(isAntiBanOn ? "Đang bảo vệ" : "Đang tắt")
                        .font(.system(size: 11))
                        .foregroundStyle(isAntiBanOn ? Color.green : Color.white.opacity(0.5))
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { isAntiBanOn },
                    set: { _ in
                        antiBanService.toggle(for: game.targetGame)
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                ))
                .labelsHidden()
                .tint(.green)
                .scaleEffect(0.85)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            
            // Nút cài đặt Profile DNS AntiBan HZZ nhanh
            Button {
                ProfileInstallerService.shared.startAndInstall()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Text("Cài Profile DNS HZZ")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.04))
            }
            .buttonStyle(.plain)
            
            // Tab Selector trong Overlay
            HStack(spacing: 6) {
                ForEach(HackSubCategory.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(tab.displayName)
                                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? AppTheme.accent : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Danh sách các Toggle chức năng trong Sub-Tab
            ScrollView {
                VStack(spacing: 8) {
                    if currentItems.isEmpty {
                        Text("Đang tải dữ liệu...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.vertical, 16)
                    } else {
                        ForEach(currentItems) { aim in
                            let isApplied = appliedAimIDs.contains(aim.id)
                            let isWorking = workingAimIDs.contains(aim.id)
                            
                            HStack(spacing: 10) {
                                Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(isApplied ? Color.green : Color.white.opacity(0.4))
                                
                                Text(aim.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if isWorking {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                } else {
                                    Toggle("", isOn: Binding(
                                        get: { isApplied },
                                        set: { on in
                                            onToggleAim(aim, on, selectedTab.config)
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(AppTheme.accent)
                                    .scaleEffect(0.8)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isApplied ? AppTheme.accent.opacity(0.2) : Color.white.opacity(0.05))
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: min(240, screenSize.height * 0.4))
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // Nút Khôi phục nhanh
            Button(action: onRestoreCategory) {
                HStack(spacing: 6) {
                    if isRestoringAll {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("Khôi phục tất cả \(selectedTab.displayName)")
                        .font(.system(size: 12, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white.opacity(0.9))
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRestoringAll)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: min(340, screenSize.width - 32))
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.10, green: 0.12, blue: 0.16).opacity(0.95))
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Material.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), AppTheme.accent.opacity(0.4), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black.opacity(0.6), radius: 24, y: 12)
    }
    
    // MARK: - Bounds Calculation
    private func clampedX(_ x: CGFloat, in size: CGSize) -> CGFloat {
        let radius = buttonSize / 2
        let minX = radius + edgePadding
        let maxX = max(minX, size.width - radius - edgePadding)
        return min(max(minX, x), maxX)
    }
    
    private func clampedY(_ y: CGFloat, in size: CGSize) -> CGFloat {
        let radius = buttonSize / 2
        let minY = radius + topSafeAreaMargin
        let maxY = max(minY, size.height - radius - bottomSafeAreaMargin)
        return min(max(minY, y), maxY)
    }
}