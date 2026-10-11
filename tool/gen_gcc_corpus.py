#!/usr/bin/env python3
"""Builds test/golden/gcc/: stage blobs compiled the current way (shader.py -> C -> the
Wine ae32000-elf-gcc), for every example and for random programs. The emulator runs
them and must match the Dart reference interpreter bit for bit; later the native
compiler's output is held to the same reference.

Uses shader.py's own code generator, but compiles in a private directory: never
tools/imcu/build/, which the device workflow uploads from.

  python3 tool/gen_gcc_corpus.py [--random N] [--seed S] [--src DIR --out DIR]
Writes <name>.ss, <name>.bin and manifest.txt ("name<TAB>slot<TAB>bytes"). With --src, the
stages in DIR only (e.g. tools/imcu/examples/corpus, for tool/bench.dart), no random ones.
"""
import os, random, shutil, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
IMCU = os.path.abspath(os.path.join(ROOT, "..", "..", "tools", "imcu"))
OUT = os.path.join(ROOT, "test", "golden", "gcc")

sys.path.insert(0, IMCU)
import shader  # noqa: E402

FUNCS = dict(shader.FUNCS)
INPUTS = ["x", "y", "u", "v", "t", "frame", "rnd", "w", "h", "k0", "k1", "k2", "k3", "heat", "mvx", "mvy"]
BIN = ["+", "-", "*", "/", "%", "<", "<=", ">", ">=", "==", "!=", "&&", "||"]


def rexpr(rng, depth, locals_):
    if depth <= 0 or rng.random() < 0.25:
        k = rng.random()
        if k < 0.45:
            return "in." + rng.choice(INPUTS)
        if k < 0.6 and locals_:
            return rng.choice(locals_)
        if k < 0.65:
            return rng.choice(["pi", "tau"])
        return rng.choice(["0", "1", "2", "0.5", "0.25", "3.75", "100", "0.001", "1920", "0.0001", "7"])
    k = rng.random()
    if k < 0.45:
        return f"({rexpr(rng, depth - 1, locals_)} {rng.choice(BIN)} {rexpr(rng, depth - 1, locals_)})"
    if k < 0.55:
        return f"{rng.choice(['-', '!'])}{rexpr(rng, depth - 1, locals_)}"
    f = rng.choice(sorted(FUNCS))
    return f"{f}(" + ", ".join(rexpr(rng, depth - 1, locals_) for _ in range(FUNCS[f])) + ")"


def rprog(rng):
    lines, locals_ = [], []
    for _ in range(rng.randint(1, 4)):
        name = f"a{len(locals_)}"
        lines.append(f"let {name} = {rexpr(rng, rng.randint(1, 4), locals_)};")
        locals_.append(name)
    for o in range(rng.randint(1, 4)):
        if rng.random() < 0.3:
            lines.append(f"if ({rexpr(rng, 2, locals_)}) {{ out.o{o} = {rexpr(rng, 3, locals_)}; }}")
        else:
            lines.append(f"out.o{o} = {rexpr(rng, rng.randint(1, 4), locals_)};")
    if rng.random() < 0.3 and locals_:
        lines.append(f"{locals_[0]} = {rexpr(rng, 2, locals_)};")
        lines.append(f"out.o5 = {locals_[0]} + out.o0;")
    return "\n".join(lines) + "\n"


def main():
    args = sys.argv[1:]
    src_dir = os.path.abspath(args[args.index("--src") + 1]) if "--src" in args else os.path.join(IMCU, "examples")
    out = os.path.abspath(args[args.index("--out") + 1]) if "--out" in args else OUT
    n = int(args[args.index("--random") + 1]) if "--random" in args else (0 if "--src" in args else 120)
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else 1
    work = tempfile.mkdtemp(prefix="ae32k_gcc_")
    for f in ("stage.h", "stage.ld"):
        shutil.copy(os.path.join(IMCU, f), work)
    shader.HERE = work  # compile_source builds in HERE/build and reads HERE/stage.ld
    os.makedirs(out, exist_ok=True)
    jobs = []
    for f in sorted(os.listdir(src_dir)):
        if f.endswith(".ss"):
            src = open(os.path.join(src_dir, f)).read()
            vert = f.startswith("verts") or (f[0] == "v" and f[1:3].isdigit())
            slot = 2 if vert else (1 if "@out" in src or f.startswith(("scan", "frag")) or (f[0] == "s" and f[1:3].isdigit()) else 0)
            jobs.append((f[:-3], src, slot))
    rng = random.Random(seed)
    for i in range(n):
        jobs.append((f"rand{i:03d}", rprog(rng), 0))
    manifest = []
    base = dict(shader.OUTPUTS)
    for name, src, slot in jobs:
        shader.OUTPUTS.clear()
        shader.OUTPUTS.update(base)  # @out names mutate the global table
        try:
            words, nbytes = shader.compile_source(src, slot=slot)
        except Exception as e:  # too big, or a program shader.py rejects
            print(f"skip {name}: {str(e).splitlines()[0][:100]}")
            continue
        blob = b"".join(w.to_bytes(4, "little") for w in words)
        open(os.path.join(out, name + ".ss"), "w").write(src)
        open(os.path.join(out, name + ".bin"), "wb").write(blob)
        manifest.append(f"{name}\t{slot}\t{len(blob)}")
        print(f"{name}: slot {slot}, {nbytes} bytes", flush=True)
    open(os.path.join(out, "manifest.txt"), "w").write("\n".join(manifest) + "\n")
    shutil.rmtree(work)
    print(f"{len(manifest)} blobs")


if __name__ == "__main__":
    main()
