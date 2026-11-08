// Native preview versus the WebAssembly module. Both must print the same text.
//   node tools/check_wasm.mjs
// Optional: node tools/check_wasm.mjs path/to/diary_sim.wasm path/to/diary_sim
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const wasmPath = resolve(process.argv[2] || (root + "/wasm/obj/diary_sim.wasm"));
const binPath = resolve(process.argv[3] || (root + "/bin/diary_sim"));
const cases = [
  { seed: 42, ticks: 200 },
  { seed: 7, ticks: 50 },
];

function u32(memory, addr) {
  return new DataView(memory.buffer).getUint32(addr, true);
}

async function wasmText(bytes, seed, ticks) {
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const ex = instance.exports;
  ex.adainit();
  ex.ds_set_seed(seed);
  ex.ds_set_ticks(ticks);
  ex._ada_diary_sim();
  const ptr = ex.ds_out_ptr();
  const len = ex.ds_out_len();
  const text = new TextDecoder().decode(new Uint8Array(ex.memory.buffer, ptr, len));
  if (!text.startsWith("demo preview:")) {
    const file = new TextDecoder().decode(new Uint8Array(ex.memory.buffer, ex.ds_exc.value, u32(ex.memory, ex.ds_exc_len.value)));
    throw new Error("wasm produced no preview (" + file + ")");
  }
  return text;
}

const bytes = readFileSync(wasmPath);
let failed = 0;
for (const item of cases) {
  const native = execFileSync(binPath, ["--preview", "--ticks", String(item.ticks), "--seed", String(item.seed)], {
    encoding: "utf8",
  });
  const wasm = await wasmText(bytes, item.seed, item.ticks);
  if (native !== wasm) {
    failed += 1;
    console.error("MISMATCH seed " + item.seed + " ticks " + item.ticks);
    console.error("native bytes " + Buffer.byteLength(native) + " wasm bytes " + Buffer.byteLength(wasm));
  } else {
    console.log("match seed " + item.seed + " ticks " + item.ticks + " (" + native.length + " chars)");
  }
}
if (failed) process.exit(1);
console.log("native and wasm previews match");
