import { WebSocketServer } from 'ws';
import { timingSafeEqual } from 'node:crypto';
import {
  SmartSpectraSDK,
  CameraSelection,
  breathingMetrics,
  cardioMetrics,
  decodeMetrics,
  setMetricsClass,
} from '@smartspectra/node-sdk';
import { Metrics } from '@smartspectra/node-sdk/messages';

const PORT = 8765;
setMetricsClass(Metrics);
const apiKey = process.env.PRESAGE_API_KEY;
const sessionToken = process.env.PRESAGE_SESSION_TOKEN;
delete process.env.PRESAGE_API_KEY;
delete process.env.PRESAGE_SESSION_TOKEN;

const wss = new WebSocketServer({ host: '127.0.0.1', port: PORT });
const serverReady = new Promise((resolve, reject) => {
  wss.once('listening', resolve);
  wss.once('error', reject);
});
let sdk;
let stopping = false;
let client = null;

let lastStatus = 'BRIDGE ONLINE · WAITING FOR GODOT';

function send(payload) {
  if (client?.readyState === 1) client.send(JSON.stringify(payload));
}
function sendStatus(status) {
  lastStatus = String(status);
  send({ type: 'status', status: lastStatus });
}
function latestSample(list) {
  if (!Array.isArray(list) || list.length === 0) return null;
  // The newest array item can occasionally be incomplete. Walk backwards
  // and keep the latest finite value instead of dropping the whole packet.
  for (let index = list.length - 1; index >= 0; index -= 1) {
    const sample = list[index];
    const value = Number(sample?.value);
    if (!Number.isFinite(value) || value <= 0) continue;
    return {
      value,
      confidence: Number.isFinite(Number(sample?.confidence)) ? Number(sample.confidence) : null,
      stable: typeof sample?.stable === 'boolean' ? sample.stable : null,
    };
  }
  return null;
}
function emitMetrics(buffer, timestampUs) {
  try {
    const metrics = decodeMetrics(buffer);
    if (Buffer.isBuffer(metrics)) {
      sendStatus('METRICS ARRIVED · DECODER DID NOT RETURN OBJECT');
      return;
    }
    const pulseSamples = metrics?.cardio?.pulseRate;
    const breathingSamples = metrics?.breathing?.rate;
    const pulse = latestSample(pulseSamples);
    const breathing = latestSample(breathingSamples);
    const pulseCount = Array.isArray(pulseSamples) ? pulseSamples.length : 0;
    const breathingCount = Array.isArray(breathingSamples) ? breathingSamples.length : 0;

    if (!pulse && !breathing) {
      sendStatus(`CAMERA RUNNING · WAITING FOR VALID RATES (HR ${pulseCount} / BR ${breathingCount})`);
      return;
    }
    send({
      type: 'metrics',
      timestamp_us: Number(timestampUs) || null,
      received_at_ms: Date.now(),
      heart_rate: pulse,
      breathing_rate: breathing,
    });
    const pieces = [];
    if (pulse) pieces.push(`HR ${pulse.value.toFixed(1)} BPM`);
    if (breathing) pieces.push(`BREATH ${breathing.value.toFixed(1)}/MIN`);
    sendStatus(`LIVE MEASUREMENTS · ${pieces.join(' · ')}`);
  } catch (error) {
    sendStatus(`METRICS DECODE ERROR · ${error?.message ?? 'unknown error'}`);
    console.error('Could not decode a sensor packet:', error?.message ?? 'unknown error');
  }
}

wss.on('connection', (socket) => {
  let authenticated = false;
  const authTimeout = setTimeout(() => socket.close(1008, 'Session authentication required'), 5000);
  socket.on('message', (raw) => {
    if (authenticated) return;
    try {
      const message = JSON.parse(raw.toString());
      const supplied = Buffer.from(String(message?.token ?? ''));
      const expected = Buffer.from(String(sessionToken ?? ''));
      if (message?.type !== 'auth' || supplied.length === 0 || supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
        socket.close(1008, 'Invalid local session');
        return;
      }
      authenticated = true;
      clearTimeout(authTimeout);
      client = socket;
      sendStatus(lastStatus);
    } catch {
      socket.close(1008, 'Malformed authentication message');
    }
  });
  socket.on('close', () => {
    clearTimeout(authTimeout);
    if (client === socket) client = null;
  });
});

async function shutdown() {
  if (stopping) return;
  stopping = true;
  try { if (sdk) await sdk.stopAsync(); } catch {}
  try { if (sdk) await sdk.destroy(); } catch {}
  wss.close();
}

async function main() {
  await serverReady;
  if (!apiKey) throw new Error('PRESAGE_API_KEY was not provided by the game');
  if (!sessionToken) throw new Error('PRESAGE_SESSION_TOKEN was not provided by the game');
  sdk = new SmartSpectraSDK({
    apiKey,
    requestedMetrics: [...breathingMetrics, ...cardioMetrics],
    enableTelemetry: false,
  });
  sdk.on('metrics', emitMetrics);
  const processingNames = {
    0: 'UNINITIALIZED', 1: 'IDLE', 2: 'STARTING', 3: 'RUNNING',
    4: 'STOPPING', 5: 'ERROR',
  };
  const validationNames = {
    0: 'READY · HOLD STILL',
    1: 'NO FACE FOUND · CENTER YOUR FACE',
    2: 'MULTIPLE FACES · KEEP ONE PERSON IN FRAME',
    3: 'FACE NOT CENTERED · LOOK AT THE CAMERA',
    4: 'FACE SIZE OUT OF RANGE · ADJUST DISTANCE',
    5: 'TOO DARK · INCREASE LIGHT ON YOUR FACE',
    6: 'TOO BRIGHT · REDUCE LIGHT',
    7: 'CHEST NOT VISIBLE · SHOW YOUR UPPER BODY',
    10: 'CAMERA TUNING · HOLD STILL',
    11: 'LOW FRAME RATE · CLOSE CAMERA-HEAVY APPS',
    12: 'TOO MUCH MOVEMENT · HOLD STILL',
    13: 'TOO CLOSE · MOVE BACK',
    14: 'TOO FAR · MOVE CLOSER',
    15: 'FACE TOO HIGH · ADJUST CAMERA',
    16: 'FACE TOO LOW · ADJUST CAMERA',
    17: 'FACE NOT FORWARD · FACE THE CAMERA',
  };
  sdk.on('processingStatus', (status) => {
    const label = processingNames[Number(status)] ?? String(status);
    sendStatus(`PRESAGE ${label}`);
  });
  sdk.on('validationStatus', (code, _timestamp, hint) => {
    const label = hint ? String(hint).toUpperCase() : (validationNames[Number(code)] ?? `SENSOR CHECK ${code}`);
    sendStatus(label);
  });
  sdk.on('error', (code, message, retryable) => {
    const safeMessage = String(message ?? 'unknown error').replaceAll(apiKey, '[REDACTED]');
    console.error('SmartSpectra error code:', code, 'message:', safeMessage, 'retryable=', Boolean(retryable));
    sendStatus(`PRESAGE ERROR ${code} · ${safeMessage}`.slice(0, 180));
  });
  sdk.useCamera(CameraSelection.default);
  sendStatus('CHECKING CAMERA READINESS…');
  const readiness = await sdk.checkDeviceReadiness();
  console.log('Camera readiness:', readiness.verdict, readiness.reason);
  sendStatus(`CAMERA ${String(readiness.verdict).toUpperCase()}: ${String(readiness.reason)}`);
  if (readiness.verdict === 'blocked') {
    throw new Error(`Camera readiness blocked: ${readiness.reason}`);
  }
  sdk.start();
  sendStatus('CAMERA STARTED · CENTER FACE AND UPPER CHEST · WAITING FOR READINGS');
}

main().catch((error) => {
  console.error('Presage bridge failed:', error?.message ?? 'unknown error');
  sendStatus(`PRESAGE INITIALIZATION FAILED · ${String(error?.message ?? 'unknown error')}`.slice(0, 180));
  setTimeout(shutdown, 250);
});

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
