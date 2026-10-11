// Syntax tree of the Scion shader language (zephyr_scion docs/SHADER_LANGUAGE_REFERENCE.md).
// Every value is a Q16 integer (65536 = 1.0).

sealed class Expr {
  const Expr();
}

/// A constant, already in Q16.
class Num extends Expr {
  final int q;
  const Num(this.q);
}

/// `in.<name>`: a ctx field (abi.dart ctxInput).
class In extends Expr {
  final String name;
  const In(this.name);
}

/// `out.<name>` read back: the current value of output slot [slot].
class OutRead extends Expr {
  final int slot;
  const OutRead(this.slot);
}

class Local extends Expr {
  final String name;
  const Local(this.name);
}

/// `-` or `!`.
class Unary extends Expr {
  final String op;
  final Expr e;
  const Unary(this.op, this.e);
}

/// `+ - * / % < <= > >= == != && ||`.
class Binary extends Expr {
  final String op;
  final Expr l, r;
  const Binary(this.op, this.l, this.r);
}

class Call extends Expr {
  final String fn;
  final List<Expr> args;
  const Call(this.fn, this.args);
}

sealed class Stmt {
  /// The source line the statement starts on (0 when built by hand).
  final int line;
  const Stmt({this.line = 0});
}

/// `let name = e;` or `name = e;`.
class Assign extends Stmt {
  final String name;
  final Expr e;
  const Assign(this.name, this.e, {super.line});
}

/// `out.name = e;`
class OutAssign extends Stmt {
  final int slot;
  final Expr e;
  const OutAssign(this.slot, this.e, {super.line});
}

class If extends Stmt {
  final Expr cond;
  final List<Stmt> then, otherwise;
  const If(this.cond, this.then, this.otherwise, {super.line});
}

/// One `@out name reg mask shift mode` line (scan stage).
class OutMapEntry {
  final int reg, mask, shift, mode, slot;
  const OutMapEntry(this.reg, this.mask, this.shift, this.mode, this.slot);
}

class Program {
  final List<Stmt> body;
  final List<String> locals; // in declaration order
  final List<OutMapEntry> outMap;
  final Map<String, int> outNames; // @out names -> slot
  const Program(this.body, this.locals, this.outMap, this.outNames);
}
