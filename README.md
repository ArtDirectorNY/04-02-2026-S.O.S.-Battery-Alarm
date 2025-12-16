EarthDay365_Battery_Alarm (AiBatteryAlarmClean)
Short description This project displays a web-based promo UI inside a WKWebView and provides native alarm scheduling/playback integrated with JavaScript. It supports background notifications, native audio playback, and user interactions (camera, photos, SOS SMS). The repo here is the working copy; recent fixes (Dec 2025) focus on notification suppression and reliable plug/unplug behavior.

How to reproduce the suppression issue

Open the app and set low/high thresholds.
Background the app and wait until a battery threshold is reached (or trigger PLAY_DEFAULT from the page).
Plug the device into power while the alarm is active.
Expected: alarm stops and pending/delivered notifications are removed; suppression should prevent immediate re-scheduling. Observed: banner may remain visible on some iOS versions.
Files of interest

PromoWebView.swift — WKWebView coordinator, JS bridge, suppression & resume logic
promo.js — front-end UI, threshold slider logic, posts SET_THRESHOLDS / PLAY_DEFAULT / PREVIEW_DEFAULT messages to native
NotificationManager.swift — encapsulates local notification scheduling and dedupe logic
AlarmManager.swift — native audio playback wrapper (AVAudioSession / AVPlayer)
Logs & notes

See logs/plug_unplug.log for the recorded session and recent console output.
How you can help

If you can run the app and paste the console logs for a plug/unplug sequence we will iterate quickly.
