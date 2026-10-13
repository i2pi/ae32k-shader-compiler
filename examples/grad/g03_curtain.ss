// Wave curtain: 12 boundaries down the frame, each following its own travelling sine, in bands of 84 lines (each
// band edge runs straight to the next band's position, so the boundaries are continuous curves). Right of
// boundary k the level is k+1 (spread over 16). k0 = wave amplitude scale. 144 points (12 bands: the build must fit the blanking).
let band = floor(in.x / 12);
let k = mod(in.x, 12);
let y0 = band * 84;
let a = 70 * (1 + in.k0);
let b0 = 80 + k * 150 + a * sin(y0 / 600 + in.t * 0.25 + k * 0.07);
let b1 = 80 + k * 150 + a * sin((y0 + 84) / 600 + in.t * 0.25 + k * 0.07);
out.vx = b0;
out.vy = y0;
out.p0 = floor((k + 1) * 15 / 12 + 0.5);
out.p2 = 0;
out.p3 = 84;
out.vdx = (b1 - b0) / 84;
