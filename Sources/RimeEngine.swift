// 内嵌 Rime 拼音引擎: 运行时 dlopen 鼠鬚管(Squirrel)自带的 librime, 构建时不依赖它

import AppKit
import CRime

var rimeSession: RimeSessionId = 0
var rimeApi: UnsafeMutablePointer<RimeApi>!
var rimeStatus = "未初始化"

private let rimeLibCandidates = [
    EngineInstaller.dir + "/librime.1.dylib",
    "/Library/Input Methods/Squirrel.app/Contents/Frameworks/librime.1.dylib",
    NSHomeDirectory() + "/Library/Input Methods/Squirrel.app/Contents/Frameworks/librime.1.dylib",
]
private let rimeSharedCandidates = [
    EngineInstaller.dir + "/SharedSupport",
    "/Library/Input Methods/Squirrel.app/Contents/SharedSupport",
    NSHomeDirectory() + "/Library/Input Methods/Squirrel.app/Contents/SharedSupport",
]

private func loadRimeApi() -> UnsafeMutablePointer<RimeApi>? {
    typealias GetApi = @convention(c) () -> UnsafeMutablePointer<RimeApi>?
    for path in rimeLibCandidates where FileManager.default.fileExists(atPath: path) {
        guard let h = dlopen(path, RTLD_NOW), let sym = dlsym(h, "rime_get_api") else { continue }
        return unsafeBitCast(sym, to: GetApi.self)()
    }
    return nil
}

func rimeInit() {
    guard let shared = rimeSharedCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
        rimeStatus = "未安装(可一键安装)"
        appendLog(text: "未找到拼音引擎,远端暂时只能直接输入英文/数字。可在设置里一键安装,或 brew install --cask squirrel",
                  color: .systemOrange, prefix: "🈶引擎")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { promptEngineInstall() }
        return
    }
    let user = NSHomeDirectory() + "/Library/Application Support/uuchat/rime-user"
    try? FileManager.default.createDirectory(atPath: user, withIntermediateDirectories: true)
    let customYaml = user + "/default.custom.yaml"
    if !FileManager.default.fileExists(atPath: customYaml) {          // 默认简化音
        try? "patch:\n  schema/list:\n    - schema: luna_pinyin_simp\n"
            .write(toFile: customYaml, atomically: true, encoding: .utf8)
    }
    rimeStatus = "初始化中…"
    DispatchQueue.global(qos: .userInitiated).async {
        guard let api = loadRimeApi() else {
            DispatchQueue.main.async {
                rimeStatus = "librime 加载失败"
                appendLog(text: "librime 加载失败", color: .systemOrange, prefix: "🈶引擎")
            }
            return
        }
        rimeApi = api
        var tr = RimeTraits()
        tr.data_size = Int32(MemoryLayout<RimeTraits>.stride)
        tr.shared_data_dir = cstr(shared)
        tr.user_data_dir = cstr(user)
        tr.prebuilt_data_dir = cstr(shared + "/build")
        tr.log_dir = cstr("")          // 日志只进 stderr
        tr.min_log_level = 2
        tr.distribution_name = cstr("uuchat")
        tr.distribution_code_name = cstr("uuchat")
        tr.distribution_version = cstr(appVersion)
        tr.app_name = cstr("rime.uuchat")
        api.pointee.setup(&tr)
        api.pointee.initialize(&tr)
        _ = api.pointee.start_maintenance(0)
        api.pointee.join_maintenance_thread()
        DispatchQueue.main.async {
            rimeSession = api.pointee.create_session()
            rimeStatus = "就绪(luna_pinyin 简化)"
            appendLog(text: "拼音引擎就绪(luna_pinyin 简化)·远端打字可组词", color: .systemTeal, prefix: "🈶引擎")
        }
    }
}

func keysymFromChar(_ c: Character) -> Int32? {
    guard let a = c.asciiValue, a >= 0x20, a <= 0x7e else { return nil }
    return Int32(a)
}

/// 无组词时的基础编辑(rime 未吞键 / 引擎不可用)
private func plainKey(_ keysym: Int32) {
    switch keysym {
    case 0xff0d: sendRemote()                                          // Return → 提交
    case 0xff08:                                                       // Backspace
        if !inputBuf.isEmpty { inputBuf.removeLast() }
        remoteField.stringValue = inputBuf
    case 0xff1b:                                                       // Esc
        inputBuf = ""
        remoteField.stringValue = ""
        candBar.stringValue = ""
        if rimeSession != 0 { rimeApi.pointee.clear_composition(rimeSession) }
    case 0x20...0x7e:                                                  // 可打印字符(含空格)
        inputBuf += String(Character(UnicodeScalar(UInt8(keysym))))
        remoteField.stringValue = inputBuf
    default: break
    }
}

/// 把一个注入键喂给 rime
func feedRime(keysym: Int32) {
    guard rimeSession != 0 else { plainKey(keysym); return }
    if rimeApi.pointee.process_key(rimeSession, keysym, 0) == 0 {
        plainKey(keysym)
        return
    }
    // rime 吞了: 先取可能产生的提交(get_commit 是“取一次即空”语义,只能读一遍)
    var cm = RimeCommit()
    cm.data_size = Int32(MemoryLayout<RimeCommit>.stride)
    if rimeApi.pointee.get_commit(rimeSession, &cm) != 0, let t = cm.text {
        let s = String(cString: t)
        if !s.isEmpty {
            inputBuf += s
            remoteField.stringValue = inputBuf
        }
        _ = rimeApi.pointee.free_commit(&cm)
    }
    // 更新候选条
    var ctx = RimeContext()
    ctx.data_size = Int32(MemoryLayout<RimeContext>.stride)
    if rimeApi.pointee.get_context(rimeSession, &ctx) != 0 {
        let pre = ctx.composition.preedit.map { String(cString: $0) } ?? ""
        var cands: [String] = []
        for i in 0..<max(Int(ctx.menu.num_candidates), 0) {
            if let t = ctx.menu.candidates?[i].text {
                cands.append(String(cString: t))
                if cands.count >= 5 { break }
            }
        }
        DispatchQueue.main.async {
            if pre.isEmpty && cands.isEmpty {
                candBar.stringValue = ""
            } else if cands.isEmpty {
                candBar.stringValue = "拼音 \(pre)"
            } else {
                candBar.stringValue = "拼音 \(pre)  ▏" + cands.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
            }
        }
        _ = rimeApi.pointee.free_context(&ctx)
    }
}

func clearRimeComposition() {
    guard rimeSession != 0 else { return }
    rimeApi.pointee.clear_composition(rimeSession)
    candBar.stringValue = ""
}
