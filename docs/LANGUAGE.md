# Scion shader language reference

This is the language `ae32k_shaderc` compiles, as it is implemented: `lib/src/lang/parser.dart`
for syntax, and `lib/src/lang/q16.dart` for the exact arithmetic. That arithmetic is a
bit-exact port of the C runtime in zephyr_scion's `tools/imcu/shader.py`, which defines the
language. Wherever this document says what a result is, the native code produces exactly that,
and the test suite and the device check it.

- [Overview](#overview)
- [Numbers](#numbers)
- [Lexical structure](#lexical-structure)
- [Statements](#statements)
- [Expressions and operators](#expressions-and-operators)
- [Functions](#functions)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [The `@out` map (scan stage)](#the-out-map-scan-stage)
- [`--fast`](#--fast)
- [Costs](#costs)
- [Differences from shader.py](#differences-from-shaderpy)
- [Grammar](#grammar)

## Overview

A shader is a short straight-line program that the AE32000 core in the MDIN runs once per
evaluation: per warp grid point, per scan point, or per vertex.
- It reads inputs (`in.*`), computes with fixed-point numbers, and writes outputs (`out.*`).
- It has no loops, no user functions, no arrays and no memory beyond its locals. Its running
  time is therefore bounded, which matters because it runs inside a video frame.

```c
// ripple: concentric waves from the centre. k0 = amplitude px, k1 = speed (turns/s)
let du = in.u - 0.5;
let dv = (in.v - 0.5) * 0.5625;           // 1080/1920: circular in pixels
let r = sqrt(du * du + dv * dv) + 0.0005;
let a = (in.k0 + 2) * sin(r * 8 - in.t * (in.k1 + 0.5));
out.dx = a * du / r;
out.dy = a * dv / r;
```

Each file is one stage. The stage it is built for (warp, scan or vertex) is chosen at compile
time with `--slot`/`--scan`/`--vert`, not in the source. The stage determines which inputs are
meaningful and what the outputs drive; see [Inputs](#inputs) and [Outputs](#outputs).

## Numbers

Every value is a **Q16 fixed-point number**: a 32-bit two's-complement integer *n* standing for
*n* / 65536.
- **Range:** -32768.0 to +32767.99998.
- **Resolution:** 1/65536 (about 0.0000153).
- **No other types:** there are no floats, no integers distinct from Q16, and no booleans.
- **Truth:** conditions treat 0 as false and anything else as true. Comparisons produce 1.0 or 0.0.

Overflow behaviour differs by operator, and it is part of the language:

| Operation | On overflow |
|---|---|
| `+`, `-`, unary `-` | wraps (two's complement): `32767 + 1` is `-32768` |
| `*` | saturates to +-32767.99998 |
| `/` | saturates to +-32767.99998; `x / 0` is `0` |
| function results | see each function |

Squares of pixel distances overflow (`1000 * 1000` saturates), so do geometry in the 0..1
inputs `in.u`, `in.v` and scale to pixels at the end.

## Lexical structure

- **Comments:** `//` to the end of the line. There are no block comments.
- **Number literals:** decimal only, as `12`, `0.5`, `.5` or `12.` (no exponent, no hex, no
  sign). A literal is rounded to the nearest 1/65536, halves to even (Python's `round`). It must
  not exceed 32767.99998; larger is a compile error. Negative values are written with unary
  minus (`-0.5`), so the most negative literal is `-32767.99998`. -32768.0 itself only arises
  from arithmetic.
- **Names:** `[A-Za-z_][A-Za-z0-9_]*`. Reserved:
  - the keywords `let`, `if`, `else`, `in`, `out`;
  - the constants `pi` and `tau`;
  - the function names in [Functions](#functions).

  A local named like a function or constant cannot be read, so don't use those names for
  locals.
- **Constants:** `pi` = 3.14159 (raw 205887), `tau` = 6.28319 (raw 411775).
- **Operators and punctuation:** `+ - * / % < <= > >= == != && || ! = ( ) { } ; , .`
- **Whitespace** is free. Statements end with `;`.
- **`@out` lines:** a line that starts with `@out` is a directive, not code. See
  [The `@out` map](#the-out-map-scan-stage).

## Statements

```c
let name = expr;          // declare a local (or assign it again)
name = expr;              // assign a local declared earlier in the file
out.name = expr;          // write an output
if (expr) { ... }         // braces are required
if (expr) { ... } else { ... }
if (expr) { ... } else if (expr) { ... } else { ... }
```

- **Locals** are declared by their first `let` and live for the whole evaluation.
  - Every local starts at 0. A `let` inside an `if` that does not run leaves it at 0.
  - A local can be used only after its first `let` in the text.
  - A second `let` of the same name is an ordinary assignment.
  - There is no block scope.
- **Outputs** can be read back as `out.name`, which gives the value written so far in this
  evaluation. Before the first write it is the starting value: 0, or 1.0 for a scan output
  mapped in `gain` mode.
- **`if`** takes any expression; non-zero runs the first block.
- There is no `while`, `for`, `return`, function definition or array.

## Expressions and operators

Precedence, highest first; binary operators are left-associative:

| Level | Operators | Meaning |
|---|---|---|
| 1 | `-x` `!x` | negate (wraps: the negation of -32768.0 is -32768.0); `!x` is 1.0 if x == 0, else 0.0 |
| 2 | `*` `/` `%` | multiply, divide, modulo |
| 3 | `+` `-` | add, subtract (wrapping) |
| 4 | `<` `<=` `>` `>=` | signed comparison, 1.0 or 0.0 |
| 5 | `==` `!=` | equality, 1.0 or 0.0 |
| 6 | `&&` | 1.0 if both are non-zero, else 0.0 |
| 7 | `\|\|` | 1.0 if either is non-zero, else 0.0 |

Parentheses group. Expressions have no side effects, so evaluation order never matters.

**`a * b`.** Compute the product of the magnitudes, truncate it to 1/65536 (toward zero), and
apply the sign.
- So `-0.00001 * 0.5` is `0`, and `(-x) * y == -(x * y)` always.
- If the result's magnitude does not fit, it is +-32767.99998.
- Precisely, the result saturates when `int(|a|) * int(|b|) >= 32767`, or when the full product
  is 32767.99998 or more.

**`a / b`.** Divide the magnitudes with a 48-bit numerator (`|a| * 65536 / |b|`), truncate
toward zero, and apply the sign.
- A quotient of 32768 or more saturates to +-32767.99998.
- `a / 0` is `0`.

**`a % b`** is `mod(a, b)`.

Comparisons are exact on the raw values. `0.1 + 0.2 == 0.3` is whatever the rounded constants
make it: here 6554 + 13107 = 19661 against 19661, so true.

Multiplying by a comparison is the idiomatic select. `(in.x > 100) * 5` is 5.0 or 0.0, and
`a + (c > 0) * (b - a)` picks `b` when `c > 0`.

## Functions

Angles are in **turns**: 1.0 is a full circle, so `sin(0.25)` is 1.0.

| Function | Result |
|---|---|
| `sin(x)` | Sine of x turns. Uses x modulo 1.0, from the resident's 256-entry table (Q14, `round(16384 sin)`) with linear interpolation over the low 8 bits. Range -1.0..1.0, error about 1/16384 plus interpolation. |
| `cos(x)` | `sin(x + 0.25)`. |
| `atan2(y, x)` | Angle of (x, y) in turns, -0.5..0.5 (`atan2(1, 0)` is 0.25). From a 65-entry table over one octant, indexed by the ratio of the smaller magnitude to the larger in 1/16384 steps. `atan2(0, 0)` is 0. |
| `sqrt(x)` | Square root, 0 for x <= 0. Resolution 1/4096 for x < 64, 1/256 above (the integer square root of `x << 8` or of `x`). |
| `abs(x)` | `x < 0 ? -x : x`; abs of -32768.0 wraps to -32768.0. |
| `min(a, b)`, `max(a, b)` | The smaller or larger, signed. |
| `clamp(x, lo, hi)` | `x < lo ? lo : (x > hi ? hi : x)`. With lo > hi that gives lo for x < lo and hi otherwise. |
| `floor(x)` | The largest whole number <= x (toward minus infinity: `floor(-0.5)` is -1). |
| `frac(x)` | `x - floor(x)`, always in [0, 1): `frac(-0.25)` is 0.75. |
| `lerp(a, b, t)` | `a + (b - a) * t`, with the operators' rules (the subtraction wraps, the multiply truncates and saturates). |
| `smoothstep(e0, e1, x)` | `t = clamp((x - e0) / (e1 - e0), 0, 1)`, then `t * t * (3 - 2 * t)`. 0.0..1.0. With e0 == e1 the division gives 0, so the result is 0. |
| `step(edge, x)` | `x < edge ? 0 : 1`. |
| `sign(x)` | 1.0, -1.0 or 0.0. |
| `mod(a, b)` | `a - floor(a / b) * b`, with `/` and `*` as above; `mod(a, 0)` is 0. For b > 0 the result is in [0, b), except that when a is negative and within b/65536 of a multiple of b, the truncating division makes it that small negative a. |
| `noise(x, y)` | Value noise in [0, 1). One pseudo-random value per integer lattice point (a hash of the two integer parts), blended with smoothstep weights on the fractional parts. Continuous, about one feature per unit; scale the inputs to change the feature size. |

Arity is checked. `sin(1, 2)` is a compile error.

## Inputs

`in.<name>` reads a field of the context the resident fills before each evaluation. All are
Q16. A field a stage does not set reads as whatever the resident left there, usually 0.

| Input | Meaning |
|---|---|
| `x`, `y` | Position in pixels. Warp: the grid point. Scan: the evaluation point. Vertex: `x` is the point index and `y` is 0. |
| `u`, `v` | Position as a fraction of the frame, 0..1. Vertex: `u` = index / n. |
| `t` | Seconds since the engine started. It wraps after about 9 hours (32768 s). |
| `frame` | Frame counter. |
| `k0` .. `k7` | Knobs, set live over OSC (`/send/1/shader/k/<n>`, float) or with `--knobs`. |
| `rnd` | A fresh pseudo-random value in [0, 1) per evaluation. |
| `w`, `h` | Frame size in pixels. |
| `heat`, `mvx`, `mvy` | Motion at the point from the frame-difference sampler: the warp stage with flow on, else 0. |
| `luma` | Reserved, 0. |
| `p0` .. `p3` | Scan stage, when it runs at vertex-stage points: the parameters the vertex stage emitted for this point. |

The resident does not bound the inputs (vertex coordinates can be off-screen, and `t` wraps).
The compiler therefore makes no assumptions about them, and results are exact for every input
value.

## Outputs

`out.<name> = expr;` writes output slot *n* of the 16 in the context. The names map to slots,
and different stages use different names for the same slots:

| Stage | Names | Meaning |
|---|---|---|
| warp (slot 0) | `dx` (0), `dy` (1) | Displacement of the grid point in pixels. The resident clamps it to +-4 blocks; a 64 px block whose corners jump by more than about a block goes black. |
| vertex (slot 2) | `vx` (0), `vy` (1), `p0`..`p3` (2..5) | The point's position in pixels (clamped to the frame), and four free parameters passed to the scan stage. |
| scan (slot 1) | the names declared by `@out` lines | Register values, through the map below. Also `gr gg gb swap pr pg pb` (0..6) from older stages. |
| any | `o0` .. `o15` | Slot n directly. |

A name declared by an `@out` line takes precedence over a built-in name with the same spelling.

## The `@out` map (scan stage)

The scan stage runs while the raster is drawing the frame, and its outputs are written into MDIN
registers. Lines at the top of the file say which output goes where:

```c
@out swap in_swap                  // register by name, the row's default mode
@out gy   out0_csc_y0 gain         // by name, with an explicit mode
@out gy   out0_csc_y1 gain         // the same output again: one value drives several fields
@out _    osd_pal_strobe           // a strobe row: writes its constant after any change
@out x    0x0237 0x0080 7 raw      // numeric: register, field mask, field shift, mode
```

- **Named form:** `@out <output> <name> [mode]`, where `<name>` is a row of zephyr_scion's
  `tools/imcu/registers.inc`. The row has columns name, register, mask, shift, default mode,
  granularity and description. The register, mask and shift come from the row; the mode comes
  from the line, or the row's default.
- **Numeric form:** `@out <output> <reg> <mask> <shift> <mode>`. Numbers are decimal or `0x`
  hex.
- **Outputs:** each distinct `<output>` becomes an output slot, in order of first appearance, at
  most 16. Using a name again adds another register field driven by the same value.
- **Modes:**
  - `raw`: write the integer part into the field.
  - `gain`: multiply the field's value as found when the map was set (1.0 = unchanged). It is
    signed when the field is the whole word, as CSC coefficients need. The output starts at
    1.0.
  - `add`: add the integer part to that base value.
  - `unit`: map 0..1 onto the field's range.
  - `strobe`: write the row's shift column as a constant after any earlier entry changed.
- **Writes:** the resident writes a register only when the value changed, and restores every
  mapped register when the scan engine stops.
- **Granularity:** the `granularity` column of `registers.inc` records how each register takes
  effect when written inside a line, as measured on the device: per pixel, partially within the
  line, once per line, or once per frame.

The compiler copies the map into the upload. The blob itself does not depend on it.

## `--fast`

Built with `--fast` (`compileStage(..., fast: true)`), a stage drops the overflow handling for
speed and size:

| | Exact (default) | `--fast` |
|---|---|---|
| `a * b` overflowing | +-32767.99998 | wraps (low 32 bits of the truncated product) |
| `a / 0` | 0 | +-32767.99998 (the sign of a) |
| `a / b` with a quotient >= 32768 | +-32767.99998 | +-32767.99998 (kept: the division routine needs the test to terminate) |
| `mod(a, 0)`, `a % 0` | 0 | 0 |
| everything else | | identical |

Everything that does not overflow or divide by zero gives the same result in both modes. Shaders
that keep their values in range lose nothing.

## Costs

Measured with the emulator's cycle model, which is fitted to the device (`docs/AE32000_ISA.md`,
"Timing"; the AE32000 runs at 99.75 MHz). The figures are approximate cycles one operation adds
to a stage, including loading its operands:

| Operation | Cycles |
|---|---:|
| `+` `-`, comparison, `floor` `frac` `abs` `min` `max` `step` `sign` | 4-8 |
| `x / 8`, `x % 8` (power of two) | 5-10 |
| `x * 3`, `x * 0.7` (constant) | ~20 |
| `x * 1.7` (constant with whole and fraction parts) | ~30 |
| `x * sin(..)`, `x * frac(..)`, `x * (a > b)` (a factor provably within +-1) | ~27 |
| `x * y` | ~45 |
| `x / 12`, `x % 12` (whole-number constant) | 45-65 |
| `sin`, `cos` | ~35 |
| `sqrt` | ~90 |
| `x / y` | ~140 |
| `noise` | ~145 |
| `atan2` | ~170 |
| `smoothstep` | ~300 |

For scale: one pixel at 1080p24 is 1.34 cycles, and a line is 3694.
- Prefer constants: `x * 0.5` over `x / 2`, and constant divisors over variable ones.
- Keep `smoothstep` and variable divisions out of anything evaluated per pixel or per line.

## Differences from shader.py

The gcc path (`tools/imcu/shader.py`) and this compiler accept the same language and give the
same results, with three differences:
- **`else`:** works here as documented. shader.py's parser rejects it.
- **Out-of-range constants:** a constant above 32767.99998 is an error here. shader.py passes it
  to C as an unsigned literal, which silently turns comparisons with it unsigned.
- **`--fast`:** exists only here.

## Grammar

```
stage      := { directive | stmt }
directive  := '@out' NAME ( REGNAME [MODE] | NUM NUM NUM MODE ) [';'] [comment]   (a whole line)
stmt       := 'let' NAME '=' expr ';'
            | NAME '=' expr ';'                     (NAME a local declared earlier)
            | 'out' '.' NAME '=' expr ';'
            | 'if' '(' expr ')' block [ 'else' ( block | stmt_if ) ]
block      := '{' { stmt } '}'
expr       := or
or         := and { '||' and }
and        := eq { '&&' eq }
eq         := rel { ( '==' | '!=' ) rel }
rel        := add { ( '<' | '<=' | '>' | '>=' ) add }
add        := mul { ( '+' | '-' ) mul }
mul        := unary { ( '*' | '/' | '%' ) unary }
unary      := ( '-' | '!' ) unary | primary
primary    := NUMBER | 'pi' | 'tau' | NAME
            | 'in' '.' INPUT | 'out' '.' OUTPUT
            | FUNC '(' expr { ',' expr } ')'
            | '(' expr ')'
NUMBER     := DIGITS [ '.' [DIGITS] ] | '.' DIGITS
```
