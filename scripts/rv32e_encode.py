#!/usr/bin/env python3
"""Strict encoders for the DC-Chip RV32E transition subset v0.2."""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

OPCODE_LOAD = 0b0000011
OPCODE_OP_IMM = 0b0010011
OPCODE_STORE = 0b0100011
OPCODE_OP = 0b0110011
OPCODE_LUI = 0b0110111
OPCODE_JALR = 0b1100111


def _register(value: int, name: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError(f"{name} must be an integer")
    if not 0 <= value < 16:
        raise ValueError(f"{name} must name x0--x15, got x{value}")
    return value


def _signed_imm12(value: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError("imm12 must be an integer")
    if not -2048 <= value <= 2047:
        raise ValueError(f"imm12 must be in -2048--2047, got {value}")
    return value & 0xFFF


def _unsigned_imm20(value: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError("imm20 must be an integer")
    if not 0 <= value <= 0xFFFFF:
        raise ValueError(f"imm20 must be in 0--0xfffff, got {value}")
    return value


def _encode_i(opcode: int, funct3: int, rd: int, rs1: int, imm12: int) -> int:
    return (
        (_signed_imm12(imm12) << 20)
        | (_register(rs1, "rs1") << 15)
        | (funct3 << 12)
        | (_register(rd, "rd") << 7)
        | opcode
    )


def _encode_s(opcode: int, funct3: int, rs2: int, rs1: int, imm12: int) -> int:
    immediate = _signed_imm12(imm12)
    return (
        ((immediate >> 5) << 25)
        | (_register(rs2, "rs2") << 20)
        | (_register(rs1, "rs1") << 15)
        | (funct3 << 12)
        | ((immediate & 0x1F) << 7)
        | opcode
    )


def encode_add(rd: int, rs1: int, rs2: int) -> int:
    return (
        (_register(rs2, "rs2") << 20)
        | (_register(rs1, "rs1") << 15)
        | (_register(rd, "rd") << 7)
        | OPCODE_OP
    )


def encode_addi(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_OP_IMM, 0b000, rd, rs1, imm12)


def encode_lui(rd: int, imm20: int) -> int:
    return (_unsigned_imm20(imm20) << 12) | (_register(rd, "rd") << 7) | OPCODE_LUI


def encode_lw(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_LOAD, 0b010, rd, rs1, imm12)


def encode_lbu(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_LOAD, 0b100, rd, rs1, imm12)


def encode_sw(rs2: int, rs1: int, imm12: int) -> int:
    return _encode_s(OPCODE_STORE, 0b010, rs2, rs1, imm12)


def encode_sb(rs2: int, rs1: int, imm12: int) -> int:
    return _encode_s(OPCODE_STORE, 0b000, rs2, rs1, imm12)


def encode_jalr(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_JALR, 0b000, rd, rs1, imm12)


def format_hex(words: Iterable[int], *, start_pc: int = 0) -> str:
    """Return one eight-digit instruction word per line.

    ``start_pc`` describes the address of the first word. It is checked here so
    test images cannot silently describe an instruction-misaligned or wrapping
    layout even though the address is not stored in the textual HEX itself.
    """

    if not isinstance(start_pc, int) or isinstance(start_pc, bool):
        raise TypeError("start_pc must be an integer")
    if not 0 <= start_pc <= 0xFFFFFFFF:
        raise ValueError(f"start_pc must fit in 32 bits, got {start_pc}")
    if start_pc % 4 != 0:
        raise ValueError(f"start_pc must be four-byte aligned, got 0x{start_pc:x}")

    checked_words = []
    for index, word in enumerate(words):
        if not isinstance(word, int) or isinstance(word, bool):
            raise TypeError(f"instruction {index} must be an integer")
        if not 0 <= word <= 0xFFFFFFFF:
            raise ValueError(f"instruction {index} does not fit in 32 bits: {word}")
        if start_pc + 4 * index > 0xFFFFFFFF:
            raise ValueError("instruction image address wraps past 0xffffffff")
        checked_words.append(f"{word:08x}")

    return "" if not checked_words else "\n".join(checked_words) + "\n"


def write_hex(path: str | Path, words: Iterable[int], *, start_pc: int = 0) -> None:
    Path(path).write_text(format_hex(words, start_pc=start_pc), encoding="ascii")
