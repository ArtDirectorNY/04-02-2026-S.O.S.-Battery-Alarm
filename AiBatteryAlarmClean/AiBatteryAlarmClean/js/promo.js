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
    
    batteryDisplay.textContent = batteryLevel.toFixed(2) + "%";
    batteryBar.style.background = `linear-gradient(to right, #00b894 ${batteryLevel}%, #ccc ${batteryLevel}%)`;

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
function updateBatteryHealth(health, state) {
    batteryHealth = health;
    chargingState = state;
    console.log(`🔋 Health updated in JS: ${health}%, State: ${state}`);
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

// Play selected alarm sound
function playSound() {
    if (monitoringPaused || musicPickerOpen) {
        console.log("⏸️ Sound blocked - monitoring paused or music picker open");
        return;
    }
    
    const selected = soundSelect.value;
    
    // If custom music is selected, trigger Swift alarm system
    if (selected === "custom") {
        console.log("🎵 Custom music selected - triggering Swift alarm");
        // Swift will handle custom music playback through AlarmManager
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
            window.webkit.messageHandlers.jsLogger.postMessage("START_CUSTOM_ALARM");
        }
        return;
    }

    // For all other sounds, use JavaScript audio
    console.log("🔊 Playing sound: " + selected);

    // Stop any currently playing sound before starting new one
    Object.values(soundMap).forEach(audio => {
        audio.pause();
        audio.currentTime = 0;
    });

    const audio = soundMap[selected];
    if (audio) {
        audio.currentTime = 0;
        audio.loop = true;
        audio.play();
        alarmActive = true;
        lastTriggeredLevel = batteryLevel;
        console.log("🔊 Started playing: " + selected);
    }
}

// Add function to stop alarm when thresholds are safe
function stopAlarmIfSafe() {
    const low = parseInt(lowInput.value);
    const high = parseInt(highInput.value);
    
    // Check if current battery level is within safe range
    const isSafe = batteryLevel > low && batteryLevel < high;
    
    if (alarmActive && isSafe) {
        console.log("✅ Battery safe - stopping alarm");
        Object.values(soundMap).forEach(audio => {
            audio.pause();
            audio.currentTime = 0;
        });
        alarmActive = false;
        lastTriggeredLevel = null;
    }
}

// Update updateBattery function to check for safe conditions
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
    
    batteryDisplay.textContent = batteryLevel.toFixed(2) + "%";
    batteryBar.style.background = `linear-gradient(to right, #00b894 ${batteryLevel}%, #ccc ${batteryLevel}%)`;

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
    
    console.log("Battery:", batteryLevel, "Low:", low, "High:", high, "AlarmActive:", alarmActive);
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

// Initialize battery toggle when page loads
document.addEventListener('DOMContentLoaded', setupBatteryToggle);

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

// Auto-play sound on selection change
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

    // Play sound for all other selections
    playSound();
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
// Reset Settings
function resetSettings() {
    lowInput.value = "20";
    highInput.value = "80";
    lowDisplay.textContent = "20%";
    highDisplay.textContent = "80%";
    soundSelect.value = "default";
    
    // Stop any custom music that might be playing
    stopCustomMusic();
    
    console.log("Settings reset to defaults - custom music stopped");
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
function showBatteryHealth() {
    console.log("🔋 Battery health requested");
    
    // Use native iOS alert instead of JavaScript alert
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
        console.log("🔋 Sending SHOW_BATTERY_HEALTH_ALERT to Swift");
        window.webkit.messageHandlers.jsLogger.postMessage("SHOW_BATTERY_HEALTH_ALERT");
    } else {
        // Fallback to JavaScript alert if no bridge available
        console.log("🔋 No bridge available, using JS alert");
        console.log("🔋 Current battery data - Level:", realBatteryLevel, "Health:", batteryHealth, "State:", chargingState);
        const message = `Battery Level: ${realBatteryLevel}%\nBattery Health: ${batteryHealth}%\nCharging State: ${chargingState}`;
        alert("🔋 Battery Information:\n\n" + message);
    }
    
    // Still request fresh data for future updates
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
        window.webkit.messageHandlers.jsLogger.postMessage("GET_BATTERY_HEALTH");
    }
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
function showDeviceInfo() {
    console.log("📱 Device Info requested");
    
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
        window.webkit.messageHandlers.jsLogger.postMessage("SHOW_DEVICE_INFO");
    } else {
        // Fallback
        const message = "Device Information:\n\n" +
                       "User Agent: " + navigator.userAgent + "\n" +
                       "Platform: " + navigator.platform + "\n" +
                       "Screen: " + screen.width + "x" + screen.height;
        alert(message);
    }
}

// Start battery simulation loop
setInterval(updateBattery, 3000);
