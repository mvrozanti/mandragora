import { Player, Constants } from 'yt-cast-receiver';

const LOAD_TIMEOUT_MS = 90000;

export default class MpvPlayer extends Player {
  #mpv;
  #logger;
  #urlTemplate;
  #volume = { level: 100, muted: false };
  #selfInitiated = 0;
  #loadToken = 0;

  constructor({ mpv, logger, urlTemplate }) {
    super();
    this.#mpv = mpv;
    this.#logger = logger;
    this.#urlTemplate = urlTemplate;
    this.#mpv.on('end-file', (event) => this.#onEndFile(event));
    this.#mpv.on('property', (name, value) => this.#onPropertyChange(name, value));
    this.#mpv.on('gone', () => this.#onMpvGone());
  }

  async #onEndFile(event) {
    if (event.reason !== 'eof') {
      return;
    }
    this.#logger.debug('[yt-cast-mpv] playback reached end of file');
    try {
      await this.pause();
      await this.next();
    }
    catch (error) {
      this.#logger.error('[yt-cast-mpv] failed to advance queue:', error);
    }
  }

  #onPropertyChange(name, value) {
    if (name === 'volume' && typeof value === 'number') {
      this.#volume.level = Math.round(value);
    }
    if (name === 'mute' && typeof value === 'boolean') {
      this.#volume.muted = value;
    }
    if (this.#selfInitiated > 0) {
      return;
    }
    if (name === 'pause' && typeof value === 'boolean') {
      if (value && this.status === Constants.PLAYER_STATUSES.PLAYING) {
        this.notifyExternalStateChange(Constants.PLAYER_STATUSES.PAUSED);
        return;
      }
      if (!value && this.status === Constants.PLAYER_STATUSES.PAUSED) {
        this.notifyExternalStateChange(Constants.PLAYER_STATUSES.PLAYING);
        return;
      }
    }
    if (name === 'volume' || name === 'mute') {
      this.notifyExternalStateChange();
    }
  }

  #onMpvGone() {
    if (this.status === Constants.PLAYER_STATUSES.IDLE || this.status === Constants.PLAYER_STATUSES.STOPPED) {
      return;
    }
    this.notifyExternalStateChange(Constants.PLAYER_STATUSES.STOPPED);
  }

  async #guard(action) {
    this.#selfInitiated++;
    try {
      return await action();
    }
    finally {
      setTimeout(() => {
        this.#selfInitiated--;
      }, 500);
    }
  }

  #waitForLoad(token) {
    return new Promise((resolve) => {
      let settled = false;
      const finish = (result) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        this.#mpv.off('file-loaded', onLoaded);
        this.#mpv.off('end-file', onEnded);
        resolve(result);
      };
      const onLoaded = () => finish(true);
      const onEnded = (event) => {
        if (event.reason !== 'eof') {
          finish(false);
        }
      };
      const timer = setTimeout(() => finish(false), LOAD_TIMEOUT_MS);
      this.#mpv.on('file-loaded', onLoaded);
      this.#mpv.on('end-file', onEnded);
      if (token !== this.#loadToken) {
        finish(false);
      }
    });
  }

  async doPlay(video, position) {
    const url = this.#urlTemplate.replace('%s', video.id);
    this.#logger.info(`[yt-cast-mpv] playing ${url} from ${position}s`);
    return this.#guard(async () => {
      await this.#mpv.ensureRunning();
      const token = ++this.#loadToken;
      await this.#mpv.setProperty('pause', false).catch(() => undefined);
      const loaded = this.#waitForLoad(token);
      await this.#mpv.command([ 'loadfile', url, 'replace' ]);
      if (!await loaded) {
        this.#logger.error(`[yt-cast-mpv] mpv failed to load ${url}`);
        return false;
      }
      if (token !== this.#loadToken) {
        return false;
      }
      if (position > 0) {
        await this.#mpv.command([ 'seek', position, 'absolute' ]).catch(() => undefined);
      }
      await this.#mpv.setProperty('volume', this.#volume.level).catch(() => undefined);
      await this.#mpv.setProperty('mute', this.#volume.muted).catch(() => undefined);
      return true;
    });
  }

  async doPause() {
    return this.#guard(async () => {
      await this.#mpv.setProperty('pause', true);
      return true;
    });
  }

  async doResume() {
    return this.#guard(async () => {
      await this.#mpv.setProperty('pause', false);
      return true;
    });
  }

  async doStop() {
    this.#loadToken++;
    if (!this.#mpv.running) {
      return true;
    }
    return this.#guard(async () => {
      await this.#mpv.command([ 'stop' ]).catch(() => undefined);
      return true;
    });
  }

  async doSeek(position) {
    return this.#guard(async () => {
      await this.#mpv.command([ 'seek', position, 'absolute' ]);
      return true;
    });
  }

  async doSetVolume(volume) {
    this.#volume = { level: volume.level, muted: volume.muted };
    if (!this.#mpv.running) {
      return true;
    }
    return this.#guard(async () => {
      await this.#mpv.setProperty('volume', volume.level);
      await this.#mpv.setProperty('mute', volume.muted);
      return true;
    });
  }

  async doGetVolume() {
    if (!this.#mpv.running) {
      return this.#volume;
    }
    const level = await this.#mpv.getProperty('volume', this.#volume.level);
    const muted = await this.#mpv.getProperty('mute', this.#volume.muted);
    this.#volume = { level: Math.round(level), muted: Boolean(muted) };
    return this.#volume;
  }

  async doGetPosition() {
    if (!this.#mpv.running) {
      return 0;
    }
    return await this.#mpv.getProperty('time-pos', 0);
  }

  async doGetDuration() {
    if (!this.#mpv.running) {
      return 0;
    }
    return await this.#mpv.getProperty('duration', 0);
  }
}
