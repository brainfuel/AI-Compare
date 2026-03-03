import Foundation

actor ConversationStore {
    private let storeURL: URL
    private let mediaStoreDirectoryURL: URL

    init(storeURL: URL, mediaStoreDirectoryURL: URL) {
        self.storeURL = storeURL
        self.mediaStoreDirectoryURL = mediaStoreDirectoryURL
    }

    func loadConversations() throws -> [SavedConversation] {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([SavedConversation].self, from: data) else {
            return []
        }

        let normalized = normalizeConversations(decoded)
        if normalized.didChange {
            try writeConversations(normalized.conversations)
        }
        return normalized.conversations
    }

    func saveConversations(_ conversations: [SavedConversation]) throws -> [SavedConversation] {
        let normalized = normalizeConversations(conversations)
        try writeConversations(normalized.conversations)
        return normalized.conversations
    }

    func normalizeMedia(_ mediaItems: [GeneratedMedia]) -> [GeneratedMedia] {
        persistGeneratedMediaInPlace(mediaItems).media
    }

    private func writeConversations(_ conversations: [SavedConversation]) throws {
        let data = try JSONEncoder().encode(conversations)
        try data.write(to: storeURL, options: .atomic)
    }

    private func normalizeConversations(_ conversations: [SavedConversation]) -> (conversations: [SavedConversation], didChange: Bool) {
        var didChange = false
        let normalized = conversations.map { conversation in
            var mutable = conversation
            let normalizedMessages = normalizeMessages(conversation.messages)
            mutable.messages = normalizedMessages.messages
            didChange = didChange || normalizedMessages.didChange
            return mutable
        }
        return (normalized, didChange)
    }

    private func normalizeMessages(_ messages: [ChatMessage]) -> (messages: [ChatMessage], didChange: Bool) {
        var didChange = false
        let normalized = messages.map { message in
            let normalizedMedia = persistGeneratedMediaInPlace(message.generatedMedia)
            didChange = didChange || normalizedMedia.didChange
            if normalizedMedia.didChange {
                return ChatMessage(
                    id: message.id,
                    role: message.role,
                    text: message.text,
                    attachments: message.attachments,
                    generatedMedia: normalizedMedia.media
                )
            }
            return message
        }
        return (normalized, didChange)
    }

    private func persistGeneratedMediaInPlace(_ mediaItems: [GeneratedMedia]) -> (media: [GeneratedMedia], didChange: Bool) {
        guard !mediaItems.isEmpty else { return (mediaItems, false) }

        var didChange = false
        var normalized: [GeneratedMedia] = []
        normalized.reserveCapacity(mediaItems.count)

        for media in mediaItems {
            guard let base64 = media.base64Data, !base64.isEmpty else {
                normalized.append(media)
                continue
            }

            guard let data = Data(base64Encoded: base64) else {
                normalized.append(media)
                continue
            }

            let fileURL = mediaStoreDirectoryURL
                .appendingPathComponent(media.id.uuidString)
                .appendingPathExtension(media.mimeType.fileExtensionHint)

            do {
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    try data.write(to: fileURL, options: .atomic)
                }
                normalized.append(
                    GeneratedMedia(
                        id: media.id,
                        kind: media.kind,
                        mimeType: media.mimeType,
                        base64Data: nil,
                        remoteURL: fileURL
                    )
                )
                didChange = true
            } catch {
                normalized.append(media)
            }
        }

        return (normalized, didChange)
    }
}

private extension String {
    var fileExtensionHint: String {
        let parts = split(separator: "/")
        guard let last = parts.last else { return "bin" }
        let cleaned = String(last).replacingOccurrences(of: "+xml", with: "")
        return cleaned.isEmpty ? "bin" : cleaned
    }
}
