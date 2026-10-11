let a0 = (lerp(0.5, tau, tau) * tau);
out.o0 = in.h;
out.o1 = a0;
out.o2 = min(mod((lerp(a0, 100, in.w) * clamp(0, 0.001, 7)), ((0 && in.u) * (7 == in.x))), -((in.k1 <= in.k3) % noise(in.mvy, a0)));
out.o3 = (!sqrt(in.y) == (abs(in.k3) - -0.5));
