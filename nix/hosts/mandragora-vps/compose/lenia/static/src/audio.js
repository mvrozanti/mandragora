const BAND_COUNT = 5;

export class MpdLink {
  constructor() {
    this.source = null;
    this.connected = false;
    this.available = false;
    this.state = 'unknown';
    this.title = '';
    this.artist = '';
    this.album = '';
    this.uri = '';
    this.raw = new Array(BAND_COUNT).fill(0);
    this.bands = new Array(BAND_COUNT).fill(0);
    this.level = 0;
    this.smoothLevel = 0;
    this.onset = 0;
    this.lastMessage = 0;
    this.error = '';
    this.bridge = null;
  }

  async probe(timeoutMs = 2500) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch('mpd/status', { cache: 'no-store', signal: controller.signal });
      if (!response.ok) throw new Error(String(response.status));
      await response.json();
      this.bridge = true;
    } catch {
      this.bridge = false;
    } finally {
      clearTimeout(timer);
    }
    return this.bridge;
  }

  get live() {
    return this.source !== null && this.connected && Date.now() - this.lastMessage < 2000;
  }

  get playing() {
    return this.state === 'play';
  }

  open() {
    if (this.source || this.bridge === false) return;
    this.error = '';
    try {
      this.source = new EventSource('mpd/stream');
    } catch (e) {
      this.error = e.message;
      return;
    }
    this.source.addEventListener('message', (event) => {
      let payload;
      try { payload = JSON.parse(event.data); } catch { return; }
      this.lastMessage = Date.now();
      this.connected = !!payload.connected;
      this.available = !!payload.available;
      this.state = payload.state || 'unknown';
      this.title = payload.title || '';
      this.artist = payload.artist || '';
      this.album = payload.album || '';
      this.uri = payload.uri || '';
      this.raw = payload.bands && payload.bands.length === BAND_COUNT ? payload.bands : this.raw;
      this.level = typeof payload.level === 'number' ? payload.level : 0;
      if (payload.onset) this.onset = 1;
    });
    this.source.addEventListener('error', () => {
      this.error = 'stream interrupted';
    });
  }

  get trackKey() {
    return this.uri || `${this.artist}|${this.title}`;
  }

  close() {
    if (!this.source) return;
    this.source.close();
    this.source = null;
    this.connected = false;
    this.raw.fill(0);
    this.bands.fill(0);
    this.level = 0;
    this.smoothLevel = 0;
    this.onset = 0;
  }

  advance(dt) {
    const silent = !this.live || !this.playing;
    const release = Math.pow(0.0025, dt);
    for (let i = 0; i < BAND_COUNT; i++) {
      const target = silent ? 0 : this.raw[i];
      this.bands[i] = target > this.bands[i] ? target : this.bands[i] * release;
    }
    const target = silent ? 0 : this.level;
    this.smoothLevel = target > this.smoothLevel ? target : this.smoothLevel * release;
    const fired = this.onset > 0 && !silent;
    this.onset = 0;
    return fired;
  }

  get selfHosted() {
    const host = typeof location === 'undefined' ? '' : location.hostname;
    return host === 'localhost' || host === '127.0.0.1' || host === '[::1]' || host === '';
  }

  describe() {
    if (this.bridge === false) {
      return this.selfHosted
        ? 'bridge offline — is serve.py running?'
        : 'public deploy · MPD audio needs the local server';
    }
    if (!this.source) return 'off';
    if (this.error && !this.live) return this.error;
    if (!this.live) return 'connecting…';
    if (!this.connected) return 'mpd unreachable';
    if (!this.available) return 'fifo missing';
    if (!this.playing) return `${this.state} · ${this.title || 'no track'}`;
    return this.artist ? `${this.artist} — ${this.title}` : (this.title || 'playing');
  }
}
