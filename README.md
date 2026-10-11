# ae32k_shader_compiler

Compiler for the Scion shader language (`docs/SHADER_LANGUAGE_REFERENCE.md` in zephyr_scion)
straight to native AE32000 code for the MDIN-6xx's internal MCU: no GCC, no Wine. Pure Dart, so
it runs as a CLI and inside `scion_controller_app` on every Flutter platform.

Status: phase 1 done: encoder/decoder (`lib/src/isa.dart`) verified against the vendor gas and objdump. Next: emulator.
See `docs/AE32000_ISA.md` for the instruction set as verified, and the vendor PDFs beside it.

- `dart test` runs everything; no Wine needed.
- `tool/gen_oracle.dart` (objdump, all 65536 words) and `tool/gen_gas_golden.dart` (gas, every
  form at edge-case values) regenerate `test/golden/` from the vendor toolchain (needs
  `EISC_TOOLCHAIN`, default `~/src/superchromat/eisc-toolchain`).
