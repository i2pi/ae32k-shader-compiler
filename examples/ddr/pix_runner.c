/* Pixel runner: evaluates a compiled shader (shader language, uploaded as the scan stage, slot 1) at every 20th pixel
 * of every second row of a 320x160 panel, interpolates between the samples and draws Y, Cb, Cr into Send 1's live frame buffer once per
 * vsync (into the slot the output reads next, after the input has written past the panel). The shader gets x, y (px),
 * u, v (0..1 over the panel), t (s), frame and the knobs; it returns out.o0 = Y (0..1), out.o1 = Cb, out.o2 = Cr
 * (-0.5..0.5, 0 = grey). Build/upload this runner to slot 2 (tools/imcu/cstage.py), the shader with
 * `ae32k_shaderc <file> --scan --osc`; run `imcu scan pix 2`, stop with `imcu scan stop`.
 * (Based on the colour plasma panel drawn into Send 1's live frame buffer (Y, Cb, Cr planes) once per
 * vsync, into the ring slot the output reads next. Runs until the STM sends a stop line; a 'y' line (STM needs the bus)
 * returns at once and the STM re-lends later (frame count and slot order survive in the slot's statics); 'k' lines set
 * the knobs. Build/upload: tools/imcu/cstage.py <this> 2 --upload; run: `imcu scan pix 2`; stop: `imcu scan stop`.
 * Knobs live in ctx->knob (the resident's 'k' between lends, this stage's own parse during one). Knobs (/send/1/shader/k/N): k0 speed (0 = 1x), k1 spatial scale, k2 chroma amount (0 = full). */
#include "stage.h"
#define HOST(r) (*(volatile unsigned short *)(0x72000000u + (unsigned)(r) * 4u))
#define LOCAL(r) (*(volatile unsigned short *)(0x70000000u + (unsigned)(r) * 4u))
#define U_RB  (*(volatile unsigned int *)0x80010800u)
#define U_LSR (*(volatile unsigned int *)0x80010814u)
#define FS 0x0032A000u
#ifndef LPF
#define LPF 1125u                                                    /* input line counter counts per frame (all lines, not 1080) */
#endif
#define ST 3072u
#define X0 x0v                                                     /* panel position from knobs k4, k5 (0..1 of the frame) */
#ifndef NC
#define NC 32
#endif
#define Y0 y0v
#ifndef NR
#define NR 160                                                       /* rows: 320 x 160 = ~900 of the 1125 lines per frame with px01 (NR 200: 1123) */
#endif
#define NS (NC / 2 + 1)                                             /* samples per row (every 20 px: the shader's cost) */
#ifndef GATE
#define GATE 100                                                  /* lines past the panel before drawing (margin for the base phase) */
#endif
static const unsigned PB[3] = { 0x032A0000u, 0x0459C000u, 0x05E38000u };   /* Y, Cb, Cr plane rings (Cb, Cr above 64 MB) */
static unsigned frame, step = 1, have_step, lbase, have_lbase, x0v = 800, y0v = 360, x0c = 80;   /* x0c = x0v / 10 (chunk index) */
static char line[96]; static unsigned ln;
/* Measurement builds (a file that #defines these and #includes this one; run once with `imcu hybrun a 2 1`, keeping
 * the run under the 5 s lend limit): MEASURE n draws n frames and returns out[1] shader and out[2] write time (input
 * lines, summed), out[3] the longest frame, out[4] frames still drawing past the next gate, out[5..7] (write - read
 * slot) histogram; PTRLOG instead packs target | write ptr << 2 | read ptr << 4 per frame (32 frames) into out[0..7];
 * PHLOG packs the input line at each output vsync (16 frames, bit 15 = seen). */
#ifdef MEASURE
static unsigned lc_last, m_sh, m_wr, m_max, m_late, m_n, m_rel[3];
#if defined(PTRLOG) || defined(PHLOG)
static unsigned m_log[8];
#endif
static inline unsigned lc_delta(void) { unsigned c = LOCAL(0x1F47), d = (c - lc_last) & 0xFFFFu; lc_last = c; return d; }
#endif
static inline unsigned bsw(unsigned x) { x = (x >> 16) | (x << 16); return ((x >> 8) & 0x00FF00FFu) | ((x & 0x00FF00FFu) << 8); }
static inline int sn(const short *s, unsigned ph) { return s[ph & 255]; }
static unsigned hexv(const char **pp) { const char *p = *pp; unsigned v = 0; while (*p == ' ') p++;
    for (;; p++) { char c = *p; unsigned d; if (c >= '0' && c <= '9') d = c - '0'; else if (c >= 'a' && c <= 'f') d = c - 'a' + 10; else if (c >= 'A' && c <= 'F') d = c - 'A' + 10; else break; v = (v << 4) | d; }
    *pp = p; return v; }
/* poll the UART: 0 = nothing / knobs taken, 1 = return (stop or yield line) */
static unsigned poll(int *knob)
{
    while (U_LSR & 1) {
        char ch = (char)(U_RB & 0xFF);
        if (ch == '\r') continue;
        if (ch != '\n') { if (ln < sizeof(line) - 1) line[ln++] = ch; continue; }
        line[ln] = 0; ln = 0;
        if (line[0] == 'k') { const char *p = line + 1; unsigned k; for (k = 0; k < 8; k++) knob[k] = (int)hexv(&p); continue; }
        if (line[0] == 0) continue;
        return 1;                                                    /* 'y' (yield) or anything else (stop) */
    }
    return 0;
}
typedef int (*shader_fn)(struct ctx *);
#define SHADER ((shader_fn)0x1000E000u)                              /* slot 1 */
static short sa[3][NS], sb[3][NS], mid[3][NS], (*rc)[NS] = sa, (*rn)[NS] = sb;   /* this row pair's top and next rows */
/* the shader at every 20th pixel of panel row yy (rows are evaluated in pairs: odd rows are the average of their
 * neighbours, which halves the shader's cost); 1 = stop/yield line seen */
static int eval_row(struct ctx *c, unsigned yy, short (*dst)[NS])
{
    unsigned k, o;
    for (k = 0; k < NS; k++) {
        c->x = (int)((X0 + k * 20) << 16); c->y = (int)((Y0 + yy) << 16);
        c->u = (int)(k * (131072u / NC)); c->v = (int)(yy * (65536u / NR));   /* constant divides fold at compile time */
        for (o = 0; o < 3; o++) c->out[o] = 0;
        SHADER(c);
        { int Y = c->out[0] >> 4, Cb = 2048 + (c->out[1] >> 4), Cr = 2048 + (c->out[2] >> 4);
          dst[0][k] = (short)(Y < 0 ? 0 : Y > 4095 ? 4095 : Y); dst[1][k] = (short)(Cb < 0 ? 0 : Cb > 4095 ? 4095 : Cb); dst[2][k] = (short)(Cr < 0 ? 0 : Cr > 4095 ? 4095 : Cr); }
        if ((U_LSR & 1) && poll(c->knob)) return 1;
    }
    return 0;
}
__attribute__((section(".entry"))) int stage(struct ctx *c)
{
    unsigned short s2 = HOST(0x0002), s9 = HOST(0x0009);
    unsigned prev, cur, y, ck, k, pl, quit = 0;
    HOST(0x0002) = (unsigned short)(s2 & 0x7FFF);
#ifdef MEASURE
    m_sh = m_wr = m_max = m_late = m_n = 0; m_rel[0] = m_rel[1] = m_rel[2] = 0;
#if defined(PTRLOG) || defined(PHLOG)
    { unsigned i; for (i = 0; i < 8; i++) m_log[i] = 0; }
#endif
#endif
    if (!have_step) {
        unsigned n = 0; HOST(0x0010) = 1; while (!(HOST(0x0010) & 1) && ++n < 4000000u) {} prev = (LOCAL(0x042D) >> 4) & 15;
        n = 0; HOST(0x0010) = 1; while (!(HOST(0x0010) & 1) && ++n < 4000000u) {} cur = (LOCAL(0x042D) >> 4) & 15;
        step = cur + 3 - prev; while (step >= 3) step -= 3; if (!step) step = 1; have_step = 1;
    }
    {
        unsigned short sel = LOCAL(0x1F48), v0; unsigned n = 0;
        if (!have_lbase) {
            LOCAL(0x1F48) = (unsigned short)((sel & ~0x3Fu) | 0x10u); v0 = LOCAL(0x1F47);
            while (LOCAL(0x1F47) == v0 && ++n < 4000000u) {}
            LOCAL(0x1F48) = (unsigned short)(sel & ~0x3Fu); lbase = LOCAL(0x1F47); have_lbase = 1;
        }
    }
    while (!quit) {
        unsigned tgt, n = 0, d = 0, cnt;
        /* paced by the INPUT: wait for its next frame (its line falls back below the gate), then until it has written
         * past the panel; draw into the slot it is writing (no output-vsync wait: that left too little of the frame) */
#ifdef PHLOG
        HOST(0x0010) = 1; { unsigned seen = 0;                       /* input line at the output vsync, per frame */
#endif
        for (;;) { cnt = LOCAL(0x1F47); d = (cnt - lbase) & 0xFFFFu; while (d >= LPF) d -= LPF; lbase = (cnt - d) & 0xFFFFu;
#ifdef PHLOG
                   if (!seen && (HOST(0x0010) & 1)) { seen = 1; if (m_n < 16) m_log[m_n >> 1] |= (d | 0x8000u) << ((m_n & 1) * 16); }
#endif
                   if (d < Y0 + NR + GATE || ++n > 4000000u) break; if (!(n & 255) && poll(c->knob)) { quit = 1; break; } }
        if (quit) break;
        n = 0;
        for (;;) { cnt = LOCAL(0x1F47); d = (cnt - lbase) & 0xFFFFu; while (d >= LPF) d -= LPF; lbase = (cnt - d) & 0xFFFFu;
#ifdef PHLOG
                   if (!seen && (HOST(0x0010) & 1)) { seen = 1; if (m_n < 16) m_log[m_n >> 1] |= (d | 0x8000u) << ((m_n & 1) * 16); }
#endif
                   if (d >= Y0 + NR + GATE || ++n > 4000000u) break; if (!(n & 255) && poll(c->knob)) { quit = 1; break; } }
#ifdef PHLOG
        }
#endif
        if (quit) break;
        tgt = (LOCAL(0x042D) >> 12) & 15; if (tgt > 2) tgt = 0;           /* the slot the input is writing (past the panel now) */
#ifdef MEASURE
        { unsigned rp = (LOCAL(0x042D) >> 4) & 15; unsigned r = tgt + 3 - rp; while (r >= 3) r -= 3; m_rel[r]++; }
#endif
        { int kx = c->knob[4], ky = c->knob[5];                         /* knobs 4, 5: panel x, y (0 = the default spot) */
          if (kx > 0) { unsigned v = (unsigned)((kx > 65536 ? 65536 : kx) * 1600u) >> 16; x0c = v * 6554u >> 16; x0v = x0c * 10u; }   /* a multiple of 10 (chunks) */
          if (ky > 0) { unsigned v = (unsigned)((ky > 65536 ? 65536 : ky) * (1000u - NR)) >> 16; y0v = v; } }
        c->t = (int)(frame * 2731u); c->frame = (int)(frame << 16); frame++;
#ifdef MEASURE
        { unsigned f0; lc_delta(); f0 = m_sh + m_wr;
#endif
        for (y = 0; y < NR && !quit; y++) {
            short (*src)[NS];
            if (poll(c->knob)) { quit = 1; break; }
            if (y == 0) { if (eval_row(c, 0, rc)) { quit = 1; break; } src = rc; }
            else if (!(y & 1)) src = rc;                                   /* even row: evaluated with the odd row above */
            else {                                                          /* odd row: evaluate the next row, draw the average */
                short (*t)[NS] = rn;
                if (eval_row(c, y + 1, rn)) { quit = 1; break; }
                for (pl = 0; pl < 3; pl++) for (k = 0; k < NS; k++) mid[pl][k] = (short)((rc[pl][k] + rn[pl][k]) >> 1);
                rn = rc; rc = t; src = mid;
            }
#ifdef MEASURE
            m_sh += lc_delta();
#endif
            for (pl = 0; pl < 3; pl++) {
                unsigned ad = PB[pl] + tgt * FS + (Y0 + y) * ST, msb = (ad >> 26) & 3;
                volatile unsigned *row;
                HOST(0x0009) = (unsigned short)((s9 & ~0x7700) | (msb << 12) | (msb << 8));
                row = (volatile unsigned *)(0x78000000u + (ad & 0x03FFFFFFu)) + x0c * 4;
                for (ck = 0; ck < NC; ck++) {
                    volatile unsigned *q = row + ck * 4;
                    int s0 = src[pl][ck >> 1], s1 = src[pl][(ck >> 1) + 1], m2 = (s0 + s1) >> 1, va = (ck & 1) ? m2 : s0, vb = (ck & 1) ? s1 : m2;   /* two chunks per sample span */
                    unsigned P0, P1, P2, P3, P4, P5, P6, P7, P8, P9, a, b, cc, d;
                    int acc = va << 12, st = (vb - va) * 410;           /* pixel j = va + (vb - va) * j / 10, by adds; stays in 0..4095 */
                    if ((U_LSR & 1) && poll(c->knob)) { quit = 1; break; }
                    P0 = (unsigned)va; acc += st; P1 = (unsigned)(acc >> 12); acc += st; P2 = (unsigned)(acc >> 12); acc += st;
                    P3 = (unsigned)(acc >> 12); acc += st; P4 = (unsigned)(acc >> 12); acc += st; P5 = (unsigned)(acc >> 12); acc += st;
                    P6 = (unsigned)(acc >> 12); acc += st; P7 = (unsigned)(acc >> 12); acc += st; P8 = (unsigned)(acc >> 12); acc += st;
                    P9 = (unsigned)(acc >> 12);
                    a = (P9 << 12) | P8;                                  /* field k is pixel 9 - k */
                    b = (P7 << 20) | (P6 << 8) | (P5 >> 4);
                    cc = ((P5 & 0xF) << 28) | (P4 << 16) | (P3 << 4) | (P2 >> 8);
                    d = ((P2 & 0xFF) << 24) | (P1 << 12) | P0;
                    q[0] = bsw(a); q[1] = bsw(b); q[2] = bsw(cc); q[3] = bsw(d);
                }
                if (quit) break;
            }
#ifdef MEASURE
            m_wr += lc_delta();
#endif
        }
#ifdef MEASURE
          f0 = m_sh + m_wr - f0; if (f0 > m_max) m_max = f0;
          { unsigned cnt = LOCAL(0x1F47), dd = (cnt - lbase) & 0xFFFFu; while (dd >= LPF) dd -= LPF; if (dd < Y0 + NR + GATE) m_late++; }
#ifdef PTRLOG                                                         /* per frame: target slot | write ptr << 2 | read ptr << 4 at draw end */
          if (m_n < 32) { unsigned v = LOCAL(0x042D); m_log[m_n >> 2] |= (tgt | (((v >> 12) & 3) << 2) | (((v >> 4) & 3) << 4)) << ((m_n & 3) * 8); }
#endif
          if (++m_n >= MEASURE) quit = 1; }
#endif
    }
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)(frame << 16);
#ifdef MEASURE
#if defined(PTRLOG) || defined(PHLOG)
    { unsigned i; for (i = 0; i < 8; i++) c->out[i] = (int)m_log[i]; }
#else
    c->out[1] = (int)m_sh; c->out[2] = (int)m_wr; c->out[3] = (int)m_max; c->out[4] = (int)m_late; c->out[5] = (int)m_rel[0]; c->out[6] = (int)m_rel[1]; c->out[7] = (int)m_rel[2];
#endif
#endif
    return 0;
}
