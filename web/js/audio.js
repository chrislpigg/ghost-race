/**
 * The web equivalent of AudioCueEngine + HapticEngine: spoken announcements via
 * the Web Speech API, generated tones via WebAudio, and haptics via the
 * Vibration API where supported. Consumes the same cue objects the scheduler
 * emits ({kind:"say"|"play"|"haptic"}).
 */

// Short note sequences per tone: [frequencyHz, startOffsetS, durationS].
const TONE_SEQUENCES = {
  startBeep: [[880, 0, 0.14]],
  leadJingle: [[659, 0, 0.1], [880, 0.1, 0.1], [1175, 0.2, 0.18]],
  behindWarning: [[300, 0, 0.14], [240, 0.17, 0.16]],
  finalStretch: [[520, 0, 0.09], [520, 0.15, 0.09], [520, 0.3, 0.12]],
  winFanfare: [[523, 0, 0.12], [659, 0.12, 0.12], [784, 0.24, 0.12], [1047, 0.36, 0.26]],
  loseTrombone: [[330, 0, 0.22], [262, 0.22, 0.3]],
};
const HARSH_TONES = new Set(["behindWarning", "loseTrombone"]);

export class AudioCueEngine {
  constructor() {
    this.ctx = null;
  }

  /** Must be called from a user gesture to satisfy autoplay policies. */
  unlock() {
    if (!this.ctx) {
      const Ctor = window.AudioContext || window.webkitAudioContext;
      if (Ctor) this.ctx = new Ctor();
    }
    if (this.ctx && this.ctx.state === "suspended") void this.ctx.resume();
    // Prime speech synthesis so the first real utterance isn't dropped.
    if ("speechSynthesis" in window) window.speechSynthesis.cancel();
  }

  perform(cues) {
    for (const cue of cues) {
      if (cue.kind === "say") this.say(cue.text);
      else if (cue.kind === "play") this.play(cue.tone);
      else if (cue.kind === "haptic") this.haptic(cue.pattern);
    }
  }

  say(text) {
    if (!("speechSynthesis" in window)) return;
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 1.05;
    utterance.pitch = 1.0;
    window.speechSynthesis.speak(utterance);
  }

  haptic(pattern) {
    if (!navigator.vibrate) return;
    navigator.vibrate(pattern === "overtake" ? [40, 30, 40] : [120, 60, 120]);
  }

  play(tone) {
    const ctx = this.ctx;
    if (!ctx) return;
    const sequence = TONE_SEQUENCES[tone] ?? [[600, 0, 0.12]];
    const now = ctx.currentTime;
    const waveform = HARSH_TONES.has(tone) ? "sawtooth" : "triangle";
    for (const [freq, offset, dur] of sequence) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = waveform;
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.0001, now + offset);
      gain.gain.exponentialRampToValueAtTime(0.25, now + offset + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + offset + dur);
      osc.connect(gain).connect(ctx.destination);
      osc.start(now + offset);
      osc.stop(now + offset + dur + 0.03);
    }
  }
}
