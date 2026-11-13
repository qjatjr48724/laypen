import SwiftUI
import PhotosUI

struct ContentView: View {
    private enum Destination {
        case home
        case canvas
    }

    @StateObject private var session = DrawingSessionModel()
    @AppStorage(AppColorThemeStore.key) private var colorThemeRaw = AppColorTheme.system.rawValue
    @State private var photoItem: PhotosPickerItem?
    @State private var destination: Destination = .home
    @State private var showMacLink = false
    @State private var macPreferredName: String?
    @State private var macAutoConnect = false
    @State private var savedPeers: [LinkTrustStore.SavedPeer] = []

    private var colorTheme: Binding<AppColorTheme> {
        Binding(
            get: { AppColorTheme(rawValue: colorThemeRaw) ?? .system },
            set: { colorThemeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            switch destination {
            case .home:
                HomeView(
                    colorTheme: colorTheme,
                    savedPeers: savedPeers,
                    onConnectSaved: { peer in
                        openMacLink(preferredName: peer.name, autoConnect: true)
                    },
                    onConnectOtherMac: {
                        openMacLink(preferredName: nil, autoConnect: false)
                    },
                    onBlankCanvas: {
                        session.startBlankCanvas()
                        destination = .canvas
                    },
                    onPickPhoto: { image in
                        session.startWithPhoto(image)
                        destination = .canvas
                    }
                )
            case .canvas:
                canvas
            }
        }
        .preferredColorScheme(colorTheme.wrappedValue.preferredColorScheme)
        .onAppear {
            let openedFromShare = session.bootstrap()
            refreshSavedPeers()
            if openedFromShare {
                destination = .canvas
            }
        }
        .onOpenURL { _ in
            if session.consumePendingShareIfNeeded() {
                destination = .canvas
            }
        }
        .fullScreenCover(isPresented: $showMacLink, onDismiss: {
            macPreferredName = nil
            macAutoConnect = false
            refreshSavedPeers()
        }) {
            MacLinkView(
                settings: $session.settings,
                preferredPeerName: macPreferredName,
                autoConnectTrusted: macAutoConnect
            )
        }
    }

    private var canvas: some View {
        ZStack {
            AnnotatedCanvas(
                drawing: $session.drawing,
                shapes: $session.shapes,
                selectedShapeID: $session.selectedShapeID,
                canUndo: $session.canUndo,
                canRedo: $session.canRedo,
                viewport: $session.viewport,
                layoutAnchorSize: session.layoutAnchorSize,
                tool: session.currentTool,
                isDrawingEnabled: session.settings.isDrawingEnabled,
                inputMode: session.settings.inputMode,
                isPlacingWhiteRect: session.isPlacingWhiteRect,
                backgroundImage: session.backgroundImage,
                onShapesChanged: { session.persist() },
                onWhiteRectPlacementFinished: { session.endWhiteRectPlacement() },
                onCanvasSizeChange: { session.noteCanvasSize($0) }
            )
            .ignoresSafeArea()

            if session.isPlacingWhiteRect {
                VStack {
                    Text("드래그로 상자 크기 지정")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThickMaterial, in: Capsule())
                        .padding(.top, 12)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            EdgeSnappingDraggable { maxHeight in
                FloatingToolbar(
                    settings: $session.settings,
                    isMenuOpen: $session.isMenuOpen,
                    photoItem: $photoItem,
                    isPlacingWhiteRect: session.isPlacingWhiteRect,
                    isSavingPhoto: session.isSavingPhoto,
                    isPreparingShare: session.isPreparingShare,
                    canUndo: session.canUndo,
                    canRedo: session.canRedo,
                    onUndo: { session.undo() },
                    onRedo: { session.redo() },
                    onClearAll: { session.showClearConfirm = true },
                    onClearInk: { session.requestClearInk() },
                    onAddWhiteRect: { session.beginWhiteRectPlacement() },
                    onSavePhoto: {
                        Task { await session.saveAnnotatedPhoto() }
                    },
                    onExportShare: {
                        Task { await session.prepareShare() }
                    },
                    onConnectMac: {
                        openMacLink(preferredName: nil, autoConnect: false)
                    },
                    onGoHome: {
                        session.persist()
                        session.isMenuOpen = false
                        refreshSavedPeers()
                        destination = .home
                    },
                    availableHeight: maxHeight
                )
            }
        }
        .onChange(of: session.drawing) { _, _ in
            session.persist()
        }
        .onChange(of: session.settings) { _, _ in
            session.persistSettings()
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                session.setBackground(image)
                session.isMenuOpen = false
                photoItem = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            session.persist()
        }
        .confirmationDialog("필기와 도형을 모두 삭제할까요?", isPresented: $session.showClearConfirm, titleVisibility: .visible) {
            Button("전체 삭제", role: .destructive) {
                session.clearAllConfirmed()
            }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("필기만 삭제할까요? (상자는 유지)", isPresented: $session.showClearInkConfirm, titleVisibility: .visible) {
            Button("필기만 삭제", role: .destructive) {
                session.clearInkConfirmed()
            }
            Button("취소", role: .cancel) {}
        }
        .alert("알림", isPresented: Binding(
            get: { session.saveMessage != nil },
            set: { if !$0 { session.saveMessage = nil } }
        )) {
            Button("확인", role: .cancel) { session.saveMessage = nil }
        } message: {
            Text(session.saveMessage ?? "")
        }
        .laypenShareSheet(image: $session.shareImage)
    }

    private func openMacLink(preferredName: String?, autoConnect: Bool) {
        macPreferredName = preferredName
        macAutoConnect = autoConnect
        showMacLink = true
    }

    private func refreshSavedPeers() {
        savedPeers = LinkTrustStore.savedPeers()
    }
}
