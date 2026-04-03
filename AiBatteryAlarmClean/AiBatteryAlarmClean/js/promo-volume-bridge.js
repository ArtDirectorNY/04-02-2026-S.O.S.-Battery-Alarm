// promo-volume-bridge.js (APP-VOLUME mode) — diagnostic variant
(function () {
  'use strict';
  function $(sel) { return document.querySelector(sel); }

  var slider = $('#volume-slider');
  var display = $('#volume-display');

  if (!slider || !display) {
    console.warn('promo-volume-bridge (app-volume): volume-slider or volume-display not found');
    return;
  }

  var soundIDs = [
    'slide_whistle-sound',
    'default-sound',
    'alarm_clock-sound',
    'boing-sound'
  ];

  function fmtPercent(v) { return Math.round(v) + '%'; }
  function updateDisplay(value) { display.textContent = fmtPercent(value); }

  function setPageAudioVolumes(value) {
    var normalized = Math.max(0, Math.min(100, Math.round(value))) / 100;
    soundIDs.forEach(function(id) {
      var el = document.getElementById(id);
      if (el && typeof el.volume !== 'undefined') {
        try {
          el.volume = normalized;
          console.log('promo-volume-bridge: set volume for', id, '=>', normalized);
        } catch (e) {
          console.warn('promo-volume-bridge: failed to set volume for', id, e);
        }
      } else {
        console.log('promo-volume-bridge: element not found or no volume property for', id);
      }
    });
  }

  function sendAppVolume(value) {
    // Ensure page audio updated immediately (keeps UI in-sync)
    setPageAudioVolumes(value);

    var msg = 'SET_ALARM_VOLUME:' + Math.round(value);
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
      try { window.webkit.messageHandlers.jsLogger.postMessage(msg); }
      catch (e) { console.warn('promo-volume-bridge: failed to post jsLogger', e); }
    } else {
      console.log('promo-volume-bridge: would post', msg);
    }
  }

  // Debounce native bridge posts to avoid flooding native with rapid input events.
  var pendingVolumeTimeout = null;
  var debounceMs = 250; // conservative debounce interval

  slider.addEventListener('input', function (ev) {
    var v = Number(ev.target.value || 0);
    updateDisplay(v);
    // Update in-page audio immediately for responsive feedback
    setPageAudioVolumes(v);

    // Debounce the native post
    if (pendingVolumeTimeout) clearTimeout(pendingVolumeTimeout);
    pendingVolumeTimeout = setTimeout(function () {
      pendingVolumeTimeout = null;
      sendAppVolume(v);
    }, debounceMs);
  }, { passive: true });

  // On explicit change (finalized by user), send immediately (cancel any debounce)
  slider.addEventListener('change', function (ev) {
    var v = Number(ev.target.value || 0);
    updateDisplay(v);
    if (pendingVolumeTimeout) { clearTimeout(pendingVolumeTimeout); pendingVolumeTimeout = null; }
    sendAppVolume(v);
  });

  var initialValue = Number(slider.value || 0);
  updateDisplay(initialValue);
  setPageAudioVolumes(initialValue);
})();
