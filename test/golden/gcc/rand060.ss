let a0 = clamp(cos((in.k2 - in.mvy)), frac((100 > in.w)), ((0.001 / in.k3) <= in.y));
let a1 = (sin(clamp((in.frame % in.k0), (a0 + a0), sin(7))) > (in.y < in.t));
let a2 = (in.k1 > a1);
let a3 = -2;
out.o0 = a2;
