import SwiftUI
import SwiftWABackupAPI

struct MessageListView: View {
    let exported: ArchivedConversation
    let searchText: String
    let initialMessageID: Int?
    let saveReadingPosition: (Int) -> Void

    @State private var timeline: MessageTimelineWindow
    @State private var lastReadingPosition: Int?
    @State private var positionBeforeSearch: Int?
    @State private var observedSearchText: String
    @State private var visibleMessageIDs: Set<Int> = []
    @State private var isRestoringPosition = true
    @State private var isAtBeginning = false
    @State private var restorationID = UUID()
    @State private var highlightedMessageID: Int?
    @State private var highlightID = UUID()
    @State private var replyReturnMessageID: Int?
    @State private var activeTimelineShift: TimelineShiftRequest?
    @State private var pendingTimelineShift: TimelineShiftRequest?

    init(
        exported: ArchivedConversation,
        searchText: String,
        initialMessageID: Int?,
        saveReadingPosition: @escaping (Int) -> Void
    ) {
        self.exported = exported
        self.searchText = searchText
        self.initialMessageID = initialMessageID
        self.saveReadingPosition = saveReadingPosition

        let filteredMessages = MessageSearch.filter(exported.document.messages, query: searchText)
        let initialTarget = searchText.isEmpty ? initialMessageID : filteredMessages.first?.id
        _timeline = State(
            initialValue: MessageTimelineWindow(
                messages: filteredMessages,
                centeredOn: initialTarget
            )
        )
        _lastReadingPosition = State(initialValue: initialMessageID)
        _observedSearchText = State(initialValue: searchText)
    }

    var body: some View {
        Group {
            if timeline.isEmpty {
                UnavailableContentView(
                    "No hay resultados",
                    systemImage: "magnifyingglass",
                    description: "No se han encontrado mensajes que contengan “\(searchText)”."
                )
            } else {
                messageScrollView
            }
        }
        .onChange(of: searchText) { query in
            let previousQuery = observedSearchText
            observedSearchText = query
            resetTimeline(from: previousQuery, to: query)
        }
    }

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !timeline.hasEarlierMessages {
                            historyBoundary
                                .onAppear { isAtBeginning = true }
                                .onDisappear { isAtBeginning = false }
                        }

                        ForEach(timeline.rows) { row in
                            if row.beginsNewDay {
                                Text(Self.dayFormatter.string(from: row.message.date))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            }
                            MessageRowView(
                                message: row.message,
                                mediaDirectoryURL: exported.mediaDirectoryURL,
                                isHighlighted: highlightedMessageID == row.id,
                                navigateToReply: { messageID in
                                    jumpToMessage(
                                        messageID,
                                        returnTo: row.id,
                                        using: proxy
                                    )
                                }
                            )
                            .id(row.id)
                            .onAppear {
                                messageBecameVisible(row.id, using: proxy)
                            }
                            .onDisappear {
                                messageDisappeared(row.id, using: proxy)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                timelineJumpButton(using: proxy)
                    .padding(16)
            }
            .onAppear {
                restoreReadingPosition(using: proxy)
            }
            .task(id: lastReadingPosition) {
                guard let messageID = lastReadingPosition else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                saveReadingPosition(messageID)
            }
            .task(id: highlightID) {
                guard highlightedMessageID != nil else { return }
                try? await Task.sleep(for: .milliseconds(1_400))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.45)) {
                    highlightedMessageID = nil
                }
            }
            .onDisappear {
                restorationID = UUID()
                activeTimelineShift = nil
                pendingTimelineShift = nil
                if searchText.isEmpty, let messageID = lastReadingPosition {
                    saveReadingPosition(messageID)
                }
            }
        }
        .id(searchText)
    }

    private func timelineJumpButton(using proxy: ScrollViewProxy) -> some View {
        let pointsDown = replyReturnMessageID != nil || isAtBeginning
        let actionLabel = replyReturnMessageID != nil
            ? "Volver al mensaje de respuesta"
            : (isAtBeginning ? "Ir al último mensaje" : "Ir al primer mensaje")

        return Button {
            if let replyReturnMessageID {
                jumpToMessage(replyReturnMessageID, returnTo: nil, using: proxy)
            } else {
                jumpToBoundary(isAtBeginning ? .end : .beginning, using: proxy)
            }
        } label: {
            Image(systemName: pointsDown ? "chevron.down" : "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 34, height: 34)
                .background(Color.white, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .help(actionLabel)
        .accessibilityLabel(actionLabel)
    }

    private var historyBoundary: some View {
        Color.clear
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func resetTimeline(from previousQuery: String, to query: String) {
        if previousQuery.isEmpty, !query.isEmpty {
            positionBeforeSearch = lastReadingPosition ?? initialMessageID
        }

        restorationID = UUID()
        activeTimelineShift = nil
        pendingTimelineShift = nil
        isRestoringPosition = true
        isAtBeginning = false
        replyReturnMessageID = nil
        visibleMessageIDs.removeAll()

        let filteredMessages = MessageSearch.filter(exported.document.messages, query: query)
        let target = query.isEmpty
            ? (positionBeforeSearch ?? lastReadingPosition ?? initialMessageID)
            : filteredMessages.first?.id
        if query.isEmpty, let target {
            lastReadingPosition = target
        }
        timeline = MessageTimelineWindow(messages: filteredMessages, centeredOn: target)
    }

    private func restoreReadingPosition(using proxy: ScrollViewProxy) {
        let savedPosition = lastReadingPosition ?? initialMessageID
        let validSavedPosition = savedPosition.flatMap { savedID in
            timeline.contains(messageID: savedID) ? savedID : nil
        }
        let target: Int?
        let anchor: UnitPoint

        if searchText.isEmpty {
            target = validSavedPosition ?? timeline.lastMessageID
            anchor = validSavedPosition == nil ? .bottom : .top
        } else {
            target = timeline.firstMessageID
            anchor = .top
        }

        guard let target else { return }
        activeTimelineShift = nil
        pendingTimelineShift = nil
        isRestoringPosition = true
        visibleMessageIDs.removeAll()
        let requestID = UUID()
        restorationID = requestID

        Task { @MainActor in
            for delay in [0, 40] {
                if delay == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard restorationID == requestID else { return }
                proxy.scrollTo(target, anchor: anchor)
            }

            guard restorationID == requestID else { return }
            if searchText.isEmpty {
                lastReadingPosition = target
                positionBeforeSearch = nil
            }
            if !timeline.hasEarlierMessages,
               target == timeline.firstMessageID,
               anchor == .top {
                isAtBeginning = true
            }
            isRestoringPosition = false
            requestTimelineShiftIfNeeded(around: target, using: proxy)
        }
    }

    private func messageBecameVisible(_ messageID: Int, using proxy: ScrollViewProxy) {
        visibleMessageIDs.insert(messageID)
        updateVisiblePosition(using: proxy)
    }

    private func messageDisappeared(_ messageID: Int, using proxy: ScrollViewProxy) {
        visibleMessageIDs.remove(messageID)
        updateVisiblePosition(using: proxy)
    }

    private func updateVisiblePosition(using proxy: ScrollViewProxy) {
        guard !isRestoringPosition else { return }
        guard let messageID = timeline.rows.first(where: {
            visibleMessageIDs.contains($0.id)
        })?.id else { return }

        // Lazy stacks can emit visibility changes after a programmatic jump has
        // completed. Keep the reply return destination until an explicit
        // navigation action clears or replaces it.
        if searchText.isEmpty {
            lastReadingPosition = messageID
        }
        requestTimelineShiftIfNeeded(around: messageID, using: proxy)
    }

    private func requestTimelineShiftIfNeeded(
        around messageID: Int,
        using proxy: ScrollViewProxy
    ) {
        guard let rowIndex = timeline.rows.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let threshold = min(
            Self.timelinePreloadThreshold,
            max(1, timeline.rows.count / 3)
        )
        let request: TimelineShiftRequest?
        if timeline.hasEarlierMessages, rowIndex < threshold {
            request = .earlier(preserving: messageID)
        } else if timeline.hasLaterMessages,
                  rowIndex >= timeline.rows.count - threshold {
            request = .later(preserving: messageID)
        } else {
            request = nil
        }

        guard let request else { return }
        requestTimelineShift(request, using: proxy)
    }

    private func requestTimelineShift(
        _ request: TimelineShiftRequest,
        using proxy: ScrollViewProxy
    ) {
        guard !isRestoringPosition else {
            if activeTimelineShift != nil {
                pendingTimelineShift = request
            }
            return
        }

        activeTimelineShift = request
        pendingTimelineShift = nil
        isRestoringPosition = true
        isAtBeginning = false
        visibleMessageIDs.removeAll()

        let loadedBoundaryID: Int?
        switch request {
        case .earlier:
            loadedBoundaryID = timeline.loadEarlier()
        case .later:
            loadedBoundaryID = timeline.loadLater()
        }

        guard let loadedBoundaryID else {
            activeTimelineShift = nil
            isRestoringPosition = false
            return
        }

        let requestedAnchor = request.messageID
        let anchor = timeline.contains(messageID: requestedAnchor)
            ? requestedAnchor
            : loadedBoundaryID
        preserveBoundary(anchor, using: proxy)
    }

    private func preserveBoundary(
        _ messageID: Int,
        using proxy: ScrollViewProxy
    ) {
        let requestID = UUID()
        restorationID = requestID
        Task { @MainActor in
            await Task.yield()
            guard restorationID == requestID else { return }

            proxy.scrollTo(messageID, anchor: .top)

            try? await Task.sleep(for: .milliseconds(40))
            guard restorationID == requestID else { return }
            finishTimelineShift(using: proxy)
        }
    }

    private func finishTimelineShift(using proxy: ScrollViewProxy) {
        let pendingShift = pendingTimelineShift
        activeTimelineShift = nil
        pendingTimelineShift = nil
        isRestoringPosition = false

        if let pendingShift {
            requestTimelineShift(pendingShift, using: proxy)
        }
    }

    private func jumpToBoundary(
        _ boundary: TimelineBoundary,
        using proxy: ScrollViewProxy
    ) {
        restorationID = UUID()
        activeTimelineShift = nil
        pendingTimelineShift = nil
        isRestoringPosition = true
        isAtBeginning = false
        replyReturnMessageID = nil
        visibleMessageIDs.removeAll()

        let target: Int?
        let anchor: UnitPoint
        switch boundary {
        case .beginning:
            target = timeline.moveToBeginning()
            anchor = .top
        case .end:
            target = timeline.moveToEnd()
            anchor = .bottom
        }

        guard let target else {
            isRestoringPosition = false
            return
        }

        let requestID = UUID()
        restorationID = requestID
        Task { @MainActor in
            await Task.yield()
            guard restorationID == requestID else { return }
            proxy.scrollTo(target, anchor: anchor)
            try? await Task.sleep(for: .milliseconds(40))
            guard restorationID == requestID else { return }
            if searchText.isEmpty {
                lastReadingPosition = target
            }
            isAtBeginning = boundary == .beginning
            isRestoringPosition = false
        }
    }

    private func jumpToMessage(
        _ messageID: Int,
        returnTo returnMessageID: Int?,
        using proxy: ScrollViewProxy
    ) {
        restorationID = UUID()
        activeTimelineShift = nil
        pendingTimelineShift = nil
        isRestoringPosition = true
        isAtBeginning = false
        visibleMessageIDs.removeAll()

        guard let target = timeline.move(to: messageID) else {
            isRestoringPosition = false
            return
        }

        // Publish the return destination as soon as the jump is accepted. Its
        // availability must not depend on SwiftUI finishing layout within the
        // delay used below to let the new scroll position settle.
        replyReturnMessageID = returnMessageID

        let requestID = UUID()
        restorationID = requestID
        Task { @MainActor in
            await Task.yield()
            guard restorationID == requestID else { return }
            proxy.scrollTo(target, anchor: .center)
            withAnimation(.easeInOut(duration: 0.2)) {
                highlightedMessageID = target
                highlightID = UUID()
            }
            try? await Task.sleep(for: .milliseconds(40))
            guard restorationID == requestID else { return }
            if searchText.isEmpty {
                lastReadingPosition = target
            }
            isAtBeginning = !timeline.hasEarlierMessages && target == timeline.firstMessageID
            isRestoringPosition = false
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private enum TimelineBoundary {
        case beginning
        case end
    }

    private enum TimelineShiftRequest {
        case earlier(preserving: Int)
        case later(preserving: Int)

        var messageID: Int {
            switch self {
            case .earlier(let messageID), .later(let messageID):
                messageID
            }
        }
    }

    private static let timelinePreloadThreshold = 150
}
