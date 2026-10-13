// An 8 x 10 grid whose column lines are bent by a noise field that fades in from the centre: each cell's left
// edge runs from its own displaced top to the displaced top of the cell below (vdx), so the lines are continuous.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let gx = (col - 3.5) * 0.125;
let ga = (row - 4.5) * 0.1;
let gb = (row - 3.5) * 0.1;
let wa = smoothstep(0.1, 0.5, sqrt(gx * gx + ga * ga));
let wb = smoothstep(0.1, 0.5, sqrt(gx * gx + gb * gb));
let na = noise(col * 0.5 + in.t * 0.2, row * 0.5) - 0.5;
let nb = noise(col * 0.5 + in.t * 0.2, row * 0.5 + 0.5) - 0.5;
let xa = col * 240 + na * wa * 300;
let xb = col * 240 + nb * wb * 300;
out.vx = xa;
out.vy = row * 96;
out.p0 = mod(col + row, 2);
out.p1 = wa;
out.p2 = step(6.5, col) * 240;
out.p3 = 96;
out.vdx = (xb - xa) / 96;
