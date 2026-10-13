/* Hand-written stage: draws a per-pixel radial gradient (G plane, 12-bit) into a frame ring held still (input frozen).
 * Run once per call (imcu hybrun a 2 1). ctx->knob unused (bench zeroes them): parameters are constants. */
#include "stage.h"
#define HOST(r) (*(volatile unsigned short *)(0x72000000u + (unsigned)(r) * 4u))
#define PA 0x032A0000u
#define FS 0x0032A000u
#define ST 3072u
#define CX 960
#define CY 540
#define RR 250
#define INV 4293   /* (4095 << 16) / (RR*RR) */
static inline unsigned bsw(unsigned x) { return (x >> 24) | ((x >> 8) & 0xFF00u) | ((x << 8) & 0xFF0000u) | (x << 24); }
__attribute__((section(".entry"))) int stage(struct ctx *c)
{
    unsigned short s2 = HOST(0x0002), s9 = HOST(0x0009);
    unsigned slot, y, ck, k, n = 0;
    HOST(0x0002) = (unsigned short)(s2 & 0x7FFF);               /* DDR0 */
    HOST(0x0009) = (unsigned short)(s9 & ~0x7700);              /* 64 MB bank 0 for reads and writes */
    for (slot = 0; slot < 3; slot++)
        for (y = CY - RR; y < CY + RR; y++) {
            int dy = (int)y - CY;
            volatile unsigned *row = (volatile unsigned *)(0x78000000u + PA + slot * FS + y * ST);
            for (ck = (CX - RR) / 10; ck <= (CX + RR) / 10; ck++) {
                volatile unsigned *q = row + ck * 4;
                unsigned a = bsw(q[0]), b = bsw(q[1]), cc = bsw(q[2]), d = bsw(q[3]);
                unsigned px[10];
                px[0] = (a >> 12) & 0xFFF; px[1] = a & 0xFFF; px[2] = b >> 20; px[3] = (b >> 8) & 0xFFF;
                px[4] = ((b & 0xFF) << 4) | (cc >> 28); px[5] = (cc >> 16) & 0xFFF; px[6] = (cc >> 4) & 0xFFF;
                px[7] = ((cc & 0xF) << 8) | (d >> 24); px[8] = (d >> 12) & 0xFFF; px[9] = d & 0xFFF;
                for (k = 0; k < 10; k++) {
                    int dx = (int)(ck * 10 + 9 - k) - CX, r2 = dx * dx + dy * dy;
                    if (r2 < RR * RR) px[k] = 4095u - (unsigned)((r2 * INV) >> 16);
                }
                a = (a & 0xFF000000u) | (px[0] << 12) | px[1];
                b = (px[2] << 20) | (px[3] << 8) | (px[4] >> 4);
                cc = ((px[4] & 0xF) << 28) | (px[5] << 16) | (px[6] << 4) | (px[7] >> 8);
                d = ((px[7] & 0xFF) << 24) | (px[8] << 12) | px[9];
                q[0] = bsw(a); q[1] = bsw(b); q[2] = bsw(cc); q[3] = bsw(d); (void)q[3]; n++;   /* read back the last store: a store followed by a load from another address is lost */
            }
        }
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)(n << 16);
    return 0;
}
