window.Room = (function () {
  "use strict";

  const HEADER_BYTES = 8;
  const MAX_BUFFERED = 65536;
  const PING_MS = 4000;

  function connect(handlers) {
    let ws = null;
    let backoff = 500;
    let seq = 0;
    let failures = 0;
    let retry = null;
    let lastHeard = 0;
    let pingSent = 0;

    function probeAuth() {
      fetch("/", { cache: "no-store", redirect: "manual", credentials: "same-origin" })
        .then(function (r) { if (r.type === "opaqueredirect") handlers.authExpired(); })
        .catch(function () {});
    }

    function open() {
      if (retry) { clearTimeout(retry); retry = null; }
      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      ws = new WebSocket(proto + "//" + location.host + "/ws");
      ws.binaryType = "arraybuffer";
      let opened = false;
      ws.onopen = function () {
        opened = true;
        pingSent = 0;
        lastHeard = Date.now();
        failures = 0;
        backoff = 500;
        handlers.open();
      };
      ws.onmessage = function (ev) {
        lastHeard = Date.now();
        if (typeof ev.data === "string") {
          let msg;
          try { msg = JSON.parse(ev.data); } catch (e) { return; }
          handlers.message(msg);
          return;
        }
        if (ev.data.byteLength <= HEADER_BYTES) return;
        const view = new DataView(ev.data);
        handlers.frame({
          sampleRate: view.getUint32(4, true),
          pcm: new Float32Array(ev.data, HEADER_BYTES),
        });
      };
      ws.onclose = function () {
        if (!opened && ++failures >= 2) probeAuth();
        handlers.close();
        retry = setTimeout(open, backoff);
        backoff = Math.min(backoff * 2, 4000);
      };
    }

    function replace() {
      const dead = ws;
      dead.onopen = dead.onmessage = dead.onclose = null;
      try { dead.close(); } catch (e) {}
      handlers.close();
      open();
    }

    setInterval(function () {
      if (!ws || ws.readyState !== WebSocket.OPEN) return;
      if (pingSent && lastHeard < pingSent) { replace(); return; }
      pingSent = Date.now();
      ws.send('{"t":"ping"}');
    }, PING_MS);

    open();

    document.addEventListener("visibilitychange", function () {
      if (document.visibilityState !== "visible" || !ws) return;
      if (retry) {
        backoff = 500;
        open();
      }
    });

    return {
      ready: function () { return ws && ws.readyState === WebSocket.OPEN; },
      send: function (obj) {
        if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
      },
      sendPcm: function (pcm, sampleRate) {
        if (!ws || ws.readyState !== WebSocket.OPEN) return false;
        if (ws.bufferedAmount > MAX_BUFFERED) return false;
        const frame = new ArrayBuffer(HEADER_BYTES + pcm.byteLength);
        const view = new DataView(frame);
        view.setUint32(0, seq, true);
        view.setUint32(4, sampleRate, true);
        new Float32Array(frame, HEADER_BYTES).set(pcm);
        ws.send(frame);
        seq = (seq + 1) >>> 0;
        return true;
      },
    };
  }

  return { connect: connect };
})();
