import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case calculatorHistory
    case emoji
    case uninstall
    case quicklinks
    /// Collects a quicklink's `{argument}` values before it opens; the pending request lives on
    /// `AppCore.quicklinkArguments`, the way `.uninstall`'s target lives on `UninstallSession`.
    case quicklinkArguments

    var id: String { rawValue }
    var title: String {
        switch self {
        case .launcher: return "Apps"
        case .clipboard: return "Clipboard"
        case .calculatorHistory: return "Calculator History"
        case .emoji: return "Emoji & Symbols"
        case .uninstall: return "Uninstall Application"
        case .quicklinks: return "Quicklinks"
        case .quicklinkArguments: return "Open Quicklink"
        }
    }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .uninstall: return "trash"
        case .quicklinks, .quicklinkArguments: return Quicklink.sfSymbol
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        case .uninstall: return "Filter files and folders by name…"
        case .quicklinks: return "Search quicklinks…"
        // Replaced by the pending argument's name; only reached if the session vanished mid-render.
        case .quicklinkArguments: return "Enter a value…"
        }
    }
}

/// The app a paste will land in, resolved once per palette show so the footer pill and menu rows can name it without re-reading `NSWorkspace` on every render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}

/// View-model shared between the panel's SwiftUI tree and the coordinator.
@MainActor
@Observable
final class PaletteViewModel {
    var mode: PaletteMode = .launcher
    var query: String = ""
    var selection: Int = 0
    /// Changes every time the palette is shown so the search field can re-focus.
    var focusToken = UUID()
    /// Changes only when `prepare` resets the palette, so the lists snap their scroll to the top even when query/mode were already at their defaults (`focusToken` can't serve: it bumps on every reopen, which must preserve a within-timeout scroll).
    var resetToken = UUID()
    /// Changes when an action reorders the list under the selection (pinning a clip lifts it into the Pinned section), so the list scrolls the highlight back into view.
    var followToken = UUID()
    /// Set by the compact bar's "…" overflow to expand into the full launcher without a query; cleared on every `prepare`.
    var forceExpanded = false
    /// The app a paste would land in, mirrored from `PaletteWindowController.previousApp` on every show. Deliberately *not* cleared by `prepare` — pop-to-root resets the screen, not the paste target.
    var pasteTarget: PasteTarget?
    /// Gates the mouse-hover highlight: true only while the pointer is physically moving (armed on `.mouseMoved`, disarmed on any `.keyDown` in `PalettePanel.sendEvent`). Untracked — read at hover time, never drives a re-render.
    @ObservationIgnored var hoverHighlightArmed = false
    /// True while a footer popover menu (⌘K Actions or the app menu) is open, so `PalettePanel.sendEvent` swallows text-editing keystrokes the field editor would otherwise consume — the query must stay frozen while a menu owns the keyboard (matches Raycast). Untracked — read at event time, mirrored from the view's menu state.
    @ObservationIgnored var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    /// Fired when `menuOpen` flips so `PalettePanel` can hide/show the search field's caret while it keeps first-responder status (no focus swap, so the placeholder never reflows).
    @ObservationIgnored var onMenuOpenChanged: ((Bool) -> Void)?

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        forceExpanded = false
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }
}

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customCommands = CustomCommandStore()
    let quicklinks = QuicklinkStore()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let snippetsStore: SnippetsStore
    let snippetListener = SnippetKeywordListener(
        syntheticEventTag: Paster.tinycastEventTag)
    let snippetTextInjector: SnippetTextInjector
    let hotKeys = HotKeyManager()
    let hyperKeyTap = HyperKeyTap()
    let windowMover = WindowMover()
    let settings: AppSettings
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteViewModel()
    let uninstall = UninstallSession()
    let quicklinkArguments = QuicklinkArgumentSession()

    /// Set when a quicklink editor should open as the Settings window appears; the pane consumes it.
    var pendingQuicklinkEdit: QuicklinkEditRequest?

    @ObservationIgnored private(set) lazy var snippetExpansion = SnippetExpansionCoordinator(
        store: snippetsStore, listener: snippetListener, injector: snippetTextInjector,
        clipboardStore: clipboardStore, appIndex: appIndex, settings: settings,
        showMessage: { [unowned self] in self.showMessage($0) }, core: self)
    @ObservationIgnored private(set) lazy var quicklinkCoordinator = QuicklinkCoordinator(
        store: quicklinks, argumentSession: quicklinkArguments, settings: settings,
        appIndex: appIndex, injector: snippetTextInjector, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, windowController: windowController,
        clipboardHistory: { [unowned self] in self.snippetExpansion.clipboardHistoryForExpansion() },
        core: self)

    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: appIndex,
        windowController: windowController, core: self)
    @ObservationIgnored private(set) lazy var systemActionCoordinator = SystemActionCoordinator(
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var uninstallCoordinator = UninstallCoordinator(
        session: uninstall, palette: palette, paletteCoordinator: paletteCoordinator,
        appIndex: appIndex, runningApps: runningApps, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, core: self)
    @ObservationIgnored private(set) lazy var customCommandCoordinator = CustomCommandCoordinator(
        store: customCommands, settings: settings, appIndex: appIndex,
        paletteCoordinator: paletteCoordinator, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, core: self)

    @ObservationIgnored private(set) lazy var launcherCoordinator = LauncherCoordinator(
        ranking: launcherRanking, windowController: windowController,
        paletteCoordinator: paletteCoordinator,
        customCommandCoordinator: customCommandCoordinator,
        systemActionCoordinator: systemActionCoordinator,
        quicklinkCoordinator: quicklinkCoordinator, snippetExpansion: snippetExpansion, core: self)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        clipboardStore: clipboardStore, palette: palette, windowController: windowController,
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var emojiCoordinator = EmojiCoordinator(
        frequentEmoji: frequentEmoji, settings: settings, windowController: windowController,
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var calculatorCoordinator = CalculatorCoordinator(
        calcHistory: calcHistory, paletteCoordinator: paletteCoordinator)

    @ObservationIgnored private lazy var windowController = PaletteWindowController(core: self)
    @ObservationIgnored private lazy var messageHUD = MessageHUDController(settings: settings)
    /// Every confirmation, failure report and value prompt in the app; it also guards against a held hotkey stacking dialogs.
    private let dialogs = DialogController()
    private let healthTicker = HealthTicker()

    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        self.launcherRanking = launcherRanking
        self.settings = settings
        appIndex = AppIndex(ranking: launcherRanking)
        let clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
        snippetsStore = SnippetsStore()
        snippetTextInjector = SnippetTextInjector(
            clipboardManager: clipboardManager,
            settings: settings)
    }

    func start() {
        Signposts.interval("AppCore.start") {
            // AppKit's default tooltip delay is ~2–3s; shorten it (in ms) so the compact-bar favorite tooltips appear promptly. Registration domain — never overrides a user default.
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            // Force dark: the Liquid Glass material is tuned for a deep dark surface and renders washed-out in Light mode.
            NSApp.appearance = NSAppearance(named: .darkAqua)

            clipboardStore.maxAge = settings.clipboardRetention.maxAge
            // Defer the SQLite read + prune off the launch path; the palette fills in later.
            Task { clipboardStore.load() }
            clipboardManager.start()

            appIndex.start(settings: settings)
            customCommands.onChange = { [weak self] _ in
                self?.customCommandCoordinator.applyCustomCommandsPresence()
            }
            customCommandCoordinator.applyCustomCommandsPresence()
            applyWindowCommandsPresence()
            quicklinks.onChange = { [weak self] _ in
                self?.quicklinkCoordinator.applyQuicklinksPresence()
            }
            // Loaded even while the feature is off, and before `hotKeys.start`: its stale-binding prune
            // reads this list, so an unloaded store would look like "every quicklink was deleted" and
            // throw away the user's shortcuts. The library is small, so this is one short read.
            quicklinks.load()
            quicklinkCoordinator.applyQuicklinksPresence()
            Task { await appIndex.refresh() }
            Task { await emojiIndex.load() }
            currencyRates.start()

            hyperKeyTap.healthTicker = healthTicker
            hotKeys.doubleTapMonitor.healthTicker = healthTicker
            snippetListener.healthTicker = healthTicker

            hotKeys.onTogglePalette = { [weak self] in self?.paletteCoordinator.togglePalette() }
            hotKeys.onToggleClipboard = { [weak self] in self?.paletteCoordinator.toggleClipboard() }
            hotKeys.onToggleEmoji = { [weak self] in self?.paletteCoordinator.toggleEmoji() }
            hotKeys.onRunCustomCommand = { [weak self] id in
                self?.customCommandCoordinator.runCustomCommand(id: id)
            }
            hotKeys.onRunSystemAction = { [weak self] id in
                self?.systemActionCoordinator.runSystemAction(id: id)
            }
            hotKeys.onRunWindowCommand = { [weak self] id in self?.runWindowCommand(id: id) }
            hotKeys.onOpenQuicklink = { [weak self] id in
                self?.quicklinkCoordinator.openQuicklink(id: id)
            }
            hotKeys.start(
                customCommandIDs: Set(customCommands.commands.map(\.id)),
                quicklinkIDs: Set(quicklinks.quicklinks.map(\.id)))
            // Deliberately keeps running while `hotKeys.recordingAction` pauses Carbon: the recorder relies on the tap's rewritten flags to capture Hyper shortcuts.
            hyperKeyTap.start(settings: settings)

            snippetsStore.onSnapshot = { [weak self] snapshot in
                guard let self else { return }
                self.snippetExpansion.applySnippetsLauncherPresence()
                self.snippetListener.update(snapshot.records)
            }
            // Off out of the box, so a user who never enables snippets pays for no load, no watcher and no tap.
            if settings.snippetsEnabled {
                Task { await snippetsStore.start() }
                snippetExpansion.startSnippetKeywordListener()
            }

            observeFeatureSwitches()

            // First launch has no palette hotkey bound and shows nothing but the menu-bar icon; guide the user once. Marker is written at show-time so it stays one-time even if they Cmd-Q mid-flow.
            if !OnboardingState.hasOnboarded {
                OnboardingState.markShown()
                showOnboarding()
            }
        }
    }

    func prepareForTermination() {
        // Caps Lock first: its HID remap is the only teardown that outlives the process, so nothing else may come before it.
        hyperKeyTap.prepareForTermination()
        snippetTextInjector.prepareForTermination()
        snippetListener.stop()
        snippetsStore.stop()
    }

    // MARK: - Feature switches

    private func observeFeatureSwitches() {
        track({
            _ = $0.windowManagementEnabled
            _ = $0.windowManagementShowInLauncher
        }, reproject: { $0.applyWindowCommandsPresence() })
        track({
            _ = $0.customCommandsEnabled
            _ = $0.customCommandsShowInLauncher
        }, reproject: { $0.customCommandCoordinator.applyCustomCommandsPresence() })
        track({
            _ = $0.quicklinksEnabled
            _ = $0.quicklinksShowInLauncher
        }, reproject: { $0.quicklinkCoordinator.applyQuicklinksPresence() })
        track({ _ = $0.snippetsEnabled }, reproject: { $0.snippetExpansion.applySnippetsEnabled() })
        track(
            { _ = $0.snippetsShowInLauncher },
            reproject: { $0.snippetExpansion.applySnippetsLauncherPresence() })
    }

    /// Fires synchronously on main before the write lands, so the task re-arms and re-reads.
    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(settings)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(reads, reproject: reproject)
                reproject(self)
            }
        }
    }

    private func applyWindowCommandsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setWindowCommandsVisible(visible)
    }

    // MARK: - Palette control

    func togglePalette() {
        paletteCoordinator.togglePalette()
    }

    func toggleClipboard() {
        paletteCoordinator.toggleClipboard()
    }

    func toggleEmoji() {
        paletteCoordinator.toggleEmoji()
    }

    func showPalette(mode: PaletteMode, restoreAnyMode: Bool = false) {
        paletteCoordinator.showPalette(mode: mode, restoreAnyMode: restoreAnyMode)
    }

    func hidePalette(restoreFocus: Bool = true) {
        paletteCoordinator.hidePalette(restoreFocus: restoreFocus)
    }

    var paletteIsCollapsed: Bool { paletteCoordinator.paletteIsCollapsed }

    func expandFromCompact() {
        paletteCoordinator.expandFromCompact()
    }

    func syncPaletteSize() {
        paletteCoordinator.syncPaletteSize()
    }

    func handleReopen() {
        paletteCoordinator.handleReopen()
    }

    func showSettings(tab: SettingsTab = .general) {
        paletteCoordinator.showSettings(tab: tab)
    }

    func showBackupSettings() {
        paletteCoordinator.showBackupSettings()
    }

    func showAbout() {
        paletteCoordinator.showAbout()
    }

    func showOnboarding() {
        paletteCoordinator.showOnboarding()
    }

    func finishOnboarding() {
        paletteCoordinator.finishOnboarding()
    }

    // MARK: - Actions invoked from the palette UI

    func launch(_ app: AppEntry, searchQuery: String? = nil) {
        launcherCoordinator.launch(app, searchQuery: searchQuery)
    }

    func resetRanking(for app: AppEntry) {
        launcherCoordinator.resetRanking(for: app)
    }

    // MARK: - Window commands

    /// The one funnel for both palette activation and a command's global hotkey, so the feature switch
    /// can't be bypassed by either — a shortcut stays registered while the feature is off and must move
    /// nothing.
    ///
    /// The command acts on the app the user was in, so the palette hands focus back before dispatching,
    /// the same dance the paste path does. Focus is restored rather than dropped: the window being moved
    /// is the one they want to keep working in.
    func runWindowCommand(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { hidePalette(restoreFocus: true) }
        windowMover.perform(
            id, target: target, gap: CGFloat(settings.windowGap),
            cycleOnRepeat: settings.windowCycleOnRepeat)
    }

    // MARK: - System actions

    func runSystemAction(id: SystemAction.ID) {
        systemActionCoordinator.runSystemAction(id: id)
    }

    // MARK: - Dialogs
    //
    // Routed through `AppCore` so `dialogs` stays the single owner; flows outside the palette (the backup
    // actions) reach the same dialogs instead of falling back to an `NSAlert`.

    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {
        await dialogs.notice(title: title, message: message, symbol: symbol, tone: tone)
    }

    /// `tone` is what the dialog looks like; `confirmRole` is what the confirm button looks like. They
    /// are separate on purpose — a red-glyph security warning can still carry a plain white button.
    func confirm(
        title: String, message: String, symbol: String, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive
    ) async -> Bool {
        await dialogs.confirm(
            title: title, message: message, symbol: symbol, tone: tone, confirmTitle: confirmTitle,
            confirmRole: confirmRole)
    }

    /// A failure with one usable second option; `true` when the user takes it.
    func reportFailure(title: String, message: String, symbol: String, recovery: String?) async
        -> Bool
    {
        await dialogs.reportFailure(
            title: title, message: message, symbol: symbol, recovery: recovery)
    }

    /// The transient success/info pill, so `messageHUD` stays single-owned alongside `dialogs`.
    func showMessage(_ message: String, tone: DialogTone = .success) {
        messageHUD.show(message: message, tone: tone)
    }

    /// The volume slider, so `dialogs` stays the single owner of every prompt in the app.
    func pickVolume(current: Float32) async -> Float32? {
        await dialogs.pickVolume(current: current)
    }

    func presentSystemActionFailure(id: SystemAction.ID, failure: SystemActionFailure) {
        systemActionCoordinator.presentSystemActionFailure(id: id, failure: failure)
    }

    // MARK: - Quicklinks

    func openQuicklink(id: UUID, forcingDefaultApp: Bool = false) {
        quicklinkCoordinator.openQuicklink(id: id, forcingDefaultApp: forcingDefaultApp)
    }

    @discardableResult
    func submitQuicklinkArgument(_ value: String) -> Bool {
        quicklinkCoordinator.submitQuicklinkArgument(value)
    }

    func cancelQuicklinkArguments() {
        quicklinkCoordinator.cancelQuicklinkArguments()
    }

    @discardableResult
    func addQuicklink(_ draft: Quicklink) throws -> Quicklink {
        try quicklinkCoordinator.addQuicklink(draft)
    }

    func updateQuicklink(_ draft: Quicklink) throws {
        try quicklinkCoordinator.updateQuicklink(draft)
    }

    func deleteQuicklink(id: UUID, confirming: Bool = true) async {
        await quicklinkCoordinator.deleteQuicklink(id: id, confirming: confirming)
    }

    func toggleQuicklinkPinned(id: UUID) {
        quicklinkCoordinator.toggleQuicklinkPinned(id: id)
    }

    func setQuicklinkShowsInRootSearch(_ shows: Bool, id: UUID) {
        quicklinkCoordinator.setQuicklinkShowsInRootSearch(shows, id: id)
    }

    func duplicateQuicklink(id: UUID) {
        quicklinkCoordinator.duplicateQuicklink(id: id)
    }

    func editQuicklink(_ quicklink: Quicklink?) {
        quicklinkCoordinator.editQuicklink(quicklink)
    }

    @discardableResult
    func replaceQuicklinks(_ incoming: [Quicklink]) -> Int {
        quicklinkCoordinator.replaceQuicklinks(incoming)
    }

    func exportQuicklinks() async {
        await quicklinkCoordinator.exportQuicklinks()
    }

    func importQuicklinks() async {
        await quicklinkCoordinator.importQuicklinks()
    }

    // MARK: - Custom commands

    @discardableResult
    func addCustomCommand(_ draft: CustomCommand) throws -> CustomCommand {
        try customCommandCoordinator.addCustomCommand(draft)
    }

    func updateCustomCommand(_ draft: CustomCommand) throws {
        try customCommandCoordinator.updateCustomCommand(draft)
    }

    func deleteCustomCommand(id: UUID) {
        customCommandCoordinator.deleteCustomCommand(id: id)
    }

    @discardableResult
    func replaceCustomCommands(_ commands: [CustomCommand]) -> Int {
        customCommandCoordinator.replaceCustomCommands(commands)
    }

    func runCustomCommand(id: UUID) {
        customCommandCoordinator.runCustomCommand(id: id)
    }

    func quit(_ app: AppEntry) {
        launcherCoordinator.quit(app)
    }

    // MARK: - Uninstall

    func beginUninstall(_ app: AppEntry) {
        uninstallCoordinator.beginUninstall(app)
    }

    func performUninstall() {
        uninstallCoordinator.performUninstall()
    }

    func copyUninstallPath(_ candidate: UninstallCandidate) {
        uninstallCoordinator.copyUninstallPath(candidate)
    }

    func showUninstallItemInFinder(_ candidate: UninstallCandidate) {
        uninstallCoordinator.showUninstallItemInFinder(candidate)
    }

    func showUninstallItemInfo(_ candidate: UninstallCandidate) {
        uninstallCoordinator.showUninstallItemInfo(candidate)
    }

    func copyCalculatorResult(_ result: CalcResult) {
        calculatorCoordinator.copyCalculatorResult(result)
    }

    func copyHistoryEntry(_ entry: CalcHistoryEntry) {
        calculatorCoordinator.copyHistoryEntry(entry)
    }

    func copyHistoryExpression(_ entry: CalcHistoryEntry) {
        calculatorCoordinator.copyHistoryExpression(entry)
    }

    func showInFinder(_ app: AppEntry) {
        launcherCoordinator.showInFinder(app)
    }

    func paste(_ item: ClipboardItem) {
        clipboardCoordinator.paste(item)
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        clipboardCoordinator.pasteKeepingWindowOpen(item)
    }

    func copyToClipboard(_ item: ClipboardItem) {
        clipboardCoordinator.copyToClipboard(item)
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        clipboardCoordinator.revealClipboardImage(item)
    }

    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardCoordinator.togglePinnedClip(item)
    }

    // MARK: - Emoji

    func pasteEmoji(_ entry: EmojiEntry) {
        emojiCoordinator.pasteEmoji(entry)
    }

    func copyEmoji(_ entry: EmojiEntry) {
        emojiCoordinator.copyEmoji(entry)
    }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry) {
        emojiCoordinator.pasteEmojiKeepingWindowOpen(entry)
    }

    // MARK: - Snippets

    func revealSnippetsInFinder() {
        snippetExpansion.revealSnippetsInFinder()
    }

    func setSnippetsEnabled(_ enabled: Bool) {
        snippetExpansion.setSnippetsEnabled(enabled)
    }
}
