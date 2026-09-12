window.AI = (function () {
  "use strict";

  function channel(onFrame) {
    let ws = null;
    let seq = 0;

    function open() {
      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      ws = new WebSocket(`${proto}//${location.host}/ws`);
      ws.binaryType = "arraybuffer";
      ws.onmessage = (ev) => {
        const view = new DataView(ev.data);
        const frameSeq = view.getUint32(0, true);
        const pcm = new Float32Array(ev.data, 8);
        onFrame({ seq: frameSeq, pcm });
      };
      return ws;
    }

    function send(pcm) {
      if (!ws || ws.readyState !== WebSocket.OPEN) return -1;
      const header = new ArrayBuffer(8);
      const view = new DataView(header);
      view.setUint32(0, seq, true);
      view.setUint32(4, 0, true);
      const payload = new Uint8Array(pcm.buffer);
      const frame = new Uint8Array(8 + payload.byteLength);
      frame.set(new Uint8Array(header), 0);
      frame.set(payload, 8);
      ws.send(frame.buffer);
      return seq++;
    }

    function close() {
      if (ws) { try { ws.close(); } catch (e) {} ws = null; }
    }

    function ready() {
      return !!ws && ws.readyState === WebSocket.OPEN;
    }

    return { open, send, close, ready };
  }

  return { channel };
})();
