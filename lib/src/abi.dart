// The resident <-> stage ABI (zephyr_scion tools/imcu/stage.h, imcu_broker/hybrid/hyb_main.c).
//
// A stage is `int stage(struct ctx *c)` at the start of its slot. The EISC gcc calling
// convention: first argument and return value in R8 (second argument R9); R0-R7 and
// R10-R14 are preserved by callees; LR holds the return address; %SP is its own register.

/// Slot base addresses in ISPM (warp, scan, vertex). The resident owns ISPM below 0xA000.
const slotAddr = {0: 0x1000C000, 1: 0x1000E000, 2: 0x1000A000};
const slotBytes = 0x2000;

/// The OSC upload buffer caps a blob at 4 KB.
const maxBlobBytes = 4096;

/// struct ctx field offsets (bytes): x y u v t frame heat mvx mvy luma knob[8] rnd w h
/// out[16] p[4] sin256.
const ctxInput = {
  'x': 0, 'y': 4, 'u': 8, 'v': 12, 't': 16, 'frame': 20, 'heat': 24, 'mvx': 28, 'mvy': 32,
  'luma': 36,
  'k0': 40, 'k1': 44, 'k2': 48, 'k3': 52, 'k4': 56, 'k5': 60, 'k6': 64, 'k7': 68,
  'rnd': 72, 'w': 76, 'h': 80,
  'p0': 148, 'p1': 152, 'p2': 156, 'p3': 160,
};
const ctxOut = 84; // int out[16]
const ctxSin = 164; // const short *sin256
const ctxBytes = 168;

/// Output names (shader.py OUTPUTS). Several stages share slots: warp dx/dy, scan gr..pb,
/// vertex vx/vy/p0..p3, and o0..o15 address any slot.
const outputSlot = {
  'dx': 0, 'dy': 1,
  'gr': 0, 'gg': 1, 'gb': 2, 'swap': 3, 'pr': 4, 'pg': 5, 'pb': 6,
  'o0': 0, 'o1': 1, 'o2': 2, 'o3': 3, 'o4': 4, 'o5': 5, 'o6': 6, 'o7': 7,
  'o8': 8, 'o9': 9, 'o10': 10, 'o11': 11, 'o12': 12, 'o13': 13, 'o14': 14, 'o15': 15,
  'vx': 0, 'vy': 1, 'p0': 2, 'p1': 3, 'p2': 4, 'p3': 5,
};
