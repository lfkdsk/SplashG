import SwiftUI
import UIKit
import Kingfisher

/// One pager page: a UIScrollView-backed zoomable image. Native pinch,
/// pan, and double-tap-to-zoom; while zoomed the scroll view owns drags,
/// so the pager and the pull-down-dismiss stay quiet (isZoomed binding).
struct ZoomableImageView: UIViewRepresentable {
    let photo: Photo
    @Binding var isZoomed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isZoomed: $isZoomed)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator

        let imageView = UIImageView(frame: scroll.bounds)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.backgroundColor = .clear
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        // Thumbnail first (usually cached from the grid), then full-res on
        // top of it, with the CDN backup as fallback.
        var fullOptions: KingfisherOptionsInfo = [
            .keepCurrentImageWhileLoading,
            .transition(.fade(0.2)),
            .retryStrategy(DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(1))),
        ]
        if let backup = photo.backupFullURL {
            fullOptions.append(.alternativeSources([.network(backup)]))
        }
        let fullURL = photo.fullURL
        imageView.kf.setImage(with: photo.thumbURL) { _ in
            imageView.kf.setImage(with: fullURL, options: fullOptions)
        }

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        // Reset zoom when SwiftUI reuses the page for a new photo.
        if context.coordinator.photoId != photo.id {
            context.coordinator.photoId = photo.id
            scroll.setZoomScale(1, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var photoId: String?
        private var isZoomed: Binding<Bool>

        init(isZoomed: Binding<Bool>) {
            self.isZoomed = isZoomed
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Keep the (aspect-fit) content centered while zoomed out of bounds.
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
            DispatchQueue.main.async {
                self.isZoomed.wrappedValue = scrollView.zoomScale > 1.01
            }
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = scroll.bounds.size
                let scale: CGFloat = 2.5
                let zoomRect = CGRect(x: point.x - size.width / (2 * scale),
                                      y: point.y - size.height / (2 * scale),
                                      width: size.width / scale,
                                      height: size.height / scale)
                scroll.zoom(to: zoomRect, animated: true)
            }
        }
    }
}
