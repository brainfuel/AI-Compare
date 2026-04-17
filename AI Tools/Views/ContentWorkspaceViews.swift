import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

protocol SidebarConversationSummarizing: Identifiable where ID == UUID {
    var title: String { get }
    var updatedAt: Date { get }
}

extension SavedConversation: SidebarConversationSummarizing {}
extension CompareConversation: SidebarConversationSummarizing {}

// MARK: - Sidebar

struct ConversationSidebarView: View {
    @ObservedObject var viewModel: PlaygroundViewModel
    @ObservedObject var compareViewModel: CompareViewModel
    @Binding var workspaceMode: WorkspaceMode
    @State private var historySearch = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    if workspaceMode == .single {
                        viewModel.startNewChat()
                    } else {
                        compareViewModel.startNewThread()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(workspaceMode == .single ? "New Chat" : "New Compare")
                .buttonStyle(.borderedProminent)

                Spacer()

                Button(role: .destructive) {
                    if workspaceMode == .single {
                        viewModel.deleteSelectedConversation()
                    } else {
                        compareViewModel.deleteSelectedConversation()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(workspaceMode == .single ? "Delete Chat" : "Delete Compare")
                .buttonStyle(.bordered)
                .disabled(
                    workspaceMode == .single
                        ? viewModel.selectedConversationID == nil
                        : compareViewModel.selectedConversationID == nil
                )
            }

            TextField(workspaceMode == .single ? "Search History" : "Search Compares", text: $historySearch)
                .textFieldStyle(.roundedBorder)

            List {
                if workspaceMode == .single {
                    conversationList(
                        conversations: viewModel.filteredConversations(query: historySearch),
                        selectedConversationID: viewModel.selectedConversationID,
                        newRowTitle: "New Chat",
                        newRowIcon: "plus.bubble",
                        newRowAction: { viewModel.startNewChat() },
                        selectAction: { viewModel.selectConversation($0) }
                    )
                } else {
                    conversationList(
                        conversations: compareViewModel.filteredConversations(query: historySearch),
                        selectedConversationID: compareViewModel.selectedConversationID,
                        newRowTitle: "New Compare",
                        newRowIcon: "rectangle.3.group.bubble.left",
                        newRowAction: { compareViewModel.startNewThread() },
                        selectAction: { compareViewModel.selectConversation($0) }
                    )
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(AppTheme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(
                .easeInOut(duration: 0.2),
                value: workspaceMode == .single
                    ? viewModel.savedConversations.map(\.id)
                    : compareViewModel.savedConversations.map(\.id)
            )
        }
        .padding(8)
        .background(AppTheme.surfaceGrouped)
        .frame(minWidth: 280)
        .onChange(of: workspaceMode) { _, _ in
            historySearch = ""
        }
    }

    @ViewBuilder
    private func conversationList<Conversation: SidebarConversationSummarizing>(
        conversations: [Conversation],
        selectedConversationID: UUID?,
        newRowTitle: String,
        newRowIcon: String,
        newRowAction: @escaping () -> Void,
        selectAction: @escaping (UUID) -> Void
    ) -> some View {
        if selectedConversationID == nil {
            Button(action: newRowAction) {
                HStack {
                    Image(systemName: newRowIcon)
                    Text(newRowTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .listRowBackground(AppTheme.brandTint.opacity(0.14))
        }

        ForEach(conversations) { conversation in
            Button {
                selectAction(conversation.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .lineLimit(1)
                    Text(conversation.updatedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .listRowBackground(selectedConversationID == conversation.id ? AppTheme.brandTint.opacity(0.14) : Color.clear)
        }
    }
}

// MARK: - Workspace detail

struct WorkspaceDetailView: View {
    @ObservedObject var viewModel: PlaygroundViewModel
    @ObservedObject var compareViewModel: CompareViewModel
    @Binding var workspaceMode: WorkspaceMode
    let continueProviderInSingle: (AIProvider) -> Void
    @State private var showingUsageStats = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $workspaceMode) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if workspaceMode == .single {
                SingleWorkspaceView(viewModel: viewModel)
            } else {
                CompareWorkspaceView(
                    compareViewModel: compareViewModel,
                    continueProviderInSingle: continueProviderInSingle
                )
            }
        }
        .padding()
        .background(AppTheme.canvasBackground)
#if os(macOS)
        .frame(minWidth: 760)
#endif
        .navigationTitle("AI Compare")
        .toolbar {
            if workspaceMode == .single {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingUsageStats = true
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .help("Usage Stats")
                }
            }
        }
        .sheet(isPresented: $showingUsageStats) {
            UsageStatsSheet(
                modelID: viewModel.modelID,
                sessionInputTokens: viewModel.sessionInputTokens,
                sessionOutputTokens: viewModel.sessionOutputTokens,
                windows: viewModel.usageTimeWindows
            )
        }
    }
}

// MARK: - Single chat workspace

struct SingleWorkspaceView: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        VStack(spacing: 12) {
            SingleConfigurationSection(viewModel: viewModel)
            Divider()
            SingleMessagesSection(viewModel: viewModel)
            SingleComposerSection(viewModel: viewModel)
        }
    }
}

struct SingleConfigurationSection: View {
    @ObservedObject var viewModel: PlaygroundViewModel
    @State private var isKeyHidden = true

    var body: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Provider", selection: $viewModel.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedProvider) { _, newValue in
                    Task {
                        await viewModel.selectProvider(newValue)
                    }
                }

                HStack {
                    if isKeyHidden {
                        SecureField(viewModel.providerAPIKeyPlaceholder, text: apiKeyBinding)
                    } else {
                        TextField(viewModel.providerAPIKeyPlaceholder, text: apiKeyBinding)
                    }
                    Button(isKeyHidden ? "Show" : "Hide") {
                        isKeyHidden.toggle()
                    }
                }

                HStack {
                    Button("Load Models") {
                        Task {
                            await viewModel.refreshModels()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading || viewModel.currentAPIKey.isEmpty || !viewModel.canLoadModels)

                    if viewModel.availableModels.isEmpty {
                        Text(viewModel.currentAPIKey.isEmpty ? "Enter API key to load models" : "Load models to choose one")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !viewModel.availableModels.isEmpty {
                    Picker("Available Models", selection: modelSelectionBinding) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }

                TextField("System Instructions (optional)", text: $viewModel.systemInstruction, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .groupBoxStyle(ThemeGroupBoxStyle())
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { viewModel.currentAPIKey },
            set: { viewModel.updateCurrentAPIKey($0) }
        )
    }

    private var modelSelectionBinding: Binding<String> {
        Binding(
            get: { viewModel.modelID },
            set: { viewModel.selectModel($0) }
        )
    }
}

struct SingleMessagesSection: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    if viewModel.isLoading {
                        if viewModel.streamingText.isEmpty {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 16, height: 16)
                                Text("Thinking...")
                                    .foregroundStyle(.secondary)
                            }
                            .id("loading-indicator")
                        } else {
                            StreamingBubbleView(text: viewModel.streamingText)
                                .id("streaming-bubble")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    proxy.scrollTo("loading-indicator", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.streamingText) {
                proxy.scrollTo("streaming-bubble", anchor: .bottom)
            }
            .textSelection(.enabled)
        }
    }
}

struct SingleComposerSection: View {
    @ObservedObject var viewModel: PlaygroundViewModel
    @State private var prompt = ""
    @State private var isDropTargeted = false
    @State private var showingFileImporter = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.pendingAttachments.isEmpty {
                AttachmentStripView(
                    attachments: viewModel.pendingAttachments,
                    removeAction: { viewModel.removeAttachment(id: $0) }
                )
            }

            composerEditor

            HStack {
                statusView
                Spacer()
                Button("Attach") { showingFileImporter = true }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading)
                Button("Send") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        viewModel.isLoading ||
                        !viewModel.canSendRequests ||
                        (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.pendingAttachments.isEmpty)
                    )
            }
        }
        .padding(8)
        .background(AppTheme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            viewModel.addAttachments(fromResult: result)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let errorMessage = viewModel.errorMessage {
            Button { copyToClipboard(errorMessage) } label: {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Click to copy error")
        } else {
            Text("Ready").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var composerEditor: some View {
        Group {
#if os(macOS)
            AttachmentDropTextEditor(text: $prompt, isDropTargeted: $isDropTargeted) { urls in
                viewModel.addAttachments(fromResult: .success(urls))
            }
#else
            TextEditor(text: $prompt).focused($inputFocused).padding(8)
#endif
        }
        .frame(minHeight: 90, maxHeight: 150)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? AppTheme.brandTint : AppTheme.cardBorder,
                        lineWidth: isDropTargeted ? 2 : 1)
        }
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !viewModel.pendingAttachments.isEmpty else { return }
        prompt = ""
        inputFocused = false
        Task { await viewModel.send(text: text) }
    }
}

// MARK: - Compare workspace

struct CompareWorkspaceView: View {
    @ObservedObject var compareViewModel: CompareViewModel
    let continueProviderInSingle: (AIProvider) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(AIProvider.allCases) { provider in
                    CompareProviderColumnView(
                        compareViewModel: compareViewModel,
                        provider: provider,
                        continueProviderInSingle: continueProviderInSingle
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            CompareComposerSection(compareViewModel: compareViewModel)
        }
    }
}

struct CompareProviderColumnView: View {
    @ObservedObject var compareViewModel: CompareViewModel
    let provider: AIProvider
    let continueProviderInSingle: (AIProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName).font(.headline)
                Spacer()
                Button {
                    continueProviderInSingle(provider)
                } label: {
                    Image(systemName: "arrowshape.turn.up.right.circle").imageScale(.large)
                }
                .buttonStyle(.plain)
                .help("Open \(provider.displayName) compare history in Single mode")
                .disabled(!compareViewModel.canContinueInSingle(for: provider) || compareViewModel.isSending)

                if compareViewModel.hasAPIKey(for: provider) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("API key is configured")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Missing API key")
                }
            }

            HStack(spacing: 8) {
                if compareViewModel.modelsForPicker(for: provider).isEmpty {
                    Text("No models cached").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: compareModelBinding) {
                        ForEach(compareViewModel.modelsForPicker(for: provider), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Button("Load") {
                    Task { await compareViewModel.refreshModels(for: provider) }
                }
                .buttonStyle(.bordered)
                .disabled(compareViewModel.isSending || !compareViewModel.hasAPIKey(for: provider))
            }

            if let message = compareViewModel.providerStatusMessage(provider), !message.isEmpty {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        let displayedRuns = compareViewModel.runsChronological
                        if displayedRuns.isEmpty {
                            Text(compareEmptyStateMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(displayedRuns) { run in
                                CompareRunCardView(run: run, provider: provider).id(run.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .textSelection(.enabled)
                .onChange(of: compareViewModel.runs.count) {
                    if let lastID = compareViewModel.runsChronological.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
                .onChange(of: compareViewModel.selectedConversationID) {
                    if let lastID = compareViewModel.runsChronological.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let lastID = compareViewModel.runsChronological.last?.id {
                        DispatchQueue.main.async { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(10)
        .background(AppTheme.surfaceSecondary)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var compareEmptyStateMessage: String {
        if compareViewModel.hasAPIKey(for: provider) {
            return "No compare runs yet."
        }
        return "Add an API key in Single mode to start comparing."
    }

    private var compareModelBinding: Binding<String> {
        Binding(
            get: { compareViewModel.selectedModel(for: provider) },
            set: { compareViewModel.selectModel($0, for: provider) }
        )
    }
}

struct CompareRunCardView: View {
    let run: CompareRun
    let provider: AIProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(run.createdAt, format: .dateTime.hour().minute().second())
                .font(.caption2).foregroundStyle(.secondary)

            Text(run.prompt)
                .font(.subheadline)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.nodeInput.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if !run.attachments.isEmpty {
                ForEach(run.attachments) { MessageAttachmentView(attachment: $0) }
            }

            if let result = run.results[provider] {
                switch result.state {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).frame(width: 16, height: 16)
                        Text("Thinking...").foregroundStyle(.secondary)
                    }
                    if !result.text.isEmpty {
                        MarkdownText(result.text)
                            .padding(8).background(AppTheme.surfacePrimary).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                case .success:
                    if !result.text.isEmpty {
                        MarkdownText(result.text)
                            .padding(8).background(AppTheme.surfacePrimary).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if !result.generatedMedia.isEmpty {
                        ForEach(result.generatedMedia) { media in
                            AssistantMediaView(media: media).frame(maxWidth: 360).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    if result.inputTokens > 0 || result.outputTokens > 0 {
                        TokenUsageRow(modelID: result.modelID, inputTokens: result.inputTokens, outputTokens: result.outputTokens)
                    }
                case .failed:
                    if let error = result.errorMessage {
                        Button { copyToClipboard(error) } label: {
                            Text(error)
                                .font(.caption).foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain).help("Click to copy error")
                    }
                case .skipped:
                    Text(result.errorMessage ?? "Skipped").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(AppTheme.surfaceGrouped)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CompareComposerSection: View {
    @ObservedObject var compareViewModel: CompareViewModel
    @State private var prompt = ""
    @State private var isDropTargeted = false
    @State private var showingFileImporter = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !compareViewModel.pendingAttachments.isEmpty {
                AttachmentStripView(
                    attachments: compareViewModel.pendingAttachments,
                    removeAction: { compareViewModel.removeAttachment(id: $0) }
                )
            }

            Group {
#if os(macOS)
                AttachmentDropTextEditor(text: $prompt, isDropTargeted: $isDropTargeted) { urls in
                    compareViewModel.addAttachments(fromResult: .success(urls))
                }
#else
                TextEditor(text: $prompt).focused($inputFocused).padding(8)
#endif
            }
            .frame(minHeight: 90, maxHeight: 150)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDropTargeted ? AppTheme.brandTint : AppTheme.cardBorder,
                            lineWidth: isDropTargeted ? 2 : 1)
            }

            HStack {
                if let errorMessage = compareViewModel.errorMessage {
                    Button { copyToClipboard(errorMessage) } label: {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain).help("Click to copy error")
                } else {
                    Text(compareViewModel.composerStatusLabel).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Attach") { showingFileImporter = true }
                    .buttonStyle(.bordered)
                    .disabled(compareViewModel.isSending)
                Button("Send All") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        compareViewModel.isSending ||
                        (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && compareViewModel.pendingAttachments.isEmpty)
                    )
            }
        }
        .padding(8)
        .background(AppTheme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.cardBorder, lineWidth: 1))
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            compareViewModel.addAttachments(fromResult: result)
        }
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !compareViewModel.pendingAttachments.isEmpty else { return }
        prompt = ""
        inputFocused = false
        Task { await compareViewModel.sendCompare(text: text) }
    }
}

// MARK: - Shared subviews

/// Horizontal scrolling strip of pending attachment previews.
struct AttachmentStripView: View {
    let attachments: [PendingAttachment]
    let removeAction: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            AttachmentPreview(attachment: attachment)
                                .frame(width: 120, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Button { removeAction(attachment.id) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.65))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(attachment.name).lineLimit(1).font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role.label).font(.caption).foregroundStyle(.secondary)

            if !message.text.isEmpty {
                Group {
                    if message.role == .assistant {
                        MarkdownText(message.text)
                    } else {
                        Text(message.text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(message.role == .user ? AppTheme.nodeHuman.opacity(0.2) : AppTheme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if !message.attachments.isEmpty {
                ForEach(message.attachments) { MessageAttachmentView(attachment: $0) }
            }

            if !message.generatedMedia.isEmpty {
                ForEach(message.generatedMedia) { media in
                    AssistantMediaView(media: media).frame(maxWidth: 420).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if message.role == .assistant, message.inputTokens > 0 || message.outputTokens > 0 {
                TokenUsageRow(modelID: message.modelID ?? "", inputTokens: message.inputTokens, outputTokens: message.outputTokens)
            }
        }
    }
}

private struct StreamingBubbleView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MessageRole.assistant.label).font(.caption).foregroundStyle(.secondary)
            MarkdownText(text)
                .padding(10)
                .background(AppTheme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct TokenUsageRow: View {
    let modelID: String
    let inputTokens: Int
    let outputTokens: Int

    var body: some View {
        HStack(spacing: 10) {
            Label("\(inputTokens.formatted()) in", systemImage: "arrow.up")
            Label("\(outputTokens.formatted()) out", systemImage: "arrow.down")
            if let cost = TokenCostCalculator.cost(for: modelID, inputTokens: inputTokens, outputTokens: outputTokens) {
                Text(costString(cost))
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func costString(_ cost: Double) -> String {
        if cost < 0.0001 { return String(format: "~$%.6f", cost) }
        if cost < 0.01   { return String(format: "~$%.4f", cost) }
        return String(format: "~$%.3f", cost)
    }
}

private struct SessionTokenSummary: View {
    let modelID: String
    let inputTokens: Int
    let outputTokens: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis").imageScale(.small)
            Text("Session: \(inputTokens.formatted()) in · \(outputTokens.formatted()) out")
            if let cost = TokenCostCalculator.cost(for: modelID, inputTokens: inputTokens, outputTokens: outputTokens) {
                Text(costString(cost))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func costString(_ cost: Double) -> String {
        if cost < 0.0001 { return String(format: "·~$%.6f", cost) }
        if cost < 0.01   { return String(format: "·~$%.4f", cost) }
        return String(format: "·~$%.3f", cost)
    }
}

private struct UsageTimeWindowSummaryView: View {
    let windows: [UsageTimeWindowSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Usage (estimate)").font(.caption2).foregroundStyle(.tertiary)
            ForEach(windows) { window in
                Text("\(window.label): \(window.inputTokens.formatted()) in · \(window.outputTokens.formatted()) out · \(costString(window.estimatedCost))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func costString(_ cost: Double) -> String {
        if cost < 0.0001 { return String(format: "~$%.6f", cost) }
        if cost < 0.01   { return String(format: "~$%.4f", cost) }
        return String(format: "~$%.3f", cost)
    }
}

struct UsageStatsSheet: View {
    let modelID: String
    let sessionInputTokens: Int
    let sessionOutputTokens: Int
    let windows: [UsageTimeWindowSummary]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Usage Stats", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            GroupBox("Current Chat") {
                if sessionInputTokens > 0 || sessionOutputTokens > 0 {
                    SessionTokenSummary(modelID: modelID, inputTokens: sessionInputTokens, outputTokens: sessionOutputTokens)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No token usage yet in this chat.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Rolling Totals") {
                UsageTimeWindowSummaryView(windows: windows)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 250)
    }
}

private func copyToClipboard(_ value: String) {
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
#elseif canImport(UIKit)
    UIPasteboard.general.string = value
#endif
}
