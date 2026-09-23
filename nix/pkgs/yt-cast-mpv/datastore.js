import { DataStore } from 'yt-cast-receiver';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

export default class FileDataStore extends DataStore {
  #path;
  #cache = null;
  #writes = Promise.resolve();

  constructor(path) {
    super();
    this.#path = path;
  }

  async #load() {
    if (this.#cache) {
      return this.#cache;
    }
    try {
      this.#cache = JSON.parse(await readFile(this.#path, 'utf8'));
    }
    catch {
      this.#cache = {};
    }
    return this.#cache;
  }

  async set(key, value) {
    const data = await this.#load();
    data[key] = value;
    this.#writes = this.#writes.then(async () => {
      const temp = `${this.#path}.tmp`;
      await mkdir(dirname(this.#path), { recursive: true });
      await writeFile(temp, JSON.stringify(data, null, 2), 'utf8');
      await rename(temp, this.#path);
    }).catch((error) => {
      this.logger.error(`[yt-cast-mpv] failed to persist data store at ${this.#path}:`, error);
    });
    return this.#writes;
  }

  async get(key) {
    const data = await this.#load();
    return data[key] !== undefined ? data[key] : null;
  }
}
