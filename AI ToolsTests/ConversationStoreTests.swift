import XCTest
@testable import AI_Tools

@MainActor
final class ConversationStoreTests: XCTestCase {
    private var tempRootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AI Tools ConversationStore Tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRootURL {
            try? FileManager.default.removeItem(at: tempRootURL)
        }
        tempRootURL = nil
        try super.tearDownWithError()
    }

    func testSaveAndLoadConversationsRoundTripAndPersistMediaFiles() throws {
        let mediaDirectoryURL = tempRootURL.appendingPathComponent("media", isDirectory: true)
        guard let store = ConversationStore(mediaStoreDirectoryURL: mediaDirectoryURL) else {
            XCTFail("Store should initialize")
            return
        }

        let generatedMediaData = Data("fake-image-data".utf8).base64EncodedString()
        let conversation = SavedConversation(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            provider: .chatGPT,
            title: "Test Conversation",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            modelID: "gpt-4.1-mini",
            messages: [
                ChatMessage(
                    id: UUID(uuidString: "66666666-7777-8888-9999-aaaaaaaaaaaa")!,
                    role: .assistant,
                    text: "hello",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_100),
                    attachments: [],
                    generatedMedia: [
                        GeneratedMedia(
                            id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
                            kind: .image,
                            mimeType: "image/png",
                            base64Data: generatedMediaData
                        )
                    ],
                    inputTokens: 12,
                    outputTokens: 34,
                    modelID: "gpt-4.1-mini"
                )
            ]
        )

        let saved = try store.saveConversations([conversation])

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.id, conversation.id)
        XCTAssertNil(saved.first?.messages.first?.generatedMedia.first?.base64Data)
        XCTAssertNotNil(saved.first?.messages.first?.generatedMedia.first?.remoteURL)

        let storeFileURL = tempRootURL.appendingPathComponent("conversations_v1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeFileURL.path))

        let loaded = try store.loadConversations()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, conversation.id)
        XCTAssertEqual(loaded.first?.provider, .chatGPT)
        XCTAssertEqual(loaded.first?.modelID, "gpt-4.1-mini")
        XCTAssertNil(loaded.first?.messages.first?.generatedMedia.first?.base64Data)
        XCTAssertEqual(loaded.first?.messages.first?.generatedMedia.first?.remoteURL?.isFileURL, true)

        let mediaFiles = try FileManager.default.contentsOfDirectory(at: mediaDirectoryURL, includingPropertiesForKeys: nil)
        XCTAssertEqual(mediaFiles.count, 1)
    }

    func testLoadConversationsReturnsEmptyWhenNoStoreFileExists() throws {
        let mediaDirectoryURL = tempRootURL.appendingPathComponent("media", isDirectory: true)
        guard let store = ConversationStore(mediaStoreDirectoryURL: mediaDirectoryURL) else {
            XCTFail("Store should initialize")
            return
        }

        XCTAssertTrue(try store.loadConversations().isEmpty)
    }
}
