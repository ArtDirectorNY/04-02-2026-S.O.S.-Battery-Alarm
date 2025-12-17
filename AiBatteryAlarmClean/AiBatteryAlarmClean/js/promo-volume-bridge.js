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
    setPageAudioVolumes(value);
    var msg = 'SET_ALARM_VOLUME:' + Math.round(value);
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
      try { window.webkit.messageHandlers.jsLogger.postMessage(msg); }
      catch (e) { console.warn('promo-volume-bridge: failed to post jsLogger', e); }
    } else {
      console.log('promo-volume-bridge: would post', msg);
    }
  }

  slider.addEventListener('input', function (ev) {
    var v = Number(ev.target.value || 0);
    updateDisplay(v);
    requestAnimationFrame(function () { sendAppVolume(v); });
  }, { passive: true });

  slider.addEventListener('change', function (ev) {
    var v = Number(ev.target.value || 0);
    updateDisplay(v);
    sendAppVolume(v);
  });

  var initialValue = Number(slider.value || 0);
  updateDisplay(initialValue);
  setPageAudioVolumes(initialValue);
})();
