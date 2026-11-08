//
//  批量水印工作台 / Batch Watermark Studio
//  Copyright (c) 2026 KYO4926
//  SPDX-License-Identifier: MIT
//
//  Licensed under the MIT License. See LICENSE for the full text.
//  Privacy: all photo processing happens locally in WKWebView; this binary
//  makes no network requests and embeds no user data.
//

import Cocoa
import WebKit
import UniformTypeIdentifiers

private let kSelfTest = ProcessInfo.processInfo.environment["WB_SELFTEST"] == "1"
private var strongDelegate: AppDelegate?

private let kImageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "bmp", "tif", "tiff", "avif"]
private func isImageURL(_ u: URL) -> Bool { kImageExts.contains(u.pathExtension.lowercased()) }

/// JSON 字符串字面量（用于把文件名 / base64 安全注入 JS）
private func jsLiteral(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
    let text = String(data: data, encoding: .utf8)!
    return String(text.dropFirst().dropLast())
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler,
                         WKNavigationDelegate, WKUIDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        strongDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(kSelfTest ? .accessory : .regular)
        app.run()
    }

    private var window: NSWindow!
    private var webView: DropWebView!
    private var saveChunks: [String] = []
    private var saveName = "export"
    private var testTimer: Timer?
    private var testStart = Date()

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        loadPage()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.makeKeyAndOrderFront(nil) }
        return true
    }

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        if #available(macOS 11.0, *) {
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let uc = cfg.userContentController
        uc.addUserScript(WKUserScript(source: "window.__NATIVE_APP__=true;",
                                      injectionTime: .atDocumentStart, forMainFrameOnly: true))
        uc.add(self, name: "nativeSave")

        let rect = NSRect(x: 0, y: 0, width: 1460, height: 920)
        webView = DropWebView(frame: rect, configuration: cfg)
        webView.owner = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]

        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "批量水印工作台"
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 1080, height: 680)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        if kSelfTest {
            window.setFrame(NSRect(x: -4000, y: -4000, width: rect.width, height: rect.height), display: false)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        if !kSelfTest { NSApp.activate(ignoringOtherApps: true) }
    }

    private func loadPage() {
        guard let res = Bundle.main.resourceURL else {
            fatalError("缺少 Resources 目录")
        }
        let html = res.appendingPathComponent("app.html")
        webView.loadFileURL(html, allowingReadAccessTo: res)
    }

    // MARK: - 主菜单

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 批量水印工作台",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 批量水印工作台",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 批量水印工作台",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        let importItem = NSMenuItem(title: "导入照片…", action: #selector(importFromMenu), keyEquivalent: "o")
        importItem.target = self
        fileMenu.addItem(importItem)
        fileMenu.addItem(NSMenuItem.separator())
        let exportItem = NSMenuItem(title: "导出结果图片…", action: #selector(exportFromMenu), keyEquivalent: "e")
        exportItem.target = self
        fileMenu.addItem(exportItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: "窗口")
        winMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winItem.submenu = winMenu

        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
    }

    @objc private func importFromMenu() {
        evalJS("document.getElementById('fileInput').click()")
    }

    @objc private func exportFromMenu() {
        evalJS("document.getElementById('exportBtn').click()")
    }

    // MARK: - JS 调用

    private func evalJS(_ js: String, completion: ((Any?, Error?) -> Void)? = nil) {
        let work = { self.webView?.evaluateJavaScript(js) { r, e in completion?(r, e) } }
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async { work() } }
    }

    /// 后台线程调用：等待一次 JS 注入完成，避免大量消息堆积
    private func evalJSSync(_ js: String) {
        if Thread.isMainThread {
            webView?.evaluateJavaScript(js) { _, _ in }
            return
        }
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { _, _ in sem.signal() }
        }
        _ = sem.wait(timeout: .now() + 20)
    }

    func notifyJS(_ msg: String, _ kind: String = "ok") {
        evalJS("window.__nativeToast && window.__nativeToast(\(jsLiteral(msg)),\(jsLiteral(kind)))")
    }

    func setDragHighlight(_ on: Bool) {
        evalJS("window.__setDragOver && window.__setDragOver(\(on))")
    }

    /// AppKit 拖入的文件 → base64 分片 → 页面构造 File 对象导入
    func importDroppedFiles(_ urls: [URL]) {
        let images = urls.filter(isImageURL)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let total = images.count
            self.evalJSSync("window.__nativeFile && window.__nativeFile({type:'begin',total:\(total)})")
            var index = 0
            for url in images {
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                let b64 = data.base64EncodedString()
                let name = jsLiteral(url.lastPathComponent)
                var i = b64.startIndex
                while i < b64.endIndex {
                    let end = b64.index(i, offsetBy: 262144, limitedBy: b64.endIndex) ?? b64.endIndex
                    let piece = jsLiteral(String(b64[i..<end]))
                    self.evalJSSync("window.__nativeFile && window.__nativeFile({type:'chunk',name:\(name),data:\(piece)})")
                    i = end
                }
                index += 1
                // 每接收完一张就回报进度，页面上的导入窗口会实时刷新
                self.evalJSSync("window.__nativeFile && window.__nativeFile({type:'fileDone',index:\(index),total:\(total),name:\(name)})")
            }
            self.evalJSSync("window.__nativeFile && window.__nativeFile({type:'end'})")
            if index == 0 { self.notifyJS("拖入的文件中没有可识别的图片", "warn") }
        }
    }

    // MARK: - 文件保存（网页导出桥接）

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "nativeSave",
              let d = message.body as? [String: Any],
              let type = d["type"] as? String else { return }
        switch type {
        case "begin":
            saveChunks.removeAll(keepingCapacity: true)
            saveName = (d["name"] as? String) ?? "export"
        case "chunk":
            if let s = d["data"] as? String { saveChunks.append(s) }
        case "end":
            let data = Data(base64Encoded: saveChunks.joined()) ?? Data()
            let name = saveName
            saveChunks.removeAll(keepingCapacity: false)
            presentSavePanel(data: data, name: name)
        default:
            break
        }
    }

    private func presentSavePanel(data: Data, name: String) {
        guard !data.isEmpty else { notifyJS("导出内容为空", "err"); return }
        if kSelfTest {
            // 自检模式：跳过保存面板，直接落盘供外部校验
            let dest = URL(fileURLWithPath: "/tmp/wb-native-save-test.zip")
            try? data.write(to: dest, options: .atomic)
            evalJS("window.__SELFTEST_SAVE_BYTES__ = \(data.count)")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        panel.canSelectHiddenExtension = true
        panel.message = "选择导出位置（默认「下载」文件夹）"
        panel.prompt = "导出"
        guard let win = window else { return }
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                self?.notifyJS("已取消导出", "warn")
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                self?.notifyJS("已保存：" + url.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self?.notifyJS("保存失败：" + error.localizedDescription, "err")
            }
        }
    }

    // MARK: - WKUIDelegate：文件选择面板

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.message = "选择要批量加水印的照片（可按住 ⌘ 多选）"
        panel.prompt = "导入"
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.image]
        } else {
            panel.allowedFileTypes = Array(kImageExts)
        }
        guard let win = webView.window else { completionHandler(nil); return }
        panel.beginSheetModal(for: win) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("页面加载失败: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard kSelfTest else { return }
        let js = """
        (()=>{
          window.__SELFTEST_RESULT__='';
          (async()=>{
            const out={};
            try{
              out.native = window.__NATIVE_APP__ === true;
              out.bridge = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeSave);
              out.ready  = typeof addFiles==='function' && typeof applyAll==='function' && typeof downloadBlob==='function';
              out.jsErr  = 'none';
              const fs=[];
              for(const [w,h] of [[640,420],[420,640]]){
                const c=document.createElement('canvas'); c.width=w; c.height=h;
                const x=c.getContext('2d'); x.fillStyle='#4477aa'; x.fillRect(0,0,w,h);
                const b=await new Promise(r=>c.toBlob(r,'image/png'));
                fs.push(new File([b],'selftest_'+w+'.png',{type:'image/png'}));
              }
              await addFiles(fs);
              S.resizeMode='width'; S.resizeValue=320; onSettingsChange();
              await applyAll();
              out.count=state.photos.length;
              out.statuses=state.photos.map(p=>p.status).join(',');
              out.dims=state.photos.map(p=>p.resultW+'x'+p.resultH).join(',');
              out.status=document.getElementById('statusTitle').textContent;
              out.queue=document.querySelectorAll('.photo-card').length;
              // 走一遍原生导出：JS 打包 ZIP -> 分片 base64 -> Swift 落盘
              await exportAll();
              for(let i=0;i<80;i++){
                if(window.__SELFTEST_SAVE_BYTES__){ out.saveBytes=window.__SELFTEST_SAVE_BYTES__; break; }
                await new Promise(r=>setTimeout(r,100));
              }
              out.zipOk = (typeof buildZip==='function');
              // 新增：拖放导入进度窗口 + 原生文件接收协议
              out.importUI = typeof showImport==='function' && !!document.getElementById('importOverlay');
              const cc=document.createElement('canvas'); cc.width=32; cc.height=32;
              cc.getContext('2d').fillRect(0,0,32,32);
              const bl=await new Promise(r=>cc.toBlob(r,'image/png'));
              const u8=new Uint8Array(await bl.arrayBuffer());
              let bin='';
              for(let k=0;k<u8.length;k+=8192) bin+=String.fromCharCode.apply(null,u8.subarray(k,k+8192));
              window.__nativeFile({type:'begin',total:1});
              out.overlayShown = !document.getElementById('importOverlay').classList.contains('hidden');
              window.__nativeFile({type:'chunk',name:'dropped.png',data:btoa(bin)});
              window.__nativeFile({type:'fileDone',index:1,total:1,name:'dropped.png'});
              out.progressText = document.getElementById('importCount').textContent;
              window.__nativeFile({type:'end'});
              for(let k=0;k<80;k++){
                if(document.getElementById('importCard').classList.contains('done')) break;
                await new Promise(r=>setTimeout(r,100));
              }
              out.importDone = document.getElementById('importTitle').textContent;
              out.photosAfterDrop = state.photos.length;
            }catch(e){ out.error=String(e&&e.stack||e); }
            window.__SELFTEST_RESULT__=JSON.stringify(out);
          })();
        })()
        """
        webView.evaluateJavaScript(js) { _, err in
            if let err = err {
                print("SELFTEST_INJECT_ERROR: \(err.localizedDescription)")
                exit(1)
            }
        }
        testStart = Date()
        testTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self,
                                         selector: #selector(pollTest), userInfo: nil, repeats: true)
    }

    @objc private func pollTest() {
        if Date().timeIntervalSince(testStart) > 60 {
            print("SELFTEST_TIMEOUT")
            exit(1)
        }
        webView?.evaluateJavaScript("window.__SELFTEST_RESULT__ || ''") { res, _ in
            guard let s = res as? String, !s.isEmpty else { return }
            print("SELFTEST_RESULT: \(s)")
            fflush(stdout)
            exit(0)
        }
    }
}

// MARK: - 支持 macOS 原生文件拖放的 WKWebView

final class DropWebView: WKWebView {
    weak var owner: AppDelegate?

    override init(frame frameRect: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frameRect, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func droppedURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let images = droppedURLs(sender).filter(isImageURL)
        guard !images.isEmpty else { return [] }
        owner?.setDragHighlight(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).contains(where: isImageURL) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        owner?.setDragHighlight(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        owner?.setDragHighlight(false)
        let images = droppedURLs(sender).filter(isImageURL)
        guard !images.isEmpty else { return false }
        owner?.importDroppedFiles(images)
        return true
    }
}
