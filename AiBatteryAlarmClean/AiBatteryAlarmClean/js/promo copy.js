//promo.js
let musicPickerOpen = false;
let alarmActive = false;
let lastTriggeredLevel = null;
let currentlyPlaying = null;
let batteryLevel = 50;
let adsRemoved = false;
let customAudio = null;
let useRealBattery = false;
let realBatteryLevel = 50;
let monitoringPaused = false;
let batteryHealth = "--";
let chargingState = "--";

const batteryDisplay = document.getElementById("battery-percent");
const batteryBar = document.getElementById("battery-bar");
const lowInput = document.getElementById("low-threshold");
const highInput = document.getElementById("high-threshold");
const lowDisplay = document.getElementById("low-display");
const highDisplay = document.getElementById("high-display");
const soundSelect = document.getElementById("sound-select");

// Sound map for 4 working sounds
const soundMap = {
  slide_whistle: document.getElementById("slide_whistle-sound"),
  default: document.getElementById("default-sound"),
  alarm_clock: document.getElementById("alarm_clock-sound"),
  boing: document.getElementById("boing-sound")
};

// --- enforceAndPlayElement helper: stronger enforcement for iOS WKWebView fallback audio ---
function enforceAndPlayElement(el, loop) {
    try {
        if (!el) return;
        // Best-effort attributes
        try { el.crossOrigin = 'anonymous'; } catch (e) {}
        try { el.preload = 'auto'; } catch (e) {}

        // Desired app volume (normalized 0.0 - 1.0)
        const desired = (typeof window.__appAlarmVolume !== 'undefined') ? window.__appAlarmVolume : null;

        // Apply desired volume immediately and defensively set mute for zero volume
        function applyDesired() {
            try {
                if (desired !== null) {
                    try { el.volume = desired; } catch (e) {}
                    try { el.muted = (desired === 0); } catch (e) {}
                }
            } catch (e) {}
        }

        // Initial setup
        try { el.loop = !!loop; } catch (e) {}
        try { el.currentTime = 0; } catch (e) {}
        applyDesired();

        // Event handlers to re-apply desired volume during lifecycle
        const onLoaded = function() { applyDesired(); el.removeEventListener('loadedmetadata', onLoaded); };
        const onPlaying = function() {
            applyDesired();
            // reinforce after short delays too
            setTimeout(applyDesired, 250);
            setTimeout(applyDesired, 600);
            el.removeEventListener('playing', onPlaying);
        };
        const onVolumeChange = function() {
            // if browser changes volume away from desired, put it back
            if (desired !== null && Math.abs((el.volume || 0) - desired) > 0.02) {
                try { el.volume = desired; } catch (e) {}
            }
        };

        el.addEventListener('loadedmetadata', onLoaded);
        el.addEventListener('playing', onPlaying);
        el.addEventListener('volumechange', onVolumeChange);

        // Reinforce repeatedly for up to ~1.5s to catch late resets
        let attempts = 0;
        const reinforcer = setInterval(() => {
            attempts += 1;
            applyDesired();
            if (attempts >= 15) {
                clearInterval(reinforcer);
                try {
                    el.removeEventListener('loadedmetadata', onLoaded);
                    el.removeEventListener('playing', onPlaying);
                    el.removeEventListener('volumechange', onVolumeChange);
                } catch (e) {}
            }
        }, 100);

        // Force a reload of the media resource (helps with some remote streams)
        try { if (typeof el.load === 'function') el.load(); } catch (e) {}

        // Start playback and handle promise
        const p = el.play();
        if (p && typeof p.then === 'function') {
            p.then(() => {
                applyDesired();
                setTimeout(applyDesired, 250);
                console.log('promo.js: enforceAndPlayElement play resolved, enforced volume=', el.volume);
            }).catch(err => {
                console.warn('promo.js: enforceAndPlayElement play rejected', err);
            });
        }
    } catch (err) {
        console.warn('promo.js: enforceAndPlayElement unexpected error', err);
    }
}
// --- end stronger helper ---

// --- Preferred sound persistence helpers (INSERTED) ---
function addDefaultLabel() {
    try {
        const opt = soundSelect.querySelector('option[value="default"]');
        if (!opt) return;
        // Only append once
        if (!opt.dataset.defaultTagged || opt.dataset.defaultTagged !== '1') {
            opt.textContent = opt.textContent.replace(/\s*\(default\)\s*$/, '').trim() + ' (default)';
            opt.dataset.defaultTagged = '1';
        }
    } catch (e) {
        console.warn("addDefaultLabel error:", e);
    }
}

function removeDefaultLabel() {
    try {
        const opt = soundSelect.querySelector('option[value="default"]');
        if (!opt) return;
        opt.textContent = opt.textContent.replace(/\s*\(default\)\s*$/, '').trim();
        opt.dataset.defaultTagged = '0';
    } catch (e) {
        console.warn("removeDefaultLabel error:", e);
    }
}

function applyPreferredSoundOnLoad() {
    try {
        const stored = localStorage.getItem('preferredAlarmSound');
        if (stored) {
            // If the stored value is one of the options, select it and remove the (default) label
            const opt = soundSelect.querySelector(`option[value="${stored}"]`);
            if (opt) {
                soundSelect.value = stored;
                removeDefaultLabel();
                console.log("promo.js: Applied stored preferredAlarmSound =", stored);
                return;
            }
        }
        // No stored preference or invalid value -> ensure default shows the (default) label
        addDefaultLabel();
        soundSelect.value = 'default';
        console.log("promo.js: No stored preferred sound — using default");
    } catch (e) {
        console.warn("applyPreferredSoundOnLoad error:", e);
    }
}
// --- end inserted helpers ---

// Function for Swift to call when music picker closes
function resetMusicPickerFlag() {
    if (musicPickerOpen) {
        musicPickerOpen = false;
        console.log("🎵 Music picker flag reset - alarm triggers enabled");
    }
}

// Simulate battery fluctuation and update UI
function updateBattery() {
    // Skip update if monitoring is paused
    if (monitoringPaused) {
        console.log("⏸️ Monitoring paused - skipping battery update");
        return;
    }
    
    // Use real battery level if enabled, otherwise simulation
    if (useRealBattery) {
        batteryLevel = realBatteryLevel;
    } else {
        batteryLevel = Math.min(100, Math.max(0, batteryLevel + (Math.random() * 10 - 5)));
    }
    
    // Show a ±2% range to account for measurement lag/variance
    const minRange = Math.max(0, Math.round(batteryLevel - 2));
    const maxRange = Math.min(100, Math.round(batteryLevel + 2));
    batteryDisplay.textContent = `${minRange}% - ${maxRange}%`;
    // Visualize the range: green from 0..minRange, brighter green for min..max, then grey
    batteryBar.style.background = `linear-gradient(to right, #00b894 ${minRange}%, #00b894 ${maxRange}%, #ccc ${maxRange}%)`;

    const low = parseInt(lowInput.value);
    const high = parseInt(highInput.value);

    if (!isNaN(low) && batteryLevel <= low) playSound();
    // Log for debugging
    console.log("Battery:", batteryLevel, "Low:", low, "High:", high);
    if (!isNaN(high) && batteryLevel >= high) playSound();
}

// Function to stop custom music
function stopCustomMusic() {
    console.log("🛑 Stopping custom music");
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
        window.webkit.messageHandlers.jsLogger.postMessage("STOP_ALARM");
    }
}

// Function for Swift to call with real battery level
function updateRealBatteryLevel(level) {
    realBatteryLevel = Math.max(0, Math.min(100, level));
    console.log("Real battery level updated:", realBatteryLevel + "%");
}

// Function to update battery health data (called from Swift)
// Function to update battery health data (called from Swift) - FIXED
// Insert or replace this function in promo.js.
// It updates/creates an element showing Battery Health and places it below the battery progress bar.

function updateBatteryHealth(health, state) {
    try {
        // Store values for debugging / future use but DO NOT show the numeric health percentage.
        // Only display the charging state to avoid showing a possibly stale/non-official "health" percentage.
        batteryHealth = (health === "N/A") ? "N/A" : String(health);
        chargingState = String(state);

        // Find or create the element that displays battery health/state
        let el = document.getElementById('battery-health');
        if (!el) {
            el = document.createElement('div');
            el.id = 'battery-health';
            el.style.fontSize = '13px';
            el.style.color = '#8a8a8a';
            el.style.marginTop = '6px';
            el.style.marginBottom = '4px';

            const insertionCandidates = [
                document.getElementById('battery-progress'),
                document.querySelector('.battery-progress'),
                document.getElementById('battery-bar'),
                document.querySelector('#battery-container'),
                document.querySelector('.right-column'),
                document.querySelector('.battery-row')
            ];

            let inserted = false;
            for (const candidate of insertionCandidates) {
                if (candidate && candidate.parentNode) {
                    candidate.parentNode.insertBefore(el, candidate.nextSibling);
                    inserted = true;
                    break;
                }
            }
            if (!inserted) {
                const fallback = document.querySelector('#right-column') || document.body;
                fallback.appendChild(el);
            }
        }

        // Display ONLY the charging state so users see reliable information;
        // avoid displaying a numeric "Battery Health" percentage here.
        el.textContent = String(state);
        el.title = `Battery info source: native (state: ${state})`;

        console.log("promo.js: updateBatteryHealth -> charging state only:", state, " (native health stored but not displayed)");
    } catch (e) {
        console.error("updateBatteryHealth error:", e);
    }
}

// Reset the flag after 30 seconds as a safety measure
setTimeout(resetMusicPickerFlag, 30000);

// Battery Health Display - IMMEDIATE VERSION
// Battery Health Display - Using Native Alert
function showBatteryHealth() {
    console.log("🔋 Battery health requested");
    
    // Use native iOS alert instead of JavaScript alert
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("SHOW_BATTERY_HEALTH_ALERT");
    } else {
        // Fallback to JavaScript alert if no bridge available
        console.log("🔋 Current battery data - Level:", realBatteryLevel, "Health:", batteryHealth, "State:", chargingState);
        const message = `Battery Level: ${realBatteryLevel}%\nBattery Health: ${batteryHealth}%\nCharging State: ${chargingState}`;
        alert("🔋 Battery Information:\n\n" + message);
    }
    
    // Still request fresh data for future updates
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("GET_BATTERY_HEALTH");
    }
}

// Play selected alarm sound (this is used for ALARM triggers — loops until stopped)
function playSound() {
    if (monitoringPaused || musicPickerOpen) {
        console.log("⏸️ Sound blocked - monitoring paused or music picker open");
        return;
    }

    const selected = soundSelect.value;

    // If custom music is selected, trigger Swift alarm system (native)
    if (selected === "custom") {
        console.log("🎵 Custom music selected - triggering Swift alarm (native)");
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
            window.webkit.messageHandlers.jsLogger.postMessage("START_CUSTOM_ALARM");
            // mark that an alarm is active (native)
            alarmActive = true;
            lastTriggeredLevel = batteryLevel;
        }
        return;
    }

    // For named default sounds, request native playback (so volume is controlled natively)
    console.log("🔊 Request native playback for sound: " + selected);

    // Stop any currently playing in-page audio first (defensive)
    Object.values(soundMap).forEach(audio => {
        try { audio.pause(); audio.currentTime = 0; } catch(e) {}
    });

    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
        try {
            // Ask native to play the default sound by name (e.g., "default", "slide_whistle")
            window.webkit.messageHandlers.jsLogger.postMessage("PLAY_DEFAULT:" + selected);
            // mark that an alarm is active (native)
            alarmActive = true;
            lastTriggeredLevel = batteryLevel;
        } catch (e) {
            console.warn("promo.js: failed to post PLAY_DEFAULT to native:", e);
            // Fallback to in-page audio playback if native bridge fails
            const fallback = soundMap[selected];
            if (fallback) {
                try {
                    // Use helper to enforce app volume robustly while starting playback
                    enforceAndPlayElement(fallback, true);
                    alarmActive = true;
                    lastTriggeredLevel = batteryLevel;
                    console.log("🔊 (fallback) Started playing (enforced): " + selected);
                } catch(e) {
                    console.warn("promo.js: fallback audio play failed:", e);
                }
            }
        }
    } else {
        // No native bridge present — fallback to page audio
        const audio = soundMap[selected];
        if (audio) {
            audio.currentTime = 0;
            audio.loop = true;
            audio.play();
            alarmActive = true;
            lastTriggeredLevel = batteryLevel;
            console.log("🔊 (no bridge) Started playing: " + selected);
        }
    }
}

// Preview a selected sound once for ~3 seconds (used on selection change)
function previewSound(name) {
    try {
        // If native preview supported, ask native
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
            window.webkit.messageHandlers.jsLogger.postMessage("PREVIEW_DEFAULT:" + name);
            return;
        }

        // Fallback: play the page audio once for ~3s — use enforceAndPlayElement to keep volume enforced
        const el = soundMap[name];
        if (el) {
            try {
                el.loop = false;
                // Use the helper so volume() is enforced and re-applied during playback startup
                enforceAndPlayElement(el, false);
                setTimeout(() => { try { el.pause(); el.currentTime = 0; } catch(e) {} }, 3000);
            } catch (e) { console.warn("previewSound fallback failed:", e); }
        }
    } catch (e) {
        console.warn("previewSound error:", e);
    }
}

// Add function to stop alarm when thresholds are safe
function stopAlarmIfSafe() {
    const low = parseInt(lowInput.value);
    const high = parseInt(highInput.value);
    
    // Check if current battery level is within safe range
    const isSafe = batteryLevel > low && batteryLevel < high;
    
    if (isSafe) {
        // Stop any in-page audio
        Object.values(soundMap).forEach(audio => {
            try { audio.pause(); audio.currentTime = 0; } catch(e) {}
        });

        // Ask native to stop any currently playing alarm (custom or default)
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
                window.webkit.messageHandlers.jsLogger.postMessage("STOP_ALARM");
            }
        } catch (e) {
            console.warn("stopAlarmIfSafe: failed to post STOP_ALARM", e);
        }

        if (alarmActive) {
            console.log("✅ Battery safe - stopping alarm");
            alarmActive = false;
            lastTriggeredLevel = null;
        } else {
            // still clear lastTriggeredLevel defensively
            lastTriggeredLevel = null;
        }
    }
}

// Update updateBattery function to check for safe conditions (shows ±2% range)
function updateBattery() {
    // Skip update if monitoring is paused
    if (monitoringPaused) {
        console.log("⏸️ Monitoring paused - skipping battery update");
        return;
    }
    
    // Use real battery level if enabled, otherwise simulation
    if (useRealBattery) {
        batteryLevel = realBatteryLevel;
    } else {
        batteryLevel = Math.min(100, Math.max(0, batteryLevel + (Math.random() * 10 - 5)));
    }
    
    // Show a ±2% range to account for measurement lag/variance
    const minRange = Math.max(0, Math.round(batteryLevel - 2));
    const maxRange = Math.min(100, Math.round(batteryLevel + 2));
    batteryDisplay.textContent = `${minRange}% - ${maxRange}%`;
    batteryBar.style.background = `linear-gradient(to right, #00b894 ${minRange}%, #00b894 ${maxRange}%, #ccc ${maxRange}%)`;

    const low = parseInt(lowInput.value);
    const high = parseInt(highInput.value);

    // Check if we should trigger alarm
    if (!isNaN(low) && batteryLevel <= low) {
        playSound();
    } else if (!isNaN(high) && batteryLevel >= high) {
        playSound();
    } else {
        // Battery is within safe range - stop alarm if playing
        stopAlarmIfSafe();
    }
    
    console.log("Battery:", batteryLevel, "Range:", `${minRange}-${maxRange}`, "Low:", low, "High:", high, "AlarmActive:", alarmActive);
}

// Validate that low threshold is less than high threshold
function validateThresholds() {
    const low = parseInt(lowInput.value);
    const high = parseInt(highInput.value);
    
    if (low >= high) {
        // Adjust high threshold to be at least 5% higher than low
        highInput.value = Math.min(100, low + 5);
        highDisplay.textContent = highInput.value + "%";
        console.log("⚠️ Adjusted high threshold to be above low threshold");
    }
}

// Simulate purchase and hide promo sections
function simulatePurchase() {
    adsRemoved = true;
    document.getElementById("purchase").style.display = "none";
    document.getElementById("promo-banner").style.display = "none";
    document.getElementById("noAds").style.display = "none";
}

// Toggle hamburger menu visibility
document.getElementById("menu-toggle").addEventListener("click", () => {
    const menu = document.getElementById("menu");
    menu.style.display = menu.style.display === "block" ? "none" : "block";
});

// Add battery mode toggle to menu
function setupBatteryToggle() {
    const menu = document.getElementById("menu");
    const batteryToggle = document.createElement("li");
    batteryToggle.innerHTML = '<a href="#" id="battery-toggle">🔋 Use Real Battery</a>';
    menu.querySelector("ul").insertBefore(batteryToggle, menu.querySelector("ul").children[3]);
  
    document.getElementById("battery-toggle").addEventListener("click", function(e) {
        e.preventDefault();
        useRealBattery = !useRealBattery;
        console.log("Battery mode:", useRealBattery ? "REAL" : "SIMULATION");
        this.textContent = useRealBattery ? "🎮 Use Simulation" : "🔋 Use Real Battery";
        document.getElementById("menu").style.display = "none";
    });
}

// Initialize battery toggle and preferred sound when page loads
document.addEventListener('DOMContentLoaded', setupBatteryToggle);
document.addEventListener('DOMContentLoaded', applyPreferredSoundOnLoad);

// Ensure no stale/static Battery Health element is shown on page load — native will populate real value
document.addEventListener('DOMContentLoaded', function() {
    try {
        const bh = document.getElementById('battery-health');
        if (bh) {
            bh.remove();
            console.log("promo.js: removed stale battery-health element on load");
        }
    } catch (e) {
        console.warn("promo.js: failed to remove stale battery-health element", e);
    }
});

// Close menu when clicking outside
document.addEventListener("click", (e) => {
    if (!e.target.closest("#menu") && !e.target.closest("#menu-toggle")) {
        document.getElementById("menu").style.display = "none";
    }
});

// Update slider displays and validate thresholds
lowInput.addEventListener("input", function() {
    lowDisplay.textContent = this.value + "%";
    validateThresholds();
});

highInput.addEventListener("input", function() {
    highDisplay.textContent = this.value + "%";
    validateThresholds();
});

// Auto-play a preview on selection change (plays once ~3s)
soundSelect.addEventListener("change", () => {
    const selected = soundSelect.value;
    console.log("Sound selection changed to:", selected);

    // If switching to a non-custom sound, stop any custom music first
    if (selected !== "custom") {
        console.log("🔄 Switching to non-custom sound, stopping custom music");
        stopCustomMusic();
        
        // RESET THE FLAG HERE - This was missing!
        musicPickerOpen = false;
        console.log("🎵 Music picker flag reset - alarm triggers enabled");
    }

    // Persist user preference: if user chooses default, clear stored preference; otherwise save it
    try {
        if (selected === "default") {
            localStorage.removeItem('preferredAlarmSound');
            addDefaultLabel();
            console.log("promo.js: Cleared stored preferredAlarmSound (using default)");
        } else {
            localStorage.setItem('preferredAlarmSound', selected);
            removeDefaultLabel();
            console.log("promo.js: Stored preferredAlarmSound =", selected);
        }
    } catch (e) {
        console.warn("promo.js: failed to persist preferredAlarmSound", e);
    }

    if (selected === "custom") {
        // Set flag to prevent alarm triggers during music selection
        musicPickerOpen = true;
        console.log("🎵 Music picker opening - alarm triggers disabled");
        
        // Request music library access from Swift
        if (window.webkit && window.webkit.messageHandlers) {
            window.webkit.messageHandlers.jsLogger.postMessage("REQUEST_MUSIC_PICKER");
        } else {
            alert("Music library integration requires the app version.");
        }
        // Don't play sound immediately for custom selection
        return;
    }

    // Preview selected sound once (do NOT start looping alarm)
    previewSound(selected);
});

// Pause Monitoring Toggle
// Pause Monitoring Toggle
function toggleMonitoring() {
    monitoringPaused = !monitoringPaused;
    const button = document.querySelector('.pause-btn');
    
    if (monitoringPaused) {
        // STOP ALL PLAYING SOUNDS when pausing - including custom music
        Object.values(soundMap).forEach(audio => {
            audio.pause();
            audio.currentTime = 0;
        });
        
        // Also stop Swift custom music
        stopCustomMusic();
        
        button.textContent = '▶️ Resume Monitoring';
        console.log("⏸️ Battery monitoring paused - ALL sounds stopped");
    } else {
        button.textContent = '⏸️ Pause Monitoring';
        console.log("▶️ Battery monitoring resumed");
    }
}

// Reset Settings
// Reset Settings (thresholds only)
function resetSettings() {
    // Reset numeric thresholds and their UI displays only
    lowInput.value = "20";
    highInput.value = "80";
    lowDisplay.textContent = "20%";
    highDisplay.textContent = "80%";

    // Do NOT change sound selection or stored preference here.
    // This preserves the user's preferred sound across resets.

    console.log("Settings reset to defaults (thresholds only)");
}

// Brightness Control
let brightnessLevel = 50;

function updateBrightness() {
    const slider = document.getElementById("brightness-slider");
    const display = document.getElementById("brightness-display");
    
    brightnessLevel = parseInt(slider.value);
    display.textContent = brightnessLevel + "%";
    
    // Send to Swift to adjust actual screen brightness
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("SET_BRIGHTNESS:" + brightnessLevel);
    }
    
    console.log("💡 Brightness set to: " + brightnessLevel + "%");
}

// Flashlight Toggle
function toggleFlashlight() {
    console.log("🔦 Flashlight toggle requested");
    
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("TOGGLE_FLASHLIGHT");
    } else {
        console.log("❌ No message handlers available for flashlight");
    }
}

// Battery Health Display
// Battery Health Display - FIXED TIMING
// Battery Health Display - Using Native Alert
// Battery Health Display - Using Native Settings (opens system Battery settings when available)
function showBatteryHealth() {
    console.log("🔋 Battery health requested - asking native to open Battery settings");

    // If native bridge available, ask native to open Battery settings directly
    if (window.webkit && window.webkit.messageHandlers) {
        // use a distinct message name so Swift opens Settings
        window.webkit.messageHandlers.jsLogger.postMessage("OPEN_BATTERY_SETTINGS");
        return;
    }

    // Fallback if no native bridge: show the old alert with current JS values
    console.log("🔋 Current battery data - Level:", realBatteryLevel, "Health:", batteryHealth, "State:", chargingState);
    const message = `Battery Level: ${realBatteryLevel}%\nBattery Health: ${batteryHealth}%\nCharging State: ${chargingState}`;
    alert("🔋 Battery Information:\n\n" + message);
}

// Debug function to check current battery health data
function debugBatteryHealth() {
    console.log("🔋 DEBUG - Current battery data:", {
        realBatteryLevel: realBatteryLevel,
        batteryHealth: batteryHealth,
        chargingState: chargingState
    });
}

// Event Listeners
document.getElementById("brightness-slider").addEventListener("input", updateBrightness);

// Quick App Launcher
function showQuickLauncher() {
    console.log("🚀 Quick App Launcher requested");
    
    // For now, show an alert with available system apps
    const message = "Quick App Launcher\n\nAvailable Apps:\n• Camera\n• Photos\n• Settings\n• Calendar\n• Notes\n\nThis feature will open system apps directly in future updates.";
    alert(message);
    
    // In future, we can integrate with Swift to open specific apps
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
        window.webkit.messageHandlers.jsLogger.postMessage("QUICK_APP_LAUNCHER");
    }
}

// Device Information Dashboard
// Quick App icon handlers for the right column

function quickOpenCamera() {
    console.log("📟 JS LOG: QUICK_OPEN_CAMERA");
    // If native bridge exists, ask Swift to open camera (or present picker)
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("OPEN_CAMERA");
        return;
    }
    // Fallback: implement in-js behavior if you have it
    alert("Camera quick open (no native bridge available)");
}

function quickOpenPhotos() {
    console.log("📟 JS LOG: QUICK_OPEN_PHOTOS");
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("OPEN_PHOTOS");
        return;
    }
    alert("Photos quick open (no native bridge available)");
}

function openAppSettings() {
    console.log("📟 JS LOG: OPEN_APP_SETTINGS");
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("OPEN_APP_SETTINGS");
        return;
    }
    // fallback: open a web explanation
    alert("Open App Settings (no native bridge available)");
}

// Defensive helper: ensure the right column exists and contains the expected icons.
// Paste at the end of promo.js. This only creates the DOM if #right-column is missing.
// Note: Device Info button removed per request.

(function ensureRightColumnExists() {
    try {
        if (document.getElementById('right-column')) {
            console.log("Right column already present");
            return;
        }

        console.log("Right column missing — creating right-column DOM (no Device Info)");

        const right = document.createElement('div');
        right.id = 'right-column';
        right.className = 'right-column';
        right.setAttribute('role','region');
        right.setAttribute('aria-label','Quick Actions');

        right.innerHTML = `
            <button id="flashlight-button" class="right-icon" onclick="toggleFlashlight()" aria-label="Flashlight">
                <span class="icon flashlight-icon" aria-hidden="true"></span>
            </button>

            <button id="camera-button" class="right-icon" onclick="quickOpenCamera()" aria-label="Camera">
                <span class="icon camera-icon" aria-hidden="true"></span>
            </button>

            <button id="photos-button" class="right-icon" onclick="quickOpenPhotos()" aria-label="Photos">
                <span class="icon photos-icon" aria-hidden="true"></span>
            </button>

            <div class="icon-with-caption">
                <button id="app-settings-button" class="right-icon" onclick="openAppSettings()" aria-label="App Settings">
                    <span class="icon app-settings-icon" aria-hidden="true"></span>
                </button>
                <div class="icon-caption">App Settings</div>
            </div>
        `;

        const container = document.querySelector('#app') || document.querySelector('#main') || document.body;
        container.appendChild(right);

        console.log("Right column DOM created (no Device Info)");
    } catch (e) {
        console.error("Failed to ensure right column exists:", e);
    }
})();

// Quick App icon handlers — keep these and remove showDeviceInfo
function quickOpenCamera() {
    console.log("📟 JS LOG: QUICK_OPEN_CAMERA");
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("OPEN_CAMERA");
        return;
    }
    alert("Camera quick open (no native bridge available)");
}

function quickOpenPhotos() {
    console.log("📟 JS LOG: QUICK_OPEN_PHOTOS");
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("OPEN_PHOTOS");
        return;
    }
    alert("Photos quick open (no native bridge available)");
}

function openAppSettings() {
    console.log("📟 JS LOG: OPEN_APP_SETTINGS");
    if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.jsLogger.postMessage("OPEN_APP_SETTINGS");
        return;
    }
    alert("Open App Settings (no native bridge available)");
}

//FDOM

// remove or ignore any prior showDeviceInfo() calls in your UI so they don't attempt to run

// Start battery simulation loop
setInterval(updateBattery, 3000);

// SOS Controls (in-page) - Toggle SOS beacon and Send SOS SMS (posts to native)
(function addSOSControls(){
  try {
    // Ensure captions use 12px (per request)
    (function setCaptionSize(){
      try {
        var caps = document.querySelectorAll('#bottom-icons-row .icon-caption');
        for (var i = 0; i < caps.length; i++) {
          caps[i].style.fontSize = '12px';
        }
      } catch(e) { console.warn('promo.js: setCaptionSize error', e); }
    })();

    // Expose global callback for native -> JS SOS state notifications.
    // Native must call: window.onNativeSosStateChanged(true) or window.onNativeSosStateChanged(false)
    window.onNativeSosStateChanged = function(state) {
      try {
        var b = document.getElementById('sos-beacon-button-bottom');
        if (!b) return;
        var icon = b.querySelector('.icon-emoji');
        var caption = b.querySelector('.icon-caption');
        if (state) {
          if (icon) icon.textContent = '🛑';
          b.style.background = '#ff6347';
        } else {
          if (icon) icon.textContent = '🆘';
          b.style.background = 'transparent';
        }
        if (caption) caption.textContent = 'Beacon';
      } catch(e) { console.warn('promo.js: onNativeSosStateChanged error', e); }
    };

    // Wire to hard-coded buttons in the HTML (we do NOT create new buttons here)
    var beaconBtn = document.getElementById('sos-beacon-button-bottom');
    var smsBtn = document.getElementById('sos-sms-button-bottom');

    function refreshBeaconUI() {
      try {
        if (!beaconBtn) return;
        var icon = beaconBtn.querySelector('.icon-emoji');
        var caption = beaconBtn.querySelector('.icon-caption');
        // reflect current icon content (native will drive content via onNativeSosStateChanged)
        if (icon && icon.textContent === '🛑') beaconBtn.style.background = '#ff6347';
        else beaconBtn.style.background = 'transparent';
        if (caption) caption.textContent = 'Beacon';
      } catch(e) { console.warn('promo.js: refreshBeaconUI error', e); }
    }

    // Initialize UI (will be updated by native if state exists)
    refreshBeaconUI();

    if (beaconBtn) {
      beaconBtn.addEventListener('click', function(e){
        try { if (e && typeof e.preventDefault === 'function') e.preventDefault(); } catch(e){}
        try {
          var icon = beaconBtn.querySelector('.icon-emoji');
          var isOn = icon && icon.textContent === '🛑';
          if (!isOn) {
            // Ask native to start — DO NOT change UI here; wait for native callback
            console.log('promo.js: START_SOS requested (via hard-coded button)');
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
                window.webkit.messageHandlers.jsLogger.postMessage('START_SOS');
              } else { console.warn('promo.js: native bridge not available for START_SOS'); }
            } catch(err) { console.warn('promo.js: START_SOS post failed', err); }
          } else {
            // Ask native to stop — DO NOT change UI here; wait for native callback
            console.log('promo.js: STOP_SOS requested (via hard-coded button)');
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
                window.webkit.messageHandlers.jsLogger.postMessage('STOP_SOS');
              } else { console.warn('promo.js: native bridge not available for STOP_SOS'); }
            } catch(err) { console.warn('promo.js: STOP_SOS post failed', err); }
          }
        } catch(err) { console.warn('promo.js: beacon click error', err); }
      }, { passive: false });
    } else {
      console.log('promo.js: beaconBtn not found (hard-coded HTML may be missing)');
    }

    if (smsBtn) {
      smsBtn.addEventListener('click', function(e){
        try { if (e && typeof e.preventDefault === 'function') e.preventDefault(); } catch(e){}
        console.log('promo.js: SOS_SMS button clicked - posting SOS_SMS to native (no JS confirm)');
        try {
          setTimeout(function(){
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
                window.webkit.messageHandlers.jsLogger.postMessage('SOS_SMS');
                console.log('promo.js: SOS_SMS posted to native bridge');
              } else {
                console.warn('promo.js: native bridge not available for SOS_SMS');
                // fallback to sms: URL
                var deviceLabel = (window.deviceName || navigator.userAgent || 'this device');
                var batteryText = (typeof realBatteryLevel !== 'undefined') ? (realBatteryLevel + '%') : '';
                var body = encodeURIComponent('Help! This is ' + deviceLabel + '. My battery is ' + batteryText + '.');
                window.location.href = 'sms:?body=' + body;
              }
            } catch(err) {
              console.warn('promo.js: SOS_SMS send error', err);
            }
          }, 8);
        } catch(err) {
          console.warn('promo.js: SOS_SMS outer error', err);
        }
      }, { passive: false });
    } else {
      console.log('promo.js: smsBtn not found (hard-coded HTML may be missing)');
    }

    console.log('promo.js: SOS controls wired to hard-coded HTML buttons (inline)');
  } catch(e) {
    console.warn('promo.js: addSOSControls error', e);
  }
})();
