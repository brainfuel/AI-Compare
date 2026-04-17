import Foundation
import SwiftData

@MainActor
final class ConversationStore {
    private let context: ModelContext
    private let mediaStoreDirectoryURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init?(context: ModelContext, mediaStoreDirectoryURL: URL) {
        self.context = context
        self.mediaStoreDirectoryURL = mediaStoreDirectoryURL
        do {
            try FileManager.default.createDirectory(
                at: mediaStoreDirectoryURL, withIntermediateDirectories: true
            )
            try migrateFromJSONIfNeeded()
        } catch {
            return nil
        }
    }

    // MARK: - Public API

    func loadConversations() throws -> [SavedConversation] {
        let descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toStruct(decoder: decoder) }
    }

    func saveConversations(_ conversations: [SavedConversation]) throws -> [SavedConversation] {
        let existing    = try context.fetch(FetchDescriptor<ConversationRecord>())
        let byID        = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let snapshotIDs = Set(conversations.map(\.id))

        for record in existing where !snapshotIDs.contains(record.id) {
            context.delete(record) // cascades to MessageRecords
        }
        for conversation in conversations {
            if let record = byID[conversation.id] {
                upsertRecord(record, from: conversation)
            } else {
                context.insert(makeConversationRecord(from: conversation))
            }
        }
        try context.save()
        return try loadConversations()
    }

    func normalizeMedia(_ mediaItems: [GeneratedMedia]) -> [GeneratedMedia] {
        persistGeneratedMediaInPlace(mediaItems).media
    }

    // MARK: - Record construction

    private func makeConversationRecord(from conversation: SavedConversation) -> ConversationRecord {
        let record = ConversationRecord(
            id: conversation.id,
            providerRaw: conversation.provider.rawValue,
            title: conversation.title,
            updatedAt: conversation.updatedAt,
            modelID: conversation.modelID
        )
        record.messages = conversation.messages.map { makeMessageRecord(from: $0) }
        return record
    }

    private func makeMessageRecord(from message: ChatMessage) -> MessageRecord {
        MessageRecord(
            id: message.id,
            roleRaw: message.role.rawValue,
            text: message.text,
            createdAt: message.createdAt,
            attachmentsData:   (try? encoder.encode(message.attachments))    ?? Data(),
            generatedMediaData: (try? encoder.encode(message.generatedMedia)) ?? Data(),
            inputTokens:  message.inputTokens,
            outputTokens: message.outputTokens,
            modelID: message.modelID
        )
    }

    /// Merges a snapshot conversation into an existing record, avoiding unnecessary work on
    /// immutable fields (role, text, attachments) and only touching what can change.
    private func upsertRecord(_ record: ConversationRecord, from conversation: SavedConversation) {
        record.providerRaw = conversation.provider.rawValue
        record.title       = conversation.title
        record.updatedAt   = conversation.updatedAt
        record.modelID     = conversation.modelID

        let existingByID = Dictionary(uniqueKeysWithValues: record.messages.map { ($0.id, $0) })
        let newIDs       = Set(conversation.messages.map(\.id))

        for msg in record.messages where !newIDs.contains(msg.id) {
            context.delete(msg)
        }
        for message in conversation.messages {
            if let existing = existingByID[message.id] {
                // Only mutable fields: token counts and persisted media references
                existing.inputTokens       = message.inputTokens
                existing.outputTokens      = message.outputTokens
                existing.modelID           = message.modelID
                existing.generatedMediaData = (try? encoder.encode(message.generatedMedia)) ?? existing.generatedMediaData
            } else {
                let msgRecord = makeMessageRecord(from: message)
                msgRecord.conversation = record
                context.insert(msgRecord)
            }
        }
    }

    // MARK: - Media normalisation (writes base64 blobs to disk, replaces with file URLs)

    private func persistGeneratedMediaInPlace(
        _ mediaItems: [GeneratedMedia]
    ) -> (media: [GeneratedMedia], didChange: Bool) {
        guard !mediaItems.isEmpty else { return (mediaItems, false) }
        var didChange = false
        var normalized: [GeneratedMedia] = []
        normalized.reserveCapacity(mediaItems.count)

        for media in mediaItems {
            guard let base64 = media.base64Data, !base64.isEmpty,
                  let data = Data(base64Encoded: base64) else {
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
                normalized.append(GeneratedMedia(
                    id: media.id, kind: media.kind, mimeType: media.mimeType,
                    base64Data: nil, remoteURL: fileURL
                ))
                didChange = true
            } catch {
                normalized.append(media)
            }
        }
        return (normalized, didChange)
    }

    // MARK: - One-time migration from conversations_v1.json

    private func migrateFromJSONIfNeeded() throws {
        let jsonURL = mediaStoreDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("conversations_v1.json")

        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return }

        let data          = try Data(contentsOf: jsonURL)
        let conversations = try decoder.decode([SavedConversation].self, from: data)

        for conversation in conversations {
            context.insert(makeConversationRecord(from: conversation))
        }
        try context.save()

        // Rename so migration never runs again
        let doneURL = jsonURL.deletingPathExtension().appendingPathExtension("json.migrated")
        try? FileManager.default.moveItem(at: jsonURL, to: doneURL)
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
