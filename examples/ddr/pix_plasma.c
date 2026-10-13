/* Continuous pixel stage: a colour plasma panel drawn into Send 1's live frame buffer (Y, Cb, Cr planes) once per
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
#define ST 3072u
#define X0 800
#define NC 32
#define Y0 360
#define NR 100
#ifndef GATE
#define GATE 250                                                  /* lines past the panel before drawing (margin for the base phase) */
#endif
static const unsigned PB[3] = { 0x032A0000u, 0x0459C000u, 0x05E38000u };   /* Y, Cb, Cr plane rings (Cb, Cr above 64 MB) */
static unsigned frame, step = 1, have_step, lbase, have_lbase;
static char line[96]; static unsigned ln;
static inline unsigned bsw(unsigned x) { return (x >> 24) | ((x >> 8) & 0xFF00u) | ((x << 8) & 0xFF0000u) | (x << 24); }
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
__attribute__((section(".entry"))) int stage(struct ctx *c)
{
    const short *s = c->sin256;
    unsigned short s2 = HOST(0x0002), s9 = HOST(0x0009);
    unsigned prev, cur, y, ck, k, pl, quit = 0;
    HOST(0x0002) = (unsigned short)(s2 & 0x7FFF);
    if (!have_step) {                                                /* learn the read order from two vsyncs (once) */
        unsigned n = 0; HOST(0x0010) = 1; while (!(HOST(0x0010) & 1) && ++n < 4000000u) {} prev = (LOCAL(0x042D) >> 4) & 15;
        n = 0; HOST(0x0010) = 1; while (!(HOST(0x0010) & 1) && ++n < 4000000u) {} cur = (LOCAL(0x042D) >> 4) & 15;
        step = cur + 3 - prev; while (step >= 3) step -= 3; if (!step) step = 1; have_step = 1;
    }
    {   /* input line position: cdc_in_mon_count (0x1F47) counts the rising edges of the sync chosen in 0x1F48; find an
         * input frame start on vactive (0x10), then count hactive (0x00) from there: line = (count - base) mod 1080 */
        unsigned short sel = LOCAL(0x1F48), v0; unsigned n = 0;
        if (!have_lbase) {
            LOCAL(0x1F48) = (unsigned short)((sel & ~0x3Fu) | 0x10u); v0 = LOCAL(0x1F47);
            while (LOCAL(0x1F47) == v0 && ++n < 4000000u) {}
            LOCAL(0x1F48) = (unsigned short)(sel & ~0x3Fu); lbase = LOCAL(0x1F47); have_lbase = 1;
        }
    }
    while (!quit) {
        unsigned tgt, f, n = 0;
        int spd = 65536 + c->knob[0], scl = 65536 + c->knob[1], camt = 65536 - c->knob[2];
        HOST(0x0010) = 1; while (!(HOST(0x0010) & 1) && ++n < 4000000u) { if (!(n & 255) && poll(c->knob)) { quit = 1; break; } }
        if (quit) break;
        cur = (LOCAL(0x042D) >> 4) & 15; if (cur > 2) cur = 0;
        tgt = cur + step; while (tgt >= 3) tgt -= 3;
        n = 0;                                                       /* wait until the input has written past the panel in this slot */
        for (;;) { unsigned cnt = LOCAL(0x1F47), d = (cnt - lbase) & 0xFFFFu; while (d >= 1125u) d -= 1125u; lbase = (cnt - d) & 0xFFFFu;   /* 1125 counts per frame (every line); rebase each read: the 16-bit count wraps at 65536, not a multiple of 1125 */
                   if (d >= Y0 + NR + GATE || ++n > 400000u) break; if (!(n & 255) && poll(c->knob)) { quit = 1; break; } }
        if (quit) break;
        tgt = (LOCAL(0x042D) >> 12) & 15; if (tgt > 2) tgt = 0;           /* the slot the input is writing: it has passed the panel, so the drawing
                                                                          * survives until the input comes back to this slot (whichever frame the output reads) */
        f = ((frame * (unsigned)(spd >> 8)) >> 8) & 0xFFFF; frame++;
        if (camt < 0) camt = 0;
        for (y = 0; y < NR && !quit; y++) {
            unsigned ys = (unsigned)((y * (unsigned)scl) >> 16);
            if (poll(c->knob)) { quit = 1; break; }
            for (pl = 0; pl < 3; pl++) {
                unsigned ad = PB[pl] + tgt * FS + (Y0 + y) * ST, msb = (ad >> 26) & 3;
                volatile unsigned *row;
                int ry = pl == 0 ? sn(s, ys * 2 + f * 3) + sn(s, ys + f * 2) : pl == 1 ? sn(s, ys * 3 + f * 2) : sn(s, ys + 64 + f * 4);
                int sh = pl == 0 ? 4 : 5, va, vb;
                HOST(0x0009) = (unsigned short)((s9 & ~0x7700) | (msb << 12) | (msb << 8));
                row = (volatile unsigned *)(0x78000000u + (ad & 0x03FFFFFFu)) + (X0 / 10) * 4;
                va = (ry + sn(s, f * 4)) >> sh; if (pl) va = (va * camt) >> 16; va += 2048;
                for (ck = 0; ck < NC; ck++) {
                    volatile unsigned *q = row + ck * 4;
                    if ((U_LSR & 1) && poll(c->knob)) { quit = 1; break; }   /* drain the UART every chunk: at ~3 Mbaud a knob line overruns the FIFO within a row */
                    unsigned xs = (unsigned)((((ck + 1) * 10) * (unsigned)scl) >> 16), px[10], a, b, cc, d;
                    int cx = pl == 0 ? sn(s, xs + f * 4) + sn(s, ((xs + ys) >> 1) + f * 5) : pl == 1 ? sn(s, ((xs * 3 * 13107) >> 16) + f * 3) : sn(s, ((xs * 2 * 13107) >> 16) + 128 + f * 6);
                    vb = (ry + cx) >> sh; if (pl) vb = (vb * camt) >> 16; vb += 2048;
                    for (k = 0; k < 10; k++) { int v = va + (((vb - va) * (int)(9 - k) * 6554) >> 16); px[k] = v < 0 ? 0u : v > 4095 ? 4095u : (unsigned)v; }
                    a = (px[0] << 12) | px[1];
                    b = (px[2] << 20) | (px[3] << 8) | (px[4] >> 4);
                    cc = ((px[4] & 0xF) << 28) | (px[5] << 16) | (px[6] << 4) | (px[7] >> 8);
                    d = ((px[7] & 0xFF) << 24) | (px[8] << 12) | px[9];
                    q[0] = bsw(a); q[1] = bsw(b); q[2] = bsw(cc); q[3] = bsw(d);   /* write-only: no read-back needed */
                    va = vb;
                }
            }
        }
    }
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)(frame << 16);
    return 0;
}
