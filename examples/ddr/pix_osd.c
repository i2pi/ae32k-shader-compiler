/* Pixel shader runner on the OSD canvas: evaluates a compiled shader (shader language, uploaded as the scan stage,
 * slot 1) on a grid of every 32nd pixel of every 8th row of a W x H canvas, interpolates bilinearly and draws the
 * result into a 16-bit YCbCr 4:2:2 OSD sprite (`imcu canvas yc <W> <H> <x> <y>`), double-buffered: draw into the
 * back buffer, point the sprite at it (the OSD takes the address at the next vertical blank), wait for the output
 * vsync, repeat. Unlike pix_runner.c (Send 1's 12-bit frame planes, 4.8 bytes per pixel, raced against the input)
 * the canvas is 2 bytes per pixel and nothing else writes it.
 * The shader gets x, y (px in the canvas), u, v (0..1), t (s), frame and the knobs; it returns out.o0 = Y (0..1),
 * out.o1 = Cb, out.o2 = Cr (-0.5..0.5). Build/upload to slot 2 (tools/imcu/cstage.py), the shader with
 * `ae32k_shaderc <file> --scan --osc`; set up the canvas, then `imcu scan pix 2`; stop with `imcu scan stop`.
 * Canvas dword (two pixels): Y | Cb << 8 | Y' << 16 | Cr << 24 (8-bit, limited range). */
#include "stage.h"
#define HOST(r) (*(volatile unsigned short *)(0x72000000u + (unsigned)(r) * 4u))
#define LOCAL(r) (*(volatile unsigned short *)(0x70000000u + (unsigned)(r) * 4u))
#define U_RB  (*(volatile unsigned int *)0x80010800u)
#define U_LSR (*(volatile unsigned int *)0x80010814u)
#ifndef W
#define W 640                                                        /* must match `imcu canvas yc W H ...` */
#endif
#ifndef H
#define H 360
#endif
#ifndef SX
#define SX 32                                                        /* shader grid: every 32nd pixel (16: twice the calls) ... */
#endif
#define SXS (SX == 32 ? 5 : 4)                                       /* log2 SX */
#define SY 8                                                         /* ... of every 8th row */
#define NSX (W / SX + 1)
#define NSY (H / SY + 1)
static const unsigned BUF[2] = { 0x0C200000u, 0x0C680000u };         /* DDR0 bank 3; 4.5 MB each, below the resident's scratch */
static unsigned frame, back = 1;
static char line[96]; static unsigned ln;
static int top[3][NSX], bot[3][NSX];                                  /* sample rows above and below, Q8 bytes */
#ifdef MEASURE
static unsigned m_n, m_late;
#endif
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
        return 1;
    }
    return 0;
}
typedef int (*shader_fn)(struct ctx *);
#define SHADER ((shader_fn)0x1000E000u)                              /* slot 1 */
static inline int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }
/* the shader along sample row j into dst (Q8 bytes: Y 16..235, Cb/Cr 16..240); 1 = stop/yield line seen */
static int eval_row(struct ctx *c, unsigned j, int (*dst)[NSX])
{
    unsigned k, o;
    for (k = 0; k < NSX; k++) {
        c->x = (int)((k * SX) << 16); c->y = (int)((j * SY) << 16);
        c->u = (int)(k * (65536u / (NSX - 1))); c->v = (int)(j * (65536u / (NSY - 1)));
        for (o = 0; o < 3; o++) c->out[o] = 0;
        SHADER(c);
        dst[0][k] = clampi(16 * 256 + ((c->out[0] * 219) >> 8), 16 * 256, 235 * 256);          /* Q16 0..1 -> Q8 16..235 */
        dst[1][k] = clampi(128 * 256 + ((c->out[1] * 224) >> 8), 16 * 256, 240 * 256);         /* Q16 -0.5..0.5 -> Q8 16..240 */
        dst[2][k] = clampi(128 * 256 + ((c->out[2] * 224) >> 8), 16 * 256, 240 * 256);
        if ((U_LSR & 1) && poll(c->knob)) return 1;
    }
    return 0;
}
/* point the sprite (layer 4, sprite 0) at buffer b; the OSD takes it at the next vertical blank */
static void show(unsigned b)
{
    unsigned r = BUF[b] >> 11;                                        /* row address, 2 KB banks */
    LOCAL(0x1000) = (unsigned short)((LOCAL(0x1000) & ~7u) | 4u);
    LOCAL(0x1053) = (unsigned short)((LOCAL(0x1053) & ~3u) | ((r >> 16) & 3u));
    LOCAL(0x1024) = (unsigned short)(r & 0xFFFFu);
    LOCAL(0x1025) = (unsigned short)((BUF[b] & 2047u) >> 4);
}
__attribute__((section(".entry"))) int stage(struct ctx *c)
{
    unsigned short s2 = HOST(0x0002), s9 = HOST(0x0009);
    unsigned msb = (BUF[0] >> 26) & 3, quit = 0, j, k, pl;
    HOST(0x0002) = (unsigned short)(s2 & 0x7FFF);                     /* DDR0 */
    HOST(0x0009) = (unsigned short)((s9 & ~0x7700) | (msb << 12) | (msb << 8));   /* both buffers in bank 3 */
#ifdef MEASURE
    m_n = m_late = 0;
#endif
    while (!quit) {
        unsigned n = 0;
        c->t = (int)(frame * 2731u); c->frame = (int)(frame << 16);
        if (eval_row(c, 0, bot)) break;
        for (j = 0; j + 1 < NSY && !quit; j++) {
            unsigned r;
            for (pl = 0; pl < 3; pl++) for (k = 0; k < NSX; k++) top[pl][k] = bot[pl][k];
            if (eval_row(c, j + 1, bot)) { quit = 1; break; }
            for (r = 0; r < SY; r++) {
                volatile unsigned *q = (volatile unsigned *)(0x78000000u + (BUF[back] & 0x03FFFFFFu) + (j * SY + r) * (W * 2));
                for (k = 0; k + 1 < NSX; k++) {                       /* one SX-px span = SX / 2 dwords */
                    int y0 = top[0][k] + (((bot[0][k] - top[0][k]) * (int)r) >> 3), y1 = top[0][k + 1] + (((bot[0][k + 1] - top[0][k + 1]) * (int)r) >> 3);
                    int b0 = top[1][k] + (((bot[1][k] - top[1][k]) * (int)r) >> 3), b1 = top[1][k + 1] + (((bot[1][k + 1] - top[1][k + 1]) * (int)r) >> 3);
                    int r0 = top[2][k] + (((bot[2][k] - top[2][k]) * (int)r) >> 3), r1 = top[2][k + 1] + (((bot[2][k + 1] - top[2][k + 1]) * (int)r) >> 3);
                    int dy = (y1 - y0) >> SXS, db = (b1 - b0) >> (SXS - 1), dr = (r1 - r0) >> (SXS - 1), dy2 = 2 * dy;
                    volatile unsigned *e = q + SX / 2;
                    while (q < e) {                                   /* Y per pixel, Cb/Cr per pair; Q8 keeps the byte at bits 15:8 */
                        *q++ = ((unsigned)y0 >> 8) | ((unsigned)b0 & 0xFF00u) | (((unsigned)(y0 + dy) & 0xFF00u) << 8) | (((unsigned)r0 & 0xFF00u) << 16);
                        y0 += dy2; b0 += db; r0 += dr;
                    }
                    if (!(k & 3) && (U_LSR & 1) && poll(c->knob)) { quit = 1; break; }   /* every 4th span (~20 us): a knob line overruns the FIFO in ~50 us */
                }
                if (quit) break;
            }
        }
        if (quit) break;
        show(back); back ^= 1; frame++;
        /* wait for the vsync that applies the new address: after it the other buffer is free to draw */
        HOST(0x0010) = 1;
        while (!(HOST(0x0010) & 1) && ++n < 4000000u) { if (!(n & 255) && poll(c->knob)) { quit = 1; break; } }
#ifdef MEASURE
        if (++m_n >= MEASURE) quit = 1;
#endif
    }
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)(frame << 16);
    return 0;
}
