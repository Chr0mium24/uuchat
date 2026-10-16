// uuchat — UU 远控浮窗聊天: 接管 UU 注入的键鼠, 内嵌 Rime 拼音, 双光标

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
setvbuf(stdout, nil, _IOLBF, 8192)

buildWindow()
installStatusItem()
NotificationCenter.default.addObserver(forName: .uuSettingsChanged, object: nil, queue: .main) { _ in refreshUI() }

remotePids = readPids()
appendLog(text: "uuchat \(appVersion) 已启动 · ⌘⌥G 切换接管/放行", color: .systemTeal, prefix: "🚀启动")
startTapWhenTrusted()
rimeInit()
if CommandLine.arguments.contains("--settings") { SettingsWindow.show() }

// 每 2 秒探测 UU 被控进程上下线
Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
    let pids = readPids()
    guard pids != remotePids else { return }
    let added = pids.subtracting(remotePids)
    remotePids = pids
    if !added.isEmpty {
        appendLog(text: "UU 被控进程在线(\(added.map(String.init).joined(separator: ","))),开始接管其键鼠注入",
                  color: .systemPurple, prefix: "👁监视")
    } else {
        appendLog(text: "UU 被控进程离线", color: .systemGray, prefix: "👁监视")
        hideFakeCursor()
    }
}
app.run()
