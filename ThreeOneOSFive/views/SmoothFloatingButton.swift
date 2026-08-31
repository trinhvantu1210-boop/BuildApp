import SwiftUI
import UIKit

// MARK: - Nút Tròn Mượt Cho Free Fire (Zero-Lag AssistiveTouch)
struct SmoothFloatingButton: View {
    let game: AimGameKind
    let isAntiBanOn: Bool
    let hasActiveHack: Bool
    let activeHackCount: Int
    let onTap: () -> Void
    
    // Trạng thái di chuyển
    @State private var position: CGPoint = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var isIdle: Bool = false
    @State private var idleTimerTask: Task<Void, Never>?
    @State private var isHapticEnabled: Bool = true
    
    // Kích thước
    private let buttonSize: CGFloat = 60
    private let edgePadding: CGFloat = 8
    private let topSafeArea: CGFloat = 50
    private let bottomSafeArea: CGFloat = 80
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Nút tròn chính
                floatingButton
                    .position(
                        x: clampedX(position.x + dragOffset.width, in: geometry.size),
                        y: clampedY(position.y + dragOffset.height, in: geometry.size)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDragChanged(value)
                            }
                            .onEnded { value in
                                handleDragEnded(value, in: geometry.size)
                            }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                setupInitialPosition(in: geometry.size)
                startIdleTimer()
            }
            .onChange(of: geometry.size) { newSize in
                clampPosition(in: newSize)
            }
        }
    }
    
    // MARK: - Nút Tròn Chính
    private var floatingButton: some View {
        ZStack {
            // Vòng sáng bên ngoài (Glow Effect)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (isAntiBanOn ? Color.green : AppTheme.accent).opacity(isDragging ? 0.8 : 0.4),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 15,
                        endRadius: isDragging ? 48 : 40
                    )
                )
                .frame(width: buttonSize + 24, height: buttonSize + 24)
                .opacity(isDragging ? 1 : (isIdle ? 0.2 : 0.7))
                .scaleEffect(isDragging ? 1.1 : 1)
            
            // Vỏ ngoài mờ (Glass Effect)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDragging ? 0.5 : 0.25),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .blur(radius: 3)
                )
            
            // Lõi nút chính
            Circle()
                .fill(
                    LinearGradient(
                        colors: getGradientColors(),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: buttonSize - 10, height: buttonSize - 10)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.8),
                                    Color.white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(
                    color: (isAntiBanOn ? Color.green : AppTheme.accent).opacity(0.5),
                    radius: isDragging ? 18 : 10,
                    y: isDragging ? 8 : 4
                )
            
            // Icon bên trong
            VStack(spacing: 2) {
                Image(systemName: "scope")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .scaleEffect(isDragging ? 1.15 : 1)
                
                if isAntiBanOn {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                        .padding(.top, -2)
                }
            }
            
            // Badge số lượng hack đang bật
            if hasActiveHack && !isDragging && activeHackCount > 0 {
                Text("\(activeHackCount)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.red)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                            )
                    )
                    .offset(x: 22, y: -22)
                    .scaleEffect(isIdle ? 0.5 : 1)
                    .opacity(isIdle ? 0 : 1)
            }
        }
        .contentShape(Circle())
        .opacity(isDragging ? 1 : (isIdle ? 0.45 : 0.95))
        .scaleEffect(isDragging ? 1.15 : (isIdle ? 0.92 : 1))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .animation(.easeInOut(duration: 0.4), value: isIdle)
    }
    
    // MARK: - Drag Handlers
    private func handleDragChanged(_ value: DragGesture.Value) {
        if !isDragging {
            isDragging = true
            if isHapticEnabled {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        dragOffset = value.translation
        resetIdleTimer()
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, in size: CGSize) {
        let translationDistance = hypot(value.translation.width, value.translation.height)
        
        // Nếu kéo quá ngắn (Tap) => Kích hoạt onTap tức thì
        if translationDistance < 8 {
            dragOffset = .zero
            isDragging = false
            if isHapticEnabled {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            onTap()
            resetIdleTimer()
            return
        }
        
        // Tính toán vị trí mới với quán tính hít mép
        let predictedX = position.x + value.predictedEndTranslation.width
        let targetX: CGFloat = predictedX < size.width / 2
            ? (buttonSize / 2 + edgePadding)
            : (size.width - buttonSize / 2 - edgePadding)
        
        let velocityY = (value.predictedEndTranslation.height - value.translation.height) * 0.15
        let targetY = clampedY(
            position.y + value.translation.height + velocityY,
            in: size
        )
        
        if isHapticEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        
        withAnimation(.spring(
            response: 0.4,
            dampingFraction: 0.75,
            blendDuration: 0.05
        )) {
            position = CGPoint(x: targetX, y: targetY)
            dragOffset = .zero
            isDragging = false
        }
        
        resetIdleTimer()
    }
    
    // MARK: - Position Helpers
    private func clampedX(_ x: CGFloat, in size: CGSize) -> CGFloat {
        let radius = buttonSize / 2
        let minX = radius + edgePadding
        let maxX = max(minX, size.width - radius - edgePadding)
        return min(max(minX, x), maxX)
    }
    
    private func clampedY(_ y: CGFloat, in size: CGSize) -> CGFloat {
        let radius = buttonSize / 2
        let minY = radius + topSafeArea
        let maxY = max(minY, size.height - radius - bottomSafeArea)
        return min(max(minY, y), maxY)
    }
    
    private func setupInitialPosition(in size: CGSize) {
        if position == .zero {
            position = CGPoint(
                x: size.width - buttonSize / 2 - edgePadding,
                y: size.height * 0.4
            )
        }
    }
    
    private func clampPosition(in size: CGSize) {
        position = CGPoint(
            x: clampedX(position.x, in: size),
            y: clampedY(position.y, in: size)
        )
    }
    
    // MARK: - Idle Timer (Tự làm mờ)
    private func startIdleTimer() {
        resetIdleTimer()
    }
    
    private func resetIdleTimer() {
        idleTimerTask?.cancel()
        isIdle = false
        
        idleTimerTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 giây
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isIdle = true
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func getGradientColors() -> [Color] {
        if isAntiBanOn {
            return [
                Color(red: 0.12, green: 0.92, blue: 0.50),
                Color(red: 0.04, green: 0.65, blue: 0.32)
            ]
        } else if hasActiveHack {
            return [
                Color(red: 1.0, green: 0.6, blue: 0.1),
                Color(red: 0.9, green: 0.3, blue: 0.05)
            ]
        }
        return [
            AppTheme.gradientStart,
            AppTheme.gradientEnd
        ]
    }
}

// MARK: - Floating Menu Overlay
struct FloatingMenuOverlay: View {
    let game: AimGameKind
    let aimsByCategory: [HackSubCategory: [BundledAim]]
    let appliedAimIDs: Set<UUID>
    let workingAimIDs: Set<UUID>
    let selectedTab: HackSubCategory
    let isRestoringAll: Bool
    let antiBanService: FFAntiBanService
    let onToggleAim: (BundledAim, Bool, PatchCatalogConfig) -> Void
    let onRestoreCategory: () -> Void
    let onDismiss: () -> Void
    
    @State private var localSelectedTab: HackSubCategory = .aim
    @State private var appeared: Bool = false
    
    var body: some View {
        ZStack {
            // Background mờ
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            // Menu card
            VStack(spacing: 0) {
                // Header
                headerView
                
                Divider()
                    .background(Color.white.opacity(0.12))
                
                // Anti-Ban Toggle
                antiBanToggle
                
                // Tab Selector
                tabSelector
                
                // Danh sách tính năng
                featureList
                
                // Nút khôi phục
                restoreButton
            }
            .frame(width: min(360, UIScreen.main.bounds.width - 32))
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.95))
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Material.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), AppTheme.accent.opacity(0.3), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: Color.black.opacity(0.6), radius: 30, y: 15)
            .scaleEffect(appeared ? 1.0 : 0.92)
            .opacity(appeared ? 1.0 : 0.0)
        }
        .transition(.opacity)
        .onAppear {
            localSelectedTab = selectedTab
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Overlay Menu")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(game.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private var antiBanToggle: some View {
        let isAntiBanOn = antiBanService.isRunning(game.targetGame)
        
        return HStack(spacing: 12) {
            Image(systemName: isAntiBanOn ? "shield.fill" : "shield.slash")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isAntiBanOn ? Color.green : Color.white.opacity(0.5))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Anti-Ban Cực Cao")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(isAntiBanOn ? "Đang bảo vệ" : "Đang tắt")
                    .font(.system(size: 12))
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
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
    }
    
    private var tabSelector: some View {
        HStack(spacing: 6) {
            ForEach(HackSubCategory.allCases) { tab in
                let isSelected = localSelectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        localSelectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(tab.displayName)
                            .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? AppTheme.accent : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private var featureList: some View {
        let currentItems = aimsByCategory[localSelectedTab] ?? []
        
        return ScrollView {
            VStack(spacing: 8) {
                if currentItems.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                        Text("Đang tải dữ liệu...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(currentItems) { aim in
                        let isApplied = appliedAimIDs.contains(aim.id)
                        let isWorking = workingAimIDs.contains(aim.id)
                        
                        HStack(spacing: 10) {
                            Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isApplied ? Color.green : Color.white.opacity(0.3))
                            
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
                                        onToggleAim(aim, on, localSelectedTab.config)
                                    }
                                ))
                                .labelsHidden()
                                .tint(AppTheme.accent)
                                .scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isApplied ? AppTheme.accent.opacity(0.15) : Color.white.opacity(0.04))
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: min(200, UIScreen.main.bounds.height * 0.35))
    }
    
    private var restoreButton: some View {
        Button(action: onRestoreCategory) {
            HStack(spacing: 6) {
                if isRestoringAll {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .bold))
                }
                Text("Khôi phục tất cả \(localSelectedTab.displayName)")
                    .font(.system(size: 13, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white.opacity(0.9))
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRestoringAll)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

// MARK: - SwiftUI Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Text("Free Fire")
                .foregroundColor(.white)
                .font(.largeTitle)
                .padding()
            
            SmoothFloatingButton(
                game: .freeFire,
                isAntiBanOn: true,
                hasActiveHack: true,
                activeHackCount: 3,
                onTap: {
                    print("Button tapped!")
                }
            )
        }
    }
}