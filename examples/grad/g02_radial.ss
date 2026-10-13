// Radial gradient: 5 concentric rings around a moving centre, in bands of 58 lines, 10 cells per band (the left and
// right end of each ring's chord; every cell spans the whole band, its chord ends evaluated on every line, a chord
// closing to the centre where the ring does not cover the band). Inside ring k the level is 3k+3; leaving a ring
// returns to the outer ring's level (0 outside). Geometry in fractions of the height (squares of pixel distances
// overflow Q16). 140 points (14 bands: the build must fit the blanking).
let band = floor(in.x / 10);
let j = mod(in.x, 10);
let k = floor(j / 2);
let side = mod(j, 2);
let cx = 960 + 420 * sin(in.t * 0.08);
let cy = 540 + 50 * sin(in.t * 0.11);
let r = 0.37 * (5 - k) / 5;
let y0 = cy - 400 + band * 58;
let u0 = (y0 - cy) / 1080;
let u1 = (y0 + 58 - cy) / 1080;
let d0 = sqrt(max(r * r - u0 * u0, 0)) * 1080;
let d1 = sqrt(max(r * r - u1 * u1, 0)) * 1080;
let inside = step(1, d0 + d1);
let sg = 1 - 2 * side;
out.vx = cx - sg * d0;
out.vy = y0 * inside + 1124 * (1 - inside);
out.p0 = (1 - side) * (3 * k + 3) + side * 3 * k;
out.p2 = 0;
out.p3 = 58;
out.vdx = (sg * (d0 - d1)) / 58 * inside;
