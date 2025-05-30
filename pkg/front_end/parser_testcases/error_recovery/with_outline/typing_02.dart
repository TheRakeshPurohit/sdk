// Without specific missing-brace recovery, we'll end up with:
// * Class Foo, member Foo.foo_method1, Foo.toplevel_method1, Foo.toplevel_method2
// With specific missing-brace recovery, we'll end up with the correct:
// * Class Foo, members Foo.foo_method1, Foo.foo_method2
// * Top-level members toplevel_method1, toplevel_method2

class Foo {
  void foo_method1() {
    if (1+1==2) { // we just typed the begin brace and there's no end brace yet.
    // e.g. we're editing in IntelliJ and we haven't hit enter yet.
    // missing: }
  }

  void foo_method2() {
    // bla
  }
}

void toplevel_method1() {
  // bla
}

void toplevel_method2() {
  // bla
}
