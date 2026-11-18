import Foundation

/// 把数据文件镜像到任意本地目录：iCloud Drive、Dropbox、OneDrive、挂载的 NAS 均可。
/// 原生文件读写，没有浏览器 CORS 限制。
enum SyncFolder {
    static let fileName = "promptbox.json"

    static func fileURL(_ folderPath: String) -> URL {
        URL(fileURLWithPath: folderPath).appendingPathComponent(fileName)
    }

    static func write(data: Data, to folderPath: String) throws {
        let fm = FileManager.default
        let folder = URL(fileURLWithPath: folderPath)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        let target = folder.appendingPathComponent(fileName)
        try data.write(to: target, options: .atomic)

        // 同步文件夹内也保留轻量版本历史
        let versions = folder.appendingPathComponent("versions", isDirectory: true)
        try? fm.createDirectory(at: versions, withIntermediateDirectories: true, attributes: nil)
        let stamp = msNow()
        try? data.write(to: versions.appendingPathComponent("promptbox-\(stamp).json"), options: .atomic)
        prune(versions, keep: 20)
    }

    static func read(from folderPath: String) -> Data? {
        try? Data(contentsOf: fileURL(folderPath))
    }

    static func modifiedDate(_ folderPath: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL(folderPath).path)
        return attrs?[.modificationDate] as? Date
    }

    private static func prune(_ dir: URL, keep: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let files = names.filter { $0.hasPrefix("promptbox-") && $0.hasSuffix(".json") }.sorted()
        if files.count > keep {
            for name in files.prefix(files.count - keep) {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }
}
