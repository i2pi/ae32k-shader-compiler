/* Animated per-pixel luma plasma drawn into Send 1's held frame ring (input frozen): one frame per vsync for NF frames,
 * each drawn into the ring slot the output reads next. Luma per pixel: sines evaluated at each 10-px chunk's ends and
 * interpolated across it. Region X0..X0+NC*10, Y0..Y0+NR. Run: imcu hybrun a 2 1 (one lend, < 5 s). */
#include "stage.h"
#define HOST(r) (*(volatile unsigned short *)(0x72000000u + (unsigned)(r) * 4u))
#define LOCAL(r) (*(volatile unsigned short *)(0x70000000u + (unsigned)(r) * 4u))
#define PA 0x032A0000u
#define FS 0x0032A000u
#define ST 3072u
#define X0 720
#define NC 48
#define Y0 340
#define NR 200
#define NF 96
#ifndef TSTEP
#define TSTEP 1
#endif
static inline unsigned bsw(unsigned x) { return (x >> 24) | ((x >> 8) & 0xFF00u) | ((x << 8) & 0xFF0000u) | (x << 24); }
static inline int sn(const short *s, unsigned ph) { return s[ph & 255]; }            /* Q14, 256 per turn */
static unsigned vsync(void) { unsigned n = 0; HOST(0x0010) = 1; while (!(HOST(0x0010) & 1) && ++n < 4000000u) {} return n; }
__attribute__((section(".entry"))) int stage(struct ctx *c)
{
    const short *s = c->sin256;
    unsigned short s2 = HOST(0x0002), s9 = HOST(0x0009);
    unsigned f, y, ck, k, prev, cur, step = 1, done = 0;
    HOST(0x0002) = (unsigned short)(s2 & 0x7FFF); HOST(0x0009) = (unsigned short)(s9 & ~0x7700);
    vsync(); prev = (LOCAL(0x042D) >> 4) & 15;
    vsync(); cur = (LOCAL(0x042D) >> 4) & 15;
    step = cur + 3 - prev; if (step >= 3) step -= 3; if (step >= 3) step -= 3; if (!step) step = 1;
    for (f = 0; f < NF; f++) {
        unsigned tgt;
        vsync(); cur = (LOCAL(0x042D) >> 4) & 15; if (cur > 2) cur = 0;
        tgt = cur + step * TSTEP; while (tgt >= 3) tgt -= 3;
        for (y = 0; y < NR; y++) {
            volatile unsigned *row = (volatile unsigned *)(0x78000000u + PA + tgt * FS + (Y0 + y) * ST) + (X0 / 10) * 4;
            int ry = sn(s, y * 2 + f * 3) + sn(s, (y + f * 2) * 1);          /* row term */
            int va = 2048 + ((ry + sn(s, 0 + f * 4)) >> 4);
            for (ck = 0; ck < NC; ck++) {
                volatile unsigned *q = row + ck * 4;
                int vb = 2048 + ((ry + sn(s, (ck + 1) * 10 + f * 4) + sn(s, (((ck + 1) * 10 + y) >> 1) + f * 5)) >> 4);
                unsigned px[10], a, b, cc, d;
                for (k = 0; k < 10; k++) {                                    /* field k = pixel 9 - k */
                    int v = va + (((vb - va) * (int)(9 - k) * 6554) >> 16);
                    px[k] = v < 0 ? 0u : v > 4095 ? 4095u : (unsigned)v;
                }
                a = (px[0] << 12) | px[1];
                b = (px[2] << 20) | (px[3] << 8) | (px[4] >> 4);
                cc = ((px[4] & 0xF) << 28) | (px[5] << 16) | (px[6] << 4) | (px[7] >> 8);
                d = ((px[7] & 0xFF) << 24) | (px[8] << 12) | px[9];
                q[0] = bsw(a); q[1] = bsw(b); q[2] = bsw(cc); q[3] = bsw(d);   /* write-only: no DDR load follows, so no read-back needed (write-loss rule) */
                va = vb;
            }
        }
        done++;
    }
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)(done << 16); c->out[1] = (int)(step << 16);
    return 0;
}
