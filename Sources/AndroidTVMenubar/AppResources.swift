import AppKit

enum AppResources {
    static let bundle: Bundle = {
        if let resources = Bundle.main.resourceURL, let packaged = Bundle(url: resources.appendingPathComponent("AndroidTVMenubar_AndroidTVMenubar.bundle")) {
            return packaged
        }
        return Bundle.module
    }()

    static let icons: [String: NSImage] = AppNames.icons.compactMapValues { file in
        bundle.url(forResource: file, withExtension: "svg", subdirectory: "AppIcons").flatMap(NSImage.init(contentsOf:))
    }

    static func asset(_ name: String) -> NSImage? {
        bundle.url(forResource: name, withExtension: "png", subdirectory: "AppAssets").flatMap(NSImage.init(contentsOf:))
    }
}

enum LauncherIcons {
    static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Remoty/icons")

    static func cached(_ package: String) -> URL? {
        ["png", "webp"].map { directory.appendingPathComponent("\(package).\($0)") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func load(serial: String, package: String) async -> NSImage? {
        guard Adb.validPackage(package) else { return nil }
        if let url = cached(package) { return NSImage(contentsOf: url) }
        let missing = directory.appendingPathComponent("\(package).none")
        if FileManager.default.fileExists(atPath: missing.path) { return nil }
        let output = (try? await Adb.shell(serial, "pm path \(package)")) ?? ""
        guard let apk = output.split(whereSeparator: \.isNewline).first.map({ $0.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces) }), apk.hasPrefix("/") else { return nil }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("remoty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let local = work.appendingPathComponent("app.apk")
            _ = try await Adb.run(["-s", serial, "pull", apk, local.path], timeout: 300)
            let listing = try await Adb.run(["-Z1", local.path], executable: "/usr/bin/unzip")
            guard let entry = bestIcon(listing) else {
                FileManager.default.createFile(atPath: missing.path, contents: nil)
                return nil
            }
            _ = try await Adb.run(["-o", "-j", local.path, entry, "-d", work.path], executable: "/usr/bin/unzip")
            let target = directory.appendingPathComponent("\(package).\((entry as NSString).pathExtension)")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: work.appendingPathComponent((entry as NSString).lastPathComponent), to: target)
            return NSImage(contentsOf: target)
        } catch {
            return nil
        }
    }

    static func bestIcon(_ listing: String) -> String? {
        let densities = ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]
        let names: Set<String> = ["ic_launcher", "icon", "app_icon", "ic_launcher_round"]
        let candidates = listing.split(whereSeparator: \.isNewline).map(String.init).filter { entry in
            guard entry.hasPrefix("res/mipmap") || entry.hasPrefix("res/drawable"), entry.hasSuffix(".png") || entry.hasSuffix(".webp") else { return false }
            let name = ((entry as NSString).lastPathComponent as NSString).deletingPathExtension
            return names.contains(name) || name.hasSuffix("launcher_icon")
        }
        func rank(_ entry: String) -> Int {
            let folder = entry.split(separator: "/").dropFirst().first.map(String.init) ?? ""
            let density = densities.lastIndex { folder.split(separator: "-").contains(Substring($0)) } ?? -1
            return (density + 1) * 2 + (entry.hasPrefix("res/mipmap") ? 1 : 0)
        }
        return candidates.max { rank($0) < rank($1) }
    }
}
