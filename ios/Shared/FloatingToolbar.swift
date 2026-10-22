import SwiftUI
import PhotosUI
import UIKit

struct FloatingToolbar: View {
    @Binding var settings: ToolSettings
    @Binding var isMenuOpen: Bool
    @Binding var photoItem: PhotosPickerItem?
    var isPlacingWhiteRect: Bool
    var isSavingPhoto: Bool = false
    var isPreparingShare: Bool = false
    var canUndo: Bool = false
    var canRedo: Bool = false
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClearAll: () -> Void
    var onClearInk: () -> Void = {}
    var onAddWhiteRect: () -> Void
    var onSavePhoto: () -> Void
    var onExportShare: () -> Void
    var onConnectMac: (() -> Void)? = nil
    var showsMacScreen: Binding<Bool>? = nil
    /// 맥 화면 위 필기·상자를 지우지 않고 잠깐 숨긴다. nil이면 버튼을 그리지 않는다.
    var showsMacInk: Binding<Bool>? = nil
    var onDisconnect: (() -> Void)? = nil
    /// 맥 연결 화면은 사진 선택·저장·내보내기를 쓰지 않는다.
    var showsPhotoActions: Bool = true
    /// EdgeSnappingDraggable가 넘기는 가용 높이. 접기 버튼이 잘리지 않게 메뉴 높이를 제한한다.
    var availableHeight: CGFloat = 600

    private let palette = ["#E53935", "#1E88E5", "#43A047", "#FB8C00", "#8E24AA", "#111111"]
    private let buttonSide: CGFloat = 30
    private let menuWidth: CGFloat = 200
    private let chromeHeight: CGFloat = 52
    @State private var didCopyHex = false
    @State private var showShortcutsGuide = false
    @State private var menuContentHeight: CGFloat = 0
    @State private var menuViewportHeight: CGFloat = 0
    @State private var isScrolledNearBottom = false
    @State private var flashScrollToken = 0
    /// 페이드만 담당. 레이아웃(폭) 변화는 애니메이션 없이 해서 버튼이 옆으로 안 밀리게 한다.
    @State private var menuFadedIn = false
    @State private var menuToggleTask: Task<Void, Never>?

    private var menuMaxHeight: CGFloat {
        // 접기/ON 크롬 + 패딩을 빼고, Split View에서도 스크롤로 전부 닿게 한다.
        max(80, min(240, availableHeight - chromeHeight - 16))
    }

    private var menuNeedsScroll: Bool {
        menuContentHeight > menuViewportHeight + 4
    }

    private var showScrollHint: Bool {
        menuNeedsScroll && !isScrolledNearBottom
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // 접기/ON을 위에 고정 — 창이 작아져도 항상 보이게
            HStack(spacing: 5) {
                Button {
                    toggleMenu()
                } label: {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: buttonSide, height: buttonSide)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                // 메뉴를 열지 않고 지우개 ↔ 직전 펜 전환
                Button {
                    settings.toggleEraserWithLastInk()
                } label: {
                    Image(systemName: quickToolSwapSystemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(quickToolSwapForeground)
                        .frame(width: buttonSide, height: buttonSide)
                        .background(quickToolSwapBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.isEraserSelected ? "이전 펜으로 전환" : "지우개로 전환")

                Button {
                    settings.isDrawingEnabled.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: settings.isDrawingEnabled ? "pencil" : "pencil.slash")
                            .font(.caption2.weight(.semibold))
                        Text(settings.isDrawingEnabled ? "ON" : "OFF")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(onOffForeground)
                    .frame(minWidth: 50, minHeight: buttonSide)
                    .padding(.horizontal, 5)
                    .background(onOffBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                if let showsMacScreen {
                    let screenOn = showsMacScreen.wrappedValue
                    Button {
                        showsMacScreen.wrappedValue.toggle()
                    } label: {
                        Image(systemName: "macwindow")
                            .font(.caption2.weight(.semibold))
                            .overlay {
                                if !screenOn {
                                    Rectangle()
                                        .fill(Color.primary)
                                        .frame(width: 1.5, height: 16)
                                        .rotationEffect(.degrees(-42))
                                }
                            }
                            .foregroundStyle(Color.primary)
                            .frame(width: buttonSide, height: buttonSide)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(screenOn ? 0.08 : 0.16))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(screenOn ? "맥 화면 끄기" : "맥 화면 켜기")
                }

                if let showsMacInk {
                    Button {
                        showsMacInk.wrappedValue.toggle()
                    } label: {
                        Image(systemName: showsMacInk.wrappedValue ? "eye" : "eye.slash")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(showsMacInk.wrappedValue ? Color.primary : Color.secondary)
                            .frame(width: buttonSide, height: buttonSide)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(showsMacInk.wrappedValue ? 0.08 : 0.16))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsMacInk.wrappedValue ? "맥 위 필기 숨기기" : "맥 위 필기 보기")
                }
            }

            if isMenuOpen {
                menuScrollChrome
                    .opacity(menuFadedIn ? 1 : 0)
            }
        }
        .padding(6)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            menuFadedIn = isMenuOpen
        }
        .onChange(of: isMenuOpen) { _, open in
            if open {
                isScrolledNearBottom = false
                flashScrollToken &+= 1
            } else {
                menuFadedIn = false
            }
        }
        .sheet(isPresented: $showShortcutsGuide) {
            ShortcutsGuideSheet()
        }
    }

    /// 메뉴는 페이드만, 폭·위치 변화는 즉시 — 접기/ON이 좌우로 미끄러지지 않는다.
    private func toggleMenu() {
        menuToggleTask?.cancel()

        if isMenuOpen {
            withAnimation(.easeInOut(duration: 0.18)) {
                menuFadedIn = false
            }
            menuToggleTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isMenuOpen = false
                }
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isMenuOpen = true
                menuFadedIn = false
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                menuFadedIn = true
            }
        }
    }

    private var menuScrollChrome: some View {
        ScrollView {
            menuPanel
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MenuContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .scrollIndicators(.visible)
        .frame(width: menuWidth)
        .frame(maxHeight: menuMaxHeight)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { menuViewportHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in menuViewportHeight = h }
            }
        )
        .onPreferenceChange(MenuContentHeightKey.self) { menuContentHeight = $0 }
        .background(
            Color(.secondarySystemBackground).opacity(0.97),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            ScrollIndicatorFlash(token: flashScrollToken)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            if menuNeedsScroll {
                Capsule()
                    .fill(Color.primary.opacity(0.22))
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.trailing, 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            if showScrollHint {
                VStack(spacing: 2) {
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemBackground).opacity(0),
                            Color(.secondarySystemBackground).opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 28)

                    HStack(spacing: 4) {
                        Image(systemName: "chevron.compact.down")
                            .font(.caption.weight(.bold))
                        Text("더보기")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .modifier(MenuScrollBottomTracker { nearBottom in
            isScrolledNearBottom = nearBottom
        })
        .animation(.easeOut(duration: 0.18), value: showScrollHint)
        .accessibilityHint(menuNeedsScroll ? "아래로 스크롤하면 더 많은 도구가 있습니다" : "")
    }

    private var panelBackground: some ShapeStyle {
        Color(.secondarySystemBackground).opacity(0.94)
    }

    private var onOffBackground: Color {
        guard settings.isDrawingEnabled else {
            return Color.gray.opacity(0.85)
        }
        switch settings.selectedTool {
        case .blackPen: return .solidBlack
        case .colorPen: return Color(hex: settings.colorPenColorHex)
        case .highlighter: return Color(hex: settings.highlighterColorHex)
        case .eraser: return Color.gray.opacity(0.85)
        }
    }

    private var onOffForeground: Color {
        onOffBackground.contrastingForeground
    }

    /// 탭하면 전환될 도구 아이콘 (지우개일 땐 직전 펜, 펜일 땐 지우개)
    private var quickToolSwapSystemImage: String {
        if settings.isEraserSelected {
            return settings.resolvedLastInkTool.systemImage
        }
        return DrawingToolKind.eraser.systemImage
    }

    private var quickToolSwapBackground: Color {
        if settings.isEraserSelected {
            switch settings.resolvedLastInkTool {
            case .blackPen: return .solidBlack
            case .colorPen: return Color(hex: settings.colorPenColorHex)
            case .highlighter: return Color(hex: settings.highlighterColorHex)
            case .eraser: return Color.gray.opacity(0.85)
            }
        }
        return Color.gray.opacity(0.85)
    }

    private var quickToolSwapForeground: Color {
        quickToolSwapBackground.contrastingForeground
    }

    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(DrawingToolKind.allCases) { kind in
                    toolCell(kind)
                }
            }

            HStack(spacing: 6) {
                inputModeButton(
                    title: "펜만",
                    systemImage: "applepencil",
                    selected: !settings.allowsFingerDrawing
                ) {
                    settings.allowsFingerDrawing = false
                }
                inputModeButton(
                    title: "손+펜",
                    systemImage: "hand.draw",
                    selected: settings.allowsFingerDrawing
                ) {
                    settings.allowsFingerDrawing = true
                }
            }

            Divider()

            Text("굵기 / 크기")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(
                value: widthBinding,
                in: eraserOrHighlighterWidthRange
            )
            .controlSize(.small)

            if settings.selectedTool == .colorPen || settings.selectedTool == .highlighter {
                Text("색상")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(palette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 20, height: 20)
                            .overlay {
                                if currentColorHex.uppercased() == hex.uppercased() {
                                    Circle().strokeBorder(Color.primary, lineWidth: 1.5)
                                }
                            }
                            .onTapGesture {
                                setCurrentColorHex(hex)
                            }
                    }

                    ColorPicker(
                        "",
                        selection: spectrumColorBinding,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("스펙트럼에서 색상 선택")
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: currentColorHex))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))

                    Text(currentColorHex.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)

                    Button {
                        UIPasteboard.general.string = currentColorHex.uppercased()
                        didCopyHex = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            didCopyHex = false
                        }
                    } label: {
                        Image(systemName: didCopyHex ? "checkmark" : "doc.on.doc")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(didCopyHex ? Color.accentColor : Color.secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("HEX 복사")

                    if didCopyHex {
                        Text("복사됨")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .transition(.opacity)
                    }

                    Spacer(minLength: 0)
                }
                .animation(.easeOut(duration: 0.15), value: didCopyHex)
            }

            Divider()

            if showsPhotoActions {
                HStack(spacing: 6) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("사진 선택", systemImage: "photo.on.rectangle")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)

                    boxButton
                }
            } else {
                boxButton
            }

            if let onConnectMac {
                Button(action: onConnectMac) {
                    Label("맥에 연결", systemImage: "link")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }

            if showsPhotoActions {
                HStack(spacing: 6) {
                    Button(action: onSavePhoto) {
                    HStack(spacing: 4) {
                        if isSavingPhoto {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isSavingPhoto ? "저장 중…" : "사진 저장")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSavingPhoto || isPreparingShare)

                Button(action: onExportShare) {
                    HStack(spacing: 4) {
                        if isPreparingShare {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isPreparingShare ? "준비 중…" : "내보내기")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSavingPhoto || isPreparingShare)
                }
            }

            HStack(spacing: 6) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canUndo ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(canUndo ? Color.accentColor : Color.secondary.opacity(0.35))
                .disabled(!canUndo)
                .accessibilityLabel("실행 취소")

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canRedo ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(canRedo ? Color.accentColor : Color.secondary.opacity(0.35))
                .disabled(!canRedo)
                .accessibilityLabel("다시 실행")

                Spacer()

                Button(role: .destructive, action: onClearAll) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Divider()

            Button {
                showShortcutsGuide = true
            } label: {
                Label("단축어로 빠르게 열기", systemImage: "bolt.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if let onDisconnect {
                Button(role: .destructive, action: onDisconnect) {
                    Label("연결 끊기", systemImage: "xmark.circle")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    private var boxButton: some View {
        Button(action: onAddWhiteRect) {
            Label(
                isPlacingWhiteRect ? "크기 지정" : "상자 추가",
                systemImage: "rectangle.dashed"
            )
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPlacingWhiteRect ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private func inputModeButton(
        title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func toolCell(_ kind: DrawingToolKind) -> some View {
        let selected = settings.selectedTool == kind
        let fill = toolFillColor(for: kind, selected: selected)
        let fg = fill.contrastingForeground

        return Button {
            if kind == .eraser, settings.selectedTool == .eraser {
                onClearInk()
            } else {
                settings.selectTool(kind)
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: kind.systemImage)
                        .font(.body)
                        .foregroundStyle(fg)
                        .frame(maxWidth: .infinity)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .background(Circle().fill(Color.white).padding(1))
                    }
                }
                Text(kind.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(fg)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                guard kind == .eraser else { return }
                settings.selectTool(.eraser)
                onClearInk()
            }
        )
        .accessibilityHint(kind == .eraser ? "두 번 탭하거나 길게 눌러 필기만 삭제" : "")
    }

    private func toolFillColor(for kind: DrawingToolKind, selected: Bool) -> Color {
        let base: Color = {
            switch kind {
            case .blackPen: return .solidBlack
            case .colorPen: return Color(hex: settings.colorPenColorHex)
            case .highlighter: return Color(hex: settings.highlighterColorHex)
            case .eraser: return Color.gray.opacity(0.85)
            }
        }()
        return selected ? base : base.opacity(0.72)
    }

    private var eraserOrHighlighterWidthRange: ClosedRange<CGFloat> {
        switch settings.selectedTool {
        case .eraser: return 8...96
        case .highlighter: return 8...48
        default: return 1...24
        }
    }

    private var widthBinding: Binding<CGFloat> {
        Binding(
            get: { settings.width(for: settings.selectedTool) },
            set: { settings.setWidth($0, for: settings.selectedTool) }
        )
    }

    private var currentColorHex: String {
        settings.selectedTool == .highlighter ? settings.highlighterColorHex : settings.colorPenColorHex
    }

    private var spectrumColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: currentColorHex) },
            set: { setCurrentColorHex($0.hexString) }
        )
    }

    private func setCurrentColorHex(_ hex: String) {
        if settings.selectedTool == .colorPen {
            settings.colorPenColorHex = hex
        } else if settings.selectedTool == .highlighter {
            settings.highlighterColorHex = hex
        }
    }
}

private struct MenuContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 메뉴를 열 때 시스템 스크롤 인디케이터를 한 번 깜빡여 스크롤 가능함을 알린다.
private struct ScrollIndicatorFlash: UIViewRepresentable {
    var token: Int

    func makeUIView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.flash(token: token)
    }

    final class ProbeView: UIView {
        private var lastToken = Int.min

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func flash(token: Int) {
            guard token != lastToken else { return }
            lastToken = token
            DispatchQueue.main.async { [weak self] in
                self?.enclosingScrollView()?.flashScrollIndicators()
            }
        }

        private func enclosingScrollView() -> UIScrollView? {
            var node: UIView? = self
            while let current = node {
                if let scroll = current as? UIScrollView {
                    return scroll
                }
                if let parent = current.superview {
                    for sub in parent.subviews {
                        if let scroll = sub as? UIScrollView { return scroll }
                        for child in sub.subviews {
                            if let scroll = child as? UIScrollView { return scroll }
                        }
                    }
                }
                node = current.superview
            }
            return nil
        }
    }
}

/// 스크롤이 맨 아래에 가까운지 추적해 "더보기" 힌트를 숨긴다.
private struct MenuScrollBottomTracker: ViewModifier {
    var onNearBottomChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                    return visibleBottom >= geometry.contentSize.height - 16
                } action: { _, nearBottom in
                    onNearBottomChange(nearBottom)
                }
        } else {
            content
        }
    }
}
