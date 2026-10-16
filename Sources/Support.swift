// 共享常量 / 全局状态 / 小工具

import AppKit
import CoreGraphics

let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
let repoURL = "https://github.com/Chr0mium24/uuchat"

let FIELD_UNIX_PID = CGEventField(rawValue: 41)!     // kCGEventSourceUnixProcessID
let FIELD_KEYCODE  = CGEventField(rawValue: 9)!
let FIELD_UNACCEL_X = CGEventField(rawValue: 170)!   // kCGEventUnacceleratedPointerMovementX
let FIELD_UNACCEL_Y = CGEventField(rawValue: 171)!
let kFakePidsFile  = "/tmp/uuhook/fake_pids"         // 测试钩子: 逗号分隔 pid = 模拟远端注入源
let kHotkeyCode: UInt32 = 5                          // kVK_ANSI_G, 配合 ⌘⌥

var captureMode = true                // 总开关: 接管 ↔ 放行(⌘⌥G)
var remotePids: Set<pid_t> = []       // UU 被控进程 pid
var inputBuf = ""                     // 远端已提交文字缓冲

func cstr(_ s: String) -> UnsafePointer<CChar> { UnsafePointer(strdup(s)) }

func timestamp() -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

/// 调试日志(设置里开启后写入 /tmp/uuchat-mouse.log)
func debugLog(_ line: String) {
    guard Settings.shared.debugLog else { return }
    let path = "/tmp/uuchat-mouse.log"
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    }
}

// MARK: - pid 发现

func readPids() -> Set<pid_t> {
    var pids: Set<pid_t> = []
    let out = Pipe(); let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    proc.arguments = ["-x", "UURemoteServer"]
    proc.standardOutput = out
    try? proc.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    if let s = String(data: data, encoding: .utf8) {
        pids.formUnion(s.split(whereSeparator: \.isNewline).compactMap { pid_t($0) })
    }
    if let s = try? String(contentsOfFile: kFakePidsFile, encoding: .utf8) {
        pids.formUnion(s.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { pid_t($0) })
    }
    return pids
}
