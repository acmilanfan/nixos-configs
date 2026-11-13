// ==UserScript==
// @name         Google Meet: browser-processed microphone
// @namespace    nixos-configs
// @version      3
// @description  Feeds Meet's own audio processing the browser-processed microphone instead of the raw one, so speech is not quiet for the first ~15 s of a call.
// @match        https://meet.google.com/*
// @run-at       document-start
// @inject-into  page
// @grant        none
// ==/UserScript==

// Meet opens the microphone raw (echoCancellation, autoGainControl and
// noiseSuppression all `{exact: false}`), runs it through its own Web Audio
// processing and sends that to the call. Its own gain control starts low and
// takes ~15 s of speech to reach a normal level with the quiet built-in mic.
// The browser-processed mic (all three on) is at full level from the first
// word, so hand Meet that one for its raw request; Meet's processing still
// runs on top. Meet's other requests are left alone.

(() => {
  'use strict';

  const TAG = '[meet-mic]';
  const PROCESSING = ['echoCancellation', 'autoGainControl', 'noiseSuppression'];

  const isExactFalse = (v) => v && typeof v === 'object' && v.exact === false;
  const isRawRequest = (audio) =>
    audio && typeof audio === 'object' && PROCESSING.every((k) => isExactFalse(audio[k]));

  const devices = MediaDevices.prototype;
  const getUserMedia = devices.getUserMedia;
  devices.getUserMedia = function (constraints) {
    if (!constraints || !isRawRequest(constraints.audio)) {
      return getUserMedia.call(this, constraints);
    }
    const audio = { ...constraints.audio };
    for (const k of PROCESSING) audio[k] = true;
    return getUserMedia.call(this, { ...constraints, audio }).then((stream) => {
      const s = stream.getAudioTracks()[0]?.getSettings() ?? {};
      console.info(TAG, 'gave Meet the processed mic instead of the raw one:',
        PROCESSING.map((k) => `${k}=${s[k]}`).join(' '));
      return stream;
    });
  };

  console.info(TAG, 'active');
})();
