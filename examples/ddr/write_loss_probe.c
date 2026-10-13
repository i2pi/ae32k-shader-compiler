/* DDR window write-loss probe: each test writes 0xA0A0A0A0 + test*0x10 + word into its own 16-byte line in DDR0
 * scratch (0x0CB00000 + test * 64), with a different access sequence; the STM reads them back. */
#include "stage.h"
#define HOST(r) (*(volatile unsigned short *)(0x72000000u + (unsigned)(r) * 4u))
#define BASE (0x78000000u + 0x032A0000u + 200u * 3072u)   /* bank 0: inside the CH0 frame ring (live input overwrites it) */
__attribute__((section(".entry"))) int stage(struct ctx *c)
{
    unsigned short s2 = HOST(0x0002), s9 = HOST(0x0009);
    volatile unsigned *far = (volatile unsigned *)(BASE + 0x8000);
    unsigned t, w, dummy = 0;
    HOST(0x0002) = (unsigned short)(s2 & 0x7FFF); HOST(0x0009) = (unsigned short)((s9 & ~0x7700) );
    for (t = 0; t < 8; t++) { volatile unsigned *q = (volatile unsigned *)(BASE + t * 64); for (w = 0; w < 4; w++) q[w] = 0x11111111u; }
    dummy += far[0];                                                     /* settle */
#if TEST == 0
    { volatile unsigned *q = (volatile unsigned *)(BASE + 0 * 64); for (w = 0; w < 4; w++) q[w] = 0xA0A0A000u + w; }              /* 0: 4 stores */
#endif
    dummy += far[1];
#if TEST == 1
    { volatile unsigned *q = (volatile unsigned *)(BASE + 1 * 64); for (w = 0; w < 4; w++) q[w] = 0xA0A0A010u + w; dummy += q[0]; } /* 1: 4 stores, read same line */
#endif
    dummy += far[2];
#if TEST == 2
    { volatile unsigned *q = (volatile unsigned *)(BASE + 2 * 64); for (w = 0; w < 4; w++) { q[w] = 0xA0A0A020u + w; dummy += q[w]; } } /* 2: store, read */
#endif
    dummy += far[3];
#if TEST == 3
    { volatile unsigned *q = (volatile unsigned *)(BASE + 3 * 64); for (w = 0; w < 4; w++) q[w] = 0xA0A0A030u + w; far[8] = 1; }   /* 3: 4 stores, far store */
#endif
    dummy += far[4];
#if TEST == 4
    { volatile unsigned *q = (volatile unsigned *)(BASE + 4 * 64); for (w = 0; w < 4; w++) { q[w] = 0xA0A0A040u + w; dummy += far[w]; } } /* 4: store, far read */
#endif
    dummy += far[5];
#if TEST == 5
    { volatile unsigned *q = (volatile unsigned *)(BASE + 5 * 64); q[0] = 0xA0A0A050u; dummy += q[0]; }                            /* 5: one store, read it */
#endif
    dummy += far[6];
#if TEST == 6
    { volatile unsigned *q = (volatile unsigned *)(BASE + 6 * 64); q[0] = 0xA0A0A060u; q[1] = 0xA0A0A061u; }                      /* 6: 2 stores */
#endif
    dummy += far[7];
#if TEST == 7
    { volatile unsigned *q = (volatile unsigned *)(BASE + 7 * 64); for (w = 0; w < 4; w++) q[w] = 0xA0A0A070u + w; }               /* 7: 4 stores, nothing after */
#endif
    HOST(0x0009) = s9; HOST(0x0002) = s2;
    c->out[0] = (int)dummy;
    return 0;
}
