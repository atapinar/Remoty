import Foundation
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics

struct MediaFile: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int64
    var video: Bool { path.hasPrefix(Media.movies) }
}

struct MediaUpload: Equatable {
    let local: URL
    let remote: String
    let size: Int64
}

enum Media {
    static let pictures = "/sdcard/Pictures/Remoty"
    static let movies = "/sdcard/Movies/Remoty"
    static let listCommand = "ls -l \(pictures) \(movies) 2>/dev/null; true"
    static let freeCommand = "df /sdcard"
    static let openPhotos = "am start -n com.android.gallery3d/.app.GalleryActivity"
    static let openVideos = "am start -n com.droidlogic.videoplayer/.FileList"

    static let extraVideoExtensions: Set<String> = ["mkv", "webm", "avi", "ts", "m2ts", "flv", "wmv"]

    static func folder(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if extraVideoExtensions.contains(ext) { return movies }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .image) { return pictures }
        if type.conforms(to: .movie) { return movies }
        return nil
    }

    static func collect(_ urls: [URL]) -> (uploads: [MediaUpload], rejected: [String]) {
        var uploads: [MediaUpload] = []
        var rejected: [String] = []
        func add(_ url: URL, strict: Bool) {
            guard let folder = folder(for: url) else { if strict { rejected.append(url.lastPathComponent) }; return }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init) ?? 0
            uploads.append(MediaUpload(local: url, remote: folder + "/" + url.lastPathComponent, size: size))
        }
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let item = walker?.nextObject() as? URL {
                    if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { add(item, strict: false) }
                }
            } else {
                add(url, strict: true)
            }
        }
        return (uploads, rejected)
    }

    static func scanCommand(_ path: String) -> String {
        "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d " + Adb.quote("file://" + path)
    }

    static func deleteCommand(_ path: String) -> String { "rm -f " + Adb.quote(path) + " && " + scanCommand(path) }

    static func list(_ output: String) -> [MediaFile] {
        var folder = ""
        var files: [MediaFile] = []
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasSuffix(":") && line.hasPrefix("/") { folder = String(line.dropLast()); continue }
            guard !folder.isEmpty, let match = line.firstMatch(of: #/^-\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\d{4}-\d\d-\d\d\s+\d\d:\d\d\s+(.+)$/#) else { continue }
            let name = String(match.2)
            files.append(MediaFile(path: folder + "/" + name, name: name, size: Int64(match.1) ?? 0))
        }
        return files
    }

    static func freeBytes(_ output: String) -> Int64? {
        guard let line = output.split(whereSeparator: \.isNewline).last(where: { !$0.hasPrefix("Filesystem") }) else { return nil }
        let columns = line.split(whereSeparator: \.isWhitespace)
        guard columns.count >= 4, let kilobytes = Int64(columns[3]) else { return nil }
        return kilobytes * 1024
    }

    static func percent(_ output: String) -> Int? {
        output.matches(of: #/\[\s*(\d{1,3})%\]/#).last.flatMap { Int($0.1) }.map { min(100, $0) }
    }

    static let canvas = CGSize(width: 1920, height: 1080)

    static func letterbox(_ source: URL, to destination: URL) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw AdbError.failed("Could not read the photo \(source.lastPathComponent).")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let upright = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let scale = min(canvas.width / upright.width, canvas.height / upright.height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int((max(upright.width, upright.height) * min(1, scale)).rounded()),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(input, 0, options as CFDictionary),
              let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw AdbError.failed("Could not convert the photo \(source.lastPathComponent).")
        }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))
        context.interpolationQuality = .high
        let size = CGSize(width: (upright.width * scale).rounded(), height: (upright.height * scale).rounded())
        let drawn = CGRect(x: ((canvas.width - size.width) / 2).rounded(), y: ((canvas.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        context.draw(image, in: drawn)
        guard let padded = context.makeImage(),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AdbError.failed("Could not write the photo \(source.lastPathComponent).")
        }
        CGImageDestinationAddImage(output, padded, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw AdbError.failed("Could not write the photo \(source.lastPathComponent).") }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
