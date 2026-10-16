// 一键安装拼音引擎: 从 rime/squirrel 官方 GitHub Release 下载安装包, 只解出 librime 与词库,
// 不安装鼠鬚管输入法、不需要管理员密码。安装包须通过 Apple Developer ID 签名校验。

import AppKit

enum EngineInstaller {
    static let dir = NSHomeDirectory() + "/Library/Application Support/uuchat/engine"
    static let fallbackURL = "https://github.com/rime/squirrel/releases/download/1.1.2/Squirrel-1.1.2.pkg"
    static var busy = false

    static var installed: Bool {
        FileManager.default.fileExists(atPath: dir + "/librime.1.dylib")
            && FileManager.default.fileExists(atPath: dir + "/SharedSupport")
    }

    private static func status(_ s: String) {
        DispatchQueue.main.async { rimeStatus = s }
    }

    /// 后台执行; 完成后回到主线程调用 completion(成功?, 说明)
    static func install(completion: @escaping (Bool, String) -> Void) {
        guard !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let (ok, msg) = run()
            DispatchQueue.main.async {
                busy = false
                completion(ok, msg)
            }
        }
    }

    private static func run() -> (Bool, String) {
        let fm = FileManager.default
        let work = NSTemporaryDirectory() + "uuchat-engine-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: work) }

        // 1. 最新版安装包地址(失败回退到固定版本); 只接受 rime/squirrel 仓库下的 https 链接
        status("查询最新版本…")
        var url = fallbackURL
        if let api = URL(string: "https://api.github.com/repos/rime/squirrel/releases/latest"),
           let data = syncGet(api),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let assets = obj["assets"] as? [[String: Any]],
           let found = assets.compactMap({ $0["browser_download_url"] as? String })
               .first(where: { $0.hasSuffix(".pkg") && $0.hasPrefix("https://github.com/rime/squirrel/") }) {
            url = found
        }

        // 2. 下载
        let pkg = work + "/squirrel.pkg"
        guard download(URL(string: url)!, to: pkg) else { status("下载失败"); return (false, "下载失败,请检查网络") }

        // 3. 校验签名(Apple Developer ID Installer)
        status("校验安装包…")
        let (code, out) = shell("/usr/sbin/pkgutil", ["--check-signature", pkg])
        guard code == 0, out.contains("Developer ID Installer") else {
            status("安装包签名校验失败"); return (false, "安装包签名校验失败,已中止")
        }

        // 4. 展开(不安装)并拷贝引擎文件
        status("解压引擎…")
        let expanded = work + "/expanded"
        guard shell("/usr/sbin/pkgutil", ["--expand-full", pkg, expanded]).0 == 0 else {
            status("解压失败"); return (false, "解压失败")
        }
        let app = expanded + "/Payload/Squirrel.app/Contents"
        guard fm.fileExists(atPath: app + "/Frameworks/librime.1.dylib"),
              fm.fileExists(atPath: app + "/SharedSupport") else {
            status("安装包结构异常"); return (false, "安装包结构异常")
        }
        try? fm.removeItem(atPath: dir)
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try fm.copyItem(atPath: app + "/Frameworks/librime.1.dylib", toPath: dir + "/librime.1.dylib")
            try fm.copyItem(atPath: app + "/SharedSupport", toPath: dir + "/SharedSupport")
        } catch {
            status("拷贝失败"); return (false, "拷贝失败: \(error.localizedDescription)")
        }
        return (true, "拼音引擎已安装")
    }

    // MARK: - 小工具

    private static func syncGet(_ url: URL) -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("uuchat", forHTTPHeaderField: "User-Agent")
        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, _, _ in result = d; sem.signal() }.resume()
        sem.wait()
        return result
    }

    private static func download(_ url: URL, to path: String) -> Bool {
        var ok = false
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.downloadTask(with: url) { tmp, resp, _ in
            if let tmp = tmp, (resp as? HTTPURLResponse)?.statusCode == 200 {
                ok = (try? FileManager.default.moveItem(atPath: tmp.path, toPath: path)) != nil
            }
            sem.signal()
        }
        let obs = task.progress.observe(\.fractionCompleted) { p, _ in
            status("下载中 \(Int(p.fractionCompleted * 100))%")
        }
        task.resume()
        sem.wait()
        obs.invalidate()
        return ok
    }

    private static func shell(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// 引导安装: 首次发现没有引擎时弹窗询问; 设置里的「一键安装」按钮也走这里
func installEngineFlow(thenInit: Bool = true) {
    EngineInstaller.install { ok, msg in
        appendLog(text: msg, color: ok ? .systemTeal : .systemOrange, prefix: "🈶引擎")
        if ok, thenInit, rimeSession == 0 { rimeInit() }
        if !ok { rimeStatus = "未安装(可在设置里重试)" }
    }
}

func promptEngineInstall() {
    let key = "engineInstallDeclined"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    let a = NSAlert()
    a.messageText = "需要拼音引擎"
    a.informativeText = "远端打中文需要 Rime 拼音引擎与词库(约 25 MB)。\n\n将从 GitHub rime/squirrel 官方发布页下载经 Apple 公证的安装包,只解出引擎文件到\n~/Library/Application Support/uuchat/engine,不会安装鼠鬚管输入法,也不需要管理员密码。"
    a.addButton(withTitle: "下载并安装")
    a.addButton(withTitle: "以后再说")
    NSApp.activate(ignoringOtherApps: true)
    if a.runModal() == .alertFirstButtonReturn {
        installEngineFlow()
    } else {
        UserDefaults.standard.set(true, forKey: key)
    }
}
