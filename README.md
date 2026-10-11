# ae32k_shader_compiler

Compiler for the Scion shader language (`docs/SHADER_LANGUAGE_REFERENCE.md` in zephyr_scion)
straight to native AE32000 code for the MDIN-6xx's internal MCU: no GCC, no Wine. Pure Dart, so
it runs as a CLI and inside `scion_controller_app` on every Flutter platform.

## Use

```
dart run bin/ae32k_shaderc.dart file.ss [--scan|--vert] [--asm] [--out f.bin] [--check N] [--osc --host IP --knobs a,b]
dart compile exe bin/ae32k_shaderc.dart -o ae32k_shaderc     # a standalone binary (a stage compiles in well under a second, no Wine)
```

Same slots, upload paths and packets as `tools/imcu/shader.py` (pinned by `test/osc_test.dart`).
From Dart/Flutter: `compileStage(source, slot: n)` (pure Dart, any platform) and
`uploadStage(stage, host)` from `package:ae32k_shader_compiler/upload.dart` (dart:io).

## How it is checked (no hardware yet)

| Layer | Checked against |
|---|---|
| ISA encoder/decoder (`lib/src/isa.dart`) | vendor gas on ~3100 forms; vendor objdump on all 65536 words x 3 LERI contexts |
| Emulator (`lib/src/emu.dart`) | 132 gcc-built stages (examples + random) vs the reference interpreter |
| Q16 runtime in assembly (`lib/src/runtime.dart`) | `q16.dart` (bit-exact port of shader.py's C) on edge + random arguments |
| Compiler (`lib/src/codegen.dart`) | the reference on every corpus program + 400 random programs, in the emulator |

`tool/bench.dart`: native vs gcc on the corpus, emulated (an estimate, not hardware): mean blob
1775 -> 578 bytes, mean cycles per evaluation 1625 -> 1383.

Not yet done: a run on the device. The emulator's flag semantics come from the quick
reference and from gcc's code agreeing with the reference; `NEG`'s flags, the 3-LERI forms and
the DSP-extension instructions are unverified on the MDIN core and the compiler avoids them.

Language differences from shader.py: `else` works (shader.py rejects it), and constants beyond
the Q16 range are an error (shader.py hands C an unsigned literal, so comparisons with it turn
unsigned).

See `docs/AE32000_ISA.md` for the instruction set as verified, and the vendor PDFs beside it.

- `dart test` runs everything; no Wine needed.
- `tool/gen_oracle.dart` (objdump, all 65536 words) and `tool/gen_gas_golden.dart` (gas, every
  form at edge-case values) regenerate `test/golden/` from the vendor toolchain (needs
  `EISC_TOOLCHAIN`, default `~/src/superchromat/eisc-toolchain`).
