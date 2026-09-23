import { hostname } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import YouTubeCastReceiver, { Constants, DefaultLogger } from 'yt-cast-receiver';
import FileDataStore from './datastore.js';
import MpvClient from './mpv.js';
import MpvPlayer from './player.js';

const env = process.env;
const runtimeDir = env.XDG_RUNTIME_DIR || '/tmp';
const stateDir = env.XDG_STATE_HOME || join(env.HOME || '/tmp', '.local/state');
const deviceName = env.YT_CAST_DEVICE_NAME || hostname();

const config = {
  deviceName,
  screenName: env.YT_CAST_SCREEN_NAME || `YouTube on ${deviceName}`,
  brand: env.YT_CAST_BRAND || 'Mandragora',
  model: env.YT_CAST_MODEL || 'Desktop',
  port: Number(env.YT_CAST_PORT || 8099),
  interfaces: (env.YT_CAST_INTERFACES || '').split(',').map((name) => name.trim()).filter(Boolean),
  logLevel: env.YT_CAST_LOG_LEVEL || Constants.LOG_LEVELS.INFO,
  dataStorePath: env.YT_CAST_DATA_STORE || join(stateDir, 'yt-cast-mpv/store.json'),
  mpvBinary: env.YT_CAST_MPV || 'mpv',
  mpvSocket: env.YT_CAST_MPV_SOCKET || join(runtimeDir, 'yt-cast-mpv.sock'),
  mpvArgs: (env.YT_CAST_MPV_ARGS || '').split(' ').map((arg) => arg.trim()).filter(Boolean),
  urlTemplate: env.YT_CAST_URL_TEMPLATE || 'https://www.youtube.com/watch?v=%s'
};

const logger = new DefaultLogger(false);
logger.setLevel(config.logLevel);

const mpv = new MpvClient({
  binary: config.mpvBinary,
  socketPath: config.mpvSocket,
  extraArgs: config.mpvArgs,
  logger
});

const player = new MpvPlayer({ mpv, logger, urlTemplate: config.urlTemplate });

const receiverOptions = {
  device: {
    name: config.deviceName,
    screenName: config.screenName,
    brand: config.brand,
    model: config.model
  },
  dial: {
    port: config.port,
    prefix: '/ytcr'
  },
  dataStore: new FileDataStore(config.dataStorePath),
  logger,
  logLevel: config.logLevel
};

if (config.interfaces.length > 0) {
  receiverOptions.dial.bindToInterfaces = config.interfaces;
}

const receiver = new YouTubeCastReceiver(player, receiverOptions);

receiver.on('senderConnect', (sender) => {
  logger.info(`[yt-cast-mpv] sender connected: ${sender.name}`);
});

receiver.on('senderDisconnect', (sender, implicit) => {
  logger.info(`[yt-cast-mpv] sender disconnected: ${sender.name} (implicit: ${implicit})`);
});

receiver.on('error', (error) => {
  logger.error('[yt-cast-mpv] receiver error:', error);
});

const pairingCodeService = receiver.getPairingCodeRequestService();

pairingCodeService.on('response', (code) => {
  logger.info(`[yt-cast-mpv] manual pairing code (Link with TV code): ${code}`);
});

pairingCodeService.on('error', (error) => {
  logger.error('[yt-cast-mpv] pairing code service error:', error);
});

let stopping = false;

const shutdown = async (signal, code) => {
  if (stopping) {
    return;
  }
  stopping = true;
  logger.info(`[yt-cast-mpv] ${signal}, shutting down`);
  pairingCodeService.stop();
  await receiver.stop().catch((error) => logger.error('[yt-cast-mpv] failed to stop receiver:', error));
  await mpv.quit();
  process.exit(code);
};

receiver.on('terminate', (error) => {
  logger.error('[yt-cast-mpv] receiver terminated:', error);
  void shutdown('terminated', 1);
});

process.on('SIGINT', () => void shutdown('SIGINT', 0));
process.on('SIGTERM', () => void shutdown('SIGTERM', 0));

await receiver.start();
pairingCodeService.start();
logger.info(`[yt-cast-mpv] "${config.deviceName}" advertising DIAL on port ${config.port}`);
