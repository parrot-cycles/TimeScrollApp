import SwiftUI
import AppKit

struct TimelineUnifiedView: View {
    @ObservedObject var appState = AppState.shared
    @StateObject var model = TimelineModel()
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var vault = VaultManager.shared
    @AppStorage("ui.timeline.compressed") private var compressedTimeline: Bool = true
    @AppStorage("ui.timeline.invertScrollDirection") private var invertTimelineScrollDirection: Bool = false

    @State private var query: String = ""
    @State private var showFilters: Bool = false
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @State private var keyMonitor: Any? = nil
    @State private var showingResults: Bool = false
    @State private var preserveOpenedResultContextOnRefresh: Bool = false
    @State private var showCalendar: Bool = false
    @State private var cameFromResults: Bool = false
    @FocusState private var searchFieldFocused: Bool
    @State private var filterConditions: [FilterCondition] = [FilterCondition(field: .text, op: .contains, value: "")]
    @State private var filterMatchMode: FilterMatchMode = .all
    @State private var calendarDate: Date = Date()
    @State private var calendarDaysWithContent: Set<Int> = []

    private let minMsPerPt: Double = 100             // 100ms per pt at max zoom-in
    private let maxMsPerPt: Double = 300_000         // 5m per pt at max zoom-out (keeps things "pretty small")
    private let zoomStep: Double = 1.25

    private var activeFilterCount: Int {
        (model.startMs != nil ? 1 : 0)
        + (model.endMs != nil ? 1 : 0)
        + (model.selectedAppBundleIds.isEmpty ? 0 : 1)
        + filterConditions.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            centerStage
            Divider()
            bottomTimeline
        }
        .onAppear {
            _ = SnapshotStore.shared.snapshotsDir
            appState.enforceRetention()
            model.load()
            installKeyMonitor()
            // Keep the text field in sync with the applied model query
            query = model.query
            // Clamp any previously persisted msPerPoint into the new, saner range
            model.msPerPoint = min(max(model.msPerPoint, minMsPerPt), maxMsPerPt)
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: vault.isUnlocked) { unlocked in
            // When the vault gets unlocked, reload timeline and show a loading state
            if unlocked { model.load() }
        }
        .onChange(of: appState.lastSnapshotURL) { _ in
            if SettingsStore.shared.refreshOnNewSnapshot { reloadTimelineKeepingSelection() }
        }
        .onChange(of: appState.lastSnapshotTick) { _ in
            if SettingsStore.shared.refreshOnNewSnapshot { reloadTimelineKeepingSelection() }
        }
        // If the user clears the search field, automatically return to timeline
        .onChange(of: query) { newVal in
            let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && showingResults {
                // Clear applied query on the model and reload latest
                preserveOpenedResultContextOnRefresh = false
                model.query = ""
                model.load()
                showingResults = false
            }
        }
        // Keep text field reflecting the currently applied model query (e.g. after programmatic changes)
        .onChange(of: model.query) { newVal in
            if query != newVal { query = newVal }
        }
        .frame(minWidth: 1000, minHeight: 700)
    }

    @MainActor
    private func reloadTimelineKeepingSelection() {
        if preserveOpenedResultContextOnRefresh,
           !showingResults,
           let selected = model.selected {
            model.openSnapshot(id: selected.id, anchorStartedAtMs: selected.startedAtMs)
            return
        }

        model.load()
        if model.followLatest {
            model.jumpToEndToken &+= 1
        }
    }

    @State private var debugOpen: Bool = false

    private var topBar: some View {
        HStack(spacing: 8) {
            // Capture toggle
            Button {
                Task {
                    if appState.isCapturing {
                        await appState.stopCaptureIfNeeded()
                    } else {
                        await appState.startCaptureIfNeeded()
                    }
                }
            } label: {
                Image(systemName: appState.isCapturing ? "stop.circle.fill" : "record.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundColor(appState.isCapturing ? .red : .accentColor)
            .help(appState.isCapturing ? "Stop Capture" : "Start Capture")

            // Back to results button (when viewing a snapshot from search)
            if cameFromResults && !showingResults {
                Button {
                    cameFromResults = false
                    showingResults = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Back to results")
            }

            // Search field
            TimelineToolbarSection {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search snapshots", text: $query)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .submitLabel(.search)
                    .onSubmit { showResults() }
                    .focused($searchFieldFocused)

                if !query.isEmpty {
                    Button {
                        query = ""
                        model.query = ""
                        model.load()
                        showingResults = false
                        cameFromResults = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            // Filters
            Button {
                showFilters.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                    if activeFilterCount > 0 {
                        TimelineToolbarCountBadge(count: activeFilterCount)
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Filters")
            .popover(isPresented: $showFilters, arrowEdge: .bottom) {
                filtersPopover
                    .padding(12)
                    .frame(minWidth: 400)
            }

            if settings.vaultEnabled {
                Divider().frame(height: 22)

                Button {
                    if vault.isUnlocked {
                        vault.lock()
                    } else {
                        Task { await vault.unlock(presentingWindow: NSApp.keyWindow) }
                    }
                } label: {
                    Image(systemName: vault.isUnlocked ? "lock.open" : "lock")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help(vault.isUnlocked ? "Lock Vault" : "Unlock Vault")

                if vault.queuedCount > 0 {
                    Text("\(vault.queuedCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            Divider().frame(height: 22)

            // Zoom controls
            HStack(spacing: 4) {
                Button(action: { model.msPerPoint = min(maxMsPerPt, model.msPerPoint * zoomStep) }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)

                Slider(value: Binding(get: {
                    let clamped = min(max(model.msPerPoint, minMsPerPt), maxMsPerPt)
                    let logMin = log(minMsPerPt)
                    let logMax = log(maxMsPerPt)
                    let logVal = log(clamped)
                    return (logMax - logVal) / (logMax - logMin)
                }, set: { value in
                    let logMin = log(minMsPerPt)
                    let logMax = log(maxMsPerPt)
                    let logVal = logMax - value * (logMax - logMin)
                    let msPerPoint = exp(logVal)
                    model.msPerPoint = min(max(msPerPoint, minMsPerPt), maxMsPerPt)
                }))
                .frame(width: 100)

                Button(action: { model.msPerPoint = max(minMsPerPt, model.msPerPoint / zoomStep) }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }

            // Live toggle
            Button {
                model.followLatest.toggle()
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundColor(model.followLatest ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Follow newest snapshots")

            if settings.debugMode {
                Button { debugOpen = true } label: {
                    Image(systemName: "ladybug")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Debug DB")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .sheet(isPresented: $debugOpen) { DebugView() }
    }

    private var filtersPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date range
            HStack(spacing: 8) {
                Text("From:")
                DatePicker("From", selection: Binding(get: { startDate ?? Date() }, set: { startDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            HStack(spacing: 8) {
                Text("To:")
                DatePicker("To", selection: Binding(get: { endDate ?? Date() }, set: { endDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }

            HStack {
                Button("Clear Dates") { startDate = nil; endDate = nil }
                Button("Clear Apps") { model.selectedAppBundleIds.removeAll() }
            }

            Divider()

            // Smart filter conditions
            SmartFilterView(
                conditions: $filterConditions,
                matchMode: $filterMatchMode,
                onApply: {
                    applySmartFilters()
                    showFilters = false
                }
            )

            Divider()

            // App filter (collapsible)
            DisclosureGroup("Apps") {
                TimelineAppMultiFilter(selected: $model.selectedAppBundleIds)
                    .frame(minHeight: 100, maxHeight: 180)
            }
        }
    }

    private func applySmartFilters() {
        // Apply date filters
        applyFilters()

        // Build query from text conditions
        let textConditions = filterConditions.compactMap { $0.toFTS() }
        if !textConditions.isEmpty {
            let includes = textConditions.filter { !$0.isExclude }.map { $0.match }
            let excludes = textConditions.filter { $0.isExclude }.map { $0.match }

            var queryParts: [String] = []
            if filterMatchMode == .all {
                queryParts.append(contentsOf: includes)
            } else {
                if !includes.isEmpty {
                    queryParts.append(includes.joined(separator: " OR "))
                }
            }
            for ex in excludes {
                queryParts.append("NOT \(ex)")
            }
            query = queryParts.joined(separator: " ")
        }

        // Apply app name conditions to the app filter
        for condition in filterConditions {
            if condition.field == .appName && !condition.value.isEmpty {
                // This is handled via the SQL query, not the app multi-select
                // For now, search by app name in text
            }
        }

        // Apply year/month/day via date range
        for condition in filterConditions {
            let trimmed = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if condition.field == .year, let yr = Int(trimmed) {
                var cal = Calendar.current
                cal.timeZone = .current
                if let s = cal.date(from: DateComponents(year: yr, month: 1, day: 1)),
                   let e = cal.date(from: DateComponents(year: yr + 1, month: 1, day: 1)) {
                    if condition.op == .equals || condition.op == .contains {
                        startDate = s; endDate = e
                    }
                }
            }
            if condition.field == .month, let mo = Int(trimmed), mo >= 1, mo <= 12 {
                var cal = Calendar.current
                cal.timeZone = .current
                let yr = cal.component(.year, from: Date())
                if let s = cal.date(from: DateComponents(year: yr, month: mo, day: 1)),
                   let e = cal.date(byAdding: .month, value: 1, to: s) {
                    if condition.op == .equals || condition.op == .contains {
                        startDate = s; endDate = e
                    }
                }
            }
            if condition.field == .day, let d = Int(trimmed), d >= 1, d <= 31 {
                var cal = Calendar.current
                cal.timeZone = .current
                let yr = cal.component(.year, from: Date())
                let mo = cal.component(.month, from: Date())
                if let s = cal.date(from: DateComponents(year: yr, month: mo, day: d)),
                   let e = cal.date(byAdding: .day, value: 1, to: s) {
                    if condition.op == .equals || condition.op == .contains {
                        startDate = s; endDate = e
                    }
                }
            }
        }

        applyFilters()
        model.load()
        showingResults = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var centerStage: some View {
        ZStack {
            if settings.vaultEnabled && !vault.isUnlocked {
                LockedView()
            } else {
            // Use the applied model.query (not the in-flight text field value)
            Group {
                if showingResults {
                    SearchResultsView(query: model.query,
                                      appBundleIds: (model.selectedAppBundleIds.isEmpty ? nil : Array(model.selectedAppBundleIds).sorted()),
                                      startMs: model.startMs,
                                      endMs: model.endMs,
                                      onOpen: { row, _ in
                                          preserveOpenedResultContextOnRefresh = true
                                          cameFromResults = true
                                          showingResults = false
                                          model.openSnapshot(id: row.id, anchorStartedAtMs: row.startedAtMs)
                                      },
                                      onClose: {
                                          preserveOpenedResultContextOnRefresh = false
                                          model.load()
                                          showingResults = false
                                      })
                        // Remount the results view when filters change to avoid stale local state
                        .id("\(model.query)|\(((model.selectedAppBundleIds.isEmpty ? ["_"] : Array(model.selectedAppBundleIds)).sorted().joined(separator: ",")))|\(model.startMs ?? -1)|\(model.endMs ?? -1)")
                        .environmentObject(settings)
                } else {
                    SnapshotStageView(model: model, globalQuery: model.query)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Loading overlay
            if model.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading snapshots\nPlease wait…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            }
        }
        .frame(minHeight: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomTimeline: some View {
        VStack(spacing: 0) {
            calendarBar
            Divider()
            ZStack(alignment: .bottomTrailing) {
                TimelineBarContainer(model: model,
                                     isCompressed: compressedTimeline,
                                     invertScrollDirection: invertTimelineScrollDirection,
                                     onJump: { t in model.jump(to: t) },
                                     onHover: { t in model.hoverTimeMs = t },
                                     onHoverExit: { model.hoverTimeMs = nil })
                    .frame(height: 100)

                Button(action: { jumpToEnd() }) {
                    Image(systemName: "chevron.right.to.line")
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    private var calendarBar: some View {
        HStack(spacing: 6) {
            Spacer()

            // Previous day
            Button { jumpCalendarDay(by: -1) } label: {
                Image(systemName: "chevron.backward.2")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Previous day")

            // Previous snapshot
            Button { model.prev() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(!(model.selectedIndex + 1 < model.metas.count))

            // Date button → calendar popover
            Button {
                if let sel = model.selected {
                    calendarDate = Date(timeIntervalSince1970: TimeInterval(sel.startedAtMs) / 1000)
                }
                loadCalendarDays()
                showCalendar.toggle()
            } label: {
                Text(selectedSnapshotDateString)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showCalendar, arrowEdge: .top) {
                CalendarPickerView(
                    selectedDate: $calendarDate,
                    daysWithContent: calendarDaysWithContent,
                    onSelectDay: { date in
                        jumpToDate(date)
                        showCalendar = false
                    }
                )
                .frame(width: 300)
                .onChange(of: calendarDate) { _ in
                    loadCalendarDays()
                }
            }

            // Next snapshot
            Button { model.next() } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(!(model.selectedIndex - 1 >= 0))

            // Next day
            Button { jumpCalendarDay(by: 1) } label: {
                Image(systemName: "chevron.forward.2")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Next day")

            Spacer()
        }
        .padding(.vertical, 6)
        .onAppear { syncCalendarToSelection() }
        .onChange(of: model.selected?.id) { _ in syncCalendarToSelection() }
    }

    private var calendarDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d. MMMM yyyy"
        return fmt.string(from: calendarDate)
    }

    private var selectedSnapshotDateString: String {
        guard let sel = model.selected else { return calendarDateString }
        let date = Date(timeIntervalSince1970: TimeInterval(sel.startedAtMs) / 1000)
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .medium
        return fmt.string(from: date)
    }

    private func syncCalendarToSelection() {
        if let sel = model.selected {
            calendarDate = Date(timeIntervalSince1970: TimeInterval(sel.startedAtMs) / 1000)
        }
    }

    private func jumpCalendarDay(by offset: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: offset, to: calendarDate) {
            calendarDate = newDate
            jumpToDate(newDate)
        }
    }

    private func jumpToDate(_ date: Date) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
        startDate = startOfDay
        endDate = endOfDay
        applyFilters()
        model.load()
        showingResults = false
    }

    private func loadCalendarDays() {
        let cal = Calendar.current
        let year = cal.component(.year, from: calendarDate)
        let month = cal.component(.month, from: calendarDate)
        DispatchQueue.global(qos: .userInitiated).async {
            let days = (try? DB.shared.daysWithSnapshots(year: year, month: month)) ?? []
            DispatchQueue.main.async {
                calendarDaysWithContent = days
            }
        }
    }

    private func applyFilters() {
        model.query = query
        model.startMs = startDate.map { Int64($0.timeIntervalSince1970 * 1000) }
        model.endMs = endDate.map { Int64($0.timeIntervalSince1970 * 1000) }
    }

    private func showResults() {
        preserveOpenedResultContextOnRefresh = false
        // Clear date filters when searching so results aren't limited to one day
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startDate = nil
            endDate = nil
        }
        applyFilters()
        showingResults = true
        showFilters = false
    }

    private func searchAndJump() {
        preserveOpenedResultContextOnRefresh = false
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startDate = nil
            endDate = nil
        }
        applyFilters()
        model.load()
        showingResults = false
        showFilters = false
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // If typing in the search field (NSTextView), intercept Cmd+Return to run Search & Jump
            if let first = NSApp.keyWindow?.firstResponder, first is NSTextView {
                // keyCode 36 = Return, 76 = keypad Enter
                if (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command) {
                    searchAndJump()
                    return nil
                }
                return event
            }
            // Cmd+F: focus search field
            if event.modifierFlags.contains(.command) && event.keyCode == 3 { // 3 = F
                searchFieldFocused = true
                return nil
            }
            // Escape: back to results or clear search
            if event.keyCode == 53 { // Escape
                if cameFromResults {
                    cameFromResults = false
                    showingResults = true
                    return nil
                }
            }
            // Ignore other modified keypresses
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) {
                return event
            }
            switch event.keyCode {
            case 123: // left
                if model.selectedIndex + 1 < model.metas.count { model.prev(); return nil }
            case 124: // right
                if model.selectedIndex - 1 >= 0 { model.next(); return nil }
            case 51, 117: // delete, forward delete
                if let sel = model.selected {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Delete Snapshot?"
                    alert.informativeText = "This will permanently delete the selected snapshot from disk and remove it from the timeline."
                    alert.addButton(withTitle: "Delete")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        model.deleteSnapshot(id: sel.id)
                        return nil
                    }
                }
            default:
                break
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    private func jumpToEnd() {
        preserveOpenedResultContextOnRefresh = false
        if !model.metas.isEmpty { model.selectedIndex = 0 }
        model.jumpToEndToken &+= 1
    }
}

// Single-select app filter removed; replaced by TimelineAppMultiFilter

private struct TimelineToolbarSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct TimelineToolbarCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor)
            )
    }
}

private struct TimelineLiveToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .fixedSize(horizontal: true, vertical: false)
        .help("Follow newest snapshots")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live follow")
    }
}

private struct TimelineAppMultiFilter: View {
    @Binding var selected: Set<String>
    @State private var apps: [(bundleId: String, name: String)] = []
    @State private var filter: String = ""
    @State private var isLoadingApps: Bool = false
    @State private var loadToken: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Filter apps", text: $filter)
                    .textFieldStyle(.roundedBorder)
                Button("Clear") { selected.removeAll() }
                Button("All") { selected = Set(apps.map { $0.bundleId }) }
            }
            if isLoadingApps && apps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading apps…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredApps(), id: \.bundleId) { entry in
                        Toggle(isOn: Binding(get: {
                            selected.contains(entry.bundleId)
                        }, set: { val in
                            if val { selected.insert(entry.bundleId) } else { selected.remove(entry.bundleId) }
                        })) {
                            Text(entry.name)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 120)
        }
        .onAppear { loadIfNeeded() }
    }

    private func filteredApps() -> [(bundleId: String, name: String)] {
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !f.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(f) || $0.bundleId.lowercased().contains(f) }
    }

    private func loadIfNeeded(force: Bool = false) {
        guard force || apps.isEmpty else { return }
        loadToken &+= 1
        let token = loadToken
        isLoadingApps = true

        DispatchQueue.global(qos: .userInitiated).async {
            let list = (try? DB.shared.distinctApps()) ?? []
            DispatchQueue.main.async {
                guard token == loadToken else { return }
                apps = list
                isLoadingApps = false
            }
        }
    }
}
