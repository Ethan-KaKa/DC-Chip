#!/usr/bin/env python3
"""Self-checking tests for the RV32E test encoder and GNU cross-check."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import rv32e_encode as isa  # noqa: E402


EXAMPLES = [
    ("add x3,x1,x2", isa.encode_add(3, 1, 2)),
    ("sub x3,x1,x2", isa.encode_sub(3, 1, 2)),
    ("sll x3,x1,x2", isa.encode_sll(3, 1, 2)),
    ("slt x3,x1,x2", isa.encode_slt(3, 1, 2)),
    ("sltu x3,x1,x2", isa.encode_sltu(3, 1, 2)),
    ("xor x3,x1,x2", isa.encode_xor(3, 1, 2)),
    ("srl x3,x1,x2", isa.encode_srl(3, 1, 2)),
    ("sra x3,x1,x2", isa.encode_sra(3, 1, 2)),
    ("or x3,x1,x2", isa.encode_or(3, 1, 2)),
    ("and x3,x1,x2", isa.encode_and(3, 1, 2)),
    ("addi x3,x1,-1", isa.encode_addi(3, 1, -1)),
    ("slti x3,x1,10", isa.encode_slti(3, 1, 10)),
    ("sltiu x3,x1,10", isa.encode_sltiu(3, 1, 10)),
    ("xori x3,x1,10", isa.encode_xori(3, 1, 10)),
    ("ori x3,x1,10", isa.encode_ori(3, 1, 10)),
    ("andi x3,x1,10", isa.encode_andi(3, 1, 10)),
    ("slli x3,x1,0x4", isa.encode_slli(3, 1, 4)),
    ("srli x3,x1,0x4", isa.encode_srli(3, 1, 4)),
    ("srai x3,x1,0x4", isa.encode_srai(3, 1, 4)),
    ("lui x3,0x12345", isa.encode_lui(3, 0x12345)),
    ("auipc x3,0x12345", isa.encode_auipc(3, 0x12345)),
    ("lw x3,4(x1)", isa.encode_lw(3, 1, 4)),
    ("lh x3,4(x1)", isa.encode_lh(3, 1, 4)),
    ("lhu x3,4(x1)", isa.encode_lhu(3, 1, 4)),
    ("lb x3,4(x1)", isa.encode_lb(3, 1, 4)),
    ("lbu x3,1(x1)", isa.encode_lbu(3, 1, 1)),
    ("sw x2,4(x1)", isa.encode_sw(2, 1, 4)),
    ("sh x2,4(x1)", isa.encode_sh(2, 1, 4)),
    ("sb x2,1(x1)", isa.encode_sb(2, 1, 1)),
    ("jalr x5,8(x1)", isa.encode_jalr(5, 1, 8)),
]


def require_raises(error_type: type[Exception], function, *args, **kwargs) -> None:
    try:
        function(*args, **kwargs)
    except error_type:
        return
    raise AssertionError(f"{function.__name__} did not raise {error_type.__name__}")


def test_encoder() -> None:
    # Test branches, JAL, and FENCE encodings directly
    assert isa.encode_beq(1, 2, 16) == 0x00208863
    assert isa.encode_bne(1, 2, 16) == 0x00209863
    assert isa.encode_blt(1, 2, 16) == 0x0020C863
    assert isa.encode_bge(1, 2, 16) == 0x0020D863
    assert isa.encode_bltu(1, 2, 16) == 0x0020E863
    assert isa.encode_bgeu(1, 2, 16) == 0x0020F863
    assert isa.encode_jal(1, 16) == 0x010000EF
    assert isa.encode_fence() == 0x0000000F

    for register in range(16):
        isa.encode_add(register, register, register)
        isa.encode_sub(register, register, register)
        isa.encode_addi(register, register, 0)
        isa.encode_lui(register, 0)
        isa.encode_auipc(register, 0)
        isa.encode_jal(register, 0)
        isa.encode_jalr(register, register, 0)
        isa.encode_lw(register, register, 0)
        isa.encode_lh(register, register, 0)
        isa.encode_lhu(register, register, 0)
        isa.encode_lb(register, register, 0)
        isa.encode_lbu(register, register, 0)
        isa.encode_sw(register, register, 0)
        isa.encode_sh(register, register, 0)
        isa.encode_sb(register, register, 0)
        isa.encode_beq(register, register, 0)
        isa.encode_bne(register, register, 0)

    boundary_words = [
        isa.encode_add(0, 0, 0),
        isa.encode_add(15, 15, 15),
        isa.encode_addi(15, 15, -2048),
        isa.encode_addi(15, 15, 2047),
        isa.encode_lui(15, 0),
        isa.encode_lui(15, 0xFFFFF),
        isa.encode_auipc(15, 0xFFFFF),
        isa.encode_jal(15, -1048576),
        isa.encode_jal(15, 1048574),
        isa.encode_beq(15, 15, -4096),
        isa.encode_beq(15, 15, 4094),
        isa.encode_sw(15, 15, -2048),
        isa.encode_sb(15, 15, 2047),
    ]
    image = isa.format_hex(boundary_words, start_pc=0x100)
    lines = image.splitlines()
    if len(lines) != len(boundary_words):
        raise AssertionError("HEX output has the wrong line count")
    if any(re.fullmatch(r"[0-9a-f]{8}", line) is None for line in lines):
        raise AssertionError(f"HEX output is not eight lowercase digits per line: {image!r}")

    for register in (-1, 16, 17, 31):
        require_raises(ValueError, isa.encode_add, register, 0, 0)
        require_raises(ValueError, isa.encode_add, 0, register, 0)
        require_raises(ValueError, isa.encode_add, 0, 0, register)
        require_raises(ValueError, isa.encode_addi, register, 0, 0)
        require_raises(ValueError, isa.encode_addi, 0, register, 0)
        require_raises(ValueError, isa.encode_lui, register, 0)
        require_raises(ValueError, isa.encode_auipc, register, 0)
        require_raises(ValueError, isa.encode_jal, register, 0)
        require_raises(ValueError, isa.encode_beq, register, 0, 0)
        require_raises(ValueError, isa.encode_beq, 0, register, 0)

    for immediate in (-2049, 2048):
        require_raises(ValueError, isa.encode_addi, 0, 0, immediate)
        require_raises(ValueError, isa.encode_sw, 0, 0, immediate)
    for immediate in (-1, 0x100000):
        require_raises(ValueError, isa.encode_lui, 0, immediate)
        require_raises(ValueError, isa.encode_auipc, 0, immediate)
    for shamt in (-1, 32):
        require_raises(ValueError, isa.encode_slli, 0, 0, shamt)
    require_raises(ValueError, isa.format_hex, [0], start_pc=2)
    require_raises(ValueError, isa.format_hex, [0, 0], start_pc=0xFFFFFFFC)
    require_raises(ValueError, isa.format_hex, [0x100000000])


def test_gnu_tools(gcc: str, objdump: str) -> None:
    source = ".text\n" + "\n".join(assembly for assembly, _ in EXAMPLES) + "\n"
    with tempfile.TemporaryDirectory(prefix="dc-chip-isa-") as directory:
        source_path = Path(directory) / "examples.S"
        object_path = Path(directory) / "examples.o"
        source_path.write_text(source, encoding="ascii")
        subprocess.run(
            [gcc, "-c", "-march=rv32e", "-mabi=ilp32e", "-o", str(object_path), str(source_path)],
            check=True,
        )
        result = subprocess.run(
            [objdump, "-d", "-M", "no-aliases,numeric", str(object_path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        )

    decoded = []
    pattern = re.compile(r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+(\S+)\s*(.*)$")
    for line in result.stdout.splitlines():
        match = pattern.match(line)
        if match:
            operands = match.group(3).replace(" ", "")
            decoded.append((int(match.group(1), 16), match.group(2), operands))

    if len(decoded) != len(EXAMPLES):
        raise AssertionError(f"GNU objdump returned {len(decoded)} instructions:\n{result.stdout}")
    for (assembly, encoded), (gnu_word, mnemonic, operands) in zip(EXAMPLES, decoded):
        expected_mnemonic, expected_operands = assembly.split(" ", 1)
        if gnu_word != encoded:
            raise AssertionError(
                f"GNU encoding for {assembly} is {gnu_word:08x}, project encoder is {encoded:08x}"
            )
        if (mnemonic, operands) != (expected_mnemonic, expected_operands):
            raise AssertionError(
                f"GNU disassembly for {encoded:08x} is {mnemonic} {operands}, expected {assembly}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gcc", required=True)
    parser.add_argument("--objdump", required=True)
    arguments = parser.parse_args()

    try:
        test_encoder()
        test_gnu_tools(arguments.gcc, arguments.objdump)
    except (AssertionError, OSError, subprocess.CalledProcessError) as error:
        print(f"test_isa: FAIL {error}", file=sys.stderr)
        return 1

    print("test_isa: PASS (encoder, HEX, GNU encoding/disassembly)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
