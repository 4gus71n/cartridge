// Headless tests for the Colossal Cave wasm engine + shell helpers.
// Run: node --test tests/   (tools/run_tests.sh does this)
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");

const WEB = path.join(__dirname, "..", "web");
const CaveSession = require(path.join(WEB, "engine.js"));
const createAdvent = require(path.join(WEB, "advent.js"));
const CaveText = require(path.join(WEB, "cavetext.js"));

// Start a session, feed `cmds` one per prompt, return {out, saves, session}.
async function play(cmds, opts = {}) {
  let out = "";
  const saves = [];
  const s = await CaveSession.start({
    createAdvent,
    save: opts.save,
    echo: true,
    onOutput: (t) => { out += t; },
    onSave: (b) => saves.push(Uint8Array.from(b)),
  });
  for (const c of cmds) {
    await s.idle();
    if (s.exited) break;
    s.send(c);
  }
  await s.idle();
  return { out, saves, session: s };
}

test("opening: no / enter building / take lamp / inventory", async () => {
  const { out, saves, session } = await play(["no", "enter building", "take lamp", "inventory"]);
  assert.match(out, /Welcome to Adventure!!\s+Would you like instructions\?/);
  assert.match(out, /end of a road before a small brick building/);
  assert.match(out, /inside a building, a well house for a large spring/);
  assert.match(out, /There is a shiny brass lamp nearby\./);
  assert.match(out, /> take lamp\s+OK/);
  assert.match(out, /You are currently holding the following:\s+Brass lantern/);
  assert.equal(session.exited, false);
  assert.equal(session.waiting, true);
  // one autosave per main command prompt (4 prompts after the yes/no question)
  assert.ok(saves.length >= 4, "autosaves: " + saves.length);
  assert.ok(saves[saves.length - 1].length > 100);
});

test("save/restore round trip keeps location and inventory", async () => {
  const first = await play(["no", "enter building", "take lamp", "take keys", "inventory"]);
  const saved = first.saves[first.saves.length - 1];
  // through localStorage-style base64 like the browser shell does
  const b64 = CaveText.toB64(saved);
  const bytes = CaveText.fromB64(b64);
  assert.deepEqual(Array.from(bytes), Array.from(saved));

  const second = await play(["inventory", "look"], { save: bytes });
  // restored games skip the instructions question and report the score
  assert.doesNotMatch(second.out, /Would you like instructions/);
  assert.match(second.out, /out of a possible 430/);
  assert.match(second.out, /You are currently holding the following:[\s\S]*Brass lantern/);
  assert.match(second.out, /Set of keys/);
  assert.match(second.out, /inside a building, a well house/);
  assert.doesNotMatch(second.out, /There is a shiny brass lamp nearby/);

  // the restored game keeps autosaving and can continue
  const third = await play(["drop lamp", "out", "look"], { save: second.saves[second.saves.length - 1] });
  assert.match(third.out, /> drop lamp\s+OK/);
  assert.match(third.out, /end of a road/);
});

test("quitting ends the session (end-of-game path)", async () => {
  let exitCode = null;
  let out = "";
  const s = await CaveSession.start({
    createAdvent, echo: true, onOutput: (t) => { out += t; },
    onExit: (c) => { exitCode = c; },
  });
  for (const c of ["no", "quit", "yes"]) { await s.idle(); s.send(c); }
  await s.idle();
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(s.exited, true);
  assert.equal(exitCode, 0);
  assert.match(out, /Do you really want to quit now\?/);
  assert.match(out, /You scored \d+ out of a possible 430/);
  assert.equal(s.send("look"), false, "no input after exit");
});

test("EOF (null line) terminates cleanly", async () => {
  const { out, session } = await play(["no", null]);
  assert.equal(session.exited, true);
  assert.match(out, /You scored/);
});

test("reflow joins hard-wrapped prose but keeps lists", () => {
  const src = "You are standing at the end of a road before a small brick building.\n" +
    "Around you is a forest.  A small stream flows out of the building and\n" +
    "down a gully.\n\nYou are currently holding the following:\nBrass lantern\nSet of keys\n";
  const p = CaveText.reflow(src);
  assert.equal(p.length, 2);
  assert.equal(p[0], "You are standing at the end of a road before a small brick building. " +
    "Around you is a forest.  A small stream flows out of the building and down a gully.");
  assert.equal(p[1], "You are currently holding the following:\nBrass lantern\nSet of keys");
});

test("wordAt / addWord / setVerb", () => {
  const s = "There is a shiny brass lamp nearby.";
  assert.equal(CaveText.wordAt(s, s.indexOf("lamp") + 2).word, "lamp");
  assert.equal(CaveText.wordAt(s, s.indexOf("nearby") + 6).word, "nearby"); // just after the word
  assert.equal(CaveText.wordAt(s, s.indexOf(" brass")).word, "shiny");
  assert.equal(CaveText.wordAt("a  b", 2).word, "");
  assert.equal(CaveText.addWord("take", "LAMP"), "take lamp");
  assert.equal(CaveText.addWord("", "Lamp"), "lamp");
  assert.equal(CaveText.setVerb("lamp", "take"), "take lamp");
  assert.equal(CaveText.setVerb("", "drop"), "drop ");
});

test("trimTranscript keeps the newest entries within budget", () => {
  const e = [];
  for (let i = 0; i < 100; i++) e.push({ k: "out", t: "x".repeat(100) });
  const kept = CaveText.trimTranscript(e, 1050);
  assert.equal(kept.length, 10);
  assert.equal(kept[kept.length - 1], e[99]);
});
