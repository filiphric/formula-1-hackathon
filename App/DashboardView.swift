import SwiftUI

struct DashboardView: View {
    let store: TimingStore
    let feed: FeedStatus
    let endpoint: String
    /// False while another tab is on screen; the dashboard stays alive underneath on wide layouts.
    let isActive: Bool
    /// The pager's slot (see `DashboardPage.loopSlots`); starts on the real running-order slot.
    @State private var slot: Int? = DashboardPage.order.slot
    @State private var radioPlayer = TeamRadioPlayer()
    @State private var raceControlSeen = SeenItems()
    @State private var radioSeen = SeenItems()
    @State private var observedSession: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The page on screen (a clone slot shows the page it imitates).
    private var page: DashboardPage { DashboardPage(slot: slot ?? DashboardPage.order.slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                hero(feed: feed)
                if let error = store.error {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(RacingStyle.Typography.body).foregroundStyle(Color(RacingPalette.statusStale))
                }
            }
            .racingPagePadding([.horizontal, .top])
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
            if let snapshot = store.snapshot {
                pageSelector(snapshot)
                pages(snapshot)
                    .onChange(of: newItemKey(snapshot), initial: true) { observeNewItems(snapshot) }
                    .onChange(of: page) {
                        // Radio plays only while its page is the one on screen.
                        if page != .radio { radioPlayer.stop() }
                        observeNewItems(snapshot)
                    }
                    .onChange(of: isActive) {
                        if !isActive { radioPlayer.stop() }
                        observeNewItems(snapshot)
                    }
            } else {
                ContentUnavailableView(
                    "Your race weekend, live",
                    systemImage: "flag.checkered",
                    description: Text("Start the backend to load timing. Demo mode works without OpenF1 credentials.")
                ).frame(minHeight: 280).frame(maxHeight: .infinity)
            }
        }
        .background(RacingStyle.background)
    }

    // MARK: Pages

    /// Icon buttons that mirror the swipe position and jump straight to a page, which is also how a
    /// mouse, keyboard or VoiceOver user reaches the other pages.
    private func pageSelector(_ snapshot: TimingSnapshot) -> some View {
        HStack(spacing: RacingStyle.Space.xs) {
            ForEach(DashboardPage.allCases) { item in
                let selected = page == item
                let hasNew = hasNewItems(on: item, snapshot)
                Button { withAnimation { slot = item.slot } } label: {
                    Image(systemName: item.symbol)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(selected ? RacingStyle.raised : .clear, in: RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
                        .overlay(alignment: .topTrailing) {
                            if hasNew {
                                Circle().fill(RacingStyle.red).frame(width: 9, height: 9)
                                    .padding(.top, 8).padding(.trailing, 8)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? RacingStyle.textPrimary : RacingStyle.textSecondary)
                .accessibilityLabel(hasNew ? "\(item.rawValue), new items" : item.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(item.rawValue)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: .infinity)
    }

    // MARK: New-item dots

    /// What the race control page lists (it shows the latest ten) and what the radio page lists.
    private func newItemIDs(for item: DashboardPage, _ snapshot: TimingSnapshot) -> [String]? {
        switch item {
        case .raceControl: snapshot.messages.prefix(10).map(\.id)
        case .radio: snapshot.radios.map(\.id)
        default: nil
        }
    }

    private func hasNewItems(on item: DashboardPage, _ snapshot: TimingSnapshot) -> Bool {
        guard let ids = newItemIDs(for: item, snapshot) else { return false }
        return (item == .raceControl ? raceControlSeen : radioSeen).hasUnseen(in: ids)
    }

    /// Changes whenever either list or the session changes, so one `onChange` covers both.
    private func newItemKey(_ snapshot: TimingSnapshot) -> [String] {
        [sessionKey(snapshot)] + (newItemIDs(for: .raceControl, snapshot) ?? []) + ["|"] + (newItemIDs(for: .radio, snapshot) ?? [])
    }

    private func sessionKey(_ snapshot: TimingSnapshot) -> String {
        snapshot.session.map { "\($0.name)|\($0.start)" } ?? ""
    }

    private func observeNewItems(_ snapshot: TimingSnapshot) {
        // A different session brings a fresh list, which is not "new" to someone just opening it.
        if sessionKey(snapshot) != observedSession {
            observedSession = sessionKey(snapshot)
            raceControlSeen.reset(); radioSeen.reset()
        }
        raceControlSeen.observe(newItemIDs(for: .raceControl, snapshot) ?? [], viewing: isActive && page == .raceControl)
        radioSeen.observe(newItemIDs(for: .radio, snapshot) ?? [], viewing: isActive && page == .radio)
    }

    /// One full-width page per slot; swiping (or a trackpad scroll) snaps to the next, and the last
    /// page is followed by the first again. Pages build lazily, so the track map only ticks once reached.
    private func pages(_ snapshot: TimingSnapshot) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(DashboardPage.loopSlots, id: \.self) { position in
                    pageContent(DashboardPage(slot: position), snapshot)
                        .containerRelativeFrame(.horizontal)
                        .id(position)
                        // The end slots only imitate a page, so assistive tech skips them.
                        .accessibilityHidden(DashboardPage.isClone(slot: position))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $slot)
        .scrollIndicators(.hidden)
        // Once a swipe has settled on a clone, jump (unanimated, so unseen) to the real page it imitates.
        .task(id: slot) {
            guard let landed = slot, DashboardPage.isClone(slot: landed) else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { slot = DashboardPage.settledSlot(landed) }
        }
    }

    @ViewBuilder private func pageContent(_ item: DashboardPage, _ snapshot: TimingSnapshot) -> some View {
        switch item {
        case .order:
            scrollingPage { timingBoard(snapshot) }
        case .track:
            // The map takes the whole page; at huge text sizes the page grows past the screen and scrolls.
            scrollingPage(fillingHeight: true) {
                TrackMapView(snapshot: snapshot, connected: store.connected, fillsHeight: true)
            }
        case .raceControl:
            scrollingPage { raceControl(snapshot) }
        case .radio:
            scrollingPage { TeamRadioFeed(snapshot: snapshot, connected: store.connected, player: radioPlayer) }
        case .championship:
            scrollingPage { ChampionshipView(snapshot: snapshot, endpoint: endpoint) }
        }
    }

    private func scrollingPage<Content: View>(fillingHeight: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        let minimum: CGFloat = typeSize.isAccessibilitySize ? 900 : 560
        return ScrollView {
            if fillingHeight {
                content()
                    .racingPagePadding()
                    .frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical) { length, _ in max(length, minimum) }
            } else {
                content()
                    .racingPagePadding()
                    .frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The one session hero: circuit large, then session name and how fresh the timing is.
    private func hero(feed: FeedStatus) -> some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
            Text(store.snapshot?.session?.circuit ?? "Ready for lights out")
                .font(RacingStyle.Typography.display).racingHeading()
                .accessibilityAddTraits(.isHeader)
            sessionName
            if let detail = feed.timingDetail {
                Text(detail).font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusStale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var sessionName: some View {
        Text(store.snapshot?.session?.name ?? "Waiting for session")
            .font(RacingStyle.Typography.headline).foregroundStyle(RacingStyle.textSecondary)
    }

    private func timingBoard(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            Image(systemName: "list.number")
                .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                .accessibilityLabel("Leaderboard").accessibilityAddTraits(.isHeader)
            if snapshot.drivers.isEmpty {
                Text("Waiting for driver data…").font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            }
            TimingTower(drivers: snapshot.drivers, showsGap: snapshot.drivers.hasUsableGaps)
        }
        .racingCard()
    }

    private func raceControl(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            RacingSectionTitle(title: "Race control")
            if snapshot.messages.isEmpty {
                Text("No race-control messages yet.").font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            }
            ForEach(snapshot.messages.prefix(10)) { message in
                raceControlRow(message)
            }
        }.racingCard()
    }

    @ScaledMetric(relativeTo: .body) private var iconWidth = 22

    // Flag categories can distinguish identical symbols (yellow/double yellow, SC/VSC).
    @ViewBuilder private func flagLabel(_ kind: RaceControlKind) -> some View {
        if kind != .info {
            Text(kind.label).racingLabel().foregroundStyle(kind.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func time(_ message: RaceMessage) -> some View {
        if let time = message.timestamp {
            Text(time.formatted(date: .omitted, time: .standard))
                .font(RacingStyle.Typography.caption.monospacedDigit()).foregroundStyle(RacingStyle.textSecondary)
                .lineLimit(1).fixedSize()
        }
    }

    private func raceControlRow(_ message: RaceMessage) -> some View {
        let kind = message.kind
        return HStack(alignment: .top, spacing: RacingStyle.Space.m) {
            Image(systemName: kind.symbol).foregroundStyle(kind.color)
                .frame(width: iconWidth).padding(.top, RacingStyle.Space.xs / 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RacingStyle.Space.s) { flagLabel(kind); time(message) }
                    VStack(alignment: .leading, spacing: RacingStyle.Space.xs) { flagLabel(kind); time(message) }
                }
                Text(message.message).font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textPrimary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(RacingStyle.Space.m)
        .background(RacingStyle.raised, in: RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
        .overlay(alignment: .leading) {
            if kind.severity >= .caution { Rectangle().fill(kind.color).frame(width: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message.accessibilitySummary(
            timeText: message.timestamp?.formatted(date: .omitted, time: .standard)))
    }
}
