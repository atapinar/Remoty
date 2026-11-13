import SwiftUI
import AppKit

private let mutedInk = Color.white.opacity(0.49)
private let baseAccent = Color(red: 0.24, green: 0.80, blue: 0.52)

private enum RemoteTab: String, CaseIterable, Identifiable {
    case home = "Your projector", remote = "Remote", apps = "Apps", mirror = "Mirror", media = "Media", usage = "Activity", picture = "Picture"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: return "videoprojector"
        case .remote: return "dpad"
        case .apps: return "square.grid.2x2"
        case .mirror: return "airplay.video"
        case .media: return "photo.on.rectangle.angled"
        case .usage: return "chart.bar.xaxis"
        case .picture: return "slider.horizontal.3"
        }
    }
}

struct Brand {
    let color: Color
    let tagline: String
    static func forApp(_ id: String) -> Brand {
        let key = id.lowercased()
        if key.contains("netflix") { return Brand(color: Color(red: 0.94, green: 0.08, blue: 0.13), tagline: "A great story is waiting for you.") }
        if key.contains("youtube") { return Brand(color: Color(red: 1, green: 0.18, blue: 0.23), tagline: "Everything you love, on the big screen.") }
        if key.contains("amazon") { return Brand(color: Color(red: 0.08, green: 0.64, blue: 1), tagline: "Time for popcorn.") }
        if key.contains("mxtech") { return Brand(color: Color(red: 0.16, green: 0.47, blue: 1), tagline: "Your files, on the wall.") }
        if key.contains("disney") { return Brand(color: Color(red: 0.20, green: 0.38, blue: 1), tagline: "A universe of stories.") }
        if key.contains("spotify") { return Brand(color: Color(red: 0.12, green: 0.84, blue: 0.43), tagline: "Set the mood. Press play.") }
        return Brand(color: baseAccent, tagline: "Your projector. Your wall. Your remote.")
    }
}

private struct PanelButton: ButtonStyle {
    var accent: Color = baseAccent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(0.79))
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.13 : 0.065)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.068)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.085), lineWidth: 0.7))
    }
}

struct AppMark: View {
    let id: String
    let title: String
    var size: CGFloat = 36
    var icon: NSImage?
    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: AppMark.symbols.first(where: { id.contains($0.key) })?.value ?? "app.dashed")
                    .resizable().scaledToFit().padding(size * 0.14).foregroundStyle(Color.white.opacity(0.6))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    static let symbols: [String: String] = [
        "youtube": "play.rectangle.fill", "tv.settings": "gearshape.fill", "vending": "bag.fill",
        "mxtech": "play.circle.fill", "musicplayer": "music.note", "videoplayer": "film", "FileBrower": "folder.fill",
        "mediacenter": "photo.on.rectangle", "updater": "arrow.down.circle.fill", "launcher": "house.fill",
    ]
}

private struct AppTile: View {
    let app: ProjectorApp
    let icon: NSImage?
    var size: CGFloat = 46
    var active = false
    var favorite: Bool?
    var onFavorite: () -> Void = {}
    let onOpen: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 7) {
                AppMark(id: app.id, title: app.title, size: size, icon: icon)
                Text(app.title).font(.system(size: 10, weight: active ? .semibold : .regular)).foregroundStyle(Color.white.opacity(active ? 0.95 : 0.75)).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(HoverStyle(hovering: hovering)).onHover { hovering = $0 }
            .overlay(alignment: .topTrailing) {
                if let favorite, hovering || favorite {
                    Button(action: onFavorite) { Image(systemName: favorite ? "star.fill" : "star").font(.system(size: 9)).foregroundStyle(Color.white.opacity(favorite ? 0.75 : 0.45)).padding(5) }
                        .buttonStyle(.plain).help(favorite ? "Remove \(app.title) from favorites" : "Add \(app.title) to favorites").accessibilityLabel("Favorite \(app.title)")
                }
            }
            .help("Open \(app.title) on the projector")
    }
}

private struct HoverStyle: ButtonStyle {
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.1 : hovering ? 0.05 : 0)))
    }
}

struct RemoteView: View {
    @ObservedObject var store: ProjectorStore
    @State private var tab: RemoteTab = .home
    @State private var settings = false
    @State private var search = ""
    @State private var text = ""
    @State private var draftHost = ""
    @State private var draftName = ""
    @State private var usageDays = 1
    @State private var showEvents = false
    @State private var draftDevice: FoundDevice?
    @State private var dropTargeted = false
    @State private var pendingDelete: MediaFile?
    private var theme: Brand { Brand.forApp(store.foregroundID) }
    private var accent: Color { theme.color }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.top, 16).padding(.bottom, 16)
            tabs.padding(.bottom, 14)
            contentScroll
            footer.padding(.top, 10).padding(.bottom, 12)
        }.padding(.horizontal, 13).frame(width: 360)
            .background(LinearGradient(colors: [Color(red: 0.065, green: 0.070, blue: 0.080), Color(white: 0.042)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .foregroundStyle(Color.white.opacity(0.86)).preferredColorScheme(.dark)
            .font(.system(size: 12))
            .tint(accent)
            .animation(.easeOut(duration: 0.22), value: store.foregroundID)
            .onChange(of: tab) { _, value in
                store.preferredPanelHeight = preferredHeight(value)
                if value == .picture { Task { await store.refreshPicture() } }
                if value == .media { Task { await store.refreshMedia() } }
            }
            .onChange(of: settings) { _, value in store.preferredPanelHeight = value ? 620 : preferredHeight(tab) }
            .onAppear { if store.host.isEmpty { showConnectionSettings() } }
    }

    private func preferredHeight(_ tab: RemoteTab) -> CGFloat { tab == .home || tab == .remote ? 740 : tab == .mirror ? 520 : tab == .usage ? 580 : 660 }

    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if settings { settingsPanel }
                else {
                    if tab != .home { sectionTitle(tab.rawValue.uppercased()) }
                    if !store.connected { connectionPanel }
                    tabContent
                }
                feedback
            }.padding(.bottom, 12)
        }.scrollIndicators(.hidden)
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .home: homePanel
        case .remote: remotePanel
        case .apps: appsPanel
        case .mirror: mirrorPanel
        case .media: mediaPanel
        case .usage: usagePanel
        case .picture: picturePanel
        }
    }

    @ViewBuilder private var feedback: some View {
        if let error = store.error {
            PanelCard {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { store.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).help("Dismiss message")
                }
            }
        } else if let notice = store.notice {
            Text(notice).font(.system(size: 11)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "videoprojector.fill").font(.system(size: 20)).foregroundStyle(baseAccent).frame(width: 31, height: 31)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.name).font(.system(size: 17, weight: .semibold)).tracking(-0.3).lineLimit(1)
                Text("Android TV · ADB").font(.system(size: 10, weight: .medium)).foregroundStyle(mutedInk)
            }
            Spacer()
            Menu {
                Button("Refresh projector data") { Task { try? await store.refresh(); await store.loadApps(); await store.refreshPicture() } }.disabled(!store.connected)
                Button(store.connected ? "Disconnect" : "Connect") {
                    if store.connected { store.disconnect() }
                    else if store.host.isEmpty { showConnectionSettings() }
                    else { store.connect() }
                }
                Divider()
                Button("Quit Remoty") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 30).foregroundStyle(mutedInk) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Menu {
                Button(store.awake ? "Put projector to sleep" : "Wake projector") { store.power() }.disabled(!store.connected)
            } label: {
                Image(systemName: "power").font(.system(size: 17)).foregroundStyle(store.connected && store.awake ? .white : mutedInk)
                    .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.06)))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Projector power")
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(RemoteTab.allCases) { item in
                Button { tab = item; settings = false } label: {
                    Image(systemName: item.symbol).font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tab == item && !settings ? accent : mutedInk)
                        .frame(maxWidth: .infinity).frame(height: 35)
                        .background(RoundedRectangle(cornerRadius: 9).fill(tab == item && !settings ? accent.opacity(0.2) : .clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(item.rawValue).accessibilityLabel(item.rawValue)
            }
        }.padding(4).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.066)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
    }

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(mutedInk)
            Spacer()
            if store.connecting { ProgressView().controlSize(.mini) }
        }.padding(.horizontal, 1)
    }

    private var homePanel: some View {
        VStack(spacing: 12) {
            nowPlayingCard
            if dozing || store.screensaver == true { screensaverCard }
            audioCard
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Favorites", systemImage: "star").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button { tab = .apps } label: { Text("See all").font(.system(size: 10)).foregroundStyle(mutedInk) }.buttonStyle(.plain)
                }.padding(.horizontal, 4)
                if store.pinnedApps.isEmpty { Text("Use the star in Apps to add favorites.").font(.system(size: 10)).foregroundStyle(mutedInk).padding(.horizontal, 4) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(store.pinnedApps) { app in
                        AppTile(app: app, icon: store.icon(app.id), size: 44, active: store.foregroundID == app.id) { store.launch(app) }.disabled(!store.connected)
                    }
                }
            }
            inputsCard
            let mostUsed = store.usage(days: 7).prefix(4)
            if !mostUsed.isEmpty {
                HStack(spacing: 8) {
                    Text("Most used").font(.system(size: 10)).foregroundStyle(mutedInk)
                    Spacer()
                    ForEach(Array(mostUsed)) { item in
                        Button { store.launch(ProjectorApp(id: item.id, title: item.title)) } label: { AppMark(id: item.id, title: item.title, size: 25, icon: store.icon(item.id)) }.buttonStyle(.plain).help("Open \(item.title)").disabled(!store.connected)
                    }
                    Button { tab = .usage } label: { Image(systemName: "chevron.right").foregroundStyle(mutedInk) }.buttonStyle(.plain).help("View activity")
                }.padding(.horizontal, 4)
            }
        }
    }

    private var nowPlayingCard: some View {
        VStack(spacing: 0) {
            ZStack {
                Ellipse().fill(accent.opacity(store.connected && store.awake ? 0.28 : 0.08)).frame(width: 230, height: 110).blur(radius: 38).offset(y: 9)
                if let hero = AppResources.asset("tv-hero") { Image(nsImage: hero).resizable().interpolation(.high).scaledToFit().frame(width: 312, height: 178).accessibilityHidden(true) }
                VStack(spacing: 9) {
                    if store.connected && store.awake && !store.foregroundID.isEmpty && !AppNames.isHome(store.foregroundID) {
                        AppMark(id: store.foregroundID, title: store.foregroundName, size: 46, icon: store.icon(store.foregroundID))
                    } else {
                        Image(systemName: store.connected && !store.awake ? "moon.zzz" : "videoprojector").font(.system(size: 32, weight: .light)).foregroundStyle(baseAccent)
                    }
                    Text(store.connected ? store.currentApp : "Android TV").font(.system(size: 15, weight: .semibold)).tracking(-0.3).lineLimit(1)
                }.offset(y: -6).shadow(color: accent.opacity(0.5), radius: 16)
            }.frame(height: 174).contentShape(Rectangle()).onTapGesture { if dozing { store.wake() } }.help(dozing ? "Click to wake the projector" : "")
            if dozing {
                Button { store.wake() } label: { Label("Wake projector", systemImage: "sun.max.fill").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).frame(height: 30) }
                    .buttonStyle(PanelButton(accent: accent)).help("Send the wake key to the projector").padding(.top, 6)
            }
            HStack(spacing: 5) {
                Circle().fill(store.connected ? accent : mutedInk).frame(width: 4, height: 4)
                Text(store.connected ? "APP REPORTED BY PROJECTOR" : "YOUR PROJECTOR, ON YOUR MAC").font(.system(size: 8, weight: .bold)).tracking(1.1).foregroundStyle(mutedInk)
                Spacer()
                if store.connected { Text(store.wakefulness.uppercased()).font(.system(size: 9, weight: .medium)).foregroundStyle(accent) }
            }.padding(.horizontal, 10).padding(.top, 7)
            Text(theme.tagline).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.65)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 7)
        }.padding(.top, 2)
    }

    private var dozing: Bool { store.connected && (store.wakefulness == "Dreaming" || store.wakefulness == "Asleep") }

    private var screensaverCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Screensaver", isOn: Binding(get: { store.screensaver ?? false }, set: { store.apply(PictureControls.screensaverWrite($0), title: "Screensaver") }))
                    .toggleStyle(.switch).controlSize(.small).disabled(!store.connected || store.screensaver == nil)
                Text("The projector starts the screensaver after 5 minutes without input.").font(.system(size: 10)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var audioCard: some View {
        PanelCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(mutedInk)
                    Text("Projector audio").fontWeight(.semibold)
                    Spacer()
                    Text(store.hasVolume ? "\(Int(store.volume))" : "-").font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                }
                HStack(spacing: 9) {
                    Button { store.toggleMute() } label: { Image(systemName: store.muted ? "speaker.slash.fill" : "speaker.fill").foregroundStyle(store.muted ? accent : mutedInk).frame(width: 20) }.buttonStyle(.plain).help("Mute or unmute")
                    Slider(value: Binding(get: { store.volume }, set: store.changeVolume), in: 0...store.volumeMax).tint(accent).accessibilityLabel("Projector volume")
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(mutedInk)
                }.disabled(!store.connected || !store.hasVolume)
                HStack {
                    Text(store.muted ? "Mute sent" : "Media volume").font(.system(size: 10)).foregroundStyle(mutedInk)
                    Spacer()
                    Button { store.volumeStep(false) } label: { Image(systemName: "minus").frame(width: 25, height: 22) }.buttonStyle(PanelButton()).help("Lower volume")
                    Button { store.volumeStep(true) } label: { Image(systemName: "plus").frame(width: 25, height: 22) }.buttonStyle(PanelButton()).help("Raise volume")
                }.disabled(!store.connected || !store.hasVolume)
            }
        }
    }

    private var inputsCard: some View {
        PanelCard {
            VStack(spacing: 7) {
                HStack { Label("Inputs", systemImage: "cable.connector").font(.system(size: 12, weight: .semibold)); Spacer() }
                inputRow("HDMI 1", "Switch to HDMI 1") { store.send(PictureControls.hdmi(1), title: "HDMI 1") }
                inputRow("HDMI 2", "Switch to HDMI 2") { store.send(PictureControls.hdmi(2), title: "HDMI 2") }
                inputRow("Input menu", "Show the projector's input list") { store.press(KeyCode.inputMenu) }
            }
        }
    }

    private func inputRow(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack { RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.055)); Image(systemName: "cable.connector").font(.system(size: 15)).foregroundStyle(mutedInk) }.frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 10)).foregroundStyle(mutedInk)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(mutedInk)
            }.padding(.horizontal, 9).padding(.vertical, 7).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!store.connected).help(detail)
    }

    private var remotePanel: some View {
        VStack(spacing: 12) {
            PanelCard {
                VStack(spacing: 16) {
                    HStack {
                        Text(store.currentApp).lineLimit(1).fontWeight(.semibold)
                        Spacer()
                        Circle().fill(store.connected ? Color.green : Color.orange).frame(width: 5, height: 5)
                        Text(store.connected ? "Remote ready" : "Not connected").font(.system(size: 9)).foregroundStyle(mutedInk)
                    }
                    HStack(spacing: 15) {
                        VStack(spacing: 12) { remoteButton("house", "Home", KeyCode.home); remoteButton("arrow.uturn.backward", "Back", KeyCode.back) }
                        ZStack {
                            Circle().fill(Color.white.opacity(0.055)).overlay(Circle().strokeBorder(Color.white.opacity(0.07)))
                            VStack { remoteDirection("chevron.up", "Up", KeyCode.up); Spacer(); remoteDirection("chevron.down", "Down", KeyCode.down) }.padding(6)
                            HStack { remoteDirection("chevron.left", "Left", KeyCode.left); Spacer(); remoteDirection("chevron.right", "Right", KeyCode.right) }.padding(6)
                            Button { store.press(KeyCode.ok) } label: { Text("OK").font(.system(size: 12, weight: .semibold)).frame(width: 46, height: 46).background(Circle().fill(accent.opacity(0.2))).foregroundStyle(accent) }.buttonStyle(.plain).help("Confirm")
                        }.frame(width: 138, height: 138)
                        VStack(spacing: 12) { remoteButton("line.3.horizontal", "Menu", KeyCode.menu); remoteButton("gearshape", "Settings", "KEYCODE_SETTINGS") }
                    }.frame(maxWidth: .infinity)
                    HStack(spacing: 7) {
                        mediaButton("backward.fill", "Rewind", KeyCode.rewind)
                        mediaButton("playpause.fill", "Play or pause", KeyCode.playPause)
                        mediaButton("forward.fill", "Fast forward", KeyCode.forward)
                    }
                }.disabled(!store.connected)
            }
            audioCard
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Keyboard", systemImage: "keyboard").fontWeight(.semibold)
                    TextField("Type into the open field on the projector", text: $text).textFieldStyle(.roundedBorder).onSubmit(sendText)
                    HStack {
                        Text("Open a text field on the projector first.").font(.system(size: 10)).foregroundStyle(mutedInk)
                        Spacer()
                        Button("Send", action: sendText).disabled(text.isEmpty)
                        Button { store.press(KeyCode.delete) } label: { Image(systemName: "delete.left") }.help("Delete one character")
                        Button { store.press(KeyCode.enter) } label: { Image(systemName: "return") }.help("Confirm text")
                    }
                }.disabled(!store.connected)
            }
            Text("Playback controls depend on the open app.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }

    private func sendText() { store.sendText(text); text = "" }

    private func remoteDirection(_ symbol: String, _ title: String, _ keycode: String) -> some View {
        Button { store.press(keycode) } label: { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 29, height: 29).contentShape(Rectangle()) }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func remoteButton(_ symbol: String, _ title: String, _ keycode: String) -> some View {
        Button { store.press(keycode) } label: { Image(systemName: symbol).font(.system(size: 15)).frame(width: 43, height: 42) }.buttonStyle(PanelButton()).help(title).accessibilityLabel(title)
    }

    private func mediaButton(_ symbol: String, _ title: String, _ keycode: String) -> some View {
        Button { store.press(keycode) } label: { Image(systemName: symbol).font(.system(size: 11)).frame(maxWidth: .infinity).frame(height: 30) }.buttonStyle(PanelButton()).help(title).accessibilityLabel(title)
    }

    private var appsPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(mutedInk)
                TextField("Search \(store.apps.count) apps", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(mutedInk) }.buttonStyle(.plain) }
            }.padding(11).background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.06)))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 6) {
                ForEach(store.shortcuts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { app in
                    AppTile(app: app, icon: store.icon(app.id), size: 46, active: store.foregroundID == app.id, favorite: store.favorites.contains(app.id), onFavorite: { store.toggleFavorite(app) }) { store.launch(app) }
                        .disabled(!store.connected)
                }
            }
            if store.apps.isEmpty { Text("Apps appear after connecting.").foregroundStyle(mutedInk).padding(.vertical, 15) }
            Text("Click an app to open it on the projector. Use the star to add favorites.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }

    private var mirrorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "airplay.video").font(.system(size: 26, weight: .light)).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) { Text("Your Mac, on the wall").font(.system(size: 14, weight: .semibold)); Text("Screen mirroring with AirPlay").font(.system(size: 10)).foregroundStyle(mutedInk) }
                    }
                    Text("The projector advertises AirPlay. On your Mac, open Control Center, choose Screen Mirroring, and pick the projector. To use the projector as a second display, open Displays settings and add it with the + menu.").font(.system(size: 11)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                    Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!) } label: { Label("Open Displays settings", systemImage: "arrow.up.right") }.buttonStyle(.plain).foregroundStyle(accent)
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If the projector does not appear in Screen Mirroring, open its cast receiver first.").font(.system(size: 11)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                    Button { store.send(PictureControls.castReceiver, title: "Cast receiver") } label: { Label("Open cast receiver on projector", systemImage: "dot.radiowaves.left.and.right") }.disabled(!store.connected)
                }
            }
            Text("The projector may show a code or ask you to accept the connection. Keep the Mac and the projector on the same network.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }

    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 9) {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 26, weight: .light)).foregroundStyle(accent)
                Text("Drop photos and videos here").font(.system(size: 13, weight: .semibold))
                Text("Folders work too. Photos go to Pictures/Remoty, videos to Movies/Remoty.").font(.system(size: 10)).foregroundStyle(mutedInk).multilineTextAlignment(.center)
                Button("Choose files...") { chooseFiles() }.disabled(!store.connected || store.transferring)
            }.frame(maxWidth: .infinity).padding(.vertical, 20).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(dropTargeted ? 0.16 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(dropTargeted ? 0.8 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .dropDestination(for: URL.self) { urls, _ in
                    guard store.connected, !store.transferring else { return false }
                    store.upload(urls)
                    return true
                } isTargeted: { dropTargeted = $0 }
            Toggle("Fit photos to the screen with black bars", isOn: $store.fitPhotos).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
            if let status = store.transferStatus {
                PanelCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(status).font(.system(size: 11)).lineLimit(2)
                        if store.transferring {
                            ProgressView(value: store.transferFraction).tint(accent)
                            HStack { Spacer(); Button("Cancel") { store.cancelTransfer() } }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button { store.send(Media.openPhotos, title: "Photos") } label: { Label("Open photos", systemImage: "photo").frame(maxWidth: .infinity).frame(height: 28) }.buttonStyle(PanelButton(accent: accent))
                Button { store.send(Media.openVideos, title: "Videos") } label: { Label("Open videos", systemImage: "film").frame(maxWidth: .infinity).frame(height: 28) }.buttonStyle(PanelButton(accent: accent))
            }.disabled(!store.connected)
            PanelCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("On the projector").fontWeight(.semibold)
                        Spacer()
                        Button { Task { await store.refreshMedia() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(mutedInk).help("Refresh the list")
                    }
                    if store.mediaFiles.isEmpty { Text("Nothing sent yet.").font(.system(size: 10)).foregroundStyle(mutedInk) }
                    ForEach(store.mediaFiles) { file in
                        HStack(spacing: 8) {
                            Image(systemName: file.video ? "film" : "photo").foregroundStyle(mutedInk).frame(width: 16)
                            Text(file.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Media.size(file.size)).font(.system(size: 10)).foregroundStyle(mutedInk).monospacedDigit()
                            Button { pendingDelete = file } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(mutedInk).help("Delete \(file.name) from the projector")
                        }.font(.system(size: 11))
                    }
                }
            }.disabled(!store.connected)
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete from projector", role: .destructive) { if let file = pendingDelete { store.deleteMedia(file) }; pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { Text("The file is removed from the projector. This cannot be undone.") }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .movie, .folder]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.begin { response in if response == .OK { store.upload(panel.urls) } }
    }

    private var usagePanel: some View {
        let _ = store.usageRevision
        let totals = store.usage(days: usageDays)
        let total = totals.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 14) {
            Picker("Period", selection: $usageDays) { Text("Today").tag(1); Text("7 days").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 7) {
                Text("SCREEN TIME").font(.system(size: 8, weight: .bold)).tracking(1.2).foregroundStyle(mutedInk)
                Text(duration(total)).font(.system(size: 38, weight: .medium, design: .rounded)).tracking(-1).foregroundStyle(accent)
                Text("Apps observed by your Mac").font(.system(size: 10)).foregroundStyle(mutedInk)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.08)))
            PanelCard {
                VStack(spacing: 17) {
                    ForEach(totals) { item in
                        let color = Brand.forApp(item.id).color
                        VStack(spacing: 8) {
                            HStack(spacing: 9) {
                                AppMark(id: item.id, title: item.title, size: 26, icon: store.icon(item.id))
                                Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer(); Text(duration(item.seconds)).font(.system(size: 10)).foregroundStyle(mutedInk).monospacedDigit()
                            }
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) { Capsule().fill(Color.white.opacity(0.04)); Capsule().fill(color).frame(width: geometry.size.width * CGFloat(item.seconds / max(total, 1))) }
                            }.frame(height: 4)
                        }
                    }
                    if totals.isEmpty { VStack(spacing: 9) { Image(systemName: "chart.bar.xaxis").font(.system(size: 26)).foregroundStyle(accent); Text("Your history starts here").fontWeight(.medium); Text("The first record appears after the next reading.").font(.system(size: 10)).foregroundStyle(mutedInk) }.frame(maxWidth: .infinity).padding(.vertical, 25) }
                }
            }
            Text("Tracks the foreground app while your Mac is awake and connected and the projector is awake. Sleep, screensaver and offline periods are excluded.").font(.system(size: 10)).foregroundStyle(mutedInk)
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes == 0 { return "\(Int(seconds)) s" }
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private var picturePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelCard {
                VStack(spacing: 9) {
                    HStack { Label("Lamp", systemImage: "sun.max").foregroundStyle(Color.white.opacity(0.8)); Spacer(); Text(store.lamp.map { "\(Int($0))" } ?? "-").monospacedDigit().foregroundStyle(accent) }
                    Slider(value: Binding(get: { store.lamp ?? 0 }, set: store.changeLamp), in: 0...100, step: 1).accessibilityLabel("Lamp")
                    Text("Light output of the lamp.").font(.system(size: 10)).foregroundStyle(mutedInk).frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(!store.connected || store.lamp == nil)
            }
            PanelCard {
                VStack(spacing: 9) {
                    ForEach(PictureControls.pqItems, id: \.0) { item, title in
                        HStack { Text(title).foregroundStyle(Color.white.opacity(0.8)); Spacer(); Text(store.picture[item].map { "\(Int($0))" } ?? "-").monospacedDigit().foregroundStyle(accent) }
                        Slider(value: Binding(get: { store.picture[item] ?? 0 }, set: { store.changePicture(item, $0) }), in: 0...100, step: 1).accessibilityLabel(title).disabled(store.picture[item] == nil)
                    }
                    Text("Picture settings of the current picture mode. The lamp does not change.").font(.system(size: 10)).foregroundStyle(mutedInk).frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(!store.connected)
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Projector settings").fontWeight(.semibold)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                        ForEach(PictureControls.vendorScreens) { screen in
                            Button { store.send(screen.command, title: screen.title) } label: {
                                Label(screen.title, systemImage: screen.symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).frame(height: 30)
                            }.buttonStyle(PanelButton(accent: accent)).help("Open \(screen.title) on the projector")
                        }
                    }
                    Text("These open the projector's own menu. Use the remote to adjust.").font(.system(size: 10)).foregroundStyle(mutedInk)
                }.disabled(!store.connected)
            }
            PanelCard {
                VStack(spacing: 9) {
                    Toggle("Auto keystone", isOn: Binding(get: { store.autoKeystone ?? false }, set: { store.apply(PictureControls.autoKeystoneWrite($0), title: "Auto keystone") }))
                        .toggleStyle(.switch).controlSize(.small).disabled(!store.connected || store.autoKeystone == nil)
                    statusRow("Zoom", store.zoom.map { "\($0) %" })
                    statusRow("Mount", store.mountMode)
                }
            }
            PanelCard {
                VStack(spacing: 9) {
                    HStack {
                        Text("Screen off after")
                        Spacer()
                        Picker("Screen off after", selection: Binding(get: { store.screenOffTimeout ?? 0 }, set: { store.apply(PictureControls.screenOffWrite($0), title: "Screen off timeout") })) {
                            ForEach(screenOffChoices, id: \.self) { Text(PictureControls.screenOffTitle($0)).tag($0) }
                        }.labelsHidden().fixedSize()
                    }.disabled(!store.connected || store.screenOffTimeout == nil)
                }
            }
            screensaverCard
        }
    }

    private var screenOffChoices: [Int] {
        let options = PictureControls.screenOffOptions
        guard let current = store.screenOffTimeout, !options.contains(current) else { return options }
        return [current] + options
    }

    private func statusRow(_ title: String, _ value: String?) -> some View {
        HStack { Text(title); Spacer(); Text(value ?? "-").monospacedDigit().foregroundStyle(mutedInk) }
    }

    private var connectionPanel: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(store.status, systemImage: "wifi").fontWeight(.semibold)
                Text(Adb.path == nil ? "Install adb with: brew install android-platform-tools" : "Turn on Network debugging on the projector. Accept the debugging prompt on the projector the first time.").font(.system(size: 11)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Button(store.connecting ? "Connecting…" : "Connect to projector") {
                    if store.host.isEmpty { showConnectionSettings() } else { store.connect() }
                }.disabled(store.connecting || Adb.path == nil)
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("CONNECTION")
            PanelCard {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Your projector").fontWeight(.semibold)
                    TextField("Name", text: $draftName).textFieldStyle(.roundedBorder)
                    TextField("IPv4 address or name.local", text: $draftHost).textFieldStyle(.roundedBorder)
                    Text("ADB uses port 5555 unless you add another port, for example :5556.").font(.system(size: 10)).foregroundStyle(mutedInk)
                    Button("Save and connect") {
                        store.disconnect()
                        let previous = store.host
                        store.host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let draftDevice, draftDevice.address == store.host || draftDevice.host == store.host { store.identity = draftDevice.identity }
                        else if store.host != previous { store.identity = "" }
                        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.name = trimmed.isEmpty ? "Projector" : trimmed
                        store.connect(); settings = false
                    }.disabled(!Adb.localHost(draftHost.trimmingCharacters(in: .whitespacesAndNewlines)) || store.connecting)
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Button(store.discovering ? "Searching..." : "Find projectors on your network") { store.discover() }.disabled(store.discovering)
                        if store.discovering { ProgressView().controlSize(.small) }
                    }
                    ForEach(store.devices) { device in
                        Button { draftHost = device.address; draftName = device.name; draftDevice = device } label: {
                            HStack {
                                Image(systemName: draftDevice == device ? "checkmark.circle.fill" : "circle").foregroundStyle(draftDevice == device ? accent : mutedInk)
                                VStack(alignment: .leading, spacing: 2) { Text(device.name).lineLimit(1); Text(device.address).font(.system(size: 10)).foregroundStyle(mutedInk).lineLimit(1) }
                                Spacer(); Text(device.host).font(.system(size: 10)).foregroundStyle(mutedInk)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if let failure = store.discoveryError { Text(failure).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                    Text("Discovery looks for Android TV Remote and AirPlay services. Choose a result, then Save and connect.").font(.system(size: 10)).foregroundStyle(mutedInk).fixedSize(horizontal: false, vertical: true)
                }
            }
            DisclosureGroup("Event history", isExpanded: $showEvents) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.events) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(event.title).fontWeight(.semibold); Spacer(); Text(event.date, style: .time).foregroundStyle(mutedInk).monospacedDigit() }
                            Text(event.detail).font(.system(size: 10)).foregroundStyle(mutedInk).lineLimit(3).textSelection(.enabled)
                        }.font(.system(size: 11))
                    }
                    if store.events.isEmpty { Text("No events yet.").foregroundStyle(mutedInk) }
                }.padding(.top, 10)
            }.font(.system(size: 11))
        }
    }

    private func showConnectionSettings() {
        draftHost = store.host; draftName = store.name
        settings = true
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(store.connected ? .green : store.connecting ? .orange : mutedInk).frame(width: 5, height: 5)
            Text(store.status).font(.system(size: 10)).foregroundStyle(mutedInk)
            Spacer()
            Text("ANDROID TV").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(Color.white.opacity(0.27))
            Button {
                if !settings { draftHost = store.host; draftName = store.name }
                settings.toggle()
            } label: { Image(systemName: settings ? "xmark" : "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(mutedInk).frame(width: 24, height: 22) }.buttonStyle(.plain).help("App settings")
        }
    }
}
