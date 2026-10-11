# ae32k_shader_compiler

Compiler for the Scion shader language (`docs/SHADER_LANGUAGE_REFERENCE.md` in zephyr_scion)
straight to native AE32000 code for the MDIN-6xx's internal MCU. Pure Dart: it runs as a CLI and
inside `scion_controller_app` on every Flutter platform.

## Why it exists

Scion runs small user shaders on the AE32000 core inside the MDIN video processor:
- **warp:** per grid point;
- **scan:** inside the scanline, writing MDIN registers through an `@out` map;
- **vertex:** per point of a display list.

They used to be built by `tools/imcu/shader.py`, which turned the shader into C and compiled it
with a vendor-modified ae32000-elf-gcc. That gcc is a Windows binary, so every build needed
Wine. That ruled out compiling shaders on the controller app, on other machines, or in CI.

The gcc output was also large and slow for this job. Each blob carried a full copy of the Q16
runtime, about 1.4 KB of a 4 KB upload limit (an empty stage was 1400 bytes). The general-purpose `q_div`/`q_mul` routines cost
hundreds to thousands of cycles per call, on a CPU that has a fixed per-line or per-point
budget. The demo's 96-point checkerboard missed every other vsync with gcc-built vertex stages
(about 2200 cycles per point). With this compiler's stages (88 cycles per point, `--fast`) it
renders every frame.

This compiler replaces that path for the subset the shaders need, not full C:
- **No Wine.** It is a single Dart package and compiles a stage in well under a second.
- **Same results.** Every result is bit-identical to shader.py's C. Overflow, saturation and
  the odd corner of `q_div` are all reproduced, unless you ask for `--fast`.
- **Drop-in blobs.** Same slots, same entry convention, same OSC upload and `@out` packets, so
  the resident and the upload path did not change.

## The language

A shader is a few lines of C-like code that run once per evaluation:
- **warp stage:** per grid point;
- **scan stage:** per point while the raster draws the frame;
- **vertex stage:** per point of a display list.

It reads `in.*` and writes `out.*`. Every value is a Q16 fixed-point number (16.16, range about
+-32768), because the AE32000 has no FPU. There are no loops, no user functions and no arrays,
so every evaluation takes bounded time inside a video frame.

The full reference is [`docs/LANGUAGE.md`](docs/LANGUAGE.md): syntax, every operator's exact
overflow behaviour, every function, the inputs and outputs per stage, the `@out` map, `--fast`,
and what each operation costs.

**A warp stage** displaces the picture. These concentric ripples are `tools/imcu/examples/ripple.ss`:

```c
let du = in.u - 0.5;
let dv = (in.v - 0.5) * 0.5625;           // 1080/1920: circular in pixels
let r = sqrt(du * du + dv * dv) + 0.0005;
let a = (in.k0 + 2) * sin(r * 8 - in.t * (in.k1 + 0.5));   // k0, k1: live knobs; angles in turns
out.dx = a * du / r;                      // displacement in pixels
out.dy = a * dv / r;
```

**A scan stage** writes MDIN registers as the raster passes, through `@out` lines that name
registers from `tools/imcu/registers.inc`. These per-line output-CSC gains are
`tools/imcu/examples/corpus/s02_csc_gain_rows.ss` (abridged):

```c
@out gr out0_csc_y0
@out gr out0_csc_y1                       // one output can drive several register fields
@out gb out0_csc_b0
out.gr = 0.5 + 0.5 * sin(in.v * 2 + in.t * 0.3);
out.gb = 0.5 + 0.5 * cos(in.v * 3 - in.t * 0.2);
```

**A vertex stage** emits points for the scan stage. This 8 x 12 checkerboard of 240 x 96 px
cells is `tools/imcu/examples/verts_test.ss`:

```c
let col = mod(in.x, 8);                   // in.x = point index
let sl = floor(in.x / 8);
out.vx = col * 240;
out.vy = sl * 96;
out.p0 = mod(col + sl, 2);                // passed to the scan stage as in.p0
out.p3 = 96;
```

### Compared with C

The same ripple written in C, as `tools/imcu/shader.py` generates it for gcc (`c` is the context
struct, `L_*` the locals):

```c
L_du = (c->u - 32768);
L_dv = q_mul((c->v - 32768), 36864);
L_r  = (q_sqrt((q_mul(L_du, L_du) + q_mul(L_dv, L_dv))) + 33);
L_a  = q_mul((c->knob[0] + 131072), q_sin((q_mul(L_r, 524288) - q_mul(c->t, (c->knob[1] + 32768)))));
c->out[0] = q_div(q_mul(L_a, L_du), L_r);
c->out[1] = q_div(q_mul(L_a, L_dv), L_r);
```

The C version also needs the Q16 runtime: about 1.4 KB of `q_mul`, `q_div`, `q_sin`, `q_sqrt`,
... in every blob.

Differences between the two:
- **Arithmetic:** the shader language says the arithmetic once, and Q16 is implicit, so
  `x * 0.5625` means the fixed-point multiply with C's exact truncation and saturation rules.
  In C every operator is a runtime call, and every constant a hand-scaled integer.
- **What the compiler can see:** this compiler knows what each operation means, so it can
  - inline `x * 0.5625` as two 16x16 multiplies;
  - turn `/ 8` and `mod(x, 8)` into shifts, and `/ 12` into a reciprocal multiply;
  - prove that `sin(..)` lies within +-1 and drop the saturation test after `a * sin(..)`;
  - pull in only the routines a stage uses.

  gcc sees only opaque function calls.

For this stage that is the difference between gcc's 2304-byte blob at 1925 cycles per
evaluation and 744 bytes at 538 cycles (measured on the device).
- The results are identical bit for bit, including saturation and rounding.
- `--fast` drops the overflow handling for another few percent (700 bytes, 504 cycles).

## Performance

Full tables, one row per stage: [`docs/BENCHMARK.md`](docs/BENCHMARK.md) (generated by
`tool/bench.dart`).

| Set | gcc size | native size | `--fast` size | gcc cycles | native cycles | `--fast` cycles | speed-up (geo-mean) | `--fast` speed-up |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Examples (12 stages) | 2264 B | 657 B | 496 B | 1826 | 369 | 305 | 3.99x | 5.42x |
| Corpus (40 stages) | 2006 B | 506 B | 376 B | 1833 | 249 | 197 | 3.93x | 5.14x |

These rows are emulator figures: means over realistic inputs from the emulator's cycle model,
which is fitted to device measurements. For native code it is within about 5% of the device.
It reads gcc's loop-heavy code 5-10% high, so treat the emulator speed-ups as slightly
generous.

Measured on the MDIN core (slot 0, one fixed input, call overhead subtracted; the six stages
that have a gcc blob for slot 0):

| stage | gcc | native | `--fast` | speed-up |
|---|---:|---:|---:|---:|
| ripple | 1925 | 538 | 504 | 3.6x |
| rand002 | 1791 | 482 | 464 | 3.7x |
| rand000 | 1981 | 570 | 568 | 3.5x |
| rand003 | 1617 | 662 | 644 | 2.4x |
| rand001 | 1463 | 636 | 630 | 2.3x |
| glitch | 2025 | 1035 | 879 | 2.0x |

In the emulator, speed-ups range from about 1x on trivial scan stages, which only compare and
store, to over 20x on vertex stages that divide or take `mod`. Blobs are 3-4x smaller. The largest corpus
stage is 1.6 KB, against the 4 KB upload limit.

## Use

```
dart run bin/ae32k_shaderc.dart <file.ss | file.bin> [options]
dart compile exe bin/ae32k_shaderc.dart -o ae32k_shaderc     # a standalone binary, same options
```

The first argument is the stage source. With a `.bin` instead, the blob is uploaded as-is: only
the slot and upload flags apply.

| Flag | Default | What it does |
|---|---|---|
| `--scan` | | Compile for slot 1, the scan stage (0x1000E000). Its `@out` map is sent with the upload. |
| `--vert` | | Compile for slot 2, the vertex stage (0x1000A000). |
| `--slot N` | `0` | Compile for slot N: 0 warp (0x1000C000), 1 scan, 2 vertex. `--vert` wins over `--scan`, and either wins over `--slot`. The code is placed for its slot, so upload it to the slot it was built for. |
| `--fast` | off | Drop the overflow handling for speed and size: `*` wraps instead of saturating, and `x / 0` gives +-32767.99 instead of 0 (`/` still saturates). Every other result is identical. See below. |
| `--registers FILE` | compiled-in copy | The `registers.inc` that named `@out` lines resolve against. Use it to try register rows that are newer than the copy in the package. |
| `--asm` | off | Print the generated assembly (stage, then runtime routines) to stdout. |
| `--out FILE` | none | Write the blob to FILE: little-endian, padded to 4 bytes, exactly what is uploaded. |
| `--check N` | off | Run N evaluations in the emulator on random inputs and compare all 16 outputs with the reference interpreter. `--fast` builds are compared with the `--fast` reference. Prints the worst-case cycle estimate. Exits with status 2 on the first mismatch. |
| `--osc` | off | Upload over OSC/UDP the way `shader.py --osc` does: 1 KB parts to `/send/1/shader/{part,scanpart,vertpart}`, then the knobs, then (scan stage) the `@out` map. The device arms the blob only when its checksum matches; confirm with `imcu tiles stat` / `imcu scan stat`. |
| `--host IP` | `$SCION_IP`, else 192.168.100.221 | Where `--osc` sends. |
| `--port P` | `9000` | The device's OSC port. |
| `--knobs a,b,...` | none | After the upload, set knobs `k0`, `k1`, ... to these values (`/send/1/shader/k/<n>`, float, 1.0 = 1.0). |
| `-h`, `--help` | | Print the flag summary. |

Every run prints the blob size, plus the number of map entries for a scan stage. A syntax or
compile error (unknown register name, a stage over the 4 KB limit, ...) exits with status 1.
Run with no arguments, it prints the summary and exits with status 64.

Examples:

```
ae32k_shaderc ripple.ss --check 200                      # compile the warp stage and verify it
ae32k_shaderc frag3.ss --scan --fast --osc               # build and upload a scan stage with its @out map
ae32k_shaderc verts_test.ss --vert --fast --osc --host 10.0.0.7 --knobs 1.5,0.25
ae32k_shaderc scan1.ss --scan --asm --out scan1.bin      # inspect the code, keep the blob
```

Same slots, upload paths and packets as `tools/imcu/shader.py` (pinned by `test/osc_test.dart`).
From Dart/Flutter, use `compileStage(source, slot: n, fast: bool, registers: map)` (pure Dart,
any platform) and `uploadStage(stage, host, port: p, knobs: [...])` from
`package:ae32k_shader_compiler/upload.dart` (dart:io).

`--fast` (`compileStage(..., fast: true)`) drops the overflow handling:
- `*` wraps instead of saturating at +-32767.99;
- `x / 0` gives +-32767.99 instead of 0;
- `/` still saturates, because the division routine needs that test to terminate.

Every other result is identical to the exact build.

`@out` lines take either a register name from zephyr_scion's `tools/imcu/registers.inc`
(`@out swap in_swap`, `@out gy out0_csc_y0 gain`) or the numeric form
(`@out <output> <reg> <mask> <shift> <mode>`). With a name and no mode, the row's default mode
applies. The table is compiled in (`lib/src/registers_inc.dart`, regenerated by
`tool/gen_registers.dart`), and a test fails when it is stale. `--registers FILE` or
`compileStage(..., registers: parseRegisters(text))` use another table.

Language differences from shader.py:
- `else` works (shader.py rejects it).
- Constants beyond the Q16 range are an error. shader.py hands C an unsigned literal, so
  comparisons with it turn unsigned.

## Shader IDE

[`ide/`](ide/README.md) is a small Flutter editor built on this package:
- syntax highlighting, and errors underlined as you type;
- each line's cycle cost in the gutter;
- the generated assembly beside the source, with cycles per instruction;
- upload to a SCION over OSC.

It runs on macOS, Windows and Linux. The web build edits and measures, but cannot upload.

## How it is fast

All of these keep results bit-exact (in `--fast` mode, bit-exact with the same C minus the
checks):
- **Division:** `q_div` computes the integer part by shift-and-subtract, then 16 unrolled
  fraction steps (~115 cycles instead of ~840).
- **Constant divisors:** division and `mod` by a power of two are shifts. By a whole number they
  are a reciprocal multiply, exact for every input (checked for every divisor up to 32767).
- **Constant multiplies:** always inline.
- **Value ranges:** derived without assumptions about the inputs. They drop sign handling and
  saturation tests that cannot matter, and inline `x * f` when `|f| <= 1` is provable (`sin`,
  `frac`, `noise`, comparisons, `smoothstep`).
- **Runtime routines:** `noise`, `atan2` and `sqrt` are rewritten around their actual operand
  ranges. They share hash products and replace general division loops with fixed unrolled ones.
- **Leaner code:** a register-liveness pass removes copies, the prologue saves only what the
  final code touches, and leaf stages keep the ctx pointer in R8.
- **Folding and inlining:** constant subexpressions are folded with the reference interpreter.
  Comparisons, `&&`/`||`, `abs`, `min`, `max`, `clamp`, `floor`, `frac`, `step`, `sign` and
  `lerp` are inline.

`tool/profile.dart file.ss [--fast]` shows where a stage's cycles go;
`tool/corpus_profile.dart DIR` sums that over a set of stages.

## How it is checked

| Layer | Checked against |
|---|---|
| ISA encoder/decoder (`lib/src/isa.dart`) | vendor gas on ~3100 forms; vendor objdump on all 65536 words x 3 LERI contexts |
| Emulator (`lib/src/emu.dart`) | 132 gcc-built stages (examples + random) vs the reference interpreter |
| Q16 runtime in assembly (`lib/src/runtime.dart`) | `q16.dart` (bit-exact port of shader.py's C) on edge, boundary and random arguments |
| Compiler (`lib/src/codegen.dart`) | the reference on every example, 800 random programs (exact and `--fast`) and targeted edge cases, in the emulator |
| Range analysis (`lib/src/ranges.dart`) | every subexpression of random programs lies in its computed range |
| The device | `tool/hw_bench.dart --stages --corpus`: 124 builds (examples + 40-stage corpus, exact, `--fast` and gcc) match the reference bit for bit on the MDIN core |

Cycle costs were measured on the device with microbenchmarks (`tool/hw_bench.dart`,
`--round2`). The rules are in `docs/AE32000_ISA.md` ("Timing"), and the emulator implements
them. All 30 microbenchmarks agree exactly. The compiler emits only instructions that gcc-built
code already ran on the device. `NEG`'s flags, the 3-LERI forms and the DSP-extension
instructions are unverified on the MDIN core, and the compiler avoids them.

See `docs/AE32000_ISA.md` for the instruction set as verified, and the vendor PDFs beside it.

- `dart test` runs everything; no Wine needed.
- `tool/gen_oracle.dart` (objdump, all 65536 words) and `tool/gen_gas_golden.dart` (gas, every
  form at edge-case values) regenerate `test/golden/` from the vendor toolchain. They need
  `EISC_TOOLCHAIN` (default `~/src/superchromat/eisc-toolchain`).
- `tool/gen_gcc_corpus.py` builds gcc blobs (needs Wine) for `test/golden/gcc` and, with
  `--src/--out`, for `tool/bench.dart`.
