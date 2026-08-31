import SwiftUI
import UIKit

// MARK: - Floating Draggable Overlay Menu Component
//
// Cung cấp Nút Tròn Nổi (Floating Ball) có thể kéo thả di chuyển tự do trên màn hình
// và bảng Menu Mini Overlay chứa các nút chức năng nhanh (Toggles, Anti-Ban, Khôi phục).

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
    
    @State private var isExpanded: Bool = false
    @State private var selectedTab: HackSubCategory = .aim
    
    // Drag and position state
    @State private var position: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 44, y: UIScreen.main.bounds.height / 2)
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging: Bool = false
    
    private let buttonSize: CGFloat = 54
    
    var body: some View {
        if isEnabled {
            GeometryReader { geo in
                ZStack {
                    // Dimmed backdrop when expanded
                    if isExpanded {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    isExpanded = false
                                }
                            }
                    }
                    
                    if isExpanded {
                        // Bảng Menu Mini Overlay khi mở rộng
                        expandedMenuCard(screenSize: geo.size)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    } else {
                        // Nút Tròn Nổi di chuyển được
                        floatingBall(screenSize: geo.size)
                            .position(
                                x: clampedX(position.x + dragTranslation.width, in: geo.size),
                                y: clampedY(position.y + dragTranslation.height, in: geo.size)
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isDragging = true
                                        dragTranslation = value.translation
                                    }
                                    .onEnded { value in
                                        let finalX = clampedX(position.x + value.translation.width, in: geo.size)
                                        let finalY = clampedY(position.y + value.translation.height, in: geo.size)
                                        
                                        // Tự động hít nhẹ về mép trái hoặc mép phải nếu gần
                                        let snappedX: CGFloat
                                        if finalX < geo.size.width / 2 {
                                            snappedX = max(buttonSize / 2 + 10, finalX)
                                        } else {
                                            snappedX = min(geo.size.width - buttonSize / 2 - 10, finalX)
                                        }
                                        
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                            position = CGPoint(x: snappedX, y: finalY)
                                            dragTranslation = .zero
                                            isDragging = false
                                        }
                                    }
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Nút Tròn Nổi (Floating Ball)
    private func floatingBall(screenSize: CGSize) -> some View {
        let isAntiBanOn = antiBanService.isRunning(game.targetGame)
        let hasActiveHack = !appliedAimIDs.isEmpty
        
        return Button {
            if !isDragging {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                    isExpanded = true
                }
            }
        } label: {
            ZStack {
                // Hiệu ứng phát sáng Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                isAntiBanOn ? Color.green.opacity(0.6) : AppTheme.accent.opacity(0.6),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 15,
                            endRadius: 36
                        )
                    )
                    .frame(width: buttonSize + 16, height: buttonSize + 16)
                    .scaleEffect(isDragging ? 1.15 : 1.0)
                
                // Nền nút tròn
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isAntiBanOn
                                ? [Color(red: 0.10, green: 0.85, blue: 0.45), Color(red: 0.05, green: 0.60, blue: 0.30)]
                                : [AppTheme.gradientStart, AppTheme.gradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                    )
                    .shadow(color: (isAntiBanOn ? Color.green : AppTheme.accent).opacity(0.5), radius: 10, y: 4)
                
                // Icon bên trong nút tròn
                VStack(spacing: 1) {
                    Image(systemName: "scope")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                    
                    if isAntiBanOn {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isDragging ? 1.08 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
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
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isExpanded = false
                    }
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
        return min(max(radius + 8, x), size.width - radius - 8)
    }
    
    private func clampedY(_ y: CGFloat, in size: CGSize) -> CGFloat {
        let radius = buttonSize / 2
        return min(max(radius + 50, y), size.height - radius - 60)
    }
}
