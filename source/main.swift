import Cocoa
import WebKit
import Carbon

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class PetWebView: WKWebView {
    weak var owner: PetApp?
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { owner?.demo(); return }
        owner?.dragging = true
        window?.performDrag(with: event)
        owner?.dragging = false
        owner?.save()
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = owner?.makeMenu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > 0.2 { owner?.resize(by: event.scrollingDeltaY > 0 ? 0.025 : -0.025) }
    }
}
final class PetApp: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var panel: PetPanel!
    var web: PetWebView!
    var item: NSStatusItem!
    var timer: Timer?
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var loaded = false
    var dragging = false
    var paused = false
    var lastPointer = NSEvent.mouseLocation
    var lastHead = false
    var lastSecure = false
    var scale = 0.85
    var ticks = 0
    var scriptPending = false
    let defaults = UserDefaults.standard
    // Physical key identifiers only; no input text, clipboard or keystroke history is read.
    let keyMap: [Int64:String] = [0:"KeyA",1:"KeyS",2:"KeyD",3:"KeyF",4:"KeyH",5:"KeyG",6:"KeyZ",7:"KeyX",8:"KeyC",9:"KeyV",11:"KeyB",12:"KeyQ",13:"KeyW",14:"KeyE",15:"KeyR",16:"KeyY",17:"KeyT",18:"Digit1",19:"Digit2",20:"Digit3",21:"Digit4",22:"Digit6",23:"Digit5",25:"Digit9",26:"Digit7",28:"Digit8",29:"Digit0",31:"KeyO",32:"KeyU",34:"KeyI",35:"KeyP",36:"Enter",37:"KeyL",38:"KeyJ",40:"KeyK",42:"Backslash",43:"Comma",44:"Slash",45:"KeyN",46:"KeyM",47:"Period",48:"Tab",49:"Space",51:"Backspace",53:"Escape",123:"ArrowLeft",124:"ArrowRight"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "local.jennie.typinggirl").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) { NSApp.terminate(nil); return }
        if defaults.object(forKey:"scale") != nil { scale = max(0.55,min(1.6,defaults.double(forKey:"scale"))) }
        let w = 300 * scale, h = w * 775 / 627
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800)
        var origin = NSPoint(x:screen.maxX-w-24,y:screen.minY+24)
        if defaults.object(forKey:"positionX") != nil {
            let saved = NSPoint(x:defaults.double(forKey:"positionX"),y:defaults.double(forKey:"positionY"))
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSPoint(x:saved.x+w/2,y:saved.y+h/2)) }) { origin=saved }
        }
        panel = PetPanel(contentRect:NSRect(origin:origin,size:NSSize(width:w,height:h)),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="AA TYPING"
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false
        panel.level = .floating;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web=PetWebView(frame:NSRect(x:0,y:0,width:w,height:h),configuration:configuration)
        web.owner=self;web.navigationDelegate=self
        web.setValue(false,forKey:"drawsBackground")
        panel.contentView=web
        if let url=Bundle.main.url(forResource:"pet",withExtension:"html") { web.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent()) }
        panel.orderFrontRegardless()
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.image=NSImage(systemSymbolName:"keyboard",accessibilityDescription:"AA TYPING")
        item.button?.toolTip="AA TYPING · 右键调整，双击演示"
        refreshMenu();startListener()
        timer=Timer(timeInterval:0.05,repeats:true){ [weak self] _ in self?.pollPointer() }
        RunLoop.main.add(timer!,forMode:.common)
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded=true; let outfit=defaults.string(forKey:"outfit") ?? "original"; js("window.desktopPet.outfit(\"\(outfit)\")") }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }
    func js(_ script:String) { if loaded { web.evaluateJavaScript(script,completionHandler:nil) } }

    func startListener() {
        guard tap == nil, CGPreflightListenEventAccess() else { return }
        tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.listenOnly,eventsOfInterest:CGEventMask(1<<CGEventType.keyDown.rawValue),callback:{ _,type,event,context in
            guard let context=context else { return Unmanaged.passUnretained(event) }
            let owner=Unmanaged<PetApp>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap=owner.tap { CGEvent.tapEnable(tap:tap,enable:true) } }
            else if type == .keyDown && !owner.paused && !IsSecureEventInputEnabled() && event.getIntegerValueField(.keyboardEventAutorepeat)==0 {
                let blocked:CGEventFlags=[.maskCommand,.maskControl,.maskAlternate]
                if event.flags.intersection(blocked).isEmpty, let code=owner.keyMap[event.getIntegerValueField(.keyboardEventKeycode)] {
                    owner.js("window.desktopPet.key('\(code)')")
                }
            }
            return Unmanaged.passUnretained(event)
        },userInfo:Unmanaged.passUnretained(self).toOpaque())
        if let tap=tap {
            tapSource=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
            CFRunLoopAddSource(CFRunLoopGetMain(),tapSource,.commonModes)
            CGEvent.tapEnable(tap:tap,enable:true);refreshMenu()
        }
    }
    func pollPointer() {
        ticks+=1
        if ticks%60==0 && tap==nil { startListener() }
        let p=NSEvent.mouseLocation,dx=p.x-lastPointer.x,dy=lastPointer.y-p.y
        lastPointer=p
        let secure=IsSecureEventInputEnabled()
        if secure != lastSecure { lastSecure=secure;js("window.desktopPet.secure(\(secure))") }
        guard loaded,!paused,!dragging,!scriptPending else { return }
        let x=(p.x-panel.frame.minX)/panel.frame.width*627
        let y=(panel.frame.maxY-p.y)/panel.frame.height*775
        let head=pow((x-313.5)/205,2)+pow((y-270)/180,2)<=1
        guard abs(dx)+abs(dy)>0.01 || head != lastHead else { return }
        lastHead=head
        scriptPending=true
        web.evaluateJavaScript("window.desktopPet.pointer(\(x),\(y),\(dx),\(dy))") { [weak self] _,_ in self?.scriptPending=false }
    }
    func menuItem(_ title:String,_ selector:Selector?)->NSMenuItem {
        let result=NSMenuItem(title:title,action:selector,keyEquivalent:"");result.target=self;return result
    }
    func makeMenu()->NSMenu {
        let menu=NSMenu()
        menu.addItem(menuItem("AA TYPING 2.1",nil))
        menu.addItem(menuItem(tap == nil ? "键盘响应：等待输入监控授权":"键盘响应：已连接",nil))
        menu.addItem(.separator())
        menu.addItem(menuItem("演示打字",#selector(demo)))
        menu.addItem(menuItem("演示生气",#selector(demoAngry)))
        menu.addItem(menuItem("演示鼠标",#selector(demoMouse)))
        menu.addItem(menuItem("演示休息",#selector(demoRest)))
        let clothes=menuItem("换装",nil),wardrobe=NSMenu()
        for (name,id) in [("粉围巾毛衣","original"),("蓝围巾羊羔绒","camel"),("黑帽毛绒马甲 · 灰棕发","monochrome")] {
            let choice=menuItem(name,#selector(selectOutfit(_:)));choice.representedObject=id
            choice.state=(defaults.string(forKey:"outfit") ?? "original")==id ? .on:.off;wardrobe.addItem(choice)
        }
        clothes.submenu=wardrobe;menu.addItem(clothes)
        menu.addItem(menuItem(paused ? "继续联动":"暂停联动",#selector(togglePause)))
        let sizes=menuItem("大小：\(Int(scale*100))%",nil),sub=NSMenu()
        for n in [55,70,85,100,120,150] { let choice=menuItem("\(n)%",#selector(selectSize(_:)));choice.tag=n;sub.addItem(choice) }
        sizes.submenu=sub;menu.addItem(sizes)
        menu.addItem(menuItem("移回右下角",#selector(resetPosition)))
        menu.addItem(menuItem("键盘响应权限…",#selector(permission)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出AA TYPING",#selector(quit)))
        return menu
    }
    func refreshMenu(){item?.menu=makeMenu()}
    @objc func demo(){js("window.desktopPet.demo('typing')")}
    @objc func demoAngry(){js("window.desktopPet.demo('angry')")}
    @objc func demoRest(){js("window.desktopPet.demo('rest')")}
    @objc func selectOutfit(_ sender:NSMenuItem){guard let id=sender.representedObject as? String else{return};defaults.set(id,forKey:"outfit");js("window.desktopPet.outfit('\(id)')");refreshMenu()}
    @objc func demoMouse(){js("window.desktopPet.demo('mouse')")}
    @objc func togglePause(){paused.toggle();if paused{js("window.desktopPet.stop()")};refreshMenu()}
    @objc func selectSize(_ sender:NSMenuItem){setScale(Double(sender.tag)/100)}
    func resize(by delta:Double){setScale(scale+delta)}
    func setScale(_ value:Double){scale=max(0.55,min(1.6,value));let old=panel.frame,w=300*scale;panel.setFrame(NSRect(x:old.midX-w/2,y:old.minY,width:w,height:w*775/627),display:true);screenChanged();refreshMenu();save()}
    func save(){defaults.set(scale,forKey:"scale");defaults.set(panel.frame.minX,forKey:"positionX");defaults.set(panel.frame.minY,forKey:"positionY")}
    @objc func screenChanged(){guard let s=(NSScreen.screens.first(where:{$0.visibleFrame.intersects(panel.frame)}) ?? NSScreen.main)?.visibleFrame else{return};let f=panel.frame;panel.setFrameOrigin(NSPoint(x:min(max(f.minX,s.minX),s.maxX-f.width),y:min(max(f.minY,s.minY),s.maxY-f.height)))}
    @objc func resetPosition(){if let s=NSScreen.main?.visibleFrame{panel.setFrameOrigin(NSPoint(x:s.maxX-panel.frame.width-24,y:s.minY+24));save()}}
    @objc func permission(){if CGPreflightListenEventAccess(){startListener();return};CGRequestListenEventAccess();if let u=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"){NSWorkspace.shared.open(u)}}
    @objc func quit(){NSApp.terminate(nil)}
    func applicationWillTerminate(_ notification:Notification){timer?.invalidate();if panel != nil{save()};if let tap=tap{CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap)}}
}
let application=NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate=PetApp()
application.delegate=delegate
application.run()
