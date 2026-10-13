// ripple: concentric waves from the centre. k0 = amplitude px (try 8), k1 = speed (turns/s)
let du = in.u - 0.5;
let dv = (in.v - 0.5) * 0.5625;          // 1080/1920: circular in pixels
let r = sqrt(du * du + dv * dv) + 0.0005; // 0 .. ~0.58 (frame units)
let a = (in.k0 + 2) * sin(r * 8 - in.t * (in.k1 + 0.5));
out.dx = a * du / r;
out.dy = a * dv / r;
