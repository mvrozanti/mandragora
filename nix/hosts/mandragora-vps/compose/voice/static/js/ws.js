window.Voice = (function () {
  "use strict";

  const HEADER_BYTES = 8;

  function url() {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    return proto + "//" + location.host + "/ws";
  }

  function connect(session, role, onFrame) {
    const ws = new WebSocket(url() + "?session=" + encodeURIComponent(session) + "&role=" + role);
    ws.binaryType = "arraybuffer";
    let seq = 0;

    const api = {
      ws: ws,
      ready: function () { return ws.readyState === WebSocket.OPEN; },
      send: function (pcm, sampleRate) {
        if (!api.ready()) return -1;
        const header = new ArrayBuffer(HEADER_BYTES);
        const view = new DataView(header);
        view.setUint32(0, seq, true);
        view.setUint32(4, sampleRate, true);
        const bytes = new Uint8Array(pcm.buffer, pcm.byteOffset, pcm.byteLength);
        const frame = new Uint8Array(HEADER_BYTES + bytes.byteLength);
        frame.set(new Uint8Array(header), 0);
        frame.set(bytes, HEADER_BYTES);
        ws.send(frame.buffer);
        return seq++;
      },
      close: function () { try { ws.close(); } catch (e) {} }
    };

    ws.onmessage = function (ev) {
      const view = new DataView(ev.data);
      const frameSeq = view.getUint32(0, true);
      const sampleRate = view.getUint32(4, true);
      const pcm = new Float32Array(ev.data, HEADER_BYTES);
      onFrame({ seq: frameSeq, sampleRate: sampleRate, pcm: pcm });
    };

    return api;
  }

  return { connect: connect };
})();
