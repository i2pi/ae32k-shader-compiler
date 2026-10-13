// glitch.ss: block cells jump on a beat (k1 beats/s), liquid wobble underneath, motion shake.
// k0 = jump amplitude px (try 40..120). Jumps bigger than a block leave black seams: intended.
let beat = floor(in.t * (in.k1 + 2));
let cx = floor(in.u * 6);                       // 6 x 4 cells
let cy = floor(in.v * 4);
let n1 = noise(cx * 1.7 + beat * 3.1, cy * 2.3 + beat * 0.7);   // one value per cell per beat
let n2 = noise(cx * 0.9 + beat * 5.3, cy * 1.1 + beat * 1.9);
let gate = step(0.6, n1);                       // ~40 % of the cells jump this beat
let wob = noise(in.u * 3 + in.t * 0.7, in.v * 3 - in.t * 0.4) - 0.5;
let amp = in.k0 + 40;
out.dx = gate * (n2 - 0.5) * amp * 2 + wob * 16 + in.heat * 80 * sin(in.t * 6);
out.dy = gate * (n1 - 0.7) * amp + wob * 10;
