# Upstream source snapshot

`vendor/` is a read-only, selectively imported source snapshot from
[`NJU-ProjectN/riscv-tests-am`](https://github.com/NJU-ProjectN/riscv-tests-am)
at commit `676cbc7a4e520fca1c3d4dd1b586b2550769e02e`.

Imported inputs are `LICENSE`, `isa/rv32ui`, the `isa/rv64ui` files referenced
by its RV32 wrappers, `isa/macros/scalar`, and `env/p` plus `env/encoding.h`.
The upstream `LICENSE` remains in `vendor/LICENSE`.

`bridge/riscv_test.h` is the only environment replacement: it directs pass and
fail to AM `halt()`/DC-Chip `tohost`, uses no privileged state or registers
above `x15`, and replaces dead `unimp` code with a safe terminal jump.  The
adapter Makefile invokes the existing AM build interface and writes only under
`build/`.
