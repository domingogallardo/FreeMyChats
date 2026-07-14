import SwiftUI
import SwiftWABackupAPI

struct MessageListView: View {
    let exported: ExportedChat
    let searchText: String
    let initialMessageID: Int?
    let saveReadingPosition: (Int) -> Void

    @State private var timeline: MessageTimelineWindow
    @State private var scrollPosition: Int?
    @State private var lastReadingPosition: Int?
    @State private var positionBeforeSearch: Int?
    @State private var isRestoringPosition = true
    @State private var isAtBeginning = false
    @State private var restorationID = UUID()

    init(
        exported: ExportedChat,
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
        _scrollPosition = State(initialValue: nil)
        _lastReadingPosition = State(initialValue: initialMessageID)
    }

    var body: some View {
        Group {
            if timeline.isEmpty {
                ContentUnavailableView(
                    "No hay resultados",
                    systemImage: "magnifyingglass",
                    description: Text("No se han encontrado mensajes que contengan “\(searchText)”.")
                )
            } else {
                messageScrollView
            }
        }
        .onChange(of: searchText) { previousQuery, query in
            resetTimeline(from: previousQuery, to: query)
        }
    }

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if timeline.hasEarlierMessages {
                            historyBoundary
                                .onAppear { shiftTimelineEarlier(using: proxy) }
                        } else {
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
                                mediaDirectoryURL: exported.mediaDirectoryURL
                            )
                            .id(row.id)
                        }

                        if timeline.hasLaterMessages {
                            historyBoundary
                                .onAppear { shiftTimelineLater(using: proxy) }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollPosition(id: $scrollPosition, anchor: .top)

                timelineJumpButton(using: proxy)
                    .padding(16)
            }
            .onAppear {
                restoreReadingPosition(using: proxy)
            }
            .onChange(of: scrollPosition) { _, messageID in
                guard !isRestoringPosition,
                      searchText.isEmpty,
                      let messageID else { return }
                lastReadingPosition = messageID
            }
            .task(id: lastReadingPosition) {
                guard let messageID = lastReadingPosition else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                saveReadingPosition(messageID)
            }
            .onDisappear {
                restorationID = UUID()
                if searchText.isEmpty, let messageID = lastReadingPosition {
                    saveReadingPosition(messageID)
                }
            }
        }
        .id(searchText)
    }

    private func timelineJumpButton(using proxy: ScrollViewProxy) -> some View {
        Button {
            jumpToBoundary(isAtBeginning ? .end : .beginning, using: proxy)
        } label: {
            Image(systemName: isAtBeginning ? "chevron.down" : "chevron.up")
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
        .help(isAtBeginning ? "Ir al último mensaje" : "Ir al primer mensaje")
        .accessibilityLabel(isAtBeginning ? "Ir al último mensaje" : "Ir al primer mensaje")
    }

    private var historyBoundary: some View {
        Color.clear
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func resetTimeline(from previousQuery: String, to query: String) {
        if previousQuery.isEmpty, !query.isEmpty {
            positionBeforeSearch = scrollPosition ?? lastReadingPosition ?? initialMessageID
        }

        restorationID = UUID()
        isRestoringPosition = true
        isAtBeginning = false
        scrollPosition = nil

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
        isRestoringPosition = true
        scrollPosition = nil
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
        }
    }

    private func shiftTimelineEarlier(using proxy: ScrollViewProxy) {
        guard !isRestoringPosition else { return }
        isRestoringPosition = true
        isAtBeginning = false
        scrollPosition = nil
        guard let anchor = timeline.loadEarlier() else {
            isRestoringPosition = false
            return
        }
        preserveBoundary(anchor, at: .top, using: proxy)
    }

    private func shiftTimelineLater(using proxy: ScrollViewProxy) {
        guard !isRestoringPosition else { return }
        isRestoringPosition = true
        isAtBeginning = false
        scrollPosition = nil
        guard let anchor = timeline.loadLater() else {
            isRestoringPosition = false
            return
        }
        preserveBoundary(anchor, at: .bottom, using: proxy)
    }

    private func preserveBoundary(
        _ messageID: Int,
        at anchor: UnitPoint,
        using proxy: ScrollViewProxy
    ) {
        let requestID = UUID()
        restorationID = requestID
        Task { @MainActor in
            await Task.yield()
            guard restorationID == requestID else { return }
            proxy.scrollTo(messageID, anchor: anchor)
            try? await Task.sleep(for: .milliseconds(30))
            guard restorationID == requestID else { return }
            isRestoringPosition = false
        }
    }

    private func jumpToBoundary(
        _ boundary: TimelineBoundary,
        using proxy: ScrollViewProxy
    ) {
        restorationID = UUID()
        isRestoringPosition = true
        isAtBeginning = false
        scrollPosition = nil

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
                lastReadingPosition = scrollPosition ?? target
            }
            isAtBeginning = boundary == .beginning
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
}
