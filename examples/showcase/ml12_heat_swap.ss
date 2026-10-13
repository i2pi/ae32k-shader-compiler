// in_swap where the picture moves: each cell permutes Y/Cb/Cr when its motion heat (in.heat, 0..1) is above
// 0.02 + 0.2 * k1; k2 picks the permutation. Vertex stage: corpus/v21_heat_cells.ss; `imcu scan motion 8 9`.
@out swap in_swap
out.swap = step(0.02 + in.k1 * 0.2, in.heat) * (in.k2 + 2);
