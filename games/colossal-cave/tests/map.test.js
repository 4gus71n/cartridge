// CaveMap: the auto-mapping minimap (pure logic, no DOM).
// Run: node --test tests/   (tools/run_tests.sh does this)
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");

const WEB = path.join(__dirname, "..", "web");
const CaveMap = require(path.join(WEB, "cavemap.js"));
const LABELS = require(path.join(WEB, "mapdata.js"));
const CaveSession = require(path.join(WEB, "engine.js"));
const createAdvent = require(path.join(WEB, "advent.js"));

function ok(cond, what) { assert.ok(cond, what); }
function eq(a, b, what) { assert.deepStrictEqual(a, b, what + " -> " + JSON.stringify(a)); }

test("direction parsing", () => {

eq(CaveMap.dirOf("w"), "w", "w");
eq(CaveMap.dirOf("WEST"), "w", "WEST");
eq(CaveMap.dirOf("go west"), "w", "go west");
eq(CaveMap.dirOf("  Down  "), "d", "down");
eq(CaveMap.dirOf("northeast"), "ne", "northeast");
eq(CaveMap.dirOf("enter building"), "in", "enter");
eq(CaveMap.dirOf("take lamp"), "", "non-movement");
eq(CaveMap.dirOf("xyzzy"), "", "magic word");
eq(CaveMap.dirOf(""), "", "empty");
eq(CaveMap.dirOf(null), "", "null");
});

test("reading the location out of a save file", () => {
const bytes = new Uint8Array(CaveMap.SAVE_LOC_OFFSET + 8);
bytes[CaveMap.SAVE_LOC_OFFSET] = 11;
eq(CaveMap.locFromSave(bytes), 11, "loc from save");
eq(CaveMap.locFromSave(new Uint8Array(4)), null, "short save");
eq(CaveMap.locFromSave(null), null, "no save");
});

const m = new CaveMap(LABELS);

test("building the room graph", () => {
eq(m.size(), 0, "empty");
ok(m.visit(1, ""), "first room is a change");
eq(m.size(), 1, "one room");
eq([m.rooms[1].x, m.rooms[1].y], [0, 0], "origin at 0,0");

ok(m.visit(2, "west"), "moving west adds a room");
eq([m.rooms[2].x, m.rooms[2].y], [-1, 0], "west is x-1");
eq(m.links.length, 1, "one link");
eq(m.links[0].dir, "w", "link keeps the direction");

ok(!m.visit(2, "look"), "staying put changes nothing");
eq(m.rooms[2].visits, 2, "revisit counted");

ok(!m.visit(1, "east"), "walking back over a known link is not a change");
eq(m.size(), 2, "still two rooms");
eq(m.links.length, 1, "link not duplicated");

ok(m.visit(3, "in"), "entering adds a room");
ok(m.visit(11, "xyzzy"), "magic word still links rooms");
const magic = m.links.filter((l) => l.dir === "");
eq(magic.length, 1, "magic link has no direction (drawn dashed)");

// Up/down change depth so the full map can shade lower levels.
m.visit(3, "out");
m.visit(20, "down");
ok(m.rooms[20].z < m.rooms[3].z, "down lowers the depth");
});

test("rooms never share a grid cell", () => {
const packed = new CaveMap(LABELS);
packed.visit(1, "");
[2, 3, 4, 5, 6, 7, 8].forEach((loc, i) => {
  packed.visit(1, "look");
  packed.visit(loc, "north"); // every room pushed at the same cell
});
const cells = new Set(packed.order.map((l) => packed.rooms[l].x + "," + packed.rooms[l].y));
eq(cells.size, packed.size(), "collisions resolved: one room per cell");
});

test("view bounds", () => {
  const v = m.view();
ok(v.rooms.length === m.size(), "view lists every room");
ok(v.bounds.x1 >= v.bounds.x0 && v.bounds.y1 >= v.bounds.y0, "sane bounds");
eq(v.loc, m.loc, "view reports the player");
});

test("persistence round trip and bad saves", () => {
  const saved = JSON.parse(JSON.stringify(m.toJSON()));
const loaded = new CaveMap(LABELS);
ok(loaded.load(saved), "load accepts its own JSON");
eq(loaded.size(), m.size(), "same rooms");
eq(loaded.links.length, m.links.length, "same links");
eq(loaded.loc, m.loc, "same player location");
loaded.visit(99, "south");
eq(loaded.size(), m.size() + 1, "a restored map keeps growing");

// Corrupt / old saves must be ignored, never throw.
const bad = new CaveMap(LABELS);
eq(bad.load(null), false, "null save");
eq(bad.load({ v: 99, rooms: [] }), false, "future version");
eq(bad.load({ v: 1, rooms: "nope" }), false, "garbage rooms");
eq(bad.size(), 0, "stays empty after a bad load");
});

test("room labels", () => {
eq(LABELS.length, 185, "one label per dungeon location");
eq(m.label(1), "Front of building", "label 1");
eq(m.label(11), "Debris room", "label 11");
ok(m.label(9999).startsWith("Room "), "unknown location falls back");
ok(LABELS.every((l) => typeof l === "string" && l.length > 0 && l.length <= 34), "labels are short strings");
});

test("a real playthrough maps the rooms it walks through", async () => {
  const map = new CaveMap(LABELS);
  let save = null;
  const session = await CaveSession.start({
    createAdvent,
    echo: false,
    onOutput: () => {},
    onSave: (b) => { save = Uint8Array.from(b); },
  });
  const walk = async (cmd) => {
    await session.idle();
    session.send(cmd);
    await session.idle();
    map.visit(CaveMap.locFromSave(save), cmd);
  };
  for (const cmd of ["no", "enter building", "take lamp", "xyzzy"]) await walk(cmd);

  eq(map.label(map.loc), "Debris room", "xyzzy lands in the debris room");
  ok(map.size() >= 3, "start, building and debris room are on the map");
  const magic = map.links.find((l) => !l.dir);
  ok(magic, "the xyzzy teleport is linked without a direction (dashed)");

  // The map survives a reload the way the shell stores it.
  const restored = new CaveMap(LABELS);
  ok(restored.load(JSON.parse(JSON.stringify(map.toJSON()))), "reloads");
  eq(restored.size(), map.size(), "same room count after reload");
  eq(restored.label(restored.loc), "Debris room", "still in the debris room");
});
