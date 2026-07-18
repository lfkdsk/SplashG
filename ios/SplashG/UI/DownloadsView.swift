import SwiftUI
import Kingfisher

/// The in-app downloads library. Tap a photo for the wallpaper flow.
struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss

    @State private var selected: DownloadItem?

    private let columns = [GridItem(.flexible(), spacing: 4),
                           GridItem(.flexible(), spacing: 4),
                           GridItem(.flexible(), spacing: 4)]

    var body: some View {
        NavigationStack {
            Group {
                if downloads.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Theme.subtle)
                        Text("Nothing downloaded yet")
                            .font(.headline)
                        Text("Tap the arrow on any photo to keep it here for offline viewing and wallpapers.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtle)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(downloads.items) { item in
                                tile(item)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $selected) { item in
                WallpaperPreviewView(item: item)
            }
            .task {
                if Config.demoScreen == "wallpaper", selected == nil {
                    selected = downloads.items.first
                }
            }
        }
    }

    private func tile(_ item: DownloadItem) -> some View {
        Button {
            selected = item
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    KFImage(source: .provider(LocalFileImageDataProvider(fileURL: downloads.fileURL(for: item))))
                        .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 400, height: 400)))
                        .placeholder { Rectangle().fill(Theme.card) }
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        }
        .buttonStyle(.plain)
    }
}

/// Full-bleed preview with a lock-screen mock overlay; hand-off buttons.
/// iOS has no set-wallpaper API, so the flow is: preview → save to Photos
/// → user sets it from the Photos app / Settings.
struct WallpaperPreviewView: View {
    let item: DownloadItem
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss

    @State private var showClock = true
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            KFImage(source: .provider(LocalFileImageDataProvider(fileURL: downloads.fileURL(for: item))))
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .onTapGesture { withAnimation { showClock.toggle() } }

            if showClock {
                lockScreenMock
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.ultraThinMaterial))
                    .foregroundStyle(.white)
            }
            .padding(.trailing, 20)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) { actions }
        .statusBarHidden()
    }

    private var lockScreenMock: some View {
        VStack(spacing: 2) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 17, weight: .medium))
            Text(Date.now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 84, weight: .thin))
            Spacer()
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 8)
        .padding(.top, 70)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if saved {
                Text("Saved to Photos — set it as wallpaper from the Photos app (share sheet → Use as Wallpaper).")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            HStack(spacing: 12) {
                Button {
                    do {
                        try downloads.saveToPhotos(item)
                        saved = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Label(saved ? "Saved" : "Save to Photos",
                          systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(saved ? Color.green.opacity(0.8) : Theme.accent))
                }

                ShareLink(item: downloads.fileURL(for: item)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                }

                Button(role: .destructive) {
                    downloads.delete(item)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.bottom, 24)
    }
}
