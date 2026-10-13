// Concentric rings of 12 points each, radius by ring, slowly pulsing; p0 alternates per ring.
let ring = floor(in.x / 12);
let k = mod(in.x, 12);
let a = k / 12 + ring * 0.02 + in.t * 0.05;
let r = (ring + 1) * 0.045 * (1 + 0.1 * sin(in.t * 0.5 + ring * 0.2));
out.vx = 960 + cos(a) * r * 1920;
out.vy = 540 + sin(a) * r * 1080;
out.p0 = mod(ring, 2);
out.p2 = r;
out.p3 = 30;
