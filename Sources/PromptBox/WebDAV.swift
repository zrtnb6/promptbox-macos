import Foundation

struct WebDAVPushResult {
    let ok: Bool
    let conflict: Bool
    let status: Int
    let etag: String?
    let message: String
}

struct WebDAVRemoteFile {
    let data: RemoteData?
    let etag: String?
}

/// WebDAV 协议层：PROPFIND / GET / PUT(If-Match) / MKCOL / OPTIONS / DELETE。
/// 与 web 版 lib/webdav.ts 行为一致，但原生请求不受 CORS 限制。
struct WebDAVClient {
    let config: SyncConfig

    private var baseURL: URL? {
        let base = config.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/")
    }

    var fileURL: URL? {
        guard let base = baseURL else { return nil }
        var path = config.remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.hasPrefix("/") { path = "/" + path }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    private var versionsDir: URL? {
        fileURL?.deletingLastPathComponent().appendingPathComponent("versions", isDirectory: true)
    }

    private var authHeader: String {
        let raw = "\(config.username):\(config.password)"
        return "Basic " + (raw.data(using: .utf8)?.base64EncodedString() ?? "")
    }

    private func request(_ url: URL, method: String, headers: [String: String] = [:], body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 25
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        return req
    }

    private func send(_ req: URLRequest) async throws -> (Data, Int, [String: String]) {
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        if let fields = http?.allHeaderFields {
            for (key, value) in fields { headers["\(key)"] = "\(value)" }
        }
        return (data, http?.statusCode ?? 0, headers)
    }

    private func etag(from headers: [String: String]) -> String? {
        for (key, value) in headers where key.lowercased() == "etag" {
            let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func ensureParentDirs() async {
        guard let base = baseURL else { return }
        let cleaned = config.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = cleaned.split(separator: "/").dropLast().map(String.init)
        var acc = base
        for part in parts {
            acc = acc.appendingPathComponent(part, isDirectory: true)
            _ = try? await send(request(acc, method: "MKCOL"))
        }
    }

    private func ensureVersionsDir() async {
        guard let dir = versionsDir else { return }
        _ = try? await send(request(dir, method: "MKCOL"))
    }

    // MARK: - 连接测试

    func testConnection() async -> (ok: Bool, message: String) {
        let url = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return (false, "请先填写 WebDAV 地址") }
        guard url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") else {
            return (false, "地址需以 http:// 或 https:// 开头")
        }
        guard let target = fileURL else { return (false, "地址或路径格式不正确") }
        do {
            let (_, status, _) = try await send(request(target, method: "OPTIONS"))
            if status == 401 || status == 403 { return (false, "鉴权失败（\(status)），请检查账号或密码") }
            if [200, 204, 404, 405].contains(status) { return (true, "连接成功，已可访问该地址") }
            return (true, "连接可达（HTTP \(status)）")
        } catch {
            return (false, "连接失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 读写主文件

    func fetchRemote() async throws -> WebDAVRemoteFile {
        guard let url = fileURL else { throw NSError(domain: "PromptBox", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebDAV 地址无效"]) }
        let (data, status, headers) = try await send(request(url, method: "GET"))
        if status == 404 { return WebDAVRemoteFile(data: nil, etag: nil) }
        guard (200..<300).contains(status) else {
            throw NSError(domain: "PromptBox", code: status, userInfo: [NSLocalizedDescriptionKey: "读取远端失败（HTTP \(status)）"])
        }
        do {
            let remote = try JSONDecoder().decode(RemoteData.self, from: data)
            return WebDAVRemoteFile(data: remote, etag: etag(from: headers))
        } catch {
            throw NSError(domain: "PromptBox", code: 2, userInfo: [NSLocalizedDescriptionKey: "远端文件不是合法的 JSON"])
        }
    }

    func fetchVersion(_ urlString: String) async throws -> WebDAVRemoteFile {
        guard let url = URL(string: urlString) else { throw NSError(domain: "PromptBox", code: 3, userInfo: [NSLocalizedDescriptionKey: "版本地址无效"]) }
        let (data, status, headers) = try await send(request(url, method: "GET"))
        guard (200..<300).contains(status) else {
            throw NSError(domain: "PromptBox", code: status, userInfo: [NSLocalizedDescriptionKey: "读取版本失败（HTTP \(status)）"])
        }
        let remote = try JSONDecoder().decode(RemoteData.self, from: data)
        return WebDAVRemoteFile(data: remote, etag: etag(from: headers))
    }

    func pushRemote(_ value: RemoteData, ifMatch: String?) async -> WebDAVPushResult {
        await ensureParentDirs()
        guard let url = fileURL else {
            return WebDAVPushResult(ok: false, conflict: false, status: 0, etag: nil, message: "WebDAV 地址无效")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let body = try? encoder.encode(value) else {
            return WebDAVPushResult(ok: false, conflict: false, status: 0, etag: nil, message: "数据编码失败")
        }
        var headers = ["Content-Type": "application/json; charset=utf-8"]
        if let etag = ifMatch { headers["If-Match"] = etag }

        func put() async throws -> (Int, [String: String]) {
            let (_, status, hs) = try await send(request(url, method: "PUT", headers: headers, body: body))
            return (status, hs)
        }

        do {
            var (status, hs) = try await put()
            if status == 409 {
                await ensureParentDirs()
                (status, hs) = try await put()
            }
            if status == 412 {
                return WebDAVPushResult(ok: false, conflict: true, status: 412, etag: nil, message: "远端已被改动（etag 冲突）")
            }
            guard (200..<300).contains(status) else {
                return WebDAVPushResult(ok: false, conflict: false, status: status, etag: nil, message: "上传失败（HTTP \(status)）")
            }
            return WebDAVPushResult(ok: true, conflict: false, status: status, etag: etag(from: hs), message: "已上传")
        } catch {
            return WebDAVPushResult(ok: false, conflict: false, status: 0, etag: nil, message: "上传失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 版本快照

    func pushVersion(_ value: RemoteData, name: String) async -> Bool {
        await ensureVersionsDir()
        guard let dir = versionsDir else { return false }
        let url = dir.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let body = try? encoder.encode(value) else { return false }
        let headers = ["Content-Type": "application/json; charset=utf-8"]
        do {
            let first = try await send(request(url, method: "PUT", headers: headers, body: body))
            var status = first.1
            if status == 409 {
                await ensureVersionsDir()
                let retry = try await send(request(url, method: "PUT", headers: headers, body: body))
                status = retry.1
            }
            return (200..<300).contains(status)
        } catch {
            return false
        }
    }

    func deleteRemote(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        _ = try? await send(request(url, method: "DELETE"))
    }

    func listVersions() async throws -> [VersionEntry] {
        guard let dir = versionsDir, let base = baseURL else { return [] }
        let body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:getlastmodified/><d:getcontentlength/><d:resourcetype/></d:prop></d:propfind>"
        let req = request(dir, method: "PROPFIND", headers: [
            "Depth": "1",
            "Content-Type": "application/xml; charset=utf-8"
        ], body: Data(body.utf8))
        let (data, status, _) = try await send(req)
        if status == 404 || status == 405 { return [] }
        guard (200..<300).contains(status) else {
            throw NSError(domain: "PromptBox", code: status, userInfo: [NSLocalizedDescriptionKey: "列出版本失败（HTTP \(status)）"])
        }
        let xml = String(data: data, encoding: .utf8) ?? ""

        let blocks = regexMatches("<[^>]*response[^>]*>.*?</[^>]*response>", in: xml)
        var entries: [VersionEntry] = []
        for block in blocks {
            let href = regexMatches("<[^>]*href[^>]*>\\s*([^<]+?)\\s*</[^>]*href[^>]*>", in: block, group: 1).first ?? ""
            if href.isEmpty { continue }
            let decoded = href.removingPercentEncoding ?? href
            let isDir = decoded.hasSuffix("/") || !regexMatches("<[^>]*resourcetype[^>]*>\\s*<[^>]*collection", in: block).isEmpty
            guard !isDir, decoded.lowercased().hasSuffix(".json") else { continue }

            let name = (decoded as NSString).lastPathComponent.replacingOccurrences(of: ".json", with: "", options: .caseInsensitive)
            let fullURL = URL(string: decoded, relativeTo: base)?.absoluteString ?? decoded

            var modified: Int64 = 0
            if let raw = regexMatches("<[^>]*getlastmodified[^>]*>\\s*([^<]+?)\\s*</[^>]*getlastmodified[^>]*>", in: block, group: 1).first {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss ZZZ"
                if let d = f.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    modified = Int64(d.timeIntervalSince1970 * 1000)
                }
            }
            if modified == 0 {
                let digits = name.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                if let last = digits.last, let n = Int64(last) {
                    modified = last.count >= 13 ? n : n * 1000
                }
            }
            var size: Int?
            if let raw = regexMatches("<[^>]*getcontentlength[^>]*>\\s*(\\d+)\\s*</[^>]*getcontentlength[^>]*>", in: block, group: 1).first {
                size = Int(raw)
            }
            entries.append(VersionEntry(name: name, path: fullURL, modified: modified, size: size))
        }
        return entries.sorted { $0.modified > $1.modified }
    }

    private func regexMatches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let index = min(group, match.numberOfRanges - 1)
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}
