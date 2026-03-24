import Foundation

enum Logger {
    private static let maxLogSize: UInt64 = 5 * 1024 * 1024  // 5 MB
    private static let logDir: String = {
        let dir = NSHomeDirectory() + "/Library/Logs/SidecarMenu"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var logFilePath: String { logDir + "/sidecar-menu.log" }

    static func log(_ msg: String, source: String = "App") {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(source)] \(msg)\n"
        NSLog("[SidecarMenu] [\(source)] %@", msg)

        guard let data = line.data(using: .utf8) else { return }

        let fm = FileManager.default
        if fm.fileExists(atPath: logFilePath) {
            // Rotate if too large
            if let attrs = try? fm.attributesOfItem(atPath: logFilePath),
               let size = attrs[.size] as? UInt64,
               size > maxLogSize {
                let rotated = logDir + "/sidecar-menu.1.log"
                try? fm.removeItem(atPath: rotated)
                try? fm.moveItem(atPath: logFilePath, toPath: rotated)
            }
        }

        if let fh = FileHandle(forWritingAtPath: logFilePath) {
            defer { fh.closeFile() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            fm.createFile(atPath: logFilePath, contents: data)
        }
    }
}
