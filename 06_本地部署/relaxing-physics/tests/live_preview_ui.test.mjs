/* Playback-state regression tests using Node's standard library, without a browser dependency. */
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import vm from "node:vm";

const source = (await readFile(new URL("../src/ui/live-preview.js", import.meta.url), "utf8"))
  .replace("export function createLivePreview", "function createLivePreview");

/** A small event target used to test transport behavior independently of browser layout. */
class Control {
  constructor() {
    this.value = "0"; this.checked = false; this.listeners = {};
    this.classList = { add() {}, remove() {} };
  }
  addEventListener(type, callback) { (this.listeners[type] ||= []).push(callback); }
  setAttribute(name, value) { this[name] = value; }
  fire(type, event = {}) { for (const callback of this.listeners[type] || []) callback(event); }
}

/** Provide a controlled clock, DOM events and optionally delayed network responses. */
function harness() {
  const nodes = new Map();
  const el = (id) => { if (!nodes.has(id)) nodes.set(id, new Control()); return nodes.get(id); };
  const timers = new Map(), calls = [], urls = new Map();
  let now = 0, frame, timerId = 0, draft = { name: "first" }, blockedFrame = null, heldPrepare = null;
  let blockFrame = false, blockPrepare = false;
  const document = { hidden: false, activeElement: null, getElementById: el,
    querySelector: () => el("panel"), addEventListener: (...args) => el("document").addEventListener(...args) };
  const context = vm.createContext({ document, performance: { now: () => now },
    requestAnimationFrame: (callback) => { frame = callback; },
    setTimeout: (callback) => { timers.set(++timerId, callback); return timerId; },
    clearTimeout: (id) => timers.delete(id),
    URL: { createObjectURL: (blob) => { const id = `blob:${urls.size}`; urls.set(id, blob); return id; },
      revokeObjectURL() {} },
    Image: class { async decode() {} },
    fetch: async (url) => {
      calls.push(url);
      if (blockFrame) await new Promise((resolve) => { blockedFrame = resolve; });
      return { ok: true, blob: async () => url };
    }
  });
  vm.runInContext(source, context);
  let prepares = 0;
  const live = context.createLivePreview({ readConfig: () => draft,
    request: async (_url, options) => {
      const name = JSON.parse(options.body).config.name;
      prepares++;
      if (blockPrepare) await new Promise((resolve) => { heldPrepare = resolve; });
      return { session_id: name, duration: 2, fps: 30, verdict: null };
    } });
  const settle = async () => { for (let i = 0; i < 16; i++) await Promise.resolve(); };
  return { el, live, calls, urls,
    get prepares() { return prepares; },
    async timers() { const pending = [...timers.values()]; timers.clear(); pending.forEach((run) => run()); await settle(); },
    async tick(time) { now = time; frame(time); await settle(); },
    edit(name) { draft = { name }; live.refresh(); },
    holdFrame() { blockFrame = true; },
    async releaseFrame() { blockFrame = false; blockedFrame(); await settle(); },
    holdPrepare() { blockPrepare = true; },
    async releasePrepare() { blockPrepare = false; heldPrepare(); await settle(); },
    frameText() { return urls.get(el("liveImage").src); }
  };
}

test("play, pause, seek, end, restart and looping preserve the requested time", async () => {
  const h = harness(); h.live.refresh({ reset: true }); await h.timers(); await h.tick(0);
  assert.match(h.frameText(), /first\?time=0\.000000/);
  h.el("livePlay").fire("click"); await h.tick(500);
  assert.match(h.frameText(), /time=0\.500000/);
  h.el("livePlay").fire("click"); const count = h.calls.length; await h.tick(1500);
  assert.equal(h.calls.length, count);
  h.el("liveSeek").value = "1.25"; h.el("liveSeek").fire("input"); await h.tick(1600);
  assert.match(h.frameText(), /time=1\.250000/);
  h.el("livePlay").fire("click"); await h.tick(2600);
  assert.match(h.frameText(), /time=2\.000000/);
  assert.equal(h.el("livePlay").textContent, "播放预览");
  h.el("liveRestart").fire("click"); await h.tick(2700);
  assert.match(h.frameText(), /time=0\.000000/);
  h.el("liveLoop").checked = true; h.el("livePlay").fire("click");
  await h.tick(4800); await h.tick(4900);
  assert.match(h.frameText(), /time=0\.100000/);
  assert.equal(h.el("livePlay").textContent, "暂停预览");
});

test("seeking discards old frames and never queues concurrent frame requests", async () => {
  const h = harness(); h.live.refresh({ reset: true }); await h.timers(); await h.tick(0);
  h.holdFrame(); h.el("livePlay").fire("click"); await h.tick(500);
  h.el("liveSeek").value = "1.5"; h.el("liveSeek").fire("input");
  const count = h.calls.length; await h.tick(600); assert.equal(h.calls.length, count);
  await h.releaseFrame(); assert.match(h.frameText(), /time=0\.000000/);
  await h.tick(700); assert.match(h.frameText(), /time=1\.700000/);
});

test("fast edits and edits during preparation apply only the latest configuration", async () => {
  const h = harness(); h.edit("old"); h.edit("new"); await h.timers(); await h.tick(0);
  assert.equal(h.prepares, 1); assert.match(h.frameText(), /new\?/);
  h.holdPrepare(); h.edit("slow"); await h.timers();
  h.edit("latest"); await h.timers(); await h.releasePrepare();
  await h.timers(); await h.tick(50);
  assert.match(h.frameText(), /latest\?/);
});
