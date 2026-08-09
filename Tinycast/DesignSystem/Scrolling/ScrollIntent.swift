import SwiftUI

/// A scroll request; reset and follow need different ops, so the caller states which.
struct ScrollIntent: Equatable {
    enum Kind {
        /// Reset to the content origin; the anchor sits at offset 0, so nothing is guessed.
        case top
        /// Keyboard nav: minimal scroll-to-visible, leaving a visible row where it is.
        case follow
    }

    var kind: Kind
    /// Distinguishes back-to-back intents of the same kind so `onChange` still fires.
    var nonce = UUID()
}

extension View {
    /// Marks the content top as the `scrollToOrigin` target; apply after the padding.
    func scrollOriginAnchor() -> some View {
        overlay(alignment: .top) {
            Color.clear.frame(height: 0).id(ScrollOrigin.id)
        }
    }

    /// Restores the origin when the header's safe-area inset settles after a scroll view mounts.
    func pinOriginOnInsetSettle(_ scroll: ScrollIntent, proxy: ScrollViewProxy) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, _ in
            // A settle during keyboard nav must not yank the list back, hence the `.top` guard.
            guard scroll.kind == .top else { return }
            proxy.scrollToOrigin()
        }
    }
}

private enum ScrollOrigin {
    nonisolated static let id = "scroll-origin-anchor"
}

extension ScrollViewProxy {
    /// Restores the exact resting offset; needs `scrollOriginAnchor()` on the content.
    func scrollToOrigin() {
        scrollTo(ScrollOrigin.id, anchor: .top)
    }

    /// Minimal scroll-to-visible, so the list stays put as the selection walks it.
    func reveal(_ id: String) {
        scrollTo(id, anchor: nil)
    }
}
