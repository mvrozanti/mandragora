import { spawn } from 'node:child_process';
import { connect } from 'node:net';
import { EventEmitter } from 'node:events';
import { unlink } from 'node:fs/promises';

const CONNECT_RETRY_MS = 150;
const CONNECT_TIMEOUT_MS = 15000;
const PROPERTY_IDS = {
  1: 'pause',
  2: 'volume',
  3: 'mute'
};

export default class MpvClient extends EventEmitter {
  #binary;
  #socketPath;
  #extraArgs;
  #logger;
  #process = null;
  #socket = null;
  #buffer = '';
  #nextRequestId = 1;
  #pending = new Map();
  #starting = null;
  #shuttingDown = false;

  constructor({ binary, socketPath, extraArgs, logger }) {
    super();
    this.#binary = binary;
    this.#socketPath = socketPath;
    this.#extraArgs = extraArgs;
    this.#logger = logger;
  }

  get running() {
    return this.#socket !== null && !this.#socket.destroyed;
  }

  async ensureRunning() {
    if (this.running) {
      return;
    }
    if (!this.#starting) {
      this.#starting = this.#start().finally(() => {
        this.#starting = null;
      });
    }
    return this.#starting;
  }

  async #start() {
    await unlink(this.#socketPath).catch(() => undefined);
    const args = [
      '--idle=yes',
      '--force-window=no',
      '--loop-file=no',
      '--loop-playlist=no',
      '--keep-open=no',
      '--terminal=no',
      `--input-ipc-server=${this.#socketPath}`,
      ...this.#extraArgs
    ];
    this.#logger.debug(`[yt-cast-mpv] spawning ${this.#binary} ${args.join(' ')}`);
    this.#process = spawn(this.#binary, args, { stdio: 'ignore' });
    this.#process.on('exit', (code, signal) => {
      this.#logger.info(`[yt-cast-mpv] mpv exited (code: ${code}, signal: ${signal})`);
      this.#process = null;
      this.#teardownSocket(new Error('mpv exited'));
      if (!this.#shuttingDown) {
        this.emit('gone');
      }
    });
    this.#process.on('error', (error) => {
      this.#logger.error('[yt-cast-mpv] failed to spawn mpv:', error);
    });
    this.#socket = await this.#connectWithRetry();
    this.#socket.setEncoding('utf8');
    this.#socket.on('data', (chunk) => this.#onData(chunk));
    this.#socket.on('error', (error) => this.#logger.error('[yt-cast-mpv] IPC socket error:', error));
    this.#socket.on('close', () => this.#teardownSocket(new Error('IPC socket closed')));
    for (const [ id, name ] of Object.entries(PROPERTY_IDS)) {
      await this.command([ 'observe_property', Number(id), name ]).catch(() => undefined);
    }
  }

  #connectWithRetry() {
    const deadline = Date.now() + CONNECT_TIMEOUT_MS;
    return new Promise((resolve, reject) => {
      const attempt = () => {
        if (this.#process === null) {
          reject(new Error('mpv is not running'));
          return;
        }
        const socket = connect(this.#socketPath);
        socket.once('connect', () => {
          socket.removeAllListeners('error');
          resolve(socket);
        });
        socket.once('error', () => {
          socket.destroy();
          if (Date.now() > deadline) {
            reject(new Error(`timed out connecting to ${this.#socketPath}`));
            return;
          }
          setTimeout(attempt, CONNECT_RETRY_MS);
        });
      };
      attempt();
    });
  }

  #teardownSocket(error) {
    if (this.#socket) {
      this.#socket.removeAllListeners();
      this.#socket.destroy();
      this.#socket = null;
    }
    this.#buffer = '';
    for (const { reject } of this.#pending.values()) {
      reject(error);
    }
    this.#pending.clear();
  }

  #onData(chunk) {
    this.#buffer += chunk;
    let index = this.#buffer.indexOf('\n');
    while (index >= 0) {
      const line = this.#buffer.slice(0, index).trim();
      this.#buffer = this.#buffer.slice(index + 1);
      if (line) {
        this.#onMessage(line);
      }
      index = this.#buffer.indexOf('\n');
    }
  }

  #onMessage(line) {
    let message;
    try {
      message = JSON.parse(line);
    }
    catch {
      return;
    }
    if (message.request_id !== undefined && this.#pending.has(message.request_id)) {
      const { resolve, reject } = this.#pending.get(message.request_id);
      this.#pending.delete(message.request_id);
      if (message.error === 'success') {
        resolve(message.data);
      }
      else {
        reject(new Error(message.error));
      }
      return;
    }
    if (message.event === 'property-change') {
      this.emit('property', message.name, message.data);
      return;
    }
    if (message.event) {
      this.emit(message.event, message);
    }
  }

  command(args) {
    if (!this.running) {
      return Promise.reject(new Error('mpv IPC is not connected'));
    }
    const requestId = this.#nextRequestId++;
    const payload = `${JSON.stringify({ command: args, request_id: requestId })}\n`;
    return new Promise((resolve, reject) => {
      this.#pending.set(requestId, { resolve, reject });
      this.#socket.write(payload, (error) => {
        if (error) {
          this.#pending.delete(requestId);
          reject(error);
        }
      });
    });
  }

  async getProperty(name, fallback = null) {
    try {
      const value = await this.command([ 'get_property', name ]);
      return value === null || value === undefined ? fallback : value;
    }
    catch {
      return fallback;
    }
  }

  setProperty(name, value) {
    return this.command([ 'set_property', name, value ]);
  }

  async quit() {
    this.#shuttingDown = true;
    if (this.running) {
      await this.command([ 'quit' ]).catch(() => undefined);
    }
    if (this.#process) {
      this.#process.kill('SIGTERM');
    }
    this.#teardownSocket(new Error('shutting down'));
    await unlink(this.#socketPath).catch(() => undefined);
  }
}
