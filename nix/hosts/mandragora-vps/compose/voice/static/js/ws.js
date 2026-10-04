window.Room = (function () {
  "use strict";

  const HEADER_BYTES = 8;
  const MAX_BUFFERED = 65536;

  function connect(handlers) {
    let ws = null;
    let backoff = 500;
    let seq = 0;

    function open() {
      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      ws = new WebSocket(proto + "//" + location.host + "/ws");
      ws.binaryType = "arraybuffer";
      ws.onopen = function () {
        backoff = 500;
        handlers.open();
      };
      ws.onmessage = function (ev) {
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
        handlers.close();
        setTimeout(open, backoff);
        backoff = Math.min(backoff * 2, 8000);
      };
    }

    open();

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
