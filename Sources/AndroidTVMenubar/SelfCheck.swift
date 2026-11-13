import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum SelfCheck {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else { throw Failure(description: "\(label): got \(actual), expected \(expected)") }
    }

    static func ip(_ parts: Int...) -> String { parts.map(String.init).joined(separator: ".") }

    static func run() throws {
        let volume = AdbParse.volume("[V] will control stream=3 (STREAM_MUSIC)\n[V] will get volume\n[V] Connecting to AudioService\n[V] volume is 76 in range [0..100]\n")
        try expect(volume?.value, 76, "volume value")
        try expect(volume?.max, 100, "volume max")
        try expect(AdbParse.volume("volume is 3 in range [0..15]")?.max, 15, "volume small range")
        try expect(AdbParse.volume("Error: no stream") == nil, true, "volume garbage")

        try expect(AdbParse.wakefulness("  mWakefulness=Awake\n  mWakefulnessChanging=false\n"), "Awake", "power awake")
        try expect(AdbParse.wakefulness("  mWakefulness=Asleep\n"), "Asleep", "power asleep")
        try expect(AdbParse.wakefulness("  mWakefulness=Dreaming\n  mWakefulnessChanging=false\n"), "Dreaming", "power dreaming")
        try expect(AdbParse.wakefulness("nothing") == nil, true, "power garbage")

        let activity = "      topResumedActivity=ActivityRecord{1cb0af0 u0 com.google.android.youtube.tv/com.google.android.apps.youtube.tv.activity.ShellActivity t33}\n  ResumedActivity: ActivityRecord{1cb0af0 u0 com.google.android.youtube.tv/.Shell t33}\n"
        try expect(AdbParse.foreground(activity), "com.google.android.youtube.tv", "foreground package")
        try expect(AdbParse.foreground("") == nil, true, "foreground empty")

        let query = "3 activities found:\n  Activity #0:\n    com.android.tv.settings/.MainSettings\n  Activity #1:\n    com.mxtech.videoplayer.ad/.ActivityWelcomeMX\n  Activity #2:\n    com.android.tv.settings/.Other\n"
        try expect(AdbParse.packages(query), ["com.android.tv.settings", "com.mxtech.videoplayer.ad"], "app list")

        try expect(Adb.textCommand("hello world"), "input text 'hello%sworld'", "text spaces")
        try expect(Adb.textCommand("it's"), "input text 'it'\\''s'", "text quote")
        try expect(Adb.textCommand("50% off"), "input text '50\\%%soff'", "text percent")
        try expect(Adb.quote("; reboot"), "'; reboot'", "shell quoting")

        try expect(Adb.localHost(ip(192, 168, 1, 20)), true, "local host")
        try expect(Adb.localHost(ip(10, 0, 0, 5) + ":5556"), true, "local host with port")
        try expect(Adb.localHost("8.8.8.8"), false, "public host")
        try expect(Adb.localHost("192.168.1"), false, "short host")
        try expect(Adb.localHost("example.local"), true, "local hostname")
        try expect(Adb.localHost("Smart-Box-01.local:5555"), true, "local hostname with port")
        try expect(Adb.localHost("example.com"), false, "public hostname")
        try expect(Adb.localHost("bad_name.local"), false, "invalid hostname")
        try expect(Adb.localHost("-bad.local"), false, "hostname leading hyphen")
        try expect(Adb.serial(for: ip(10, 0, 0, 5)), ip(10, 0, 0, 5) + ":5555", "default port")

        try expect(Adb.validPackage("com.netflix.mediaclient"), true, "valid package")
        try expect(Adb.validPackage("com.x; reboot"), false, "invalid package")

        try expect(AppNames.name("com.amazon.amazonvideo.livingroom"), "Prime Video", "known name")
        try expect(AppNames.name("com.example.coolplayer"), "Coolplayer", "fallback name")

        try expect(PictureControls.lamp("255\n"), 100, "lamp full")
        try expect(PictureControls.lamp("0"), 0, "lamp off")
        try expect(PictureControls.lamp("128\n"), 50, "lamp half")
        try expect(PictureControls.lamp("300") == nil, true, "lamp out of range")
        try expect(PictureControls.lamp("cat: no such file") == nil, true, "lamp garbage")
        try expect(PictureControls.lampWrite(140), "am broadcast -a com.jm.projector.brightness --ei brightness 100", "lamp write clamp")
        try expect(PictureControls.pqValues("brightness=50\ncontrast=48\nsaturation=55\nsharpness=60 rc=0\nmode=3\n"), ["brightness": 50, "contrast": 48, "saturation": 55, "sharpness": 60], "pq values")
        try expect(PictureControls.pqValues("brightness=-1\nsharpness=140\nerror=java.lang.NullPointerException\n"), [:], "pq invalid")
        try expect(PictureControls.pqWrite("sharpness", 140), PictureControls.pqRun + " set sharpness 100", "pq write clamp")
        try expect(PictureControls.pqDex.flatMap(PictureControls.md5)?.count, 32, "pq helper bundled")
        try expect(PictureControls.zoom("\n"), 100, "zoom empty")
        try expect(PictureControls.zoom("85\n"), 85, "zoom value")
        try expect(PictureControls.mountMode(""), "Auto", "mount empty")
        try expect(PictureControls.mountMode("0"), "Auto", "mount auto")
        try expect(PictureControls.mountMode("1"), "Front desk", "mount front desk")
        try expect(PictureControls.mountMode("2"), "Rear desk", "mount rear desk")
        try expect(PictureControls.mountMode("3\n"), "Front ceiling", "mount front ceiling")
        try expect(PictureControls.mountMode("4"), "Rear ceiling", "mount rear ceiling")
        try expect(PictureControls.mountMode("7") == nil, true, "mount unknown")
        try expect(PictureControls.flag("true\n"), true, "flag true")
        try expect(PictureControls.flag("0"), false, "flag zero")
        try expect(PictureControls.flag("null") == nil, true, "flag null")
        try expect(PictureControls.screenOffTitle(2147483647), "Never", "timeout never")
        try expect(PictureControls.screenOffTitle(900000), "15 min", "timeout minutes")
        try expect(PictureControls.hdmi(2), "am start -a android.media.tv.action.SETUP_INPUTS --es android.media.tv.extra.INPUT_ID 'com.droidlogic.tvinput/.services.Hdmi2InputService/HW6' --ez from_tv_source true", "hdmi 2 intent")
        try expect(AdbParse.failure("Starting: Intent { cmp=a/.b }\n"), nil, "am start success")
        try expect(AdbParse.failure("Starting: Intent { cmp=a/.b }\nError type 3\nError: Activity class {a/.b} does not exist.\n"), "Error type 3", "am start failure")

        var record = Data()
        for entry in ["srcvers=220.68", "deviceid=02:00:00:00:00:01", "flags=0x4", "novalue"] {
            record.append(UInt8(entry.utf8.count)); record.append(contentsOf: Array(entry.utf8))
        }
        let txt = Discovery.txt(record)
        try expect(txt["deviceid"], "02:00:00:00:00:01", "txt deviceid")
        try expect(txt["novalue"], "", "txt flag key")
        try expect(Discovery.txt(Data([9, 0x61])).isEmpty, true, "txt truncated")
        try expect(Discovery.hostName("Box-01.local."), "Box-01.local", "mdns host trailing dot")
        try expect(Discovery.hostName("box.example.com."), "", "non-local host")
        var socket = sockaddr_in()
        socket.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socket.sin_family = sa_family_t(AF_INET)
        socket.sin_addr.s_addr = inet_addr(ip(192, 168, 7, 9))
        try expect(Discovery.ipv4([withUnsafeBytes(of: socket) { Data($0) }]), ip(192, 168, 7, 9), "resolved ipv4")
        let device = FoundDevice(host: ip(192, 168, 7, 9), name: "P", hostName: "Box-01.local", deviceID: "")
        try expect(device.identity, "Box-01.local", "identity falls back to host name")
        try expect(device.address, "Box-01.local", "address prefers host name")

        try expect(Media.folder(for: URL(fileURLWithPath: "/x/a.JPG")), Media.pictures, "route jpeg")
        try expect(Media.folder(for: URL(fileURLWithPath: "/x/a.heic")), Media.pictures, "route heic")
        try expect(Media.folder(for: URL(fileURLWithPath: "/x/a.mp4")), Media.movies, "route mp4")
        try expect(Media.folder(for: URL(fileURLWithPath: "/x/a.mkv")), Media.movies, "route mkv")
        try expect(Media.folder(for: URL(fileURLWithPath: "/x/a.pdf")) == nil, true, "reject pdf")
        try expect(Media.folder(for: URL(fileURLWithPath: "/x/noextension")) == nil, true, "reject no extension")
        try expect(Media.scanCommand(Media.pictures + "/Çay bahçesi's.png"), "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d 'file:///sdcard/Pictures/Remoty/Çay bahçesi'\\''s.png'", "scan quoting")
        try expect(Media.deleteCommand(Media.movies + "/a b.mp4").hasPrefix("rm -f '/sdcard/Movies/Remoty/a b.mp4' && am broadcast"), true, "delete quoting")
        try expect(Media.percent("[  7%] /sdcard/a\r[ 45%] /sdcard/a"), 45, "push percent")
        try expect(Media.percent("[100%] /sdcard/a"), 100, "push complete")
        try expect(Media.percent("x: 1 file pushed, 0 skipped. 0.9 MB/s (75 bytes in 0.000s)") == nil, true, "push summary")
        try expect(Media.freeBytes("Filesystem     1K-blocks    Used Available Use% Mounted on\n/dev/fuse       12262400 1943552  10318848  16% /storage/emulated\n"), 10318848 * 1024, "free space")
        try expect(Media.freeBytes("df: /sdcard: No such file") == nil, true, "free space garbage")
        let listing = "/sdcard/Pictures/Remoty:\ntotal 8\n-rw-rw---- 1 root everybody 75 2026-10-26 19:01 Gün batımı 1.png\n\n/sdcard/Movies/Remoty:\ntotal 0\n-rw-rw---- 1 root everybody 1048576 2026-10-26 19:02 clip.mp4\n"
        try expect(Media.list(listing), [MediaFile(path: Media.pictures + "/Gün batımı 1.png", name: "Gün batımı 1.png", size: 75), MediaFile(path: Media.movies + "/clip.mp4", name: "clip.mp4", size: 1048576)], "media list")
        try expect(Media.list(listing).last?.video, true, "media list video")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("remoty-media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        for name in ["a.png", "sub/b.mov", "notes.txt"] { try Data([0]).write(to: folder.appendingPathComponent(name)) }
        let collected = Media.collect([folder, folder.appendingPathComponent("notes.txt")])
        try expect(collected.uploads.map(\.remote).sorted(), [Media.movies + "/b.mov", Media.pictures + "/a.png"], "folder walk")
        try expect(collected.rejected, ["notes.txt"], "reject dropped text file")

        func testImage(width: Int, height: Int, orientation: Int, to url: URL) throws {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(output, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            guard CGImageDestinationFinalize(output) else { throw Failure(description: "test image not written") }
        }
        func pixels(_ url: URL) throws -> (width: Int, height: Int, value: (Int, Int) -> Int) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure(description: "letterbox output unreadable") }
            let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return (image.width, image.height, { x, y in
                let buffer = context.data!.assumingMemoryBound(to: UInt8.self), i = ((image.height - 1 - y) * image.width + x) * 4
                return Int(buffer[i]) + Int(buffer[i + 1]) + Int(buffer[i + 2])
            })
        }
        let portrait = folder.appendingPathComponent("portrait.jpg"), padded = folder.appendingPathComponent("padded.jpg")
        try testImage(width: 300, height: 400, orientation: 1, to: portrait)
        try Media.letterbox(portrait, to: padded)
        var result = try pixels(padded)
        try expect("\(result.width)x\(result.height)", "1920x1080", "letterbox size")
        try expect(result.value(0, 0) < 30 && result.value(1919, 1079) < 30, true, "letterbox black corners")
        try expect(result.value(960, 540) > 200, true, "letterbox photo centre")
        try expect(result.value(400, 540) < 30, true, "letterbox black side bar")
        try expect(result.value(570, 540) > 200 && result.value(960, 5) > 200, true, "letterbox scales small photo to full height")
        let rotated = folder.appendingPathComponent("rotated.jpg")
        try testImage(width: 400, height: 300, orientation: 6, to: rotated)
        try Media.letterbox(rotated, to: padded)
        result = try pixels(padded)
        try expect(result.value(400, 540) < 30 && result.value(960, 540) > 200, true, "letterbox exif orientation 6")

        for (package, file) in AppNames.icons { try expect(AppResources.icons[package] != nil, true, "icon \(file).svg loads") }
        for file in Set(AppNames.icons.values) {
            let url = AppResources.bundle.url(forResource: file, withExtension: "svg", subdirectory: "AppIcons")
            let head = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(5) ?? ""
            try expect(head == "<svg " || head == "<?xml" || head.hasPrefix("<svg"), true, "icon \(file).svg is SVG")
        }
        try expect(AppResources.asset("tv-hero") != nil, true, "tv hero loads")
        let apk = "AndroidManifest.xml\nres/drawable-mdpi-v4/icon.png\nres/mipmap-xhdpi-v4/ic_launcher.png\nres/mipmap-xxxhdpi-v4/ic_launcher.webp\nres/mipmap-xxxhdpi-v4/ic_launcher_foreground.png\nres/drawable-xhdpi-v4/banner.png\n"
        try expect(LauncherIcons.bestIcon(apk), "res/mipmap-xxxhdpi-v4/ic_launcher.webp", "apk icon density")
        try expect(LauncherIcons.bestIcon("res/drawable-mdpi-v4/ic_settings_launcher_icon.png\nres/drawable-xhdpi-v4/ic_launcher_banner_settings.png"), "res/drawable-mdpi-v4/ic_settings_launcher_icon.png", "apk icon suffix")
        try expect(LauncherIcons.bestIcon("res/a1.png\nres/drawable-xhdpi-v4/banner.png") == nil, true, "apk icon none")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("androidtv-selfcheck-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let journal = UsageJournal(url: url)
        let start = Date()
        journal.observe(host: "p", appID: "a", title: "A", at: start)
        journal.observe(host: "p", appID: "a", title: "A", at: start.addingTimeInterval(10))
        journal.pause(at: start.addingTimeInterval(20))
        journal.observe(host: "p", appID: "a", title: "A", at: start.addingTimeInterval(200))
        journal.pause(at: start.addingTimeInterval(300))
        try journal.save()
        try expect(UsageJournal(url: url).totals(host: "p", since: start.addingTimeInterval(-1), until: start.addingTimeInterval(400)).first?.seconds, 20, "usage excludes gaps")

        print("PASS: volume, power, foreground and app list parsers; text escaping and shell quoting; local host checks; package checks; app names; lamp, picture helper, zoom, mount and timer parsers; HDMI intent; command failures; Bonjour TXT, host and address parsing; media routing, photo letterbox and EXIF orientation, quoting, push progress, free space and listing; bundled icons and TV image; APK icon choice; usage journal.")
    }

    static func probe(host: String) async {
        guard Adb.localHost(host) else { print("ERROR: use --probe <local IPv4 address or name.local>"); exit(2) }
        let serial = Adb.serial(for: host)
        do {
            try await Adb.connect(serial)
            let power = try await Adb.shell(serial, "dumpsys power | grep mWakefulness=")
            let volume = try await Adb.shell(serial, "cmd media_session volume --stream 3 --get")
            let activity = (try? await Adb.shell(serial, "dumpsys activity activities | grep -E 'topResumedActivity|ResumedActivity'")) ?? ""
            let apps = try await Adb.shell(serial, "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER")
            func read(_ command: String) async -> String { (try? await Adb.shell(serial, command)) ?? "" }
            print("power: \(AdbParse.wakefulness(power) ?? "unparsed")")
            print("volume: \(AdbParse.volume(volume).map { "\($0.value)/\($0.max)" } ?? "unparsed")")
            print("foreground: \(AdbParse.foreground(activity).map { "\($0) (\(AppNames.name($0)))" } ?? "unparsed")")
            print("apps: \(AdbParse.packages(apps).map(AppNames.name).joined(separator: ", "))")
            print("lamp: \(PictureControls.lamp(await read(PictureControls.lampRead)).map { "\($0)/100" } ?? "unparsed")")
            print("auto keystone: \(PictureControls.flag(await read(PictureControls.autoKeystoneRead)).map(String.init) ?? "unparsed")")
            print("zoom: \(PictureControls.zoom(await read(PictureControls.zoomRead)).map { "\($0) %" } ?? "unparsed")")
            print("mount: \(PictureControls.mountMode(await read(PictureControls.mountRead)) ?? "unparsed")")
            print("screen off: \(AdbParse.integer(await read(PictureControls.screenOffRead)).map(PictureControls.screenOffTitle) ?? "unparsed")")
            print("screensaver: \(PictureControls.flag(await read(PictureControls.screensaverRead)).map(String.init) ?? "unparsed")")
            exit(0)
        } catch {
            print("ERROR: \(error.localizedDescription)"); exit(1)
        }
    }
}
