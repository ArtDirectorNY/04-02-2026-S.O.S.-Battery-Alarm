let batteryLevel = 50;
let adsRemoved = false;
let customAudio = null;
    let useRealBattery = false; // added 10-22
    let realBatteryLevel = 50; // added 10-22

    let customAudio = null; //added 10-27-1005
    let customSongUrl = null; //added 10-27-1005
    let customSongTitle = null; //added 10-27-1005

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

  //overwrittten by DS 10-22-1442
    //const low = parseFloat(lowInput.value);
  //const high = parseFloat(highInput.value);
    //\\end overwrittten below by DS 10-22-1442
    
    //Added by DS 10-22-1642
    const low = parseInt(lowInput.value);
    const high = parseInt(highInput.value);
    //\\end added by DS 10-22-1642

  if (!isNaN(low) && batteryLevel <= low) playSound();
    // Log for debugging
    console.log("Battery:", batteryLevel, "Low:", low, "High:", high);
  if (!isNaN(high) && batteryLevel >= high) playSound();
}

        // added 10-27-1005
        // Set custom alarm song from Swift
        function setCustomAlarmSong(url, title) {
            customSongUrl = url;
            customSongTitle = title;
            console.log("🎵 Custom alarm song set:", title, "URL:", url);
            
            // Update the sound selection to show custom song
            const soundSelect = document.getElementById("sound-select");
            soundSelect.value = "custom";
            
            // Create a custom option if it doesn't exist
            let customOption = soundSelect.querySelector('option[value="custom"]');
            if (!customOption) {
                customOption = document.createElement("option");
                customOption.value = "custom";
                soundSelect.appendChild(customOption);
            }
            customOption.textContent = `Custom: ${title}`;
        }
        //\\added 10-27-1005


    // Function for Swift to call with real battery level
        function updateRealBatteryLevel(level) {
            realBatteryLevel = Math.max(0, Math.min(100, level));
            console.log("Real battery level updated:", realBatteryLevel + "%");
        } //added 10/22

//start Added by DS 10-24-1600
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
}//\\end Added by DS 10-24-1600

        // Play selected alarm sound Edited by DS 10-27-1013
        function playSound() {
          const selected = soundSelect.value;

          if (selected === "custom" && customSongUrl) {
            console.log("🎵 Attempting to play custom song:", customSongTitle);
            
            // For now, we'll fall back to default sound since playing custom music
            // from URL requires additional iOS permissions and setup
            console.log("⚠️ Custom music playback requires additional setup - using default sound");
            playDefaultSound();
            return;
          }

          const audio = soundMap[selected];
          if (audio) {
            audio.currentTime = 0;
            audio.play();
          }
        }

// Fallback function for custom music
function playDefaultSound() {
  const audio = soundMap["default"];
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

//###
// --> added 10-22--12:27
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

// Update slider displays and validate thresholds Added by DS 10-24-1500
lowInput.addEventListener("input", function() {
  lowDisplay.textContent = this.value + "%";
  validateThresholds();
});

highInput.addEventListener("input", function() {
  highDisplay.textContent = this.value + "%";
  validateThresholds();
});//end of added by DS\\

    // Initialize battery toggle when page loads
    document.addEventListener('DOMContentLoaded', setupBatteryToggle);
// <-- added 10-22-12:27
//##\\

// Close menu when clicking outside
document.addEventListener("click", (e) => {
  if (!e.target.closest("#menu") && !e.target.closest("#menu-toggle")) {
    document.getElementById("menu").style.display = "none";
  }
});

// Auto-play sound on selection change
soundSelect.addEventListener("change", () => {
  const selected = soundSelect.value;

  //Replced by DS
  //if (selected === "custom") {
    // Trigger native file picker (placeholder logic)
    //alert("Please choose a sound file from your device.");
    // In hybrid app, replace with Capacitor or Cordova file picker
    // Example: window.plugins.filePicker.pickAudioFile(...)
    //return;
  //}// Replaced by DS with if below

    if (selected === "custom") {
        // Request music library access from Swift
        if (window.webkit && window.webkit.messageHandlers) {
            window.webkit.messageHandlers.jsLogger.postMessage("REQUEST_MUSIC_PICKER");
        } else {
            alert("Music library integration requires the app version.");
        }
        return;
    }
    
  playSound();
});

// Start battery simulation loop
setInterval(updateBattery, 3000);
