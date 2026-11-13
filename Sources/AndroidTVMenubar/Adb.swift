import Foundation
import Darwin

enum AdbError: LocalizedError {
    case missing
    case unauthorized
    case offline(String)
    case timeout
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .missing: return "adb is not installed. Run: brew install android-platform-tools"
        case .unauthorized: return "The projector asks for USB debugging authorization. Accept the prompt on the projector screen and choose Always allow, then connect again."
        case .offline(let detail): return "The projector does not answer over ADB. Turn on Network debugging in Developer options. \(detail)"
        case .timeout: return "The adb command timed out."
        case .failed(let detail): return detail.isEmpty ? "The adb command failed." : detail
        }
    }
}

enum Adb {
    static let path: String? = {
        var candidates = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"]
        let pathVariable = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates += pathVariable.split(separator: ":").map { "\($0)/adb" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static func run(_ arguments: [String], timeout: TimeInterval = 15, executable: String? = nil, started: (@Sendable (Process) -> Void)? = nil, progress: (@Sendable (String) -> Void)? = nil) async throws -> String {
        guard let path = executable ?? path else { throw AdbError.missing }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                do { try process.run() } catch { continuation.resume(throwing: AdbError.failed(error.localizedDescription)); return }
                started?(process)
                let fd = pipe.fileHandleForReading.fileDescriptor
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 65536)
                func drain() {
                    while true {
                        let count = read(fd, &buffer, buffer.count)
                        if count > 0 {
                            data.append(buffer, count: count)
                            progress?(String(decoding: buffer[0..<count], as: UTF8.self))
                        } else { break }
                    }
                }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning {
                    drain()
                    if Date() > deadline { process.terminate(); continuation.resume(throwing: AdbError.timeout); return }
                    usleep(15_000)
                }
                drain()
                let output = String(decoding: data, as: UTF8.self)
                if output.contains("unauthorized") || output.contains("failed to authenticate") { continuation.resume(throwing: AdbError.unauthorized); return }
                if output.contains("device offline") || (output.contains("device '") && output.contains("not found")) {
                    continuation.resume(throwing: AdbError.offline(output.trimmingCharacters(in: .whitespacesAndNewlines))); return
                }
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: AdbError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))); return
                }
                continuation.resume(returning: output)
            }
        }
    }

    static func connect(_ serial: String) async throws {
        _ = try? await run(["start-server"], timeout: 20)
        let output = try await run(["connect", serial], timeout: 20)
        if output.contains("unauthorized") || output.contains("authenticate") { throw AdbError.unauthorized }
        guard output.contains("connected to") else { throw AdbError.offline(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let state = try await run(["-s", serial, "get-state"], timeout: 10)
        if state.contains("unauthorized") { throw AdbError.unauthorized }
    }

    static func disconnect(_ serial: String) async { _ = try? await run(["disconnect", serial], timeout: 5) }

    static func shell(_ serial: String, _ command: String, timeout: TimeInterval = 15) async throws -> String {
        try await run(["-s", serial, "shell", command], timeout: timeout)
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func textCommand(_ text: String) -> String {
        "input text " + quote(text.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: " ", with: "%s"))
    }

    static func validPackage(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" } && value.first?.isLetter == true
    }

    static func serial(for host: String) -> String { host.contains(":") ? host : host + ":5555" }

    static func mdnsName(_ value: String) -> Bool {
        let lower = value.lowercased()
        guard lower.hasSuffix(".local"), lower.count <= 253 else { return false }
        let labels = lower.dropLast(".local".count).split(separator: ".", omittingEmptySubsequences: false)
        return !labels.isEmpty && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    static func localHost(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        if parts.count == 2 { guard let port = Int(parts[1]), (1...65535).contains(port) else { return false } }
        if mdnsName(String(parts[0])) { return true }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        let numbers = octets.compactMap { $0.count <= 3 && $0.allSatisfy(\.isNumber) ? Int($0) : nil }
        guard numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }) else { return false }
        let (a, b) = (numbers[0], numbers[1])
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
    }
}

enum AdbParse {
    static func volume(_ output: String) -> (value: Int, max: Int)? {
        guard let range = output.range(of: #"volume is (\d+) in range \[(\d+)\.\.(\d+)\]"#, options: .regularExpression) else { return nil }
        let numbers = output[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        return (numbers[0], numbers[2])
    }

    static func wakefulness(_ output: String) -> String? {
        guard let range = output.range(of: #"mWakefulness=(\w+)"#, options: .regularExpression) else { return nil }
        return String(output[range].dropFirst("mWakefulness=".count))
    }

    static func foreground(_ output: String) -> String? {
        for line in output.split(separator: "\n") where line.contains("topResumedActivity") || line.contains("ResumedActivity") {
            for token in line.split(separator: " ") where token.contains("/") {
                let package = String(token.split(separator: "/")[0])
                if Adb.validPackage(package) { return package }
            }
        }
        return nil
    }

    static func packages(_ output: String) -> [String] {
        var result: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.contains(" "), let slash = trimmed.firstIndex(of: "/") else { continue }
            let package = String(trimmed[..<slash])
            if Adb.validPackage(package) && !result.contains(package) { result.append(package) }
        }
        return result
    }

    static func failure(_ output: String) -> String? {
        let markers = ["Error", "Exception", "Permission denied", "not found", "No activities found", "Unknown option", "inaccessible", "Failed"]
        return output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { line in markers.contains { line.contains($0) } }
    }

    static func integer(_ output: String) -> Int? { Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

enum AppNames {
    static let known: [String: String] = [
        "com.google.android.youtube.tv": "YouTube",
        "com.netflix.mediaclient": "Netflix",
        "com.netflix.ninja": "Netflix",
        "com.amazon.amazonvideo.livingroom": "Prime Video",
        "com.mxtech.videoplayer.ad": "MX Player",
        "com.mxtech.videoplayer.pro": "MX Player Pro",
        "com.android.tv.settings": "Settings",
        "com.android.vending": "Google Play",
        "com.disney.disneyplus": "Disney+",
        "com.spotify.tv.android": "Spotify",
        "com.google.android.tvlauncher": "Home",
        "com.google.android.apps.tv.launcherx": "Home",
        "com.android.dreams.basic": "Screensaver",
        "com.droidlogic.FileBrower": "File Browser",
        "com.droidlogic.mediacenter": "Media Center",
        "com.droidlogic.musicplayer": "Music Player",
        "com.droidlogic.videoplayer": "Video Player",
        "com.droidlogic.updater": "System Update",
        "ru.vk.store.tv": "RuStore",
    ]
    static let icons: [String: String] = [
        "com.netflix.mediaclient": "com.netflix.mediaclient",
        "com.netflix.ninja": "com.netflix.mediaclient",
        "com.google.android.youtube.tv": "com.google.android.youtube.tv",
        "com.amazon.amazonvideo.livingroom": "com.amazon.amazonvideo.livingroom",
        "com.android.vending": "com.android.vending",
        "ru.vk.store.tv": "ru.vk.store.tv",
    ]
    static let generic: Set<String> = ["com", "org", "net", "android", "google", "tv", "app", "apps", "activity", "mobile", "leanback", "ad", "ru", "livingroom"]

    static func name(_ package: String) -> String {
        if let name = known[package] { return name }
        let parts = package.split(separator: ".").map(String.init)
        let useful = parts.dropFirst(2).filter { !generic.contains($0.lowercased()) }
        let chosen = useful.last ?? parts.last ?? package
        return chosen.prefix(1).uppercased() + chosen.dropFirst()
    }

    static func isHome(_ package: String) -> Bool {
        package.contains("launcher") || package == "com.android.dreams.basic" || package == "com.master.t972"
    }
}

enum KeyCode {
    static let up = "KEYCODE_DPAD_UP", down = "KEYCODE_DPAD_DOWN", left = "KEYCODE_DPAD_LEFT", right = "KEYCODE_DPAD_RIGHT"
    static let ok = "KEYCODE_DPAD_CENTER", back = "KEYCODE_BACK", home = "KEYCODE_HOME", menu = "KEYCODE_MENU"
    static let playPause = "KEYCODE_MEDIA_PLAY_PAUSE", rewind = "KEYCODE_MEDIA_REWIND", forward = "KEYCODE_MEDIA_FAST_FORWARD"
    static let volumeUp = "KEYCODE_VOLUME_UP", volumeDown = "KEYCODE_VOLUME_DOWN", mute = "KEYCODE_VOLUME_MUTE"
    static let sleep = "KEYCODE_SLEEP", wake = "KEYCODE_WAKEUP", enter = "KEYCODE_ENTER", delete = "KEYCODE_DEL"
    static let inputMenu = "KEYCODE_TV_INPUT"
}
