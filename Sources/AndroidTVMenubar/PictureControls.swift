import Foundation
import CryptoKit

struct VendorScreen: Identifiable {
    var id: String { title }
    let title: String
    let symbol: String
    let command: String
}

enum PictureControls {
    static let lampRead = "cat /sys/class/backlight/aml-bl/brightness"
    static func lampWrite(_ value: Int) -> String { "am broadcast -a com.jm.projector.brightness --ei brightness \(max(0, min(100, value)))" }
    static let pqItems = [("brightness", "Picture brightness"), ("contrast", "Contrast"), ("saturation", "Saturation"), ("sharpness", "Sharpness")]
    static let pqRemote = "/data/local/tmp/remoty-pq.dex"
    static let pqRun = "CLASSPATH=\(pqRemote):/vendor/framework/droidlogic.software.core.jar app_process /system/bin PQ"
    static let pqRead = pqRun + " get"
    static let pqHash = "md5sum \(pqRemote)"
    static func pqWrite(_ item: String, _ value: Int) -> String { pqRun + " set \(item) \(max(0, min(100, value)))" }
    static var pqDex: URL? { AppResources.bundle.url(forResource: "pq", withExtension: "dex", subdirectory: "Helpers") }
    static func md5(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { Insecure.MD5.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }
    static func pqValues(_ output: String) -> [String: Int] {
        var values: [String: Int] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let number = Int(parts[1].split(separator: " ").first ?? ""), pqItems.contains(where: { $0.0 == parts[0] }), (0...100).contains(number) else { continue }
            values[String(parts[0])] = number
        }
        return values
    }
    static let autoKeystoneRead = "getprop persist.sys.auto.trapezoid"
    static func autoKeystoneWrite(_ on: Bool) -> String { "setprop persist.sys.auto.trapezoid \(on)" }
    static let zoomRead = "getprop persist.keystone.zoom.percent"
    static let mountRead = "getprop persist.sys.filp.mode"
    static let mountModes = ["Auto", "Front desk", "Rear desk", "Front ceiling", "Rear ceiling"]
    static let screenOffRead = "settings get system screen_off_timeout"
    static func screenOffWrite(_ milliseconds: Int) -> String { "settings put system screen_off_timeout \(milliseconds)" }
    static let screenOffNever = 2147483647
    static let screenOffOptions = [300_000, 900_000, 1_800_000, screenOffNever]
    static let screensaverRead = "settings get secure screensaver_enabled"
    static func screensaverWrite(_ on: Bool) -> String { "settings put secure screensaver_enabled \(on ? 1 : 0)" }
    static let castReceiver = "am start -n com.bozee.usbdisplay/.StartupActivity"

    static func hdmi(_ number: Int) -> String {
        "am start -a android.media.tv.action.SETUP_INPUTS --es android.media.tv.extra.INPUT_ID " + Adb.quote("com.droidlogic.tvinput/.services.Hdmi\(number)InputService/HW\(number + 4)") + " --ez from_tv_source true"
    }

    static let vendorScreens = [
        VendorScreen(title: "Picture mode", symbol: "photo", command: "am start -n com.droidlogic.tv.settings/.pqsettings.PictureModeActivity"),
        VendorScreen(title: "Keystone", symbol: "skew", command: "am start -n com.softwinner.tcorrection/.projection.ProjectionSettingActivity"),
        VendorScreen(title: "Manual keystone", symbol: "crop", command: "am start -n com.softwinner.tcorrection/.projection.ManuelCorrectionActivity"),
        VendorScreen(title: "Zoom", symbol: "arrow.up.left.and.arrow.down.right", command: "am start -n com.softwinner.tcorrection/.projection.ZoomActivity"),
    ]

    static func lamp(_ output: String) -> Int? {
        guard let raw = AdbParse.integer(output), (0...255).contains(raw) else { return nil }
        return Int((Double(raw) * 100 / 255).rounded())
    }

    static func zoom(_ output: String) -> Int? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? 100 : Int(value)
    }

    static func mountMode(_ output: String) -> String? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = value.isEmpty ? 0 : Int(value), mountModes.indices.contains(index) else { return nil }
        return mountModes[index]
    }

    static func flag(_ output: String) -> Bool? {
        switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    static func screenOffTitle(_ milliseconds: Int) -> String {
        milliseconds == screenOffNever ? "Never" : milliseconds % 60_000 == 0 ? "\(milliseconds / 60_000) min" : "\(milliseconds / 1000) s"
    }
}
