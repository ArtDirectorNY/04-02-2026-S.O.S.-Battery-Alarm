// VolumeScriptMessageHandler.swift
// Small, focused WKScriptMessageHandler to accept `setSystemVolume` messages from the web page
// and update the system volume. Also exposes a helper to push current volume back to the web view.
//
import Foundation
import WebKit
import MediaPlayer
import AVFoundation
import UIKit

final class VolumeScriptMessageHandler: NSObject, WKScriptMessageHandler {
    // weak reference to avoid retain cycles
    private weak var webView: WKWebView?
    private let volumeViewHost: UIView

    init(webView: WKWebView) {
        self.webView = webView
        // host view for MPVolumeView (off-screen / zero sized)
        self.volumeViewHost = UIView(frame: .zero)
        super.init()
        // debug: confirm handler attached
        print("🔊 VolumeScriptMessageHandler initialized and attached to webView")
        // add the hidden MPVolumeView to the app window (kept off-screen)
        self.attachHiddenVolumeView()
    }

    deinit {
        // remove MPVolumeView host if still present
        DispatchQueue.main.async { [weak self] in
            self?.volumeViewHost.removeFromSuperview()
        }
    }

    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "setSystemVolume" else { return }

        // Expecting body like { value: 0.0 } (normalized 0.0 - 1.0)
        if let body = message.body as? [String: Any],
           let raw = body["value"] as? Double {
            let normalized = max(0.0, min(1.0, raw))
            setSystemVolume(normalized)
        } else if let raw = message.body as? Double {
            // fallback if message is sent as numeric value directly
            let normalized = max(0.0, min(1.0, raw))
            setSystemVolume(normalized)
        } else {
            // unexpected payload - ignore silently
            return
        }
    }

    // MARK: - Set system volume using MPVolumeView's internal slider
    private func setSystemVolume(_ normalized: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // debug: log the normalized volume request
            print("🔊 setSystemVolume called with normalized:", normalized)
            let target = Float(normalized)

            // Helper that tries to update a slider and send the events the system expects
            func updateSliderAndFireEvents(_ slider: UISlider) {
                // set value without animation
                slider.setValue(target, animated: false)
                // Send both valueChanged and touchUpInside — combination more reliable on device
                slider.sendActions(for: .valueChanged)
                slider.sendActions(for: .touchUpInside)
            }

            // Try to find an existing UISlider inside the host
            if let slider = self.volumeViewHost.subviews
                .compactMap({ $0 as? UISlider })
                .first {
                updateSliderAndFireEvents(slider)
            } else {
                // No slider found — create a temporary MPVolumeView, add it to the host, find its slider, update it, then remove.
                // This ensures a concrete slider instance exists in the view hierarchy and receives events.
                let tmp = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 160, height: 30))
                tmp.showsRouteButton = false
                tmp.showsVolumeSlider = true
                tmp.alpha = 0.001
                self.volumeViewHost.addSubview(tmp)
                tmp.layoutIfNeeded()

                if let tmpSlider = tmp.subviews.compactMap({ $0 as? UISlider }).first {
                    updateSliderAndFireEvents(tmpSlider)
                } else {
                    // As a last resort try KVC set (best-effort; avoid unless needed)
                    tmp.setValue(target, forKey: "volume")
                }

                // Remove temporary MPVolumeView after a tiny delay so the system has time to register the change.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    tmp.removeFromSuperview()
                }
            }

            // After setting native volume, reflect the new value back into the web UI
            if let webView = self.webView {
                let js = "if (typeof window.setNativeVolume === 'function') { window.setNativeVolume(\(normalized)); }"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    // Attach an MPVolumeView inside a tiny off-screen host view and insert into the app's key window
        private func attachHiddenVolumeView() {
            DispatchQueue.main.async {
                // create MPVolumeView and add to host
                let mp = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 160, height: 30))
                // Keep it present in the view hierarchy but nearly invisible (avoid isHidden = true)
                mp.isHidden = false
                mp.alpha = 0.001
                mp.showsRouteButton = false
                mp.showsVolumeSlider = true
                mp.tintColor = nil

                // Add mp to the host and keep the host just offscreen (but in-window)
                // so the control is part of the view hierarchy and the OS accepts UIControl events.
                self.volumeViewHost.addSubview(mp)
                self.volumeViewHost.frame = CGRect(x: -1, y: -1, width: 1, height: 1)

                // Find a key window in a way compatible with multiple iOS versions (use connectedScenes)
                if let keyWindow = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow }) {
                    keyWindow.addSubview(self.volumeViewHost)
                    print("🔊 MPVolumeView host added to key window (connectedScenes)")
                    return
                }

                // Fallback: try the deprecated route as last resort (kept for compatibility)
                if let w = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                    w.addSubview(self.volumeViewHost)
                    print("🔊 MPVolumeView host added to key window (fallback UIApplication.shared.windows)")
                    return
                }

                // Final fallback: attempt app delegate window (legacy)
                if let appWin = (UIApplication.shared.delegate?.window ?? nil) as? UIWindow {
                    appWin.addSubview(self.volumeViewHost)
                    print("🔊 MPVolumeView host added to app delegate window (final fallback)")
                    return
                }

                print("❌ Could not add MPVolumeView host to any window")
            }
        }

    // MARK: - Helper to push current device volume into the web view
    // Call this after the web page finishes loading to synchronize UI
    static func setCurrentVolumeOnWebView(_ webView: WKWebView) {
        DispatchQueue.main.async {
            // Ensure audio session is active to read outputVolume reliably
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                // ignore if cannot activate
            }
            let vol = AVAudioSession.sharedInstance().outputVolume // 0.0 - 1.0
            let js = "if (typeof window.setNativeVolume === 'function') { window.setNativeVolume(\(vol)); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
