// Flashlight control
private func toggleFlashlight() {
    guard let device = AVCaptureDevice.default(for: .video) else {
        print("❌ No camera device available for flashlight")
        return
    }
    
    if device.hasTorch {
        do {
            try device.lockForConfiguration()
            
            if device.torchMode == .on {
                device.torchMode = .off
                print("🔦 Flashlight turned OFF")
            } else {
                try device.setTorchModeOn(level: 1.0)
                print("🔦 Flashlight turned ON")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ Flashlight error: \(error.localizedDescription)")
        }
    } else {
        print("❌ Device has no flashlight")
    }
}
import SwiftUI
import WebKit
import MediaPlayer
import AVFoundation

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
              window.webkit.messageHandlers.jsLogger.postMessage(method + ": " + args.join(" "));
              original.apply(console, args);
            };
          }
          ['log', 'warn', 'error'].forEach(wrapConsole);

          window.onerror = function(msg, url, line, col, error) {
            window.webkit.messageHandlers.jsLogger.postMessage("JS ERROR: " + msg + " at " + url + ":" + line + ":" + col);
          };
        })();
        """
        let script = WKUserScript(source: jsBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(script)
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView  // Store reference for battery updates
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

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No dynamic updates required
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            if let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https",
               navigationAction.navigationType == .linkActivated {

                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                print("🌐 External link opened in Safari: \(url.absoluteString)")
                return
            }

            decisionHandler(.allow)
        }
        
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "jsLogger", let log = message.body as? String {
                print("📟 JS LOG: \(log)")
                
                // If JavaScript reports battery mode change, start/stop Swift monitoring
                if log.contains("Battery mode: REAL") {
                    startBatteryMonitoring()
                } else if log.contains("Battery mode: SIMULATION") {
                    stopBatteryMonitoring()
                }
                // Handle music picker request
                else if log == "REQUEST_MUSIC_PICKER" {
                    print("🎵 Music picker requested from JavaScript")
                    showMusicPicker()
                }
                else if log == "STOP_ALARM" {
                    print("🛑 Stop alarm requested from JavaScript")
                    AlarmManager.shared.stopAlarm()
                }
                else if log == "START_CUSTOM_ALARM" {
                    print("🎵 Custom music alarm requested from JS")
                    AlarmManager.shared.startAlarm()
                }
                else if log.hasPrefix("SET_BRIGHTNESS:") {
                    let brightnessString = log.replacingOccurrences(of: "SET_BRIGHTNESS:", with: "")
                    if let brightness = Float(brightnessString) {
                        let normalizedBrightness = max(0.0, min(1.0, brightness / 100.0))
                        DispatchQueue.main.async {
                            UIScreen.main.brightness = CGFloat(normalizedBrightness)
                            print("💡 Screen brightness set to: \(normalizedBrightness)")
                        }
                    }
                }
                else if log == "TOGGLE_FLASHLIGHT" {
                    print("🔦 Toggling flashlight")
                    toggleFlashlight()
                }
                else if log == "SHOW_BATTERY_HEALTH_ALERT" {
                    print("🔋 Showing battery health alert from JS")
                    showBatteryHealthAlert()
                }
                else if log == "QUICK_APP_LAUNCHER" {
                    print("🚀 Quick App Launcher requested from JS")
                    showQuickAppLauncher()
                }
                
                
            }
        }
        
        // Flashlight control
        private func toggleFlashlight() {
            guard let device = AVCaptureDevice.default(for: .video) else {
                print("❌ No camera device available for flashlight")
                return
            }
            
            if device.hasTorch {
                do {
                    try device.lockForConfiguration()
                    
                    if device.torchMode == .on {
                        device.torchMode = .off
                        print("🔦 Flashlight turned OFF")
                    } else {
                        try device.setTorchModeOn(level: 1.0)
                        print("🔦 Flashlight turned ON")
                    }
                    
                    device.unlockForConfiguration()
                } catch {
                    print("❌ Flashlight error: \(error.localizedDescription)")
                }
            } else {
                print("❌ Device has no flashlight")
            }
        }
        
        // Quick App Launcher
        // Quick App Launcher
        private func showQuickAppLauncher() {
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "🚀 Quick App Launcher",
                    message: "Open system apps quickly:",
                    preferredStyle: .alert
                )
                
                // Camera Action
                alert.addAction(UIAlertAction(title: "📷 Quick Camera", style: .default) { _ in
                    self.openCamera()
                })
                
                // Photos Action
                alert.addAction(UIAlertAction(title: "🖼️ Photos", style: .default) { _ in
                    self.openPhotos()
                })
                
                // Settings Action
                alert.addAction(UIAlertAction(title: "⚙️ Settings", style: .default) { _ in
                    self.openSettings()
                })
                
                // Cancel Action
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                
                // Find the top view controller to present the alert
                if let topController = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    
                    var presentingController = topController
                    while let presented = presentingController.presentedViewController {
                        presentingController = presented
                    }
                    presentingController.present(alert, animated: true)
                    print("✅ Quick App Launcher shown with actions")
                }
            }
        }
        
        // Device Information Dashboard
        private func showDeviceInfo() {
            let device = UIDevice.current
            let screen = UIScreen.main
            
            let info = """
            📱 Device Information:
            
            Device: \(device.model)
            System: \(device.systemName) \(device.systemVersion)
            Screen: \(Int(screen.bounds.width))x\(Int(screen.bounds.height)) @ \(screen.scale)x
            Battery: \(Int(device.batteryLevel * 100))%
            
            This app: Battery Alarm
            Version: 1.0
            """
            
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "Device Info",
                    message: info,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                if let topController = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    
                    var presentingController = topController
                    while let presented = presentingController.presentedViewController {
                        presentingController = presented
                    }
                    presentingController.present(alert, animated: true)
                    print("✅ Device info shown")
                }
            }
        }
        
        

        // Open Camera - Optimized for Speed
        private func openCamera() {
            print("📷 Opening In-App Camera")
            
            #if targetEnvironment(simulator)
            // Simulator doesn't have camera
            showMessage("Camera not available in simulator. Please test on a real device.")
            return
            #endif
            
            // Pre-load the image picker on background thread for faster launch
            DispatchQueue.global(qos: .userInitiated).async {
                let imagePicker = UIImagePickerController()
                imagePicker.delegate = self
                imagePicker.sourceType = .camera
                imagePicker.allowsEditing = false
                imagePicker.showsCameraControls = true
                imagePicker.cameraCaptureMode = .photo
                
                // Switch to main thread to present
                DispatchQueue.main.async {
                    if let topController = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows })
                        .first(where: { $0.isKeyWindow })?.rootViewController {
                        
                        var presentingController = topController
                        while let presented = presentingController.presentedViewController {
                            presentingController = presented
                        }
                        
                        // Present immediately without animation for speed
                        presentingController.present(imagePicker, animated: false) {
                            print("✅ In-app camera presented (fast launch)")
                        }
                    }
                }
            }
        }

        // Open Photos - In-App Version
        private func openPhotos() {
            print("🖼️ Opening In-App Photo Library")
            
            DispatchQueue.main.async {
                let imagePicker = UIImagePickerController()
                imagePicker.delegate = self
                imagePicker.sourceType = .photoLibrary
                imagePicker.allowsEditing = false
                
                // Find the top view controller to present the photo library
                if let topController = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    
                    var presentingController = topController
                    while let presented = presentingController.presentedViewController {
                        presentingController = presented
                    }
                    presentingController.present(imagePicker, animated: true)
                    print("✅ In-app photo library presented")
                }
            }
        }

        

        // Open Settings
        private func openSettings() {
            print("⚙️ Opening Settings")
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }

        // Helper to show messages
        private func showMessage(_ message: String) {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                if let topController = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    
                    var presentingController = topController
                    while let presented = presentingController.presentedViewController {
                        presentingController = presented
                    }
                    presentingController.present(alert, animated: true)
                }
            }
        }
        
        // Battery Health Alert Display
        private func showBatteryHealthAlert() {
            let device = UIDevice.current
            
            // Get battery state
            let batteryState: String
            switch device.batteryState {
            case .charging:
                batteryState = "Charging"
            case .full:
                batteryState = "Full"
            case .unplugged:
                batteryState = "Not Charging"
            case .unknown:
                batteryState = "Unknown"
            @unknown default:
                batteryState = "Unknown"
            }
            
            // Mock battery health (for App Store compliance)
            #if targetEnvironment(simulator)
            let health = 95
            #else
            let health = max(80, min(100, 100 - (2024 - 2023))) // Simple mock
            #endif
            
            let batteryLevel = Int(device.batteryLevel * 100)
            
            // Create alert message
            let message = "Battery Level: \(batteryLevel)%\nBattery Health: \(health)%\nCharging State: \(batteryState)"
            
            // Show native iOS alert instead of JavaScript alert
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "🔋 Battery Information",
                    message: message,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                // Find the top view controller to present the alert
                if let topController = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    
                    var presentingController = topController
                    while let presented = presentingController.presentedViewController {
                        presentingController = presented
                    }
                    presentingController.present(alert, animated: true)
                    print("✅ Battery health alert shown natively")
                }
            }
        }
        
        // Battery health information - FIXED DATA SENDING
        private func sendBatteryHealthToWebView() {
            let device = UIDevice.current
            
            // Battery state
            let batteryState: String
            switch device.batteryState {
            case .charging:
                batteryState = "Charging"
            case .full:
                batteryState = "Full"
            case .unplugged:
                batteryState = "Not Charging"
            case .unknown:
                batteryState = "Unknown"
            @unknown default:
                batteryState = "Unknown"
            }
            
            // For simulator, provide mock data
            #if targetEnvironment(simulator)
            let health = 95 // Mock health for simulator
            #else
            // Note: Actual battery health requires private API
            // For App Store compliance, we'll use mock/estimated data
            let health = max(80, min(100, 100 - (2024 - 2023))) // Simple mock
            #endif
            
            // FIXED: Use proper JavaScript function call
            let script = "updateBatteryHealth('\(health)', '\(batteryState)')"
            
            webView?.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("❌ Failed to send battery health: \(error)")
                } else {
                    print("✅ Battery health sent to JS: \(health)%, State: \(batteryState)")
                }
            }
        }
        
        private func showMusicPicker() {
            print("🎵 Showing music picker")
            
            // Check music library authorization status first
            let status = MPMediaLibrary.authorizationStatus()
            print("🎵 Music library authorization status: \(status.rawValue)")
            
            switch status {
            case .authorized:
                print("🎵 Music library access authorized")
                presentMusicPicker()
            case .notDetermined:
                print("🎵 Requesting music library permission")
                MPMediaLibrary.requestAuthorization { newStatus in
                    DispatchQueue.main.async {
                        print("🎵 Permission request completed: \(newStatus.rawValue)")
                        if newStatus == .authorized {
                            self.presentMusicPicker()
                        } else {
                            print("❌ Music library permission denied")
                            // Show alert to user
                            self.showPermissionDeniedAlert()
                        }
                    }
                }
            case .denied, .restricted:
                print("❌ Music library access denied or restricted")
                self.showPermissionDeniedAlert()
            @unknown default:
                print("❌ Unknown authorization status")
            }
        }

        private func presentMusicPicker() {
            print("🎵 Presenting music picker")
            
            // Find the top-most presented view controller
            guard var topController = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController else {
                print("❌ Could not find root view controller")
                return
            }
            
            // Traverse to the top-most presented view controller
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            
            // Create and present the picker
            let picker = MPMediaPickerController(mediaTypes: .music)
            picker.allowsPickingMultipleItems = false
            picker.delegate = self
            picker.prompt = "Choose Alarm Sound"
            
            topController.present(picker, animated: true)
            print("🎵 Music picker was presented")
        }

        private func showPermissionDeniedAlert() {
            guard let topController = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController else {
                return
            }
            
            let alert = UIAlertController(
                title: "Music Access Required",
                message: "Please enable music library access in Settings to choose custom alarm sounds.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            topController.present(alert, animated: true)
        }

        private func startBatteryMonitoring() {
            // Start monitoring device battery
            UIDevice.current.isBatteryMonitoringEnabled = true
            print("🔋 Swift battery monitoring started")
            
            // Send initial battery level
            sendBatteryLevelToWebView()
            
            // Set up periodic updates (every 10 seconds)
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                self.sendBatteryLevelToWebView()
            }
        }

        private func stopBatteryMonitoring() {
            UIDevice.current.isBatteryMonitoringEnabled = false
            print("🔋 Swift battery monitoring stopped")
        }
        
        private func checkForBackgroundNotification(batteryLevel: Int) {
            print("🔔 Background notification check: \(batteryLevel)%")
            
            // Use the Swift battery level directly for notifications
            // This ensures notifications match what iOS reports, not what JavaScript displays
            let lowThreshold = 20
            let highThreshold = 80
            
            // Trigger notifications based on Swift's battery reading
            if batteryLevel <= lowThreshold {
                NotificationManager.default.scheduleBackgroundNotification(
                    title: "🔋 Battery Low!",
                    body: "Battery is at \(batteryLevel)% - needs charging!"
                )
                print("🚨 LOW battery notification triggered: \(batteryLevel)%")
            } else if batteryLevel >= highThreshold {
                NotificationManager.default.scheduleBackgroundNotification(
                    title: "🔋 Battery High!",
                    body: "Battery is at \(batteryLevel)% - high level reached!"
                )
                print("🚨 HIGH battery notification triggered: \(batteryLevel)%")
            }
        }
            
        private func sendBatteryLevelToWebView() {
            let rawBattery = UIDevice.current.batteryLevel
            let batteryLevel = Int(round(rawBattery * 100))
            print("🔋 Raw battery: \(rawBattery), Rounded: \(batteryLevel)%")
            
            // Check for background notification triggers
            checkForBackgroundNotification(batteryLevel: batteryLevel)
            
            let script = "updateRealBatteryLevel(\(batteryLevel))"
            
            webView?.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("❌ Failed to send battery level to web view: \(error)")
                } else {
                    print("✅ Sent real battery level to web view: \(batteryLevel)%")
                }
            }
            
            // Also send battery health info when level updates
            sendBatteryHealthToWebView()
        }
    }
}

// MARK: - MPMediaPickerControllerDelegate
extension PromoWebView.Coordinator: MPMediaPickerControllerDelegate {
    func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
        print("🎵 Music picker: didPickMediaItems called")
        
        if let mediaItem = mediaItemCollection.items.first {
            print("🎵 Selected song: \(mediaItem.title ?? "Unknown")")
            
            // Get the song's URL and send it to AlarmManager
            if let url = mediaItem.assetURL {
                print("🎵 Song URL obtained: \(url)")
                
                // Store the song in AlarmManager
                AlarmManager.shared.setCustomAlarmSong(url: url)
                
                // Update JavaScript to show custom selection and song name
                let script = """
                document.getElementById('sound-select').value = 'custom';
                console.log('Custom song selected and stored: \(mediaItem.title ?? "Unknown")');
                """
                webView?.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        print("❌ Failed to update sound selection: \(error)")
                    } else {
                        print("✅ Sound selection updated to custom")
                    }
                }
            } else {
                print("❌ Could not get song URL - may be DRM protected")
                // Show alert to user
                let alertScript = "alert('This song cannot be used as an alarm. Please choose a different song from your personal library.');"
                webView?.evaluateJavaScript(alertScript)
            }
        }
        
        // Dismiss the picker
        mediaPicker.dismiss(animated: true) {
            print("🎵 Music picker dismissed after selection")
        }
    }
}

// MARK: - UIImagePickerControllerDelegate & UINavigationControllerDelegate
extension PromoWebView.Coordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        print("📷 Photo taken or selected from library")
        
        // Silently save the photo to camera roll
        if picker.sourceType == .camera {
            if let image = info[.originalImage] as? UIImage {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                print("✅ Photo saved to camera roll silently")
            }
        }
        
        // Dismiss immediately without any prompts
        picker.dismiss(animated: true) {
            print("✅ Camera dismissed - back to main app")
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        print("❌ Camera cancelled")
        picker.dismiss(animated: true)
    }
}
