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

    private let palette = ["#E53935", "#1E88E5", "#43A047", "#FB8C00", "#8E24AA", "#111111"]
    private let buttonSide: CGFloat = 34
    @State private var didCopyHex = false
    @State private var showShortcutsGuide = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isMenuOpen {
                menuPanel
            }

            HStack(spacing: 6) {
                Button {
                    isMenuOpen.toggle()
                } label: {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.body.weight(.semibold))
                        .frame(width: buttonSide, height: buttonSide)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    settings.isDrawingEnabled.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: settings.isDrawingEnabled ? "pencil" : "pencil.slash")
                            .font(.caption.weight(.semibold))
                        Text(settings.isDrawingEnabled ? "ON" : "OFF")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(onOffForeground)
                    .frame(minWidth: 56, minHeight: buttonSide)
                    .padding(.horizontal, 6)
                    .background(onOffBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .sheet(isPresented: $showShortcutsGuide) {
            ShortcutsGuideSheet()
        }
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

    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(DrawingToolKind.allCases) { kind in
                    toolCell(kind)
                }
            }

            HStack(spacing: 8) {
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
                in: settings.selectedTool == .highlighter || settings.selectedTool == .eraser ? 8...48 : 1...24
            )

            if settings.selectedTool == .colorPen || settings.selectedTool == .highlighter {
                Text("색상")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(palette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if currentColorHex.uppercased() == hex.uppercased() {
                                    Circle().strokeBorder(Color.primary, lineWidth: 2)
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
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("스펙트럼에서 색상 선택")
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: currentColorHex))
                        .frame(width: 14, height: 14)
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
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
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

                    Spacer()
                    Text("스펙트럼")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .animation(.easeOut(duration: 0.15), value: didCopyHex)
            }

            Divider()

            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(
                        "사진 선택",
                        systemImage: "photo.on.rectangle"
                    )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)

                Button(action: onAddWhiteRect) {
                    Label(
                        isPlacingWhiteRect ? "크기 지정" : "상자 추가",
                        systemImage: "rectangle.dashed"
                    )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isPlacingWhiteRect ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button(action: onSavePhoto) {
                    HStack(spacing: 6) {
                        if isSavingPhoto {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isSavingPhoto ? "저장 중…" : "사진으로 저장")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSavingPhoto || isPreparingShare)

                Button(action: onExportShare) {
                    HStack(spacing: 6) {
                        if isPreparingShare {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isPreparingShare ? "준비 중…" : "내보내기")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSavingPhoto || isPreparingShare)
            }

            HStack(spacing: 8) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canUndo ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(canUndo ? Color.accentColor : Color.secondary.opacity(0.35))
                .disabled(!canUndo)
                .accessibilityLabel("실행 취소")

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canRedo ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(canRedo ? Color.accentColor : Color.secondary.opacity(0.35))
                .disabled(!canRedo)
                .accessibilityLabel("다시 실행")

                Spacer()

                Button(role: .destructive, action: onClearAll) {
                    Image(systemName: "trash")
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            Button {
                showShortcutsGuide = true
            } label: {
                Label("단축어로 빠르게 열기", systemImage: "bolt.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 248)
        .background(Color(.secondarySystemBackground).opacity(0.97), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func inputModeButton(
        title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                // 이미 선택된 지우개를 다시 탭 → 필기만 삭제
                onClearInk()
            } else {
                settings.selectedTool = kind
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: kind.systemImage)
                        .font(.title3)
                        .foregroundStyle(fg)
                        .frame(maxWidth: .infinity)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .background(Circle().fill(Color.white).padding(1))
                    }
                }
                Text(kind.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(fg)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: selected ? 3 : 1
                    )
            )
            .shadow(color: selected ? Color.accentColor.opacity(0.35) : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                guard kind == .eraser else { return }
                settings.selectedTool = .eraser
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
