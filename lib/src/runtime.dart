// The Q16 runtime as AE32000 assembly, bit-exact with q16.dart (and so with the C that
// shader.py compiles). Only routines a stage uses are linked in, with their dependencies.
//
// Convention (internal to a stage): arguments in R8, R9, R10; result in R8. A routine
// may clobber R8-R13, MH/ML and the flags (R11-R13 are scratch, so the hot routines need
// no stack), and preserves R0-R7 and R14. R14 holds the ctx pointer (the sine table is
// read through it). The stage saves R10-R13 once, since the gcc ABI has them callee-saved.
//
// Only instructions that gcc-built stages already execute on the device are used
// (MUL low word, shifts, ALU, LDS, branches, PUSH/POP); MFMH, MIN/MAX/ABS and the other
// DSP-extension instructions wait for a hardware check.

class Routine {
  final String asm;
  final List<String> deps;
  const Routine(this.asm, [this.deps = const []]);
}

final routines = <String, Routine>{
  // q_mul: sign-magnitude 16x16 split, saturating at +-0x7fffffff, as the C does.
  '__qmul': Routine('''
__qmul:
    lea (%R8,0),%R11
    xor %R9,%R11            // sign of the result in bit 31
    cmpq 0,%R8
    jge __qmul_a
    neg %R8
__qmul_a:
    cmpq 0,%R9
    jge __qmul_b
    neg %R9
__qmul_b:
    lea (%R8,0),%R12
    lsr 16,%R12             // ah
    lea (%R12,0),%R13       // ah, kept
    lea (%R9,0),%R10
    lsr 16,%R10             // bh
    mul %R10,%R12           // hi = ah*bh
    cmp 32767,%R12
    jnc __qmul_sat          // hi >= 0x7fff
    asl 16,%R12             // hi << 16
    and 65535,%R8           // al
    and 65535,%R9           // bl
    mul %R8,%R10            // al*bh
    add %R10,%R12
    lea (%R13,0),%R10
    mul %R9,%R10            // ah*bl
    add %R10,%R12
    mul %R9,%R8             // al*bl
    lsr 16,%R8
    add %R8,%R12            // r (mod 2^32, as the C)
    lea (%R12,0),%R8
    cmpq 0,%R8
    jge __qmul_sign         // r >= 0x7fffffff clamps; only r >= 2^31 changes anything
    ldi 2147483647,%R8
__qmul_sign:
    cmpq 0,%R11
    jge __qmul_ret
    neg %R8
__qmul_ret:
    jplr
__qmul_sat:
    ldi 2147483647,%R8
    jmp __qmul_sign
'''),

  // q_div: (|a| << 16) / |b| over a 48-bit numerator, saturating at 0x7fffffff, sign applied
  // after (the C's bit loop; its remainder clamp is unreachable). Computed as the integer
  // part |a| / |b| by shift-and-subtract (only when |a| >= |b|), then 16 fraction bits,
  // unrolled. The result saturates exactly when the integer part reaches 2^15.
  '__qdiv': Routine(_qdiv),

  // q_sin / q_cos: the resident's Q14 table, 256 entries per turn, linear interpolation.
  '__qcos': Routine('''
__qcos:
    add 16384,%R8
    jmp __qsin
''', ['__qsin']),
  '__qsin': Routine('''
__qsin:
    ld (%R14,164),%R10      // ctx->sin256
    lea (%R8,0),%R11
    lsr 8,%R11
    and 255,%R11            // i
    and 255,%R8             // f
    lea (%R11,0),%R13
    addq 1,%R13
    and 255,%R13            // i + 1
    add %R11,%R11
    add %R10,%R11
    lds (%R11,0),%R12       // s0
    add %R13,%R13
    add %R10,%R13
    lds (%R13,0),%R10       // s1
    ldi 256,%R11
    sub %R8,%R11            // 256 - f
    mul %R11,%R12
    mul %R8,%R10
    add %R10,%R12
    asr 6,%R12
    lea (%R12,0),%R8
    jplr
'''),

  // isqrt32 (R8 unsigned) -> R8, the classic bit-pair method.
  '__isqrt': Routine('''
__isqrt:
    push %R0,%R1
    ldi 0,%R0               // res
    ldi 1073741824,%R1      // bit
__isqrt_top:
    cmp %R8,%R1
    jls __isqrt_loop        // bit <= v
    lsr 2,%R1
    jmp __isqrt_top
__isqrt_loop:
    cmpq 0,%R1
    jz __isqrt_done
    lea (%R0,0),%R9
    add %R1,%R9             // res + bit
    cmp %R9,%R8
    jc __isqrt_less         // v < res + bit
    sub %R9,%R8
    lsr 1,%R0
    add %R1,%R0
    jmp __isqrt_next
__isqrt_less:
    lsr 1,%R0
__isqrt_next:
    lsr 2,%R1
    jmp __isqrt_loop
__isqrt_done:
    lea (%R0,0),%R8
    pop %R0,%R1
    jplr
'''),
  '__qsqrt': Routine('''
__qsqrt:
    push %lr
    cmpq 0,%R8
    jgt __qsqrt_pos
    ldi 0,%R8
    pop %pc
__qsqrt_pos:
    cmp 4194304,%R8
    jge __qsqrt_big         // x >= 1 << 22
    asl 8,%R8
    jal __isqrt
    asl 4,%R8
    pop %pc
__qsqrt_big:
    jal __isqrt
    asl 8,%R8
    pop %pc
''', ['__isqrt']),

  // udiv32 (R8 / R9, unsigned) -> R8, shift-subtract.
  '__udiv': Routine('''
__udiv:
    push %R0,%R1
    ldi 0,%R0               // q
    ldi 0,%R1               // s
    cmpq 0,%R9
    jz __udiv_zero
    cmp %R9,%R8
    jc __udiv_zero          // n < d
__udiv_align:
    lea (%R8,0),%R10
    lsr 1,%R10
    cmp %R10,%R9
    jhi __udiv_loop         // d > n >> 1
    cmp 31,%R1
    jge __udiv_loop
    add %R9,%R9
    addq 1,%R1
    jmp __udiv_align
__udiv_loop:
    add %R0,%R0
    cmp %R9,%R8
    jc __udiv_skip
    sub %R9,%R8
    or 1,%R0
__udiv_skip:
    lsr 1,%R9
    addq -1,%R1
    jge __udiv_loop
    lea (%R0,0),%R8
    pop %R0,%R1
    jplr
__udiv_zero:
    ldi 0,%R8
    pop %R0,%R1
    jplr
'''),

  // q_atan2 (R8 = y, R9 = x) -> turns, octant reduction + 65-entry table.
  '__qatan2': Routine('''
__qatan2:
    push %lr
    push %R0,%R1,%R2,%R3,%R4,%R6
    lea (%R8,0),%R2         // y
    lea (%R9,0),%R3         // x
    lea (%R8,0),%R0
    cmpq 0,%R0
    jge __qatan2_ay
    neg %R0
__qatan2_ay:                // R0 = |y|
    lea (%R9,0),%R1
    cmpq 0,%R1
    jge __qatan2_ax
    neg %R1
__qatan2_ax:                // R1 = |x|
    lea (%R1,0),%R4         // big
    lea (%R0,0),%R6         // small
    cmp %R0,%R1
    jhi __qatan2_ord        // |x| > |y|
    lea (%R0,0),%R4
    lea (%R1,0),%R6
__qatan2_ord:
    cmpq 0,%R4
    jnz __qatan2_nz
    ldi 0,%R8
    jmp __qatan2_ret
__qatan2_nz:
    cmp 131072,%R4
    jnc __qatan2_wide       // big >= 1 << 17
    lea (%R6,0),%R8
    asl 14,%R8
    lea (%R4,0),%R9
    jmp __qatan2_div
__qatan2_wide:
    lea (%R6,0),%R8
    lea (%R4,0),%R9
    lsr 14,%R9
__qatan2_div:
    jal __udiv              // r
    lea (%R8,0),%R4
    lsr 8,%R4               // i
    and 255,%R8             // f
    cmp 63,%R4
    jls __qatan2_lut
    ldi 63,%R4
    ldi 255,%R8
__qatan2_lut:
    add %R4,%R4
    ldi __qatan2_tab,%R6
    add %R4,%R6
    ldsu (%R6,0),%R4        // AT[i]
    ldsu (%R6,2),%R6        // AT[i + 1]
    ldi 256,%R9
    sub %R8,%R9
    mul %R9,%R4
    mul %R8,%R6
    add %R6,%R4
    asr 8,%R4               // a
    cmp %R0,%R1
    jnc __qatan2_x          // |x| >= |y|
    ldi 16384,%R8
    sub %R4,%R8
    lea (%R8,0),%R4
__qatan2_x:
    cmpq 0,%R3
    jge __qatan2_y
    ldi 32768,%R8
    sub %R4,%R8
    lea (%R8,0),%R4
__qatan2_y:
    lea (%R4,0),%R8
    cmpq 0,%R2
    jge __qatan2_ret
    neg %R8
__qatan2_ret:
    pop %R0,%R1,%R2,%R3,%R4,%R6
    pop %pc
    .align 2
__qatan2_tab:
    .short 0, 163, 326, 489, 651, 813, 975, 1136, 1297, 1457, 1617, 1775, 1933, 2090, 2246, 2401
    .short 2555, 2708, 2860, 3010, 3159, 3307, 3453, 3599, 3742, 3884, 4025, 4164, 4302, 4438, 4572, 4705
    .short 4836, 4966, 5094, 5220, 5344, 5467, 5589, 5708, 5826, 5943, 6058, 6171, 6282, 6392, 6500, 6607
    .short 6712, 6815, 6917, 7018, 7117, 7214, 7310, 7405, 7498, 7589, 7679, 7768, 7856, 7942, 8026, 8110
    .short 8192
''', ['__udiv']),

  // q_mod (R8 = a, R9 = b): b ? a - q_mul(q_floor(q_div(a, b)), b) : 0
  '__qmod': Routine('''
__qmod:
    push %lr
    push %R0,%R1
    lea (%R8,0),%R0
    lea (%R9,0),%R1
    cmpq 0,%R9
    jnz __qmod_nz
    ldi 0,%R8
    jmp __qmod_ret
__qmod_nz:
    jal __qdiv
    and -65536,%R8
    lea (%R1,0),%R9
    jal __qmul
    sub %R8,%R0
    lea (%R0,0),%R8
__qmod_ret:
    pop %R0,%R1
    pop %pc
''', ['__qdiv', '__qmul']),

  // q_smoothstep (R8 = e0, R9 = e1, R10 = x)
  '__qsmooth': Routine('''
__qsmooth:
    push %lr
    push %R0
    sub %R8,%R10            // x - e0
    sub %R8,%R9             // e1 - e0
    lea (%R10,0),%R8
    jal __qdiv
    cmpq 0,%R8
    jge __qsmooth_lo
    ldi 0,%R8
__qsmooth_lo:
    cmp 65536,%R8
    jle __qsmooth_hi
    ldi 65536,%R8
__qsmooth_hi:
    lea (%R8,0),%R0         // t
    lea (%R8,0),%R9
    jal __qmul              // t*t
    lea (%R0,0),%R9
    add %R9,%R9
    neg %R9
    add 196608,%R9          // 3 - 2t
    jal __qmul
    pop %R0
    pop %pc
''', ['__qdiv', '__qmul']),

  // q_noise (R8 = x, R9 = y): value noise on the integer lattice, smoothstep weights.
  '__vh': Routine('''
__vh:                       // R8 = ix, R9 = iy -> 16-bit hash
    mul 73856093,%R8
    lea (%R9,0),%R10        // MUL needs an even destination
    mul 19349663,%R10
    xor %R10,%R8
    xor -1640531527,%R8     // 0x9E3779B9
    mul -1640531535,%R8     // 2654435761
    lea (%R8,0),%R9
    lsr 15,%R9
    xor %R9,%R8
    mul -2048144777,%R8     // 2246822519
    lea (%R8,0),%R9
    lsr 13,%R9
    xor %R9,%R8
    and 65535,%R8
    jplr
'''),
  // q_noise: the weights and lerps only ever multiply fractions, so each q_mul is one MUL:
  // fx, fy in [0, 65535] make q_mul(fx, fx) = fx*fx >> 16 and the smoothstep weight
  // s = m*bh + (m*bl >> 16) in [0, 65535] (checked for every fx); hashes are in [0, 65535],
  // so a lerp step q_mul(d, s) with |d| < 65536 is +-(|d|*s >> 16). The hash is inlined.
  '__qnoise': Routine(_qnoise),
};

/// The assembly for [names] and everything they depend on, each routine once.
String runtimeFor(Iterable<String> names) {
  final want = <String>{};
  void add(String n) {
    if (!want.add(n)) return;
    for (final d in routines[n]!.deps) {
      add(d);
    }
  }

  for (final n in names) {
    add(n);
  }
  return [for (final n in routines.keys) if (want.contains(n)) routines[n]!.asm].join('\n');
}

final _qdiv = '''
__qdiv:
    lea (%R8,0),%R10
    xor %R9,%R10            // sign of the result in bit 31
    cmpq 0,%R8
    jge __qdiv_a
    neg %R8
__qdiv_a:
    cmpq 0,%R9
    jge __qdiv_b
    neg %R9
__qdiv_b:
    cmpq 0,%R9
    jz __qdiv_zero          // b == 0: 0
    ldi 0,%R11              // q
    cmp %R9,%R8
    jc __qdiv_frac          // |a| < |b|: no integer part
    lea (%R8,0),%R13
    lsr 15,%R13
    cmp %R9,%R13
    jnc __qdiv_sat          // |a| >> 15 >= |b|: the quotient reaches 2^31
    lea (%R9,0),%R12        // d = |b| << s, the largest with d <= |a|
    lea (%R8,0),%R13
    lsr 1,%R13
    cmp %R12,%R13
    jc __qdiv_int
__qdiv_norm:
    add %R12,%R12
    cmp %R12,%R13
    jnc __qdiv_norm
__qdiv_int:                 // integer bits, most significant first
    add %R11,%R11
    cmp %R12,%R8
    jc __qdiv_int0
    sub %R12,%R8
    addq 1,%R11
__qdiv_int0:
    cmp %R9,%R12
    jz __qdiv_frac
    lsr 1,%R12
    jmp __qdiv_int
__qdiv_frac:                // 16 fraction bits; the remainder stays below |b| <= 2^31
${[for (var k = 0; k < 16; k++) '    add %R8,%R8\n    add %R11,%R11\n    cmp %R9,%R8\n    jc __qdiv_f$k\n    sub %R9,%R8\n    addq 1,%R11\n__qdiv_f$k:'].join('\n')}
__qdiv_sign:
    lea (%R11,0),%R8
    cmpq 0,%R10
    jge __qdiv_ret
    neg %R8
__qdiv_ret:
    jplr
__qdiv_sat:
    ldi 2147483647,%R11
    jmp __qdiv_sign
__qdiv_zero:
    ldi 0,%R8
    jplr
''';

// The __vh hash inline: R8 = ix, R9 = iy -> R8, clobbers R9, R10.
const _vhInline = '''
    mul 73856093,%R8
    lea (%R9,0),%R10
    mul 19349663,%R10
    xor %R10,%R8
    xor -1640531527,%R8
    mul -1640531535,%R8
    lea (%R8,0),%R9
    lsr 15,%R9
    xor %R9,%R8
    mul -2048144777,%R8
    lea (%R8,0),%R9
    lsr 13,%R9
    xor %R9,%R8
    and 65535,%R8''';

// q_mul(f, f) then q_mul(m, 3 - 2f) for a fraction f in R[f] (even): the weight into R[f].
String _weight(int f) => '''
    lea (%R$f,0),%R8
    mul %R$f,%R$f
    lsr 16,%R$f             // m = f*f >> 16
    add %R8,%R8
    neg %R8
    add 196608,%R8          // 3 - 2f, in [1, 3]
    lea (%R8,0),%R10
    lsr 16,%R10             // bh
    and 65535,%R8           // bl
    mul %R$f,%R8
    lsr 16,%R8              // m*bl >> 16
    mul %R10,%R$f           // m*bh
    add %R8,%R$f''';

// R8 = +-(|R8| * R[s] >> 16), the lerp step.
String _scale(int s, String l) => '''
    cmpq 0,%R8
    jge ${l}p
    neg %R8
    mul %R$s,%R8
    lsr 16,%R8
    neg %R8
    jmp ${l}e
${l}p:
    mul %R$s,%R8
    lsr 16,%R8
${l}e:''';

final _qnoise = '''
__qnoise:
    push %R0,%R1,%R2,%R3,%R4,%R5,%R6,%R7
    lea (%R8,0),%R0
    asr 16,%R0              // ix
    lea (%R9,0),%R1
    asr 16,%R1              // iy
    lea (%R8,0),%R2
    and 65535,%R2           // fx
    lea (%R9,0),%R4
    and 65535,%R4           // fy
${_weight(2)}
${_weight(4)}
    lea (%R4,0),%R3         // sy
    lea (%R0,0),%R8
    lea (%R1,0),%R9
$_vhInline
    lea (%R8,0),%R4         // a
    lea (%R0,0),%R8
    addq 1,%R8
    lea (%R1,0),%R9
$_vhInline
    lea (%R8,0),%R5         // b
    lea (%R0,0),%R8
    lea (%R1,0),%R9
    addq 1,%R9
$_vhInline
    lea (%R8,0),%R6         // c
    lea (%R0,0),%R8
    addq 1,%R8
    lea (%R1,0),%R9
    addq 1,%R9
$_vhInline
    lea (%R8,0),%R7         // d
    lea (%R5,0),%R8
    sub %R4,%R8
${_scale(2, '__qnoise_t')}
    add %R8,%R4             // top = a + q_mul(b - a, sx)
    lea (%R7,0),%R8
    sub %R6,%R8
${_scale(2, '__qnoise_b')}
    add %R6,%R8             // bot = c + q_mul(d - c, sx)
    sub %R4,%R8
${_scale(3, '__qnoise_f')}
    add %R4,%R8             // top + q_mul(bot - top, sy)
    pop %R0,%R1,%R2,%R3,%R4,%R5,%R6,%R7
    jplr
''';
