[Rail](http://esolangs.org/wiki/Rail) is an esoteric two-dimensional language
created by [Jonathon Duerig](http://esolangs.org/wiki/User:Duerig).
This is an interpreter and a C99-backend compiler, written in Haskell by
[Michael Tolly](mailto:miketolly@gmail.com).

Usage
=====

After cloning the repository, install the [Haskell Platform](http://www.haskell.org/platform/),
and install the package using cabal:

    cd rail
    cabal install

This installs the `rail` library, and the `hrail` executable. To run the executable:

    hrail input.rail
    hrail -c input.rail output.c
    hrail -r input.rail output.rail

The first form directly runs the Rail program. The second generates a C program. The third
"cleans up" the Rail code so all lines are read horizontally, left-to-right. This can be
useful for debugging.

Code generation
===============

The interpreter/compiler starts by statically traversing each function to build a simplified
control flow graph. This enables simple C code using goto statements to travel between
(more or less) basic blocks. As an example, the following Rail function (a cat program):

    $ 'main' (--):
     \
     | /---------\
     | |         |
     | \    /-io-/
     \---e-<
            \-#

becomes this C function:

    void fun_main() {
      goto E_5_4;
    E_5_4:
      builtin_eof();
      if (pop_bool()) {
        goto done;
      } else {
        builtin_input();
        builtin_output();
        goto E_5_4;
      }
    done:
      return;
    }

where the only remnant of the grid is a single label (the point where two branching paths meet).
