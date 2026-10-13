// Output test pattern inside the shape: Send 1's output stage pattern generator (0x1C01 out_test_ptrn) set at the
// cell edges; k3 picks the pattern (0 -> 8 wide horizontal ramp).
@out tp out0_tp
out.tp = in.p0 * (8 + in.k3);
