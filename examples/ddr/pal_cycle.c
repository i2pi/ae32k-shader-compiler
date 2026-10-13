/* Palette cycling on an 8-bit OSD canvas (`imcu canvas p8 <W> <H> <x> <y>`): the stage draws a plasma index field
 * (0..255 per pixel) into the canvas once, then every output frame rewrites the layer's 256-entry palette with a
 * colour ramp rotated by the frame count. The picture is a full-screen, smoothly moving colour gradient for ~770
 * register writes per frame and no pixel writes after the first frame.
 * Run through the pixel-stage path: tools/imcu/cstage.py pal_cycle.c 2 --upload, `imcu canvas p8 1920 1080 0 0`,
 * `imcu scan pix 2`; stop with `imcu scan stop`. Knobs: k0 cycling speed, k1 colour spread (ramp turns per 256
 * entries), k2 transparency (the sprite alpha 0x101F[3:0]: 0 = opaque .. 1 = clear; the palette's alpha byte had no
 * visible effect with the sprite opaque).
 * Palette entry (layer 4): 0x1078 = alpha << 8 | R, 0x1079 = G << 8 | B, then 0x107A = 0x8000 | index (limited range). */
#include "stage.h"
#define HOST(r) (*(volatile unsigned short *)(0x72000000u + (unsigned)(r) * 4u))
#define LOCAL(r) (*(volatile unsigned short *)(0x70000000u + (unsigned)(r) * 4u))
#define U_RB  (*(volatile unsigned int *)0x80010800u)
#define U_LSR (*(volatile unsigned int *)0x80010814u)
#ifndef W
#define W 1920
#endif
#ifndef H
#define H 1080
#endif
#define CV 0x0C200000u
static unsigned drawn, frame, rows_done, sp_alpha = 15;
static char line[96]; static unsigned ln;
static unsigned hexv(const char **pp) { const char *p = *pp; unsigned v = 0; while (*p == ' ') p++;
    for (;; p++) { char c = *p; unsigned d; if (c >= '0' && c <= '9') d = c - '0'; else if (c >= 'a' && c <= 'f') d = c - 'a' + 10; else if (c >= 'A' && c <= 'F') d = c - 'A' + 10; else break; v = (v << 4) | d; }
    *pp = p; return v; }
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
static inline int sn(const short *s, unsigned ph) { return s[ph & 255]; }   /* Q14, 256 steps per turn */
__attribute__((section(".entry"))) int stage(struct ctx *c)
{
    unsigned short s2 = HOST(0x0002), s9 = HOST(0x0009);
    unsigned msb = (CV >> 26) & 3, quit = 0, i;
    const short *S = c->sin256;
    HOST(0x0002) = (unsigned short)(s2 & 0x7FFF);
    HOST(0x0009) = (unsigned short)((s9 & ~0x7700) | (msb << 12) | (msb << 8));
    /* the index field, once (resumable: a yield keeps rows_done) */
    while (!drawn && !quit) {
        unsigned y = rows_done, x;
        volatile unsigned *q = (volatile unsigned *)(0x78000000u + (CV & 0x03FFFFFFu) + y * W);
        int cy1 = sn(S, (y * 3) >> 3), cy2 = sn(S, (y * 5) >> 4);
        for (x = 0; x < W; x += 4) {                                  /* 4 indices per dword, byte 0 = leftmost (not checked) */
            unsigned w = 0, k;
            for (k = 0; k < 4; k++) {
                unsigned xx = x + k, dx = xx > 960 ? xx - 960 : 960 - xx, dy = y > 540 ? y - 540 : 540 - y;
                int f = sn(S, (xx * 3) >> 4) + cy1 + sn(S, ((xx + y) * 5) >> 5) + sn(S, ((dx + dy) * 3) >> 4) + cy2;
                w |= (unsigned)(((f + 5 * 16384) * 205) >> 16 & 255) << (k * 8);   /* -5..5 (Q14) -> 0..255 */
            }
            *q++ = w;
            if ((U_LSR & 1) && poll(c->knob)) quit = 1;                /* drain every dword: a knob line overruns the FIFO in ~50 us */
        }
        if (quit) break;
        if (++rows_done >= H) drawn = 1;
    }
    while (!quit) {
        unsigned n = 0, speed = 1 + (unsigned)(c->knob[0] >> 12), spread = 1 + (unsigned)(c->knob[1] >> 13);
        unsigned a15 = 15 - (unsigned)((c->knob[2] > 65536 ? 65536 : c->knob[2] < 0 ? 0 : c->knob[2]) * 15 >> 16);
        HOST(0x0010) = 1;                                             /* wait for the output vsync, then rewrite the palette */
        while (!(HOST(0x0010) & 1) && ++n < 4000000u) { if (!(n & 255) && poll(c->knob)) { quit = 1; break; } }
        if (quit) break;
        LOCAL(0x1000) = (unsigned short)((LOCAL(0x1000) & ~((1u << 11) | 7u)) | (1u << 7) | 4u);   /* layer 4, no auto-increment, palette_dn_mode */
        if (a15 != sp_alpha) { LOCAL(0x101F) = (unsigned short)((LOCAL(0x101F) & ~15u) | a15); sp_alpha = a15; }   /* sprite alpha: only on change (continuous writes hide the sprite) */
        for (i = 0; i < 256; i++) {
            unsigned h = i * spread + frame * speed;
            int r = 126 + ((sn(S, h) * 109) >> 14), g = 126 + ((sn(S, h + 85) * 109) >> 14), b = 126 + ((sn(S, h + 171) * 109) >> 14);
            LOCAL(0x1078) = (unsigned short)((255u << 8) | (unsigned)r);
            LOCAL(0x1079) = (unsigned short)(((unsigned)g << 8) | (unsigned)b);
            LOCAL(0x107A) = (unsigned short)(0x8000u | i);
            if (!(i & 15) && (U_LSR & 1) && poll(c->knob)) quit = 1;
        }
        frame++;
        if ((U_LSR & 1) && poll(c->knob)) quit = 1;
    }
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)(frame << 16);
    return 0;
}
