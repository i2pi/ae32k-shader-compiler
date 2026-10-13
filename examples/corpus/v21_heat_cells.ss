// An 8 x 9 grid of cells (240 px x 120 lines), one left edge each (p2 = 0: a cell lasts until the next edge on
// the line), for a scan stage that reads the motion at each cell (in.heat). Pair with `imcu scan motion 8 9`
// so each cell has its own heat point; and e.g. showcase/ml12_heat_swap.ss. 72 points.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
out.vx = col * 240;
out.vy = row * 120;
out.p0 = 1;
out.p2 = 0;
out.p3 = 120;
