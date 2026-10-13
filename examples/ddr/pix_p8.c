/* Pixel shader runner on an 8-bit palette OSD canvas (`imcu canvas p8 <W> <H> <x> <y>`): the shader (scan slot 1)
 * returns one value, out.o0 (0..1), on a grid of every 32nd pixel of every 8th row; the runner interpolates it
 * bilinearly into palette indices (1 byte per pixel, half the bytes of pix_osd.c's 16-bit canvas), double-buffers as
 * pix_osd.c does, and after each flip rewrites the 256-entry palette with a colour ramp rotated by the frame count
 * (pal_cycle.c). Knobs as the shader uses them, plus k6 palette speed and k7 palette spread.
 * Run: ae32k_shaderc <shader> --scan --osc; tools/imcu/cstage.py pix_p8.c 2 --upload; imcu canvas p8 W H x y;
 * imcu scan pix 2. Index bytes: byte 0 of each dword = leftmost pixel (assumed, as pal_cycle.c). */
#include "stage.h"
#define HOST(r) (*(volatile unsigned short *)(0x72000000u + (unsigned)(r) * 4u))
#define LOCAL(r) (*(volatile unsigned short *)(0x70000000u + (unsigned)(r) * 4u))
#ifndef W
#define W 960                                                        /* must match `imcu canvas p8 W H ...` */
#endif
#ifndef H
#define H 432
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
static int top[NSX], bot[NSX];                                        /* sample rows above and below, Q8 indices */
#ifdef MEASURE
static unsigned m_n, m_late;
#endif
static unsigned hexv(const char **pp) { const char *p = *pp; unsigned v = 0; while (*p == ' ') p++;
    for (;; p++) { char c = *p; unsigned d; if (c >= '0' && c <= '9') d = c - '0'; else if (c >= 'a' && c <= 'f') d = c - 'a' + 10; else if (c >= 'A' && c <= 'F') d = c - 'A' + 10; else break; v = (v << 4) | d; }
    *pp = p; return v; }
/* poll the UART: 0 = nothing / knobs taken, 1 = return (stop or yield line) */
static unsigned poll(struct ctx *c)
{
    int *knob = c->knob, r;
    while ((r = c->rx()) >= 0) {
        char ch = (char)r;
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
/* the shader along sample row j into dst (Q8 palette index 0..255); 1 = stop/yield line seen */
static int eval_row(struct ctx *c, unsigned j, int *dst)
{
    unsigned k, o;
    for (k = 0; k < NSX; k++) {
        c->x = (int)((k * SX) << 16); c->y = (int)((j * SY) << 16);
        c->u = (int)(k * (65536u / (NSX - 1))); c->v = (int)(j * (65536u / (NSY - 1)));
        for (o = 0; o < 3; o++) c->out[o] = 0;
        SHADER(c);
        dst[k] = clampi((c->out[0] * 255) >> 8, 0, 255 * 256);            /* Q16 0..1 -> Q8 0..255 */
        if (poll(c)) return 1;
    }
    return 0;
}
static inline int sn(const short *s, unsigned ph) { return s[ph & 255]; }
/* palette: colour ramp rotated by the frame count (pal_cycle.c), layer 4 */
static void palette(struct ctx *c)
{
    const short *S = c->sin256;
    unsigned i, speed = 1 + (unsigned)(c->knob[6] >> 12), spread = 1 + (unsigned)(c->knob[7] >> 13);
    LOCAL(0x1000) = (unsigned short)((LOCAL(0x1000) & ~((1u << 11) | 7u)) | (1u << 7) | 4u);
    for (i = 0; i < 256; i++) {
        unsigned h = i * spread + frame * speed;
        int r = 126 + ((sn(S, h) * 109) >> 14), g = 126 + ((sn(S, h + 85) * 109) >> 14), b = 126 + ((sn(S, h + 171) * 109) >> 14);
        LOCAL(0x1078) = (unsigned short)((255u << 8) | (unsigned)r);
        LOCAL(0x1079) = (unsigned short)(((unsigned)g << 8) | (unsigned)b);
        LOCAL(0x107A) = (unsigned short)(0x8000u | i);
        if (!(i & 15)) poll(c);
    }
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
    unsigned msb = (BUF[0] >> 26) & 3, quit = 0, j, k;
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
            for (k = 0; k < NSX; k++) top[k] = bot[k];
            if (eval_row(c, j + 1, bot)) { quit = 1; break; }
            for (r = 0; r < SY; r++) {
                volatile unsigned *q = (volatile unsigned *)(0x78000000u + (BUF[back] & 0x03FFFFFFu) + (j * SY + r) * W);
                for (k = 0; k + 1 < NSX; k++) {                       /* one SX-px span = SX / 4 dwords */
                    int i0 = top[k] + (((bot[k] - top[k]) * (int)r) >> 3), i1 = top[k + 1] + (((bot[k + 1] - top[k + 1]) * (int)r) >> 3);
                    int di = (i1 - i0) >> SXS, di4 = 4 * di;
                    volatile unsigned *e = q + SX / 4;
                    while (q < e) {                                   /* Q8: the index byte is bits 15:8 */
                        *q++ = ((unsigned)i0 >> 8) | ((unsigned)(i0 + di) & 0xFF00u) | (((unsigned)(i0 + 2 * di) & 0xFF00u) << 8) | (((unsigned)(i0 + 3 * di) & 0xFF00u) << 16);
                        i0 += di4;
                    }
                    if (!(k & 3) && poll(c)) { quit = 1; break; }
                }
                if (quit) break;
            }
        }
        if (quit) break;
        show(back); back ^= 1; frame++;
        /* wait for the vsync that applies the new address: after it the other buffer is free to draw */
        HOST(0x0010) = 1;
        while (!(HOST(0x0010) & 1) && ++n < 4000000u) { if (!(n & 255) && poll(c)) { quit = 1; break; } }
        if (!quit) palette(c);                                        /* in the blanking after the flip */
#ifdef MEASURE
        if (++m_n >= MEASURE) quit = 1;
#endif
    }
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)(frame << 16);
    return 0;
}
