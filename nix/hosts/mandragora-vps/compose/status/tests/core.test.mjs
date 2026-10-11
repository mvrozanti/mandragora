import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import assert from "node:assert/strict";

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const C = require(path.join(here, "..", "static", "status-core.js"));
const oct10 = JSON.parse(readFileSync(path.join(here, "fixtures", "probes-2026-10-10.json"), "utf8"));

const tests = [];
const test = (name, fn) => tests.push([name, fn]);

const at = (utc) => Math.round((Date.parse(utc) / 1000 - oct10.start) / oct10.step);
const column = (hosts, i) => Object.fromEntries(Object.entries(hosts).map(([h, s]) => [h, s[i]]));
const downIn = (col) => Object.keys(col).filter((h) => col[h] === "d").sort();
const blindIn = (col) => Object.keys(col).filter((h) => col[h] === "b").sort();

test("fixture covers 24 h of 48 hosts at a 5-minute step", () => {
  assert.equal(Object.keys(oct10.hosts).length, 48);
  for (const s of Object.values(oct10.hosts)) assert.equal(s.length, 288);
  assert.equal(oct10.step, 300);
});

test("blind rule: the 19:50 round (36 of 48 down, GitHub Pages too) becomes prober-blind", () => {
  const i = at("2026-10-10T22:50:00Z");
  const raw = column(oct10.hosts, i);
  assert.equal(downIn(raw).length, 36);
  assert.equal(raw["mvr.ac"], "d");
  const col = column(C.applyBlind(oct10.hosts), i);
  assert.equal(downIn(col).length, 0);
  assert.equal(blindIn(col).length, 36);
});

test("blind rule: the 20:10 round (45 of 48 down) becomes prober-blind", () => {
  const i = at("2026-10-10T23:10:00Z");
  assert.equal(downIn(column(oct10.hosts, i)).length, 45);
  const col = column(C.applyBlind(oct10.hosts), i);
  assert.equal(downIn(col).length, 0);
  assert.equal(blindIn(col).length, 45);
  assert.deepEqual(Object.keys(col).filter((h) => col[h] === "o").sort(), ["claude.mvr.ac", "kindle.mvr.ac", "term.mvr.ac"]);
});

test("blind rule: the 20:40 failures stay down", () => {
  const i = at("2026-10-10T23:40:00Z");
  const col = column(C.applyBlind(oct10.hosts), i);
  assert.deepEqual(downIn(col), ["chat.mvr.ac", "chess.mvr.ac", "claude.mvr.ac", "voice.mvr.ac"]);
  assert.equal(blindIn(col).length, 0);
});

test("blind rule: single-host failures elsewhere in the day stay down", () => {
  const blinded = C.applyBlind(oct10.hosts);
  assert.deepEqual(downIn(column(blinded, at("2026-10-11T00:55:00Z"))), ["kindle.mvr.ac"]);
  assert.deepEqual(downIn(column(blinded, at("2026-10-11T09:15:00Z"))), ["rgb.mvr.ac"]);
});

test("blind rule: no other bucket of the day turns blind", () => {
  const blinded = C.applyBlind(oct10.hosts);
  const blindBuckets = [];
  for (let i = 0; i < 288; i++) if (blindIn(column(blinded, i)).length) blindBuckets.push(i);
  assert.deepEqual(blindBuckets, [at("2026-10-10T22:50:00Z"), at("2026-10-10T23:10:00Z")]);
});

test("blind rule: mvr.ac down with two others is blind; with one other it is not", () => {
  assert.equal(C.isBlindColumn(["d", "d", "d", "o", "o", "o", "o", "o", "o", "o"], 0), true);
  assert.equal(C.isBlindColumn(["d", "d", "o", "o", "o", "o", "o", "o", "o", "o"], 0), false);
  assert.equal(C.isBlindColumn(["o", "d", "d", "d", "o", "o", "o", "o", "o", "o"], 0), false);
  assert.equal(C.isBlindColumn(["d", "d", "o", "o"], -1), true);
  assert.equal(C.isBlindColumn([".", ".", "d"], -1), true);
  assert.equal(C.isBlindColumn([".", ".", "."], -1), false);
  assert.equal(C.isBlindColumn(["w", "w", "d", "o"], -1), false);
});

test("merge: the VPS cell wins unless it is a gap", () => {
  const desk = { start: 1000 * 300, step: 300, hosts: { a: "ddddd", b: "ooooo" } };
  const vps = { start: 1000 * 300, step: 300, hosts: { a: "o.o.b", b: "....." } };
  const m = C.merge(desk, vps, 300);
  assert.equal(m.hosts.a, "ododb");
  assert.equal(m.hosts.b, "ooooo");
  assert.equal(m.start, 300000);
  assert.equal(m.end, 300000 + 4 * 300);
});

test("merge: sources aligned by bucket timestamp, not by index", () => {
  const desk = { start: 100 * 300, step: 300, hosts: { a: "dddddd" } };
  const vps = { start: 103 * 300, step: 300, hosts: { a: "ooooo", c: "ww" } };
  const m = C.merge(desk, vps, 300);
  assert.equal(m.start, 100 * 300);
  assert.equal(m.end, 107 * 300);
  assert.equal(m.hosts.a, "dddooooo");
  assert.equal(m.hosts.c, "...ww...");
});

test("merge: one source alone, or none", () => {
  assert.equal(C.merge({ start: 300, step: 300, hosts: { a: "od" } }, null).hosts.a, "od");
  assert.equal(C.merge(null, { start: 300, step: 300, hosts: { a: "wo" } }).hosts.a, "wo");
  assert.deepEqual(C.merge(null, null).hosts, {});
});

test("now-state: host-stats wins, the desktop's last bucket fills its gaps", () => {
  const live = { a: { now: { state: "ok" } }, b: { now: { state: "down" } }, c: {}, e: { now: { state: "ok" } }, f: { now: { state: "ok" } }, g: { now: { state: "ok" } } };
  const desk = { start: 300, step: 300, hosts: { a: "dd", c: "ow", d: "od", e: "oo", f: "oo", g: "oo" } };
  assert.deepEqual(C.nowStates(live, desk), { a: "o", b: "d", c: "w", d: "d", e: "o", f: "o", g: "o" });
  assert.deepEqual(C.nowStates(null, desk), { a: "d", c: "w", d: "d", e: "o", f: "o", g: "o" });
});

test("now-state: the blind rule also applies to the latest round", () => {
  const live = {};
  for (const h of ["mvr.ac", "a", "b", "c", "d"]) live[h] = { now: { state: "down" } };
  live.e = { now: { state: "ok" } };
  const now = C.nowStates(live, null);
  assert.equal(Object.values(now).filter((c) => c === "b").length, 5);
});

test("freshness thresholds: fresh below 3 periods, stale from 3, silent from 10", () => {
  assert.equal(C.freshness(1000 + 179, 1000, 60).state, "fresh");
  assert.equal(C.freshness(1000 + 180, 1000, 60).state, "stale");
  assert.equal(C.freshness(1000 + 599, 1000, 60).state, "stale");
  assert.equal(C.freshness(1000 + 600, 1000, 60).state, "silent");
  assert.equal(C.freshness(1000 + 200, 1000, 60).missed, 3);
  assert.equal(C.freshness(null, 1000, 60).state, "missing");
  assert.equal(C.freshness(5000, null, 60).state, "missing");
  assert.equal(C.freshness(900, 1000, 60).state, "fresh");
});

test("pull state: unreachable only when the last failure is newer than the last success", () => {
  assert.equal(C.pullState({ ok_at: 100, fail_at: 200 }).unreachable, true);
  assert.equal(C.pullState({ ok_at: 200, fail_at: 100 }).unreachable, false);
  assert.equal(C.pullState({ ok_at: null, fail_at: 100 }).unreachable, true);
  assert.equal(C.pullState({ ok_at: 100, fail_at: null }).unreachable, false);
  assert.equal(C.pullState(null).unreachable, false);
});

const cen = (o) => C.census(o);
const allUp = () => Object.fromEntries(Array.from({ length: 48 }, (_, k) => ["h" + k + ".mvr.ac", "o"]));
const fresh = { state: "fresh", age: 30, missed: 0 };

test("verdict: silent desktop, VPS still probing", () => {
  const states = allUp();
  for (let k = 0; k < 12; k++) states["h" + k + ".mvr.ac"] = "d";
  const v = C.verdict({ census: cen(states), fresh: { state: "silent", age: 7800, missed: 130 }, pull: { unreachable: true, since: 1000 }, now: 1000 + 7800, probesLive: true, vpsLive: true });
  assert.equal(v.level, "down");
  assert.equal(v.head, "The desktop has gone silent");
  assert.match(v.detail, /No snapshot for 2h 10m\./);
  assert.match(v.detail, /failed to reach it for 2h 10m/);
  assert.match(v.detail, /36 of 48 answer, 12 do not\./);
});

test("verdict: missing snapshot and no live probes", () => {
  const v = C.verdict({ census: cen({}), fresh: { state: "missing", age: null }, pull: null, probesLive: false, vpsLive: false });
  assert.equal(v.level, "down");
  assert.match(v.detail, /No desktop snapshot is available\. Live host probes are unavailable too\./);
});

test("verdict: many hosts down, then a few named", () => {
  const many = allUp();
  for (let k = 0; k < 7; k++) many["h" + k + ".mvr.ac"] = "d";
  assert.equal(C.verdict({ census: cen(many), fresh }).head, "7 of 48 hosts down");
  const few = allUp();
  few["h1.mvr.ac"] = "d";
  few["h2.mvr.ac"] = "d";
  const v = C.verdict({ census: cen(few), fresh });
  assert.equal(v.level, "down");
  assert.equal(v.head, "h1 and h2 not answering");
});

test("verdict: prober blind, restart, slow hosts, all up", () => {
  const blind = allUp();
  blind["h3.mvr.ac"] = "b";
  assert.equal(C.verdict({ census: cen(blind), fresh }).level, "unknown");
  assert.equal(C.verdict({ census: cen(allUp()), fresh, deskUptime: 300 }).head, "The desktop restarted 5m ago");
  const slow = allUp();
  slow["h9.mvr.ac"] = "w";
  assert.equal(C.verdict({ census: cen(slow), fresh }).head, "h9 is slow or erroring");
  const ok = C.verdict({ census: cen(allUp()), fresh, vpsLive: true, hot: { label: "gpu", text: "89%" } });
  assert.equal(ok.level, "ok");
  assert.equal(ok.head, "All 48 answering · gpu at 89%");
  assert.equal(ok.detail, "Both machines up.");
});

test("verdict: stale prefixes the head and lifts ok to warn", () => {
  const v = C.verdict({ census: cen(allUp()), fresh: { state: "stale", age: 200, missed: 3 }, vpsLive: true });
  assert.equal(v.level, "warn");
  assert.equal(v.head, "Stale · All 48 answering");
  assert.match(v.detail, /^Last snapshot 3m ago, 3 pulls missed\./);
});

test("cards: payload flags win; thresholded series are the fallback", () => {
  const sample = JSON.parse(readFileSync(path.join(here, "fixtures", "status-sample.json"), "utf8"));
  assert.deepEqual(C.cardSeries(sample.hosts.desk).map((s) => s.key), ["cpu", "mem", "gpu", "vram", "gputemp"]);
  const flagged = { series: [{ key: "a", warn: 1 }, { key: "b", card: true }] };
  assert.deepEqual(C.cardSeries(flagged).map((s) => s.key), ["b"]);
  const unflagged = { series: [{ key: "a", warn: 1 }, { key: "b" }, { key: "c", warn: 2 }] };
  assert.deepEqual(C.cardSeries(unflagged).map((s) => s.key), ["a", "c"]);
});

test("formatting", () => {
  assert.equal(C.duration(7800), "2h 10m");
  assert.equal(C.duration(3082071), "35d 16h");
  assert.equal(C.fmtValue("B/s", 1889071), "1.9 MB/s");
  assert.equal(C.fmtValue("%", 4.25), "4.3%");
  assert.equal(C.fmtValue("°C", 63.4), "63°C");
  assert.equal(C.fmtValue("%", null), "–");
});

let failed = 0;
for (const [name, fn] of tests) {
  try {
    fn();
    console.log("ok   " + name);
  } catch (e) {
    failed++;
    console.log("FAIL " + name + "\n     " + String(e.message).split("\n").join("\n     "));
  }
}
console.log(`\n${tests.length - failed}/${tests.length} passed`);
process.exit(failed ? 1 : 0);
