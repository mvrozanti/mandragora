const WORDS = "ableacidalsoapexaquaarchatomauntawayaxisbackbaldbarnbeltbetabiasbluebodybragbrewbulbbuzzcalmcashcatschefcityclawcodecolacookcostcruxcurlcuspcyandarkdatadaysdelidicedietdoordowndrawdropdrumdulldutyeacheasyechoedgeepicevenexamexiteyesfactfairfernfigsfilmfishfizzflapflewfluxfoxyfreefrogfuelfundgalagamegeargemsgiftgirlglowgoodgraygrimgurugushgyrohalfhanghardhawkheathelphighhillholyhopehornhutsicedideaidleinchinkyintoirisironitemjadejazzjoinjoltjowljudojugsjumpjunkjurykeepkenokeptkeyskickkilnkingkitekiwiknoblamblavalazyleaflegsliarlimplionlistlogoloudloveluaulucklungmainmanymathmazememomenumeowmildmintmissmonknailnavyneednewsnextnoonnotenumbobeyoboeomitonyxopenovalowlspaidpartpeckplaypluspoempoolposepuffpumapurrquadquizraceramprealredorichroadrockroofrubyruinrunsrustsafesagascarsetssilkskewslotsoapsolosongstubsurfswantacotasktaxitenttiedtimetinytoiltombtoystriptunatwinuglyundouniturgeuservastveryvetovialvibeviewvisavoidvowswallwandwarmwaspwavewaxywebswhatwhenwhizwolfworkyankyawnyellyogayurtzapszerozestzinczonezoom";

const MINIMAL = new Map();
for (let i = 0; i < 256; i++) MINIMAL.set(WORDS[i * 4] + WORDS[i * 4 + 3], i);

const CRC_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  CRC_TABLE[n] = c >>> 0;
}

export function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function u32be(bytes, at) {
  return ((bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]) >>> 0;
}

function bytewordsDecode(text) {
  if (text.length % 2 !== 0 || text.length < 10) throw new Error("bytewords: bad length " + text.length);
  const all = new Uint8Array(text.length / 2);
  for (let i = 0; i < all.length; i++) {
    const word = text.substr(i * 2, 2);
    const value = MINIMAL.get(word);
    if (value === undefined) throw new Error("bytewords: unknown word '" + word + "'");
    all[i] = value;
  }
  const body = all.subarray(0, all.length - 4);
  if (crc32(body) !== u32be(all, all.length - 4)) throw new Error("bytewords: checksum mismatch");
  return body;
}

function bytewordsEncode(bytes) {
  const c = crc32(bytes);
  const all = new Uint8Array(bytes.length + 4);
  all.set(bytes);
  all.set([c >>> 24, (c >>> 16) & 0xff, (c >>> 8) & 0xff, c & 0xff], bytes.length);
  let out = "";
  for (const b of all) out += WORDS[b * 4] + WORDS[b * 4 + 3];
  return out;
}

function readHead(buf, pos) {
  if (pos >= buf.length) throw new Error("cbor: truncated");
  const initial = buf[pos++];
  const major = initial >> 5;
  const info = initial & 0x1f;
  let value;
  if (info < 24) value = info;
  else if (info === 24) { value = buf[pos]; pos += 1; }
  else if (info === 25) { value = (buf[pos] << 8) | buf[pos + 1]; pos += 2; }
  else if (info === 26) { value = u32be(buf, pos); pos += 4; }
  else if (info === 27) { value = u32be(buf, pos) * 0x100000000 + u32be(buf, pos + 4); pos += 8; }
  else throw new Error("cbor: unsupported head 0x" + initial.toString(16));
  if (pos > buf.length) throw new Error("cbor: truncated");
  return { major, value, pos };
}

function decodePart(buf) {
  let h = readHead(buf, 0);
  if (h.major !== 4 || h.value !== 5) throw new Error("part: not a 5-element array");
  const nums = [];
  for (let i = 0; i < 4; i++) {
    h = readHead(buf, h.pos);
    if (h.major !== 0) throw new Error("part: expected uint");
    nums.push(h.value);
  }
  h = readHead(buf, h.pos);
  if (h.major !== 2) throw new Error("part: expected byte string");
  const data = buf.slice(h.pos, h.pos + h.value);
  if (data.length !== h.value) throw new Error("part: truncated data");
  return { seqNum: nums[0], seqLen: nums[1], messageLen: nums[2], checksum: nums[3], data };
}

function head(major, value) {
  const m = major << 5;
  if (value < 24) return [m | value];
  if (value < 0x100) return [m | 24, value];
  if (value < 0x10000) return [m | 25, value >> 8, value & 0xff];
  return [m | 26, value >>> 24, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff];
}

const utf8 = new TextEncoder();

function text(s) {
  const b = utf8.encode(s);
  return [...head(3, b.length), ...b];
}

export function encodePinReply(id, data) {
  return Uint8Array.from([
    ...head(5, 3),
    ...text("id"), ...text(id),
    ...text("method"), ...text("pin"),
    ...text("params"), ...head(5, 1), ...text("data"), ...text(data),
  ]);
}

export class UrStream {
  constructor() {
    this.reset();
  }

  reset() {
    this.type = null;
    this.seqLen = 0;
    this.messageLen = 0;
    this.checksum = 0;
    this.fragments = new Map();
    this.message = null;
  }

  get received() { return this.fragments.size; }
  get expected() { return this.seqLen; }
  get complete() { return this.message !== null; }
  get progress() {
    if (this.message) return 1;
    return this.seqLen ? this.fragments.size / this.seqLen : 0;
  }

  receive(raw) {
    const s = raw.trim().toLowerCase();
    if (!s.startsWith("ur:")) throw new Error("not a ur: string");
    const segments = s.slice(3).split("/");
    const type = segments[0];
    if (segments.length === 2) {
      this.reset();
      this.type = type;
      this.message = bytewordsDecode(segments[1]);
      return true;
    }
    if (segments.length !== 3) throw new Error("ur: unexpected path " + segments.length);
    const part = decodePart(bytewordsDecode(segments[2]));
    const sameStream = this.type === type && this.seqLen === part.seqLen
      && this.messageLen === part.messageLen && this.checksum === part.checksum;
    if (!sameStream) {
      this.reset();
      this.type = type;
      this.seqLen = part.seqLen;
      this.messageLen = part.messageLen;
      this.checksum = part.checksum;
    }
    if (this.message) return false;
    if (part.seqNum < 1 || part.seqNum > part.seqLen) return false;
    if (this.fragments.has(part.seqNum)) return false;
    this.fragments.set(part.seqNum, part.data);
    if (this.fragments.size === this.seqLen) this.assemble();
    return true;
  }

  assemble() {
    const fragLen = this.fragments.get(1).length;
    const joined = new Uint8Array(fragLen * this.seqLen);
    for (let i = 1; i <= this.seqLen; i++) joined.set(this.fragments.get(i), (i - 1) * fragLen);
    const message = joined.slice(0, this.messageLen);
    if (crc32(message) !== this.checksum) {
      this.fragments.clear();
      throw new Error("message checksum mismatch");
    }
    this.message = message;
  }
}

function nominalFragmentLength(messageLen, minFragLen, maxFragLen) {
  const maxCount = Math.max(1, Math.floor(messageLen / minFragLen));
  let fragLen = messageLen;
  for (let count = 1; count <= maxCount; count++) {
    fragLen = Math.ceil(messageLen / count);
    if (fragLen <= maxFragLen) break;
  }
  return fragLen;
}

export function encodeUr(type, message, maxFragLen = 60, minFragLen = 10) {
  const len = message.length;
  const fragLen = nominalFragmentLength(len, minFragLen, maxFragLen);
  const count = Math.ceil(len / fragLen);
  if (count === 1) return [("ur:" + type + "/" + bytewordsEncode(message)).toUpperCase()];
  const checksum = crc32(message);
  const parts = [];
  for (let i = 0; i < count; i++) {
    const data = new Uint8Array(fragLen);
    data.set(message.subarray(i * fragLen, Math.min(len, (i + 1) * fragLen)));
    const cbor = Uint8Array.from([
      ...head(4, 5), ...head(0, i + 1), ...head(0, count), ...head(0, len), ...head(0, checksum),
      ...head(2, fragLen), ...data,
    ]);
    parts.push(("ur:" + type + "/" + (i + 1) + "-" + count + "/" + bytewordsEncode(cbor)).toUpperCase());
  }
  return parts;
}
