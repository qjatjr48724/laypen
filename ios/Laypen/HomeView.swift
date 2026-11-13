import PhotosUI
import SwiftUI

/// 앱을 켰을 때 가운데에 선택지만 두는 첫 화면.
struct HomeView: View {
    @Binding var colorTheme: AppColorTheme
    var savedPeers: [LinkTrustStore.SavedPeer]
    var onConnectSaved: (LinkTrustStore.SavedPeer) -> Void
    var onConnectOtherMac: () -> Void
    var onBlankCanvas: () -> Void
    var onPickPhoto: (UIImage) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Laypen")
                        .font(.system(size: 42, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                    Text("무엇을 할까요?")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    if savedPeers.isEmpty {
                        homeButton(
                            title: "맥에 연결",
                            subtitle: "근처 맥을 찾아 필기·조작합니다",
                            systemImage: "laptopcomputer",
                            style: .regular,
                            action: onConnectOtherMac
                        )
                    } else {
                        ForEach(savedPeers) { peer in
                            homeButton(
                                title: "\(peer.name)에 연결",
                                subtitle: "저장해 둔 맥으로 바로 붙습니다",
                                systemImage: "laptopcomputer",
                                style: .savedPeer,
                                badge: "저장됨",
                                action: { onConnectSaved(peer) }
                            )
                        }
                        homeButton(
                            title: "다른 맥에 연결",
                            subtitle: "목록에서 새 맥을 고릅니다",
                            systemImage: "laptopcomputer.and.iphone",
                            style: .regular,
                            action: onConnectOtherMac
                        )
                    }

                    homeButton(
                        title: "빈 화면에서 필기",
                        subtitle: "흰 캔버스를 엽니다",
                        systemImage: "square.and.pencil",
                        style: .regular,
                        action: onBlankCanvas
                    )

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        homeLabel(
                            title: "사진 선택해서 필기",
                            subtitle: "앨범에서 고른 이미지 위에 그립니다",
                            systemImage: "photo.on.rectangle.angled",
                            style: .regular
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 380)
            }
            .padding(.horizontal, 28)

            VStack {
                HStack {
                    Spacer()
                    themeMenu
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                onPickPhoto(image)
                photoItem = nil
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(.systemBackground), Color(.secondarySystemBackground)]
                : [Color(.systemGroupedBackground), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var themeMenu: some View {
        Menu {
            ForEach(AppColorTheme.allCases) { theme in
                Button {
                    colorTheme = theme
                } label: {
                    Label(theme.title, systemImage: theme.systemImage)
                    if colorTheme == theme {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: colorTheme.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .accessibilityLabel("화면 테마")
        .accessibilityValue(colorTheme.title)
    }

    private enum HomeActionStyle {
        case savedPeer
        case regular
    }

    private func homeButton(
        title: String,
        subtitle: String,
        systemImage: String,
        style: HomeActionStyle,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            homeLabel(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                style: style,
                badge: badge
            )
        }
        .buttonStyle(.plain)
    }

    private func homeLabel(
        title: String,
        subtitle: String,
        systemImage: String,
        style: HomeActionStyle,
        badge: String? = nil
    ) -> some View {
        let isSaved = style == .savedPeer
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: isSaved ? 22 : 20, weight: .semibold))
                .foregroundStyle(isSaved ? Color.white : Color.accentColor)
                .frame(width: 40, height: 40)
                .background {
                    if isSaved {
                        Circle().fill(Color.accentColor)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(isSaved ? .title3 : .body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSaved ? Color.accentColor : Color.secondary.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isSaved ? 18 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSaved
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12)
                        : Color(.secondarySystemGroupedBackground)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSaved
                        ? Color.accentColor.opacity(0.45)
                        : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06),
                    lineWidth: isSaved ? 1.5 : 1
                )
        )
    }
}
