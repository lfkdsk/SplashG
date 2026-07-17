import SwiftUI
import Kingfisher

/// Waterfall cell: cropped thumbnail with a floating download button,
/// like the MyerSplash editor feed. Downloads go to the in-app library
/// (DownloadManager), not straight to the photo roll.
struct PhotoCard: View {
    let photo: Photo
    var onTap: () -> Void

    @EnvironmentObject private var downloads: DownloadManager
    @State private var failed = false

    var body: some View {
        Color.clear
            .aspectRatio(photo.aspect, contentMode: .fit)
            .overlay {
                KFImage(photo.thumbURL)
                    .alternativeSources(photo.backupThumbURL.map { [.network($0)] } ?? [])
                    .placeholder { Rectangle().fill(Theme.card) }
                    .retry(maxCount: 2, interval: .seconds(1))
                    .fade(duration: 0.25)
                    .cancelOnDisappear(true)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomTrailing) { downloadButton }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture(perform: onTap)
    }

    private var downloadButton: some View {
        Button {
            guard !downloads.isDownloaded(photo), !downloads.isDownloading(photo) else { return }
            failed = false
            Task {
                do { try await downloads.download(photo) } catch { failed = true }
            }
        } label: {
            Group {
                if downloads.isDownloaded(photo) {
                    Image(systemName: "checkmark")
                } else if downloads.isDownloading(photo) {
                    ProgressView().controlSize(.mini)
                } else if failed {
                    Image(systemName: "exclamationmark.triangle")
                } else {
                    Image(systemName: "arrow.down")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 32, height: 32)
            .background(Circle().fill(.ultraThinMaterial))
            .foregroundStyle(downloads.isDownloaded(photo) ? Color.green : .white)
        }
        .padding(8)
    }
}
