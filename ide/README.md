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
- completes as you type, in a dropdown at the cursor:
  - after `in.`, the stage's inputs; after `out.`, its outputs (a scan stage's own `@out` names);
  - on an `@out` line, register names from registers.inc and then modes;
  - otherwise keywords, functions with their signatures, constants and your locals;
  - Up/Down choose, Enter or Tab accepts, Esc closes;
- lists what the stage can use in the **I/O** pane:
  - its outputs, for a scan stage each `@out` name with its register fields, modes and measured
    granularity, flagging names that are declared but never written;
  - the inputs this stage gets, highlighting the ones the code uses and flagging inputs it reads
    that this stage does not set;
  - clicking an entry inserts it;
- shows the generated assembly in a pane beside the source (**ASM** hides it; drag the divider
  to resize it):
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

## Bundles

The editor holds a bundle: one document per stage slot. The WARP / SCAN / VERTEX tabs switch
between them; each keeps its own text, file and unsaved edits (a dot on the tab). A dim tab is
empty. New and Open put a stage in its slot and leave the others alone; the x on the shown tab
removes that stage. Upload sends the shown stage; Simulate runs the whole bundle; an example's
Run uploads every stage of the bundle, edits included. The bundle is remembered across restarts.

## Simulator

**Simulate** (Cmd/Ctrl+R) opens a frame simulator that plays stages on a simulated source:

- **Format**: resolution (1080p, 720p, a 960 x 540 preview, SD) and frame rate; `in.t` and
  `in.frame` follow the simulated clock (0.25x / 0.5x / 1x, pause, single frames).
- **Stages**: a warp, vertex and scan stage, each from a `.ss` file or the editor's buffer.
  With a vertex stage the scan stage runs in cell mode (once per vertex); without one, in the
  pattern mode of `imcu scan start` (every n-th line, points per line, walk lines, phase).
- **Source**: a test card (hue across, luma down, a 64 px grid, low noise, moving objects),
  colour bars and ramps, a panning card, or an image file.
- The stages run in the reference evaluator, which is bit-exact with the native code. The
  resident's handling follows `hyb_main.c`:
  - the warp grid: 16 px, +-4 blocks, sampling the source at (x + dx, y + dy), linear between
    points, blocks with jumping corners blanked;
  - the cells: left edge, width and height, slopes, clamps, the walk end at row 956 and parked
    points;
  - only the first 4 map entries are written in cell mode, at most 24 edges per span;
  - the `@out` field arithmetic (raw / gain / add / unit);
  - per-pixel registers change where they are written, line registers from the next line, and
    line-latched entries take the line's leftmost value and return to base after empty lines.
- What the registers do to the picture is modelled for the common ones: input swaps, Cb/Cr
  swaps, input and output CSC gains and offsets, dark screen and forced green. The models are
  approximate colour matrices; the output CSC rows Y/G/B are taken as R/G/B. Other registers
  show as a tinted trace of their value. Field bases are nominal: the device uses the value
  found when the map is set.
- Overlays: the warp grid, cells and vertices, scan points, the effects and trace on or off,
  and the source alone. The side panel shows warp points, scan evaluations and register
  writes for the frame, and a cycle budget from the emulator estimates (warp per frame, cell
  build against the ~125 lines after the walk, scan per line).

## Examples

**Examples** (Cmd/Ctrl+E) browses the examples bundled into the app. They come from this
repo's `examples/` folder, a copy of zephyr_scion's `tools/imcu/examples` made by
`dart run tool/sync_examples.dart`; `test/examples_copy_test.dart` fails when the copy is out of
date. The entries come from `examples.json`, one per example:

```json
{"id": "pip/sphere", "title": "Lit sphere", "desc": "...",
 "stages": {"warp": null, "scan": "pip/p01_sphere.ss", "vert": "pip/p02_sphere_bands.ss"},
 "blobs": [{"slot": 2, "file": "ddr/bin/pix_osd.bin"}],
 "fast": true, "knobs": {"k0": 0.25},
 "setup": [{"osc": "/send/1/pip/2/enable", "types": "i", "args": [1]}],
 "start": [{"osc": "...", "types": "i", "args": [1], "reply": "..."}],
 "stop":  [{"osc": "...", "reply": "..."}]}
```

- A step is `{"osc", "types", "args"}` (types i, f, s, b), optionally with `"reply": path` and
  `"timeout"` in seconds (default 10): the run waits for the device's answer and logs it. A negative number,
  or a string starting with "error", "refused" or "busy", counts as a failure. A step can also
  be `{"wait": ms}`. There are no shell-command steps: the device takes no commands over OSC.
  `"kind": "probe"` marks an entry that is not meant to run alone.
- If `examples.json` is missing or unreadable, every `.ss` file is listed, with its slot guessed
  from the source, and Run only uploads it.
- Every stage is compiled in the background; the list marks the ones that fail.
- **Open** loads the example as a bundle: each of its stages in its own tab (see below), with
  the example's FAST setting and knobs. Saving a bundled stage asks where to save it.
- **Run** works as follows:
  1. It compiles every stage first. If one fails, nothing is sent.
  2. It runs the previous example's stop steps, then this example's own stop steps.
  3. It uploads the blobs, then the warp, vertex and scan stages, then the scan map and the
     knobs.
  4. It sends the setup and start steps, and stops at the first one that fails.
  5. Each step's reply goes to the log.
  6. If the editor holds one of the example's stage files, the run uses the edited buffer.
- The toolbar chip runs, stops and simulates the current example. C stages are not simulated.

## Run

```
flutter run -d macos          # or windows / linux / chrome
flutter build macos           # build/macos/Build/Products/Release/shader_ide.app
flutter test                  # editor, upload, simulator and examples tests (a fake device on localhost)
flutter test test/live_device_test.dart --dart-define=SCION=<device ip>   # a real device: uploads to slot 0
```

Shortcuts: Cmd/Ctrl+S save, Cmd/Ctrl+Shift+S save as, Cmd/Ctrl+O open, Cmd/Ctrl+U upload,
Cmd/Ctrl+R simulate, Cmd/Ctrl+E examples.
Tab inserts two spaces; Enter keeps the indentation.
