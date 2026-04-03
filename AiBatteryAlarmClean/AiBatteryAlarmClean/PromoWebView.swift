// PromoWebView.swift
// AiBatteryAlarmClean
//
// Fixed: corrected JS-call queuing and fixed postJSLog string interpolation escaping.
// Full file replacement — keeps App Settings, Camera, Photos, Flashlight, Music picker,
// and queues evaluateJavaScript calls until the page finishes loading.
//

import SwiftUI
import WebKit
import MediaPlayer
import AVFoundation
import Photos
import PhotosUI
import AudioToolbox
import MessageUI
import UserNotifications

struct PromoWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "jsLogger")

        // Inject JS bridge for console logging
        let jsBridge = """
        (function() {
          function wrapConsole(method) {
            const original = console[method];
            console[method] = function(...args) {
              try { window.webkit.messageHandlers.jsLogger.postMessage(method + ": " + args.join(" ")); } catch(e) {}
              original.apply(console, args);
            };
          }
          ['log', 'warn', 'error'].forEach(wrapConsole);
          window.onerror = function(msg, url, line, col, error) {
            try { window.webkit.messageHandlers.jsLogger.postMessage("JS ERROR: " + msg + " at " + url + ":" + line + ":" + col); } catch(e) {}
          };
        })();
        """
        let script = WKUserScript(source: jsBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(script)
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        // VolumeScriptMessageHandler registration removed to revert to previous stable behavior
        // webView.configuration.userContentController.add(VolumeScriptMessageHandler(webView: webView), name: "setSystemVolume")
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false

        // Load local HTML file with proper base URL for resources
        if let htmlPath = Bundle.main.path(forResource: "promo", ofType: "html") {
            let fileURL = URL(fileURLWithPath: htmlPath)
            let directoryURL = fileURL.deletingLastPathComponent()
            webView.loadFileURL(fileURL, allowingReadAccessTo: directoryURL)
            print("✅ promo.html loaded via loadFileURL with resource access")
        } else {
            print("❌ promo.html not found in bundle")
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIImagePickerControllerDelegate, UINavigationControllerDelegate, MPMediaPickerControllerDelegate, PHPickerViewControllerDelegate, MFMessageComposeViewControllerDelegate {
        weak var webView: WKWebView?
        private var batteryTimer: Timer?
        private var isTorchOn = false

        // Background notification suppression (avoid spamming system notifications)
        private var lastBackgroundNotificationTs: Date?
        private let backgroundNotificationMinInterval: TimeInterval = 60.0

        // SOS/foreground haptic & torch prototype
        private var sosPatternIndex: Int = 0
        private var sosRunning: Bool = false
        private var isPresentingMessageComposer: Bool = false

        // Photo / image handling
        private var lastPickedImage: UIImage?

        // Audio recording
        private var audioRecorder: AVAudioRecorder?
        private var audioRecordingURL: URL?

        // Page-load state and queued JS scripts until page is ready
        private var pageLoaded = false
        private var pendingJSScripts: [String] = []
        // Debounce work item for SET_THRESHOLDS messages coming from JS
        private var pendingThresholdsTask: DispatchWorkItem?

        override init() {
            super.init()
            UIDevice.current.isBatteryMonitoringEnabled = true

            // Observe battery state/level changes and push updates to the web UI immediately.
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(batteryStateOrLevelChanged(_:)),
                                                   name: UIDevice.batteryStateDidChangeNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(batteryStateOrLevelChanged(_:)),
                                                   name: UIDevice.batteryLevelDidChangeNotification,
                                                   object: nil)
        }

        deinit {
            batteryTimer?.invalidate()
            // Keep system battery monitoring enabled (BatteryMonitor owns lifecycle).
            // remove JS handlers added by this coordinator to avoid duplicates/leaks
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "jsLogger")
            // Remove observers we registered (safe to call even if already removed)
            NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
            // setSystemVolume handler removed earlier; no longer deregistering here
        }

        // MARK: - Evaluate or queue JS
        private func evaluateOrQueue(_ script: String) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.pageLoaded {
                    self.webView?.evaluateJavaScript(script) { _, error in
                        if let e = error {
                            print("❌ JS eval error: \(e) — script: \(script.prefix(120))")
                        }
                    }
                } else {
                    self.pendingJSScripts.append(script)
                    print("⏳ Queued JS script until page load: \(script.prefix(120))...")
                }
            }
        }

        private func flushPendingScripts() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.pageLoaded, !self.pendingJSScripts.isEmpty else { return }
                let scripts = self.pendingJSScripts
                self.pendingJSScripts.removeAll()
                print("🔁 Flushing \(scripts.count) queued JS scripts")
                for s in scripts {
                    self.webView?.evaluateJavaScript(s) { _, error in
                        if let e = error {
                            print("❌ JS eval error while flushing: \(e)")
                        }
                    }
                }
            }
        }

        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("🌐 WebView didFinish navigation - pageReady")
            self.pageLoaded = true
            flushPendingScripts()

            // synchronization with native volume removed (VolumeScriptMessageHandler unregistered)
            // previously: VolumeScriptMessageHandler.setCurrentVolumeOnWebView(webView)

            sendBatteryLevelToWebView()
            sendBatteryHealthToWebView()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               (url.scheme == "http" || url.scheme == "https"),
               navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                print("🌐 External link opened in Safari: \(url.absoluteString)")
                return
            }
            decisionHandler(.allow)
        }

        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else {
                print("📟 JS LOG: non-string message received: \(message.body)")
                return
            }
            let log = body.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📟 JS LOG: \(log)")

            switch log {
            case "OPEN_BATTERY_SETTINGS", "SHOW_BATTERY_HEALTH_ALERT":
                print("🔋 Presenting in-app Battery Info view on request from JS")
                presentBatteryInfo()

            case let s where s.hasPrefix("SET_ALARM_VOLUME:"):
                // payload: "SET_ALARM_VOLUME:75" (0-100)
                if let numStr = s.split(separator: ":").last,
                   let n = Int(numStr) {
                    let clamped = max(0, min(100, n))
                    let normalized = Double(clamped) / 100.0
                    print("📟 JS LOG: Set alarm volume to \(clamped)% (normalized \(normalized))")
                    AlarmManager.shared.setAlarmVolume(normalized)
                }

            case let s where s.hasPrefix("SET_THRESHOLDS:"):
                // payload: "SET_THRESHOLDS:<low>:<high>" where values are 0-100 integers
                // Debounce rapid changes coming from JS so native doesn't thrash notification scheduling.
                let parts = s.components(separatedBy: ":")
                if parts.count >= 3, let lowInt = Int(parts[1]), let highInt = Int(parts[2]) {
                    let lowVal = Double(max(0, min(100, lowInt))) / 100.0
                    let highVal = Double(max(0, min(100, highInt))) / 100.0

                    // Cancel any previously scheduled threshold write and schedule a new one shortly in the future.
                    pendingThresholdsTask?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        // Persist to UserDefaults so native code (AlarmManager, BatteryMonitor) sees the updated thresholds.
                        UserDefaults.standard.set(lowVal, forKey: "lowThreshold")
                        UserDefaults.standard.set(highVal, forKey: "highThreshold")
                        print("📟 JS LOG: SET_THRESHOLDS applied (debounced) - persisted low=\(Int(lowVal*100))% high=\(Int(highVal*100))%")

                        // Clear any pending or delivered notifications scheduled under previous thresholds to prevent stale banners.
                        let center = UNUserNotificationCenter.current()
                        center.removeAllPendingNotificationRequests()
                        center.removeAllDeliveredNotifications()

                        // Defensive: if device is charging and level <= lowVal, immediately stop any playing alarm
                        UIDevice.current.isBatteryMonitoringEnabled = true
                        let deviceLevel = Double(UIDevice.current.batteryLevel) // 0.0-1.0 or -1 if unknown
                        let deviceState = UIDevice.current.batteryState
                        if deviceLevel >= 0 && (deviceState == .charging || deviceState == .full) && deviceLevel <= lowVal {
                            print("⛔ SET_THRESHOLDS safeguard: device charging and level \(Int(deviceLevel*100))% <= new low \(Int(lowVal*100))% — stopping alarm")
                            AlarmManager.shared.stopAlarm()
                        }

                        // Refresh JS with native level/state so UI & native are in sync
                        self.sendBatteryLevelToWebView()
                        self.sendBatteryHealthToWebView()
                        // clear the pendingTask reference
                        DispatchQueue.main.async { [weak self] in self?.pendingThresholdsTask = nil }
                    }

                    // Hold briefly to collapse many rapid updates into one (450ms chosen experimentally)
                    pendingThresholdsTask = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
                } else {
                    print("⚠️ SET_THRESHOLDS: malformed payload -> \(s)")
                }

            case let s where s.hasPrefix("PREVIEW_DEFAULT:"):
                // payload: "PREVIEW_DEFAULT:<name>" — play a short one-shot preview (native preferred)
                if let name = s.split(separator: ":").last {
                    let soundName = String(name)
                    print("📟 JS LOG: Request to preview default sound: \(soundName)")
                    let nativePreviewStarted = AlarmManager.shared.previewDefault(named: soundName)
                    if !nativePreviewStarted {
                        // fallback: play the page audio once (set volume to app alarm volume first)
                        let vol = AlarmManager.shared.currentAlarmVolume()
                        // Diagnostic JS: set volume/unmute, play, log state and promise outcome
                        let js = """
                        (function(){
                          try {
                            var el = document.getElementById('\(soundName)-sound');
                            if (!el) { console.log('promo-fallback: element not found for \(soundName)-sound'); return; }
                            try { el.muted = false; } catch(e) {}
                            try { el.volume = \(vol); } catch(e) {}
                            el.currentTime = 0;
                            el.loop = false;
                            console.log('promo-fallback: preview -> src=', el.src, 'volume=', el.volume, 'muted=', el.muted, 'paused=', el.paused);
                            var p = el.play();
                            if (p && typeof p.then === 'function') {
                              p.then(function(){ console.log('promo-fallback: preview play resolved, volume=', el.volume); })
                               .catch(function(err){ console.log('promo-fallback: preview play rejected', err); });
                            } else {
                              console.log('promo-fallback: preview play() returned non-promise or undefined');
                            }
                            setTimeout(function(){ try { el.pause(); el.currentTime = 0; console.log('promo-fallback: preview auto-stopped'); } catch(e) { console.log('promo-fallback: preview stop error', e); } }, 3000);
                          } catch(e) {
                            console.log('promo-fallback: preview error', e);
                          }
                        })();
                        """
                        self.webView?.evaluateJavaScript(js, completionHandler: nil)
                        print("📟 JS LOG: Fallback preview to in-page audio for '\(soundName)' (set volume = \(vol))")
                    }
                }

            case let s where s.hasPrefix("PLAY_DEFAULT:"):
                // payload: "PLAY_DEFAULT:<name>" — start/loop alarm playback (native preferred)
                if let name = s.split(separator: ":").last {
                    let soundName = String(name)
                    print("📟 JS LOG: Request to play default sound: \(soundName)")

                    // Persist user-selected default sound so native battery alarms use it
                    UserDefaults.standard.set(soundName, forKey: "preferredAlarmSound")

                    // Defensive suppression: if device is charging (or full) AND the current battery
                    // level is <= configured low threshold, do not start native playback.
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    let deviceLevel = UIDevice.current.batteryLevel
                    let deviceState = UIDevice.current.batteryState
                    let storedLow = Float(UserDefaults.standard.object(forKey: "lowThreshold") as? Double ?? 0.20)
                    if deviceLevel >= 0 && (deviceState == .charging || deviceState == .full) && deviceLevel <= storedLow {
                        print("⛔ JS-initiated PLAY_DEFAULT suppressed: device charging and battery \(Int(deviceLevel * 100))% <= lowThreshold \(Int(storedLow * 100))%")
                        // Inform page (non-fatal)
                        evaluateOrQueue("try { console.log('native: play suppressed while charging'); } catch(e) { }")
                        break
                    }

                    let nativePlayed = AlarmManager.shared.playDefault(named: soundName)
                    if !nativePlayed {
                        // Fallback to in-page audio element (uses remote URL from promo.html)
                        // Set element volume to match app alarm volume, unmute, loop, play, and log diagnostic info
                        let vol = AlarmManager.shared.currentAlarmVolume()
                        let js = """
                        (function(){
                          try {
                            var el = document.getElementById('\(soundName)-sound');
                            if (!el) { console.log('promo-fallback: element not found for \(soundName)-sound'); return; }
                            try { el.muted = false; } catch(e) {}
                            try { el.volume = \(vol); } catch(e) {}
                            el.currentTime = 0;
                            el.loop = true;
                            console.log('promo-fallback: play -> src=', el.src, 'volume=', el.volume, 'muted=', el.muted, 'paused=', el.paused);
                            var p = el.play();
                            if (p && typeof p.then === 'function') {
                              p.then(function(){ console.log('promo-fallback: play resolved, volume=', el.volume); })
                               .catch(function(err){ console.log('promo-fallback: play rejected', err); });
                            } else {
                              console.log('promo-fallback: play() returned non-promise or undefined');
                            }
                            // also log the volume again after a short delay for verification
                            setTimeout(function(){ try { console.log('promo-fallback: after 250ms volume=', el.volume, 'muted=', el.muted, 'paused=', el.paused); } catch(e) {} }, 250);
                          } catch(e) {
                            console.log('promo-fallback: play error', e);
                          }
                        })();
                        """
                        self.webView?.evaluateJavaScript(js, completionHandler: nil)
                        print("📟 JS LOG: Fallback to in-page audio for '\(soundName)' (set volume = \(vol))")
                    }
                }

            case "OPEN_APP_SETTINGS":
                print("🔧 OPEN_APP_SETTINGS requested from JS")
                openAppSettings()
            case "OPEN_CAMERA", "QUICK_OPEN_CAMERA":
                print("🔧 OPEN_CAMERA requested from JS")
                presentCamera()
            case "OPEN_PHOTOS", "QUICK_OPEN_PHOTOS":
                print("🔧 OPEN_PHOTOS requested from JS")
                presentPhotosPicker()
            case "TOGGLE_FLASHLIGHT":
                print("📟 JS LOG: TOGGLE_FLASHLIGHT")
                toggleFlashlight()

            case "START_SOS":
                print("🆘 START_SOS requested from JS")
                // Native confirmation before starting SOS beacon
                if let top = self.topViewController() {
                    // If SOS already running, ignore duplicate start requests and ensure JS state is aligned
                    if sosRunning {
                        print("🔴 START_SOS ignored — SOS already running")
                        evaluateOrQueue("try { if (typeof window.onNativeSosStateChanged === 'function') window.onNativeSosStateChanged(true); } catch(e) { console.warn('native->js callback error', e); }")
                        break
                    }

                    // If a Start alert is already presented, ignore duplicate presentation
                    if let presented = top.presentedViewController, let ac = presented as? UIAlertController, ac.title == "Start SOS Beacon?" {
                        print("⚠️ Start alert already presented — ignoring duplicate")
                        break
                    }

                    let alert = UIAlertController(title: "Start SOS Beacon?", message: "This will flash your torch repeatedly while the app is in the foreground. Continue?", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                    alert.addAction(UIAlertAction(title: "Start", style: .destructive, handler: { [weak self] _ in
                        guard let s = self else { return }
                        s.startSOS()
                        // Notify web UI that native SOS has started (only after native action succeeds)
                        s.evaluateOrQueue("try { if (typeof window.onNativeSosStateChanged === 'function') window.onNativeSosStateChanged(true); } catch(e) { console.warn('native->js callback error', e); }")
                    }))

                    // If a transient context menu or a different alert is presented, dismiss it and then present ours.
                    if let presented = top.presentedViewController {
                        let cls = String(describing: type(of: presented))
                        let isTransient = cls.contains("ContextMenu") || cls.contains("UIContextMenu") || presented is UIAlertController
                        if isTransient {
                            presented.dismiss(animated: false) {
                                top.present(alert, animated: true, completion: nil)
                            }
                        } else {
                            top.present(alert, animated: true, completion: nil)
                        }
                    } else {
                        top.present(alert, animated: true, completion: nil)
                    }
                } else {
                    // Fallback: start immediately if we can't present (shouldn't normally happen)
                    startSOS()
                    // Notify web UI fallback
                    evaluateOrQueue("try { if (typeof window.onNativeSosStateChanged === 'function') window.onNativeSosStateChanged(true); } catch(e) { console.warn('native->js callback error', e); }")
                }

            case "STOP_SOS":
                print("🛑 STOP_SOS requested from JS")
                // Native confirmation before stopping SOS beacon
                if let top = self.topViewController() {
                    let alert = UIAlertController(title: "Stop SOS Beacon?", message: "Stop the SOS beacon and turn off the torch?", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                    alert.addAction(UIAlertAction(title: "Stop", style: .default, handler: { [weak self] _ in
                        guard let s = self else { return }
                        s.stopSOS()
                        // Notify web UI that native SOS has stopped
                        s.evaluateOrQueue("try { if (typeof window.onNativeSosStateChanged === 'function') window.onNativeSosStateChanged(false); } catch(e) { console.warn('native->js callback error', e); }")
                    }))

                    // If a transient alert or context menu is already presented, dismiss it immediately then present ours.
                    if let presented = top.presentedViewController {
                        let cls = String(describing: type(of: presented))
                        let isTransient = cls.contains("ContextMenu") || cls.contains("UIContextMenu") || presented is UIAlertController
                        if isTransient {
                            presented.dismiss(animated: false) {
                                top.present(alert, animated: true, completion: nil)
                            }
                        } else {
                            top.present(alert, animated: true, completion: nil)
                        }
                    } else {
                        top.present(alert, animated: true, completion: nil)
                    }
                } else {
                    // Fallback
                    stopSOS()
                    evaluateOrQueue("try { if (typeof window.onNativeSosStateChanged === 'function') window.onNativeSosStateChanged(false); } catch(e) { console.warn('native->js callback error', e); }")
                }

            case "SOS_SMS":
                print("📟 JS LOG: SOS_SMS requested")
                // Build preview message (device name + battery percent)
                UIDevice.current.isBatteryMonitoringEnabled = true
                let deviceName = UIDevice.current.name
                let batteryPct = Int(max(0, min(1, UIDevice.current.batteryLevel)) * 100)
                let preview = "Help! This is \(deviceName). My battery is \(batteryPct)%. Send this message?"

                // Find a safe presenter (topmost view controller currently on screen)
                guard let basePresenter = self.topViewController() else {
                    // No presenter -> fallback direct open
                    if MFMessageComposeViewController.canSendText() {
                        var comps = URLComponents(string: "sms:")
                        let bodyText = "Help! This is \(deviceName). My battery is \(batteryPct)%. Location: (optional)"
                        comps?.queryItems = [URLQueryItem(name: "body", value: bodyText)]
                        if let url = comps?.url, UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            print("📟 JS LOG: Opened Messages app for SOS SMS (fallback/no-topVC)")
                        } else {
                            print("❌ Could not open Messages app for SOS SMS (fallback/no-topVC)")
                        }
                    } else {
                        print("❌ Device cannot send SMS (no messaging capability)")
                    }
                    break
                }

                // Prevent duplicate alerts/composers: if one is already presented or presentation in-flight, ignore
                if isPresentingMessageComposer {
                    print("⚠️ SMS composer presentation already in progress — ignoring duplicate")
                    break
                }
                if let presented = basePresenter.presentedViewController {
                    if presented is MFMessageComposeViewController {
                        print("⚠️ SMS composer already presented — ignoring duplicate")
                        break
                    }
                    if let ac = presented as? UIAlertController, ac.title == "Send SOS SMS?" {
                        print("⚠️ SOS SMS alert already presented — ignoring duplicate")
                        break
                    }
                }

                // Create native confirm alert
                let alert = UIAlertController(title: "Send SOS SMS?", message: preview, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

                // Send action: present composer in a robust way (topmost presenter, small defer if needed)
                alert.addAction(UIAlertAction(title: "Send", style: .default, handler: { [weak self, weak basePresenter] _ in
                    guard let s = self else { return }

                    // Compose presenter closure to present the message composer or fallback
                    func presentComposer(using presenter: UIViewController) {
                        if MFMessageComposeViewController.canSendText() {
                            let composer = MFMessageComposeViewController()
                            composer.messageComposeDelegate = s
                            composer.recipients = [] // optionally populate
                            composer.body = "Help! This is \(deviceName). My battery is \(batteryPct)%. Location: (optional)"

                            // Present on the topmost presented view controller if one exists
                            var target = presenter
                            while let presented = target.presentedViewController {
                                target = presented
                            }

                            // If the target appears to be a transient context-menu controller, delay slightly to avoid "already presenting" errors
                            let targetClass = String(describing: type(of: target))
                            let needDelay = targetClass.contains("ContextMenu") || targetClass.contains("UIContextMenu")

                            let doPresent = {
                                // mark that we are about to present the composer so duplicates are suppressed
                                s.isPresentingMessageComposer = true
                                target.present(composer, animated: true) {
                                    print("📟 JS LOG: Presented in-app Message composer for SOS SMS")
                                }
                            }

                            if needDelay {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: doPresent)
                            } else {
                                DispatchQueue.main.async(execute: doPresent)
                            }
                        } else {
                            // Fallback to sms: URL if composer not available
                            var comps = URLComponents(string: "sms:")
                            let bodyText = "Help! This is \(deviceName). My battery is \(batteryPct)%. Location: (optional)"
                            comps?.queryItems = [URLQueryItem(name: "body", value: bodyText)]
                            if let url = comps?.url, UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                print("📟 JS LOG: Opened Messages app for SOS SMS (fallback)")
                            } else {
                                print("❌ Could not open Messages app for SOS SMS (fallback)")
                                // Present an on-screen error if possible
                                if let p = basePresenter {
                                    let e = UIAlertController(title: "Error", message: "Unable to open Messages app on this device.", preferredStyle: .alert)
                                    e.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                    DispatchQueue.main.async { p.present(e, animated: true, completion: nil) }
                                }
                            }
                        }
                    }

                    // Use captured basePresenter; choose topmost target to present the alert's follow-on composer
                    if let p = basePresenter {
                        // Resolve the topmost presented controller
                        var presentTarget = p
                        while let presented = presentTarget.presentedViewController {
                            presentTarget = presented
                        }
                        // If the presentTarget is likely a context-menu container, defer slightly then present
                        let tClass = String(describing: type(of: presentTarget))
                        if tClass.contains("ContextMenu") || tClass.contains("UIContextMenu") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                presentComposer(using: presentTarget)
                            }
                        } else {
                            presentComposer(using: presentTarget)
                        }
                    } else {
                        // As a last resort, attempt direct fallback open on main queue
                        DispatchQueue.main.async {
                            var comps = URLComponents(string: "sms:")
                            let bodyText = "Help! This is \(deviceName). My battery is \(batteryPct)%. Location: (optional)"
                            comps?.queryItems = [URLQueryItem(name: "body", value: bodyText)]
                            if let url = comps?.url, UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                print("📟 JS LOG: Opened Messages app for SOS SMS (fallback/no-presenter)")
                            } else {
                                print("❌ Could not open Messages app for SOS SMS (fallback/no-presenter)")
                            }
                        }
                    }
                }))

                // Present the alert on the topmost visible controller (deferring if a transient context menu is active)
                var presenterToUse = basePresenter
                while let presented = presenterToUse.presentedViewController {
                    presenterToUse = presented
                }
                let pClass = String(describing: type(of: presenterToUse))
                if pClass.contains("ContextMenu") || pClass.contains("UIContextMenu") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        presenterToUse.present(alert, animated: true, completion: nil)
                    }
                } else {
                    DispatchQueue.main.async {
                        presenterToUse.present(alert, animated: true, completion: nil)
                    }
                }

            case "REQUEST_MUSIC_PICKER":
                print("🎵 Music picker requested from JavaScript")
                showMusicPicker()
            case "STOP_ALARM":
                print("🛑 Stop alarm requested from JavaScript")
                AlarmManager.shared.stopAlarm()

            case let s where s.hasPrefix("SET_PREFERRED_SOUND:"):
                if let name = s.split(separator: ":").last {
                    let soundName = String(name)
                    UserDefaults.standard.set(soundName, forKey: "preferredAlarmSound")
                    print("📟 JS LOG: SET_PREFERRED_SOUND persisted -> \(soundName)")
                }
            case "START_CUSTOM_ALARM":
                print("🎵 Custom music alarm requested from JS")
                AlarmManager.shared.startAlarm()
            case let s where s.hasPrefix("SET_BRIGHTNESS:"):
                handleSetBrightness(s)
            case "QUICK_APP_LAUNCHER":
                print("🚀 Quick App Launcher requested from JS")
                showQuickAppLauncher()
            case "GET_BATTERY_HEALTH":
                sendBatteryHealthToWebView()
            default:
                // intentionally quiet for generic console logs
                break
            }
        }

        // MARK: - Brightness handler
        private func handleSetBrightness(_ msg: String) {
            let parts = msg.components(separatedBy: ":")
            guard parts.count >= 2, let num = Double(parts[1]) else { return }
            let clamped = max(0.0, min(1.0, num / 100.0))
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                UIScreen.main.brightness = CGFloat(clamped)
                print("💡 Screen brightness set to: \(clamped)")
                self?.postJSLog("log: 💡 Brightness set to: \(Int(round(clamped * 100)))%")
            }
        }

        // MARK: - Battery monitoring & sends
        func startBatteryMonitoring() {
            UIDevice.current.isBatteryMonitoringEnabled = true
            print("🔋 Swift battery monitoring started")

            if let override = UserDefaults.standard.object(forKey: "batteryHealthOverride") {
                print("DEBUG: batteryHealthOverride = \(override)")
            } else {
                print("DEBUG: batteryHealthOverride = none")
            }

            batteryTimer?.invalidate()
            batteryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.sendBatteryLevelToWebView()
                self.sendBatteryHealthToWebView()
            }
        }

        func stopBatteryMonitoring() {
            batteryTimer?.invalidate()
            batteryTimer = nil
            UIDevice.current.isBatteryMonitoringEnabled = false
            print("🔋 Swift battery monitoring stopped")
        }

        private func sendBatteryLevelToWebView() {
            let rawBattery = UIDevice.current.batteryLevel
            let batteryLevel = (rawBattery >= 0) ? Int(round(rawBattery * 100)) : -1
            print("🔋 Raw battery: \(rawBattery), Rounded: \(batteryLevel)%")
            if batteryLevel >= 0 { checkForBackgroundNotification(batteryLevel: batteryLevel) }
            let script = "try { if (typeof updateRealBatteryLevel === 'function') updateRealBatteryLevel(\(batteryLevel)); else console.log('WARN: updateRealBatteryLevel not defined'); } catch(e) { console.log('JSCALL error:', e); }"
            evaluateOrQueue(script)
        }

        private func sendBatteryHealthToWebView() {
            // Ensure battery monitoring is enabled so batteryState is accurate
            UIDevice.current.isBatteryMonitoringEnabled = true

            let device = UIDevice.current
            let batteryState: String
            switch device.batteryState {
            case .charging: batteryState = "Charging"
            case .full: batteryState = "Full"
            case .unplugged: batteryState = "Not Charging"
            case .unknown: batteryState = "Unknown"
            @unknown default: batteryState = "Unknown"
            }

            var healthInt: Int = -1
            #if targetEnvironment(simulator)
            healthInt = 95
            #else
            if let override = UserDefaults.standard.object(forKey: "batteryHealthOverride") as? Int,
               (1...100).contains(override) {
                healthInt = override
            } else if device.batteryLevel >= 0 {
                healthInt = max(50, min(100, Int(device.batteryLevel * 100)))
            } else {
                healthInt = -1
            }
            #endif

            _ = ""
            let script = "try { if (typeof updateBatteryHealth === 'function') updateBatteryHealth('', '\(batteryState)'); else console.log('WARN: updateBatteryHealth not defined'); } catch(e) { console.log('JSCALL error:', e); }"
            evaluateOrQueue(script)
        }

        // MARK: - Notifications
        private func checkForBackgroundNotification(batteryLevel: Int) {
            // If a dedicated BatteryMonitor exists for the app lifecycle, let it be the single source
            // of truth for notifications. This prevents duplicate/erratic banners caused by multiple schedulers.
            if BatteryMonitor.instanceCounter > 0 {
                print("promo.Coordinator: skipping background notification scheduling because BatteryMonitor is active (instanceCounter=\(BatteryMonitor.instanceCounter))")
                return
            }

            let storedLow = UserDefaults.standard.object(forKey: "lowThreshold") as? Double ?? 0.20
            let storedHigh = UserDefaults.standard.object(forKey: "highThreshold") as? Double ?? 0.80
            let lowThreshold = Int(round(storedLow * 100))
            let highThreshold = Int(round(storedHigh * 100))

            print("🔔 Background notification check: \(batteryLevel)% (low=\(lowThreshold)% high=\(highThreshold)%)")

            // Throttle background notifications to avoid spamming the system.
            if let last = lastBackgroundNotificationTs {
                let elapsed = Date().timeIntervalSince(last)
                if elapsed < backgroundNotificationMinInterval {
                    print("⏱️ Suppressed background notification — only \(Int(elapsed))s since last (min \(Int(backgroundNotificationMinInterval))s)")
                    return
                }
            }

            // Require sane thresholds
            if lowThreshold >= highThreshold {
                print("⛔ Skipping background notification — invalid thresholds (low >= high)")
                return
            }

            // Respect charging state: high only when charging/full, low only when not charging
            let deviceState = UIDevice.current.batteryState
            let isCharging = (deviceState == .charging || deviceState == .full)

            if !isCharging && batteryLevel <= lowThreshold {
                NotificationManager.default.scheduleBackgroundNotification(title: "🔋 Battery Low!", body: "Battery is at \(batteryLevel)% - needs charging!", batteryLevel: batteryLevel)
                lastBackgroundNotificationTs = Date()
                print("🚨 LOW battery notification triggered: \(batteryLevel)%")
            } else if isCharging && batteryLevel >= highThreshold {
                NotificationManager.default.scheduleBackgroundNotification(title: "🔋 Battery High!", body: "Battery is at \(batteryLevel)% - high level reached!", batteryLevel: batteryLevel)
                lastBackgroundNotificationTs = Date()
                print("🚨 HIGH battery notification triggered: \(batteryLevel)%")
            }
        }

        // MARK: - Quick App Launcher
        private func showQuickAppLauncher() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let alert = UIAlertController(title: "🚀 Quick App Launcher", message: "Open system apps quickly:", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "📷 Quick Camera", style: .default) { _ in self.openCamera() })
                alert.addAction(UIAlertAction(title: "🖼️ Photos", style: .default) { _ in self.openPhotos() })
                alert.addAction(UIAlertAction(title: "⚙️ Settings", style: .default) { _ in self.openSettings() })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                if let top = self.topViewController() {
                    top.present(alert, animated: true)
                    print("✅ Quick App Launcher shown with actions")
                } else {
                    print("❌ Could not present Quick App Launcher")
                }
            }
        }

        // MARK: - App Settings helpers
        private func openAppSettings() {
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                let url = URL(string: UIApplication.openSettingsURLString)!
                UIApplication.shared.open(url, options: [:]) { success in
                    print(success ? "⚙️ Opened App Settings (from OPEN_APP_SETTINGS)" : "❌ Failed to open App Settings (from OPEN_APP_SETTINGS)")
                }
            }
        }

        private func openSettings() {
            let appSettingsURL = URL(string: UIApplication.openSettingsURLString)!
            #if DEBUG
            // Build the candidate list incrementally so the Swift type-checker doesn't time out
            // during Canvas/Preview compilation (large inline arrays can cause type-check issues).
            var candidateStrings: [String] = []
            candidateStrings.append("App-Prefs:root=BATTERY&path=BATTERY_USAGE")
            candidateStrings.append("App-Prefs:root=BATTERY&path=BATTERY_USAGE/")
            candidateStrings.append("App-Prefs:root=BATTERY&path=BATTERY_HEALTH")
            candidateStrings.append("App-Prefs:root=General&path=USAGE/BATTERY_USAGE")
            candidateStrings.append("App-Prefs:root=General&path=BATTERY")
            candidateStrings.append("App-Prefs:root=BATTERY")
            candidateStrings.append("App-Prefs:root=Battery")
            candidateStrings.append("prefs:root=BATTERY&path=BATTERY_USAGE")
            candidateStrings.append("prefs:root=BATTERY")
            candidateStrings.append("prefs:root=Battery")

            let candidates: [URL] = candidateStrings.compactMap { URL(string: $0) }
            if let usable = candidates.first(where: { UIApplication.shared.canOpenURL($0) }) {
                UIApplication.shared.open(usable, options: [:]) { success in
                    print("⚙️ Opened system settings via (canOpenURL): \(usable.absoluteString) (success: \(success))")
                }
                return
            }
            for (index, url) in candidates.enumerated() {
                let delay = Double(index) * 0.35
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    UIApplication.shared.open(url, options: [:]) { success in
                        print("Attempted open candidate: \(url.absoluteString) (success: \(success))")
                    }
                }
            }
            let finalDelay = Double(candidates.count) * 0.35 + 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
                UIApplication.shared.open(appSettingsURL, options: [:]) { success in
                    print("Final fallback: Opened App Settings (UIApplication.openSettingsURLString) (success: \(success))")
                }
            }
            #else
            UIApplication.shared.open(appSettingsURL, options: [:]) { success in
                print(success ? "⚙️ Opened App Settings (release build - safe)" : "❌ Failed to open App Settings (release build)")
            }
            #endif
        }

        // MARK: - Camera / Photos
        private func presentCamera() {
            DispatchQueue.main.async { [weak self] in guard let s = self else { return }; s.openCamera() }
        }

        private func presentPhotosPicker() {
            DispatchQueue.main.async { [weak self] in
                guard let s = self else { return }

                // Check photo library authorization for read/write (iOS 14+)
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                switch status {
                case .authorized, .limited:
                    // We have at least limited read or full access — open picker
                    s.openPhotos()
                case .notDetermined:
                    // Ask for read/write access (this will show system prompt)
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                        DispatchQueue.main.async {
                            if newStatus == .authorized || newStatus == .limited {
                                s.openPhotos()
                            } else {
                                s.showMessage("Photo library access denied.")
                            }
                        }
                    }
                case .denied, .restricted:
                    // Inform and offer Settings
                    s.showMessage("Photo access is restricted. Open Settings to change photo permissions.")
                @unknown default:
                    s.showMessage("Photo access unavailable.")
                }
            }
        }

        private func openCamera() {
            print("📷 Opening In-App Camera")
            #if targetEnvironment(simulator)
            showMessage("Camera not available in simulator. Please test on a real device.")
            return
            #endif

            DispatchQueue.main.async { [weak self] in
                guard let s = self else { return }
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    print("❌ Camera not available")
                    return
                }
                let imagePicker = UIImagePickerController()
                imagePicker.delegate = s
                imagePicker.sourceType = .camera
                imagePicker.allowsEditing = false
                imagePicker.showsCameraControls = true
                imagePicker.cameraCaptureMode = .photo

                if let top = s.topViewController() {
                    top.present(imagePicker, animated: false) {
                        print("✅ In-app camera presented (fast launch)")
                    }
                } else {
                    print("❌ Could not find top view controller to present camera")
                }
            }
        }
        
        // MARK: - UIImagePickerControllerDelegate (camera capture saving)
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true, completion: nil)
            guard let img = info[.originalImage] as? UIImage else {
                print("❌ No image returned from camera")
                return
            }

            // Keep a reference in case the app wants to use it
            self.lastPickedImage = img
            print("📷 Camera photo captured — attempting to save to Photo Library")

            // Save with appropriate permission flow (iOS 14+)
            if #available(iOS 14, *) {
                let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                switch status {
                case .authorized, .limited:
                    // authorized or limited both allow creating new assets
                    saveImageToLibrary(img)
                case .notDetermined:
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] newStatus in
                        DispatchQueue.main.async {
                            guard let s = self else { return }
                            if newStatus == .authorized || newStatus == .limited {
                                s.saveImageToLibrary(img)
                            } else {
                                s.showMessage("Photo save permission denied.")
                                print("❌ Photo save permission denied (post-request)")
                            }
                        }
                    }
                case .denied, .restricted:
                    showMessage("Photo save permission denied. Open Settings to allow saving photos.")
                    print("❌ Photo save permission denied or restricted")
                @unknown default:
                    showMessage("Photo save permission unavailable.")
                    print("❌ Unknown photo permission status")
                }
            } else {
                // iOS <14: handle legacy authorization API
                let status = PHPhotoLibrary.authorizationStatus()
                switch status {
                case .authorized, .limited:
                    saveImageToLibrary(img)
                case .notDetermined:
                    PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                        DispatchQueue.main.async {
                            guard let s = self else { return }
                            if newStatus == .authorized || newStatus == .limited {
                                s.saveImageToLibrary(img)
                            } else {
                                s.showMessage("Photo save permission denied.")
                                print("❌ Photo save permission denied (post-request - legacy)")
                            }
                        }
                    }
                case .denied, .restricted:
                    showMessage("Photo save permission denied. Open Settings to allow saving photos.")
                    print("❌ Photo save permission denied or restricted (legacy)")
                @unknown default:
                    showMessage("Photo save permission unavailable.")
                    print("❌ Unknown photo permission status (legacy)")
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true, completion: nil)
            print("ℹ️ Camera picker cancelled")
        }

        // Small helper to perform the save on the Photo Library
        private func saveImageToLibrary(_ image: UIImage) {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Saved photo to library")
                        self?.postJSLog("log: Photo saved to library")
                        self?.showMessage("Saved photo to Photo Library")
                    } else {
                        print("❌ Failed to save photo to library: \(error?.localizedDescription ?? "unknown error")")
                        self?.showMessage("Failed to save photo to Photo Library")
                    }
                }
            })
        }

        private func openPhotos() {
                    print("🖼️ Opening In-App Photo Library")
                    DispatchQueue.main.async { [weak self] in
                        guard let s = self else { return }

                        if #available(iOS 14, *) {
                            var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
                            config.filter = .images
                            config.selectionLimit = 0 // 0 -> require explicit Done so user can preview before confirming
                            let picker = PHPickerViewController(configuration: config)
                            picker.delegate = s
                            if var top = s.topViewController() {
                                while let presented = top.presentedViewController {
                                    top = presented
                                }
                                top.present(picker, animated: true) {
                                    print("✅ In-app PHPicker presented")
                                }
                            } else {
                                print("❌ Could not find top view controller to present PHPicker")
                            }
                        } else {
                            // Fallback for older iOS versions: use UIImagePickerController
                            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
                                print("❌ Photo library not available")
                                return
                            }
                            let picker = UIImagePickerController()
                            picker.delegate = s
                            picker.sourceType = .photoLibrary
                            picker.allowsEditing = false
                            if var top = s.topViewController() {
                                while let presented = top.presentedViewController {
                                    top = presented
                                }
                                top.present(picker, animated: true) {
                                    print("✅ In-app UIImagePicker presented (fallback)")
                                }
                            } else {
                                print("❌ Could not find top view controller to present photos picker (fallback)")
                            }
                        }
                    }
                }

        // MARK: - Present in-app battery info
        private func presentBatteryInfo() {
            DispatchQueue.main.async { [weak self] in
                guard let s = self else { return }
                let device = UIDevice.current
                let levelText = device.batteryLevel >= 0 ? "\(Int(round(device.batteryLevel * 100)))%" : "Unknown"
                let stateText: String
                switch device.batteryState {
                case .charging: stateText = "Charging"
                case .full: stateText = "Full"
                case .unplugged: stateText = "Not Charging"
                default: stateText = "Unknown"
                }
                var healthText = "N/A"
                if let ov = UserDefaults.standard.object(forKey: "batteryHealthOverride") as? Int {
                    healthText = "\(ov)% (override)"
                } else if device.batteryLevel >= 0 {
                    healthText = "\(max(50, min(100, Int(device.batteryLevel * 100))))% (estimate)"
                }
                let msg = "Level: \(levelText)\nState: \(stateText)\nHealth: \(healthText)"
                let alert = UIAlertController(title: "Battery Info", message: msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Open System Battery Settings", style: .default) { _ in
                    #if DEBUG
                    s.openSettings()
                    #else
                    s.openAppSettings()
                    #endif
                })
                alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
                if let top = s.topViewController() {
                    top.present(alert, animated: true) {
                        print("✅ Presented BatteryInfo (alert fallback)")
                    }
                } else {
                    print("❌ Could not present Battery Info (no top view controller)")
                }
            }
        }

        // MARK: - Flashlight & SOS prototype
        private func toggleFlashlight() {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let _ = self else { return }
                guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
                    print("❌ Device has no torch")
                    return
                }
                do {
                    try device.lockForConfiguration()
                    if device.torchMode == .on { device.torchMode = .off; print("🔦 Flashlight turned OFF") }
                    else { try device.setTorchModeOn(level: 1.0); print("🔦 Flashlight turned ON") }
                    device.unlockForConfiguration()
                } catch {
                    print("❌ Torch error: \(error)")
                }
            }
        }

        /// Start a foreground SOS prototype: repeated torch on/off + vibration pattern.
        /// NOTE: foreground-only. Stops when stopSOS() is called or app backgrounded.
        func startSOS() {
            DispatchQueue.main.async { [weak self] in
                guard let s = self else { return }
                if s.sosRunning {
                    print("🔴 SOS already running")
                    return
                }
                s.sosRunning = true
                s.sosPatternIndex = 0

                // Build a proper Morse SOS pattern programmatically (unit = 0.24s)
                let unit: TimeInterval = 0.24
                let dotOn = unit
                let dashOn = 3.0 * unit
                let intraGap = unit            // gap between elements of same letter
                let letterGap = 3.0 * unit     // gap between letters
                let sequenceGap: TimeInterval = 1.5 // gap between repeated SOS sequences

                // Build the alternating ON/OFF durations array for one SOS sequence.
                // pattern is [on, off, on, off, ...] starting with ON.
                var pattern: [TimeInterval] = []

                func appendElement(onDuration: TimeInterval) {
                    // ON duration
                    pattern.append(onDuration)
                    // OFF duration (intra-element gap by default)
                    pattern.append(intraGap)
                }

                // S: dot dot dot
                appendElement(onDuration: dotOn)
                appendElement(onDuration: dotOn)
                appendElement(onDuration: dotOn)
                // replace last intra-gap with letter gap
                if !pattern.isEmpty { pattern[pattern.count - 1] = letterGap }

                // O: dash dash dash
                appendElement(onDuration: dashOn)
                appendElement(onDuration: dashOn)
                appendElement(onDuration: dashOn)
                // replace last intra-gap with letter gap
                if !pattern.isEmpty { pattern[pattern.count - 1] = letterGap }

                // S: dot dot dot (final)
                appendElement(onDuration: dotOn)
                appendElement(onDuration: dotOn)
                appendElement(onDuration: dotOn)
                // replace final intra-gap with sequence gap so repeats have a pause
                if !pattern.isEmpty { pattern[pattern.count - 1] = sequenceGap }

                func runStep() {
                    guard let s = self, s.sosRunning else { return }
                    // Protect index range
                    let safeIdx = s.sosPatternIndex % pattern.count
                    let isOn = (safeIdx % 2) == 0

                    if isOn {
                        // Turn torch ON (best-effort)
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
                                do {
                                    try device.lockForConfiguration()
                                    try device.setTorchModeOn(level: 1.0)
                                    device.unlockForConfiguration()
                                } catch {
                                    print("❌ Torch SOS error (ON): \(error)")
                                }
                            }
                        }
                    } else {
                        // Turn torch OFF
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
                                do {
                                    try device.lockForConfiguration()
                                    device.torchMode = .off
                                    device.unlockForConfiguration()
                                } catch {
                                    print("❌ Torch SOS error (OFF): \(error)")
                                }
                            }
                        }
                    }

                    // advance index and schedule next step
                    s.sosPatternIndex = (safeIdx + 1) % pattern.count
                    let delay = pattern[safeIdx]
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        runStep()
                    }
                }

                print("🆘 SOS started (foreground prototype)")
                runStep()
            }
        }

        /// Stop the SOS prototype and ensure torch is off.
        func stopSOS() {
            DispatchQueue.main.async { [weak self] in
                guard let s = self else { return }
                s.sosRunning = false
                // ensure torch is off
                DispatchQueue.global(qos: .userInitiated).async {
                    if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
                        do {
                            try device.lockForConfiguration()
                            device.torchMode = .off
                            device.unlockForConfiguration()
                        } catch {
                            print("❌ Torch SOS stop error: \(error)")
                        }
                    }
                }
                print("🛑 SOS stopped")
            }
        }

        // MARK: - Music picker
        private func showMusicPicker() {
            print("🎵 Showing music picker")
            let status = MPMediaLibrary.authorizationStatus()
            switch status {
            case .authorized:
                presentMusicPicker()
            case .notDetermined:
                MPMediaLibrary.requestAuthorization { [weak self] newStatus in
                    DispatchQueue.main.async { [weak self] in
                        guard let s = self else { return }
                        if newStatus == .authorized { s.presentMusicPicker() } else { print("❌ Music library permission denied"); s.showPermissionDeniedAlert() }
                    }
                }
            case .denied, .restricted:
                print("❌ Music library access denied or restricted")
                showPermissionDeniedAlert()
            @unknown default:
                print("❌ Unknown authorization status")
            }
        }

        private func presentMusicPicker() {
            guard var top = topViewController() else { print("❌ Could not find root view controller"); return }
            while let presented = top.presentedViewController { top = presented }
            let picker = MPMediaPickerController(mediaTypes: .music)
            picker.allowsPickingMultipleItems = false
            picker.delegate = self
            picker.prompt = "Choose Alarm Sound"
            top.present(picker, animated: true) { print("🎵 Music picker was presented") }
        }

        @available(iOS 14, *)
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true, completion: nil)
            guard let first = results.first else {
                print("ℹ️ No photo selected")
                return
            }
            if first.itemProvider.canLoadObject(ofClass: UIImage.self) {
                first.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    if let err = error {
                        print("❌ PHPicker load error: \(err)")
                        return
                    }
                    guard let img = object as? UIImage else { return }
                    DispatchQueue.main.async {
                        self?.lastPickedImage = img
                        print("✅ Photo selected via PHPicker")

                        // Present system share/activity sheet so the user can use built-in actions
                        guard let top = self?.topViewController() else {
                            print("❌ Could not find top view controller to present activity sheet")
                            return
                        }
                        let activity = UIActivityViewController(activityItems: [img], applicationActivities: nil)
                        // For iPad/popover safety
                        if let pop = activity.popoverPresentationController {
                            pop.sourceView = top.view
                            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                        }
                        top.present(activity, animated: true) {
                            print("✅ Presented UIActivityViewController for selected image")
                        }

                        // (Optional) If you still want to notify JS of the selection, uncomment below:
                        /*
                        if let jpeg = img.jpegData(compressionQuality: 0.7) {
                            let b64 = jpeg.base64EncodedString()
                            let dataURL = "data:image/jpeg;base64,\(b64)"
                            let escaped = dataURL.replacingOccurrences(of: "'", with: "\\'")
                            let js = "try { if (typeof onNativeImageSelected === 'function') onNativeImageSelected('\(escaped)'); else console.log('WARN: onNativeImageSelected not defined'); } catch(e) { console.log('JSCALL error:', e); }"
                            self?.evaluateOrQueue(js)
                            print("✅ (Optional) Notified JS about selected image (data URL length: \(b64.count))")
                        }
                        */
                    }
                }
            } else {
                print("❌ Selected item is not a UIImage")
            }
        }
        
        // MARK: - MFMessageComposeViewControllerDelegate
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) { [weak self] in
                guard let s = self else { return }
                // Clear the presenting flag so future SMS requests can proceed
                s.isPresentingMessageComposer = false

                switch result {
                case .cancelled:
                    print("📟 SMS composer cancelled")
                case .sent:
                    print("📟 SMS sent")
                case .failed:
                    print("❌ SMS failed to send")
                @unknown default:
                    print("📟 SMS composer unknown result")
                }
            }
        }


        private func showPermissionDeniedAlert() {
            guard let top = topViewController() else { return }
            let alert = UIAlertController(title: "Music Access Required", message: "Please enable music library access in Settings to choose custom alarm sounds.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            top.present(alert, animated: true)
        }

        // MARK: - Utility
        private func topViewController() -> UIViewController? {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?.rootViewController
        }

        private func showMessage(_ message: String) {
            DispatchQueue.main.async { [weak self] in
                guard let s = self else { return }
                let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                if let top = s.topViewController() { top.present(alert, animated: true) }
            }
        }

        @objc private func batteryStateOrLevelChanged(_ notification: Notification) {
            // When battery state or level changes, push both pieces of information to the page
            // so the promo.html label can update reliably.
            // Use the existing helpers to send level and health/state to the web view.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Send level then health/state — JS can update UI accordingly.
                self.sendBatteryLevelToWebView()
                self.sendBatteryHealthToWebView()
                print("🔔 batteryStateOrLevelChanged: forwarded level+state to webview")
            }
        }

        private func postJSLog(_ text: String) {
            DispatchQueue.main.async { [weak self] in
                guard let s = self else { return }
                // Escape single quotes for JS safely, then use a raw string to embed it
                let escaped = text.replacingOccurrences(of: "'", with: "\\'")
                let safe = #"console.log('\#(escaped)')"#
                s.webView?.evaluateJavaScript(safe, completionHandler: nil)
            }
        }
    }
}

#if DEBUG
struct PromoWebView_Previews: PreviewProvider {
    static var previews: some View {
        PromoWebView()
            .edgesIgnoringSafeArea(.all)
            .previewDevice(PreviewDevice(rawValue: "iPhone 17 Pro"))
            .previewDisplayName("PromoWebView - iPhone 17 Pro")
    }
}
#endif
