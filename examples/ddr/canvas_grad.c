/* One-shot test of drawing into the OSD canvas (`imcu canvas yc 640 360 <x> <y>`: 16-bit YCbCr 4:2:2 sprite at DDR0
 * 0x0C200000, bank 3): luma ramps left to right, Cb top to bottom, Cr = 128. Each dword is two pixels:
 * Y | Cb << 8 | Y' << 16 | Cr << 24. Run with `imcu hybrun a 2 1`; out[0] = rows drawn. */
#include "stage.h"
#define HOST(r) (*(volatile unsigned short *)(0x72000000u + (unsigned)(r) * 4u))
#define CV 0x0C200000u
#define W 640
#define H 360
__attribute__((section(".entry"))) int stage(struct ctx *c)
{
    unsigned short s2 = HOST(0x0002), s9 = HOST(0x0009);
    unsigned y, x, msb = (CV >> 26) & 3;
    HOST(0x0002) = (unsigned short)(s2 & 0x7FFF);                                     /* DDR0 */
    HOST(0x0009) = (unsigned short)((s9 & ~0x7700) | (msb << 12) | (msb << 8));     /* bank 3 */
    for (y = 0; y < H; y++) {
        volatile unsigned *row = (volatile unsigned *)(0x78000000u + (CV & 0x03FFFFFFu) + y * W * 2);
        unsigned cb = 16 + ((y * 182) >> 8);                                          /* 16..271 -> clamp below */
        if (cb > 240) cb = 240;
        for (x = 0; x < W / 2; x++) {
            unsigned y0 = 16 + ((x * 2 * 87) >> 8), y1 = 16 + (((x * 2 + 1) * 87) >> 8);   /* 16..233 over 640 px */
            row[x] = y0 | (cb << 8) | (y1 << 16) | (128u << 24);
        }
    }
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)y;
    return 0;
}
