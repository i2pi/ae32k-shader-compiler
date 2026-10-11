# ae32k_shader_compiler

Compiler for the Scion shader language (`docs/SHADER_LANGUAGE_REFERENCE.md` in zephyr_scion)
straight to native AE32000 code for the MDIN-6xx's internal MCU: no GCC, no Wine. Pure Dart, so
it runs as a CLI and inside `scion_controller_app` on every Flutter platform.

Status: phase 1 (ISA tables + oracle). See `docs/AE32000_ISA.md` for the instruction set as
verified so far, and the vendor PDFs beside it.

- `tool/gen_oracle.dart` regenerates `test/golden/` from the vendor toolchain (needs
  `EISC_TOOLCHAIN`, default `~/src/superchromat/eisc-toolchain`). Only needed to refresh the
  goldens; the tests themselves run without Wine.
