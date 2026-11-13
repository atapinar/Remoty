import SwiftUI
import AppKit

struct ProjectorApp: Identifiable, Equatable {
    let id: String
    let title: String
}

struct RemoteEvent: Identifiable {
    let id = UUID()
    let date = Date()
    let title: String
    let detail: String
}

@MainActor final class ProjectorStore: ObservableObject {
    static let defaultFavorites = ["com.google.android.youtube.tv", "com.netflix.mediaclient", "com.amazon.amazonvideo.livingroom", "com.mxtech.videoplayer.ad"]

    @Published var host = UserDefaults.standard.string(forKey: "projector.host") ?? ""
    @Published var name = UserDefaults.standard.string(forKey: "projector.name") ?? "Projector"
    @Published var connected = false
    @Published var connecting = false
    @Published var discovering = false
    @Published var devices: [FoundDevice] = []
    @Published var apps: [ProjectorApp] = []
    @Published var foregroundID = ""
    @Published var wakefulness = ""
    @Published var volume: Double = 0
    @Published var volumeMax: Double = 100
    @Published var hasVolume = false
    @Published var muted = false
    @Published var lamp: Double?
    @Published var picture: [String: Double] = [:]
    @Published var autoKeystone: Bool?
    @Published var zoom: Int?
    @Published var mountMode: String?
    @Published var screenOffTimeout: Int?
    @Published var screensaver: Bool?
    @Published var discoveryError: String?
    @Published var launcherIcons: [String: NSImage] = [:]
    @Published var mediaFiles: [MediaFile] = []
    @Published var transferring = false
    @Published var transferStatus: String?
    @Published var transferFraction: Double = 0
    @Published var fitPhotos = UserDefaults.standard.object(forKey: "media.fitPhotos") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fitPhotos, forKey: "media.fitPhotos") }
    }
    @Published var identity = UserDefaults.standard.string(forKey: "projector.identity") ?? ""
    @Published var error: String?
    @Published var notice: String?
    @Published var events: [RemoteEvent] = []
    @Published var usageRevision = 0
    @Published var preferredPanelHeight: CGFloat = 740
    @Published var favorites = UserDefaults.standard.stringArray(forKey: "projector.favorites") ?? ProjectorStore.defaultFavorites {
        didSet { UserDefaults.standard.set(favorites, forKey: "projector.favorites") }
    }
    private var pollTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var lampTask: Task<Void, Never>?
    private var pictureTasks: [String: Task<Void, Never>] = [:]
    private var pqReady = ""
    private var refreshTask: Task<Void, Never>?
    private var transferProcess: Process?
    private var transferCancelled = false
    private var loadingIcons = false
    private var autoReconnect = false
    private var sleepSent = false
    private let dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("local.AndroidTVRemote")
    private lazy var journal = UsageJournal(url: dataDirectory.appendingPathComponent("usage.json"))
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseUsage() }
        })
    }

    var serial: String { Adb.serial(for: host) }
    var awake: Bool { wakefulness == "Awake" }
    var status: String {
        if Adb.path == nil { return "adb not installed" }
        if connecting { return "Connecting…" }
        if !connected { return "Disconnected" }
        switch wakefulness {
        case "Awake": return "Connected"
        case "Dreaming": return "Connected · screensaver"
        case "Asleep": return "Connected · asleep"
        default: return "Connected"
        }
    }
    var foregroundName: String { foregroundID.isEmpty ? "" : AppNames.name(foregroundID) }
    var currentApp: String {
        guard connected else { return "Your projector, on your Mac." }
        if wakefulness == "Asleep" { return "Projector is asleep" }
        if wakefulness == "Dreaming" { return "Screensaver" }
        return foregroundID.isEmpty ? "Projector is on" : AppNames.isHome(foregroundID) ? "Home screen" : foregroundName
    }
    var pinnedApps: [ProjectorApp] {
        favorites.map { id in apps.first { $0.id == id } ?? ProjectorApp(id: id, title: AppNames.name(id)) }
    }
    var shortcuts: [ProjectorApp] {
        apps.sorted { a, b in
            let af = favorites.contains(a.id), bf = favorites.contains(b.id)
            return af != bf ? af : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    func log(_ title: String, _ detail: String) {
        events.insert(RemoteEvent(title: title, detail: detail), at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
    }

    func connect(rediscover: Bool = true) {
        guard !connecting else { return }
        guard Adb.path != nil else { error = AdbError.missing.errorDescription; return }
        guard Adb.localHost(host) else { error = "Enter the projector's local IPv4 address or .local name, or find it on your network."; return }
        autoReconnect = true; connecting = true
        if !sleepSent { error = nil }
        pollTask?.cancel()
        let serial = serial
        Task {
            do {
                try await Adb.connect(serial)
                connected = true; connecting = false; notice = nil; sleepSent = false
                UserDefaults.standard.set(host, forKey: "projector.host")
                UserDefaults.standard.set(name, forKey: "projector.name")
                UserDefaults.standard.set(identity, forKey: "projector.identity")
                log("Connected", name)
                await loadApps()
                await refreshPicture()
                startPolling()
            } catch {
                var unauthorized = false
                if case AdbError.unauthorized = error { unauthorized = true }
                if rediscover, !unauthorized, !sleepSent, !identity.isEmpty, await relocate() {
                    connecting = false
                    connect(rediscover: false)
                    return
                }
                connecting = false; connected = false
                log("Connection failed", error.localizedDescription)
                if sleepSent && autoReconnect {
                    notice = "Projector asleep - wake it with the remote"
                    retryLater()
                } else {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func relocate() async -> Bool {
        let found = await Discovery.search().devices
        guard let match = found.first(where: { $0.identity == identity }) else { return false }
        let parts = host.split(separator: ":")
        let base = parts.first.map(String.init) ?? host
        let port = parts.count == 2 ? ":" + parts[1] : ""
        guard let next = [match.address, match.host].first(where: { $0.caseInsensitiveCompare(base) != .orderedSame }) else { return false }
        await Adb.disconnect(serial)
        host = next + port
        UserDefaults.standard.set(host, forKey: "projector.host")
        log("Projector found again", next)
        return true
    }

    private func retryLater() {
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if self.autoReconnect && !self.connected && !self.connecting { self.connect() }
        }
    }

    func disconnect() {
        autoReconnect = false
        pollTask?.cancel(); pollTask = nil
        pauseUsage()
        let wasConnected = connected
        connected = false; connecting = false; hasVolume = false; wakefulness = ""
        if wasConnected { let serial = serial; Task { await Adb.disconnect(serial) } }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do { try await self.refresh(); failures = 0 }
                catch AdbError.unauthorized { self.lost(AdbError.unauthorized); return }
                catch {
                    failures += 1
                    if failures >= 2 { self.lost(error); return }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func lost(_ failure: Error) {
        connected = false; hasVolume = false; wakefulness = ""
        pauseUsage()
        log("Connection lost", failure.localizedDescription)
        guard autoReconnect else { return }
        notice = sleepSent ? "Projector asleep - wake it with the remote" : "Connection lost. Reconnecting…"
        retryLater()
    }

    func refresh() async throws {
        let serial = serial
        let power = try await Adb.shell(serial, "dumpsys power | grep mWakefulness=")
        if let state = AdbParse.wakefulness(power) { wakefulness = state }
        if let reading = AdbParse.volume((try? await Adb.shell(serial, "cmd media_session volume --stream 3 --get")) ?? "") {
            volumeMax = Double(max(1, reading.max))
            if volumeTask == nil { volume = Double(reading.value) }
            hasVolume = true
        }
        let activity = (try? await Adb.shell(serial, "dumpsys activity activities | grep -E 'topResumedActivity|ResumedActivity'")) ?? ""
        foregroundID = AdbParse.foreground(activity) ?? ""
        recordUsage()
    }

    private func recordUsage() {
        if connected && awake && !foregroundID.isEmpty && !AppNames.isHome(foregroundID) {
            journal.observe(host: "projector", appID: foregroundID, title: foregroundName)
        } else {
            journal.pause()
        }
        saveUsage()
    }

    private func saveUsage() {
        do { try journal.save() } catch { notice = "Could not save usage history." }
        usageRevision += 1
    }

    private func pauseUsage() { journal.pause(); saveUsage() }

    func usage(days: Int) -> [UsageTotal] {
        let since = Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return journal.totals(host: "projector", since: since)
    }

    func loadApps() async {
        let output = (try? await Adb.shell(serial, "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER")) ?? ""
        var found = AdbParse.packages(output).map { ProjectorApp(id: $0, title: AppNames.name($0)) }
        let installed = Set(((try? await Adb.shell(serial, "pm list packages")) ?? "").split(whereSeparator: \.isNewline).map { $0.replacingOccurrences(of: "package:", with: "") })
        for favorite in favorites where !found.contains(where: { $0.id == favorite }) && installed.contains(favorite) {
            found.append(ProjectorApp(id: favorite, title: AppNames.name(favorite)))
        }
        apps = found
        Task { await loadLauncherIcons() }
    }

    func icon(_ id: String) -> NSImage? { AppResources.icons[id] ?? launcherIcons[id] }

    private func loadLauncherIcons() async {
        guard !loadingIcons else { return }
        loadingIcons = true
        for app in apps where AppResources.icons[app.id] == nil && launcherIcons[app.id] == nil {
            if let image = await LauncherIcons.load(serial: serial, package: app.id) { launcherIcons[app.id] = image }
        }
        loadingIcons = false
    }

    func refreshMedia() async {
        guard connected, let output = try? await Adb.shell(serial, Media.listCommand) else { return }
        mediaFiles = Media.list(output)
    }

    func upload(_ urls: [URL]) {
        guard connected, !transferring else { return }
        let (uploads, rejected) = Media.collect(urls)
        if !rejected.isEmpty { error = "Only photos and videos can be sent. Skipped: \(rejected.joined(separator: ", "))" }
        guard !uploads.isEmpty else {
            if rejected.isEmpty { error = "No photos or videos found in the dropped items." }
            return
        }
        let serial = serial, fit = fitPhotos
        let total = max(1, uploads.reduce(0) { $0 + $1.size })
        transferring = true; transferCancelled = false; transferFraction = 0
        transferStatus = "Checking free space..."
        Task {
            defer { transferring = false; transferProcess = nil }
            guard let free = Media.freeBytes((try? await Adb.shell(serial, Media.freeCommand)) ?? "") else {
                transferStatus = nil; error = "Could not read the free space on the projector."; return
            }
            guard free > total else {
                transferStatus = nil; error = "Not enough space on the projector: \(Media.size(total)) needed, \(Media.size(free)) free."; return
            }
            var sent: Int64 = 0
            var done = 0
            for (index, upload) in uploads.enumerated() {
                guard !transferCancelled else { break }
                transferStatus = "Sending \(index + 1) of \(uploads.count): \(upload.local.lastPathComponent)"
                let base = sent
                var local = upload.local, remote = upload.remote
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("remoty-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: temporary) }
                do {
                    if fit && remote.hasPrefix(Media.pictures + "/") {
                        let name = upload.local.deletingPathExtension().lastPathComponent + ".jpg"
                        let source = upload.local
                        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                        local = temporary.appendingPathComponent(name)
                        try await Task.detached { [local] in try Media.letterbox(source, to: local) }.value
                        remote = Media.pictures + "/" + name
                    }
                    _ = try await Adb.run(["-s", serial, "push", local.path, remote], timeout: 7200,
                                          started: { process in Task { @MainActor in self.transferProcess = process } },
                                          progress: { chunk in
                                              guard let percent = Media.percent(chunk) else { return }
                                              Task { @MainActor in self.transferFraction = Double(base + upload.size * Int64(percent) / 100) / Double(total) }
                                          })
                    _ = try await execute(Media.scanCommand(remote), wake: false)
                    done += 1
                } catch {
                    if transferCancelled { _ = try? await Adb.shell(serial, "rm -f " + Adb.quote(remote)); break }
                    self.error = "Could not send \(upload.local.lastPathComponent): \(error.localizedDescription)"
                    break
                }
                sent += upload.size
                transferFraction = Double(sent) / Double(total)
            }
            transferStatus = transferCancelled ? "Transfer cancelled. \(done) of \(uploads.count) sent." : "\(done) of \(uploads.count) sent."
            log("Media", transferStatus ?? "")
            await refreshMedia()
        }
    }

    func cancelTransfer() {
        transferCancelled = true
        transferProcess?.terminate()
    }

    func deleteMedia(_ file: MediaFile) {
        guard connected else { return }
        Task {
            do { _ = try await execute(Media.deleteCommand(file.path), wake: false); log("Deleted", file.name) }
            catch { self.error = "Could not delete \(file.name): \(error.localizedDescription)" }
            await refreshMedia()
        }
    }

    private func execute(_ command: String, wake: Bool) async throws -> String {
        let output = try await Adb.shell(serial, wake ? "input keyevent \(KeyCode.wake); " + command : command)
        if let failure = AdbParse.failure(output) { throw AdbError.failed(failure) }
        return output
    }

    func send(_ command: String, title: String, wake: Bool = true) {
        guard connected else { return }
        Task {
            do { _ = try await execute(command, wake: wake); log(title, command) }
            catch { self.error = "\(title): \(error.localizedDescription)"; log(title, error.localizedDescription) }
            refreshSoon()
        }
    }

    private func refreshSoon() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            try? await refresh()
        }
    }

    func press(_ keycode: String) { send("input keyevent \(keycode)", title: keycode, wake: keycode != KeyCode.sleep && keycode != KeyCode.wake) }

    func wake() {
        sleepSent = false
        press(KeyCode.wake)
    }

    func power() {
        if awake { sleepSent = true; press(KeyCode.sleep) } else { wake() }
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        send(Adb.textCommand(text), title: "Text")
    }

    func launch(_ app: ProjectorApp) {
        guard connected, Adb.validPackage(app.id) else { return }
        Task {
            do {
                let output = try await Adb.shell(serial, "input keyevent \(KeyCode.wake); monkey -p \(app.id) -c android.intent.category.LEANBACK_LAUNCHER 1")
                if output.contains("No activities found") { _ = try await execute("monkey -p \(app.id) 1", wake: false) }
                log("Launch", app.title)
            } catch { self.error = "Could not open \(app.title): \(error.localizedDescription)"; log("Launch", error.localizedDescription) }
            refreshSoon()
        }
    }

    func toggleFavorite(_ app: ProjectorApp) {
        if let index = favorites.firstIndex(of: app.id) { favorites.remove(at: index) } else { favorites.append(app.id) }
    }

    func changeVolume(_ value: Double) {
        volume = value.rounded()
        volumeTask?.cancel()
        let serial = serial, target = Int(volume)
        volumeTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            do { _ = try await Adb.shell(serial, "cmd media_session volume --stream 3 --set \(target)") }
            catch { self.error = error.localizedDescription }
            volumeTask = nil
        }
    }

    func volumeStep(_ up: Bool) {
        press(up ? KeyCode.volumeUp : KeyCode.volumeDown)
        Task { try? await Task.sleep(nanoseconds: 400_000_000); try? await refresh() }
    }

    func toggleMute() { press(KeyCode.mute); muted.toggle() }

    func refreshPicture() async {
        let serial = serial
        func read(_ command: String) async -> String? { try? await Adb.shell(serial, command) }
        if lampTask == nil, let value = await read(PictureControls.lampRead).flatMap(PictureControls.lamp) { lamp = Double(value) }
        if pictureTasks.isEmpty, await preparePQ(), let output = await read(PictureControls.pqRead) {
            let values = PictureControls.pqValues(output)
            if pictureTasks.isEmpty { picture = values.mapValues(Double.init) }
        }
        autoKeystone = await read(PictureControls.autoKeystoneRead).flatMap(PictureControls.flag)
        zoom = await read(PictureControls.zoomRead).flatMap(PictureControls.zoom)
        mountMode = await read(PictureControls.mountRead).flatMap(PictureControls.mountMode)
        screenOffTimeout = await read(PictureControls.screenOffRead).flatMap(AdbParse.integer)
        screensaver = await read(PictureControls.screensaverRead).flatMap(PictureControls.flag)
    }

    func changeLamp(_ value: Double) {
        lamp = value.rounded()
        lampTask?.cancel()
        let serial = serial, command = PictureControls.lampWrite(Int(value.rounded()))
        lampTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do { _ = try await Adb.shell(serial, command) } catch { self.error = error.localizedDescription }
            lampTask = nil
        }
    }

    func preparePQ() async -> Bool {
        let serial = serial
        guard pqReady != serial else { return true }
        guard let dex = PictureControls.pqDex, let hash = PictureControls.md5(dex) else { return false }
        let remote = (try? await Adb.shell(serial, PictureControls.pqHash)) ?? ""
        if !remote.hasPrefix(hash) {
            guard (try? await Adb.run(["-s", serial, "push", dex.path, PictureControls.pqRemote], timeout: 30)) != nil else { return false }
        }
        pqReady = serial
        return true
    }

    func changePicture(_ item: String, _ value: Double) {
        picture[item] = value.rounded()
        pictureTasks[item]?.cancel()
        let serial = serial, command = PictureControls.pqWrite(item, Int(value.rounded()))
        pictureTasks[item] = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            if await preparePQ() {
                do {
                    let output = try await Adb.shell(serial, command)
                    if output.contains("error=") { self.error = output.trimmingCharacters(in: .whitespacesAndNewlines) }
                } catch { self.error = error.localizedDescription }
            }
            if !Task.isCancelled { pictureTasks[item] = nil }
        }
    }

    func apply(_ command: String, title: String) {
        guard connected else { return }
        Task {
            do { _ = try await execute(command, wake: false); log(title, command) }
            catch { self.error = "\(title): \(error.localizedDescription)"; log(title, error.localizedDescription) }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshPicture()
        }
    }

    func discover() {
        guard !discovering else { return }
        discovering = true; discoveryError = nil
        Task {
            let result = await Discovery.search()
            devices = result.devices
            discoveryError = result.failure?.errorDescription ?? (devices.isEmpty ? "No projector found. Enter its IPv4 address or .local name." : nil)
            discovering = false
            log("Discovery", devices.isEmpty ? discoveryError ?? "" : devices.map { "\($0.name) \($0.address)" }.joined(separator: ", "))
        }
    }
}
