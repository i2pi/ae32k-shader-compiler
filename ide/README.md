# Shader IDE

A small editor for Scion shader stages (the language: [`../docs/LANGUAGE.md`](../docs/LANGUAGE.md)),
built on the `ae32k_shader_compiler` package. As you type it:

- colours the code with the compiler's own highlighter (keywords, `in.*` inputs, `out.*` outputs,
  functions, constants, locals, and `@out` lines with their register names and modes);
- compiles it and underlines errors at their line and column, with the list under **Problems**;
- runs the result in the device-fitted emulator over 24 sample inputs and shows each line's
  cycles in the gutter (mean per evaluation, including the runtime routines the line calls;
  `*` marks a line inside an `if` that does not always run), plus the stage's total, its range,
  the share of a video line, and the blob size against the 4 KB limit;
- shows the generated assembly in a pane beside the source (**ASM** hides it):
  - each instruction has its address, its mean cycles per evaluation and the source line it
    came from;
  - the instructions of the line under the cursor are highlighted and scrolled into view;
  - clicking an instruction moves the cursor to its line;
- shows a scan stage's `@out` map with the register names resolved.

**FAST** builds with `--fast`. **WARP / SCAN / VERTEX** chooses the slot (guessed from the file
when opened). The knobs `k0`..`k7` feed the cost estimate and, when connected, the device live.

## Device

Connect by address (`host[:port]`, default port 9000) or **Find** (mDNS `_scion._udp`), the way
scion_controller_app does: `/sync`, then `/ack` until the device answers. **UPLOAD**
(Cmd/Ctrl+U) sends the stage in 1 KB parts to its slot. Each part is acknowledged; the last
reply is the number of words the device armed, which the log reports. Then come the knobs and,
for a scan stage, the `@out` map. Browsers have no UDP, so the web build edits and measures but
does not upload.

## Run

```
flutter run -d macos          # or windows / linux / chrome
flutter build macos           # build/macos/Build/Products/Release/shader_ide.app
flutter test                  # editor and upload tests (a fake device on localhost)
flutter test test/live_device_test.dart --dart-define=SCION=<device ip>   # a real device: uploads to slot 0
```

Shortcuts: Cmd/Ctrl+S save, Cmd/Ctrl+Shift+S save as, Cmd/Ctrl+O open, Cmd/Ctrl+U upload.
Tab inserts two spaces; Enter keeps the indentation.
