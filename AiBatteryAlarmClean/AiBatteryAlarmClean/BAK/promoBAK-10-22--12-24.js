let batteryLevel = 50;
let adsRemoved = false;
let customAudio = null;
    let useRealBattery = false; // added 10-22
    let realBatteryLevel = 50; // added 10-22

const batteryDisplay = document.getElementById("battery-percent");
const batteryBar = document.getElementById("battery-bar");
const lowInput = document.getElementById("low-threshold");
const highInput = document.getElementById("high-threshold");
const soundSelect = document.getElementById("sound-select");

// Sound map for 4 working sounds
const soundMap = {
  slide_whistle: document.getElementById("slide_whistle-sound"),
  default: document.getElementById("default-sound"),
  alarm_clock: document.getElementById("alarm_clock-sound"),
  boing: document.getElementById("boing-sound")
};

// Simulate battery fluctuation and update UI
    //function updateBattery() {
    //batteryLevel = Math.min(100, Math.max(0, batteryLevel + (Math.random() * 10 - 5)));
    //the above replaced with:
function updateBattery() {
    // Use real battery level if enabled, otherwise simulation
    if (useRealBattery) {
        batteryLevel = realBatteryLevel;
    } else {
        batteryLevel = Math.min(100, Math.max(0, batteryLevel + (Math.random() * 10 - 5)));
    } //added 10/22--12:05
    
    
  batteryDisplay.textContent = batteryLevel.toFixed(2) + "%";
  batteryBar.style.background = `linear-gradient(to right, #00b894 ${batteryLevel}%, #ccc ${batteryLevel}%)`;

  const low = parseFloat(lowInput.value);
  const high = parseFloat(highInput.value);

  if (!isNaN(low) && batteryLevel <= low) playSound();
    // Log for debugging
    console.log("Battery:", batteryLevel, "Low:", low, "High:", high);
  if (!isNaN(high) && batteryLevel >= high) playSound();
}

    // Function for Swift to call with real battery level
        function updateRealBatteryLevel(level) {
            realBatteryLevel = Math.max(0, Math.min(100, level));
            console.log("Real battery level updated:", realBatteryLevel + "%");
        } //added 10/22

// Play selected alarm sound
function playSound() {
  const selected = soundSelect.value;

  if (selected === "custom" && customAudio) {
    customAudio.currentTime = 0;
    customAudio.play();
    return;
  }

  const audio = soundMap[selected];
  if (audio) {
    audio.currentTime = 0;
    audio.play();
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

// Close menu when clicking outside
document.addEventListener("click", (e) => {
  if (!e.target.closest("#menu") && !e.target.closest("#menu-toggle")) {
    document.getElementById("menu").style.display = "none";
  }
});

// Auto-play sound on selection change
soundSelect.addEventListener("change", () => {
  const selected = soundSelect.value;

  if (selected === "custom") {
    // Trigger native file picker (placeholder logic)
    alert("Please choose a sound file from your device.");
    // In hybrid app, replace with Capacitor or Cordova file picker
    // Example: window.plugins.filePicker.pickAudioFile(...)
    return;
  }

  playSound();
});

// Start battery simulation loop
setInterval(updateBattery, 3000);
