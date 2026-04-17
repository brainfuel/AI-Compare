#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AttachmentDropTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isDropTargeted: Bool
    var onImageURLsDropped: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DropInterceptingTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.string = text
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.registerForDraggedTypes([.fileURL, .tiff, .png, .URL])

        textView.onDropTargetChanged = { isTargeted in
            Task { @MainActor in
                context.coordinator.parent.isDropTargeted = isTargeted
            }
        }
        textView.onImageURLsDropped = { urls in
            Task { @MainActor in
                context.coordinator.parent.onImageURLsDropped(urls)
                context.coordinator.parent.isDropTargeted = false
            }
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? DropInterceptingTextView else { return }
        if textView.string != text {
            textView.string = text
        }

        textView.onDropTargetChanged = { isTargeted in
            Task { @MainActor in
                context.coordinator.parent.isDropTargeted = isTargeted
            }
        }
        textView.onImageURLsDropped = { urls in
            Task { @MainActor in
                context.coordinator.parent.onImageURLsDropped(urls)
                context.coordinator.parent.isDropTargeted = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AttachmentDropTextEditor

        init(parent: AttachmentDropTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class DropInterceptingTextView: NSTextView {
    var onDropTargetChanged: ((Bool) -> Void)?
    var onImageURLsDropped: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = droppedImageURLs(from: sender.draggingPasteboard)
        if !urls.isEmpty {
            onDropTargetChanged?(true)
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = droppedImageURLs(from: sender.draggingPasteboard)
        if !urls.isEmpty {
            onDropTargetChanged?(true)
            return .copy
        }
        onDropTargetChanged?(false)
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTargetChanged?(false)
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedImageURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else {
            onDropTargetChanged?(false)
            return super.performDragOperation(sender)
        }

        onImageURLsDropped?(urls)
        onDropTargetChanged?(false)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDropTargetChanged?(false)
        super.concludeDragOperation(sender)
    }

    private func droppedImageURLs(from pasteboard: NSPasteboard) -> [URL] {
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = pasteboard.readObjects(forClasses: classes, options: options) as? [URL] else {
            return []
        }
        return urls.filter { url in
            if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               contentType.conforms(to: .image) {
                return true
            }
            if let type = UTType(filenameExtension: url.pathExtension),
               type.conforms(to: .image) {
                return true
            }
            return false
        }
    }
}
#endif
