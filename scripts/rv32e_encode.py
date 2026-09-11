#!/usr/bin/env python3
"""Strict encoders for the DC-Chip RV32E Base Integer Instruction Set (37 instructions)."""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

OPCODE_LOAD     = 0b0000011
OPCODE_MISC_MEM = 0b0001111  # fence
OPCODE_OP_IMM   = 0b0010011
OPCODE_AUIPC    = 0b0010111
OPCODE_STORE    = 0b0100011
OPCODE_OP       = 0b0110011
OPCODE_LUI      = 0b0110111
OPCODE_BRANCH   = 0b1100011
OPCODE_JALR     = 0b1100111
OPCODE_JAL      = 0b1101111


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


def _signed_imm13_branch(value: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError("branch offset must be an integer")
    if not -4096 <= value <= 4094:
        raise ValueError(f"branch offset must be in -4096..4094, got {value}")
    if value % 2 != 0:
        raise ValueError(f"branch offset must be a multiple of 2, got {value}")
    return value & 0x1FFF


def _signed_imm21_jump(value: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError("jump offset must be an integer")
    if not -1048576 <= value <= 1048574:
        raise ValueError(f"jump offset must be in -1048576..1048574, got {value}")
    if value % 2 != 0:
        raise ValueError(f"jump offset must be a multiple of 2, got {value}")
    return value & 0x1FFFFF


def _shamt5(value: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError("shamt must be an integer")
    if not 0 <= value < 32:
        raise ValueError(f"shamt must be in 0..31, got {value}")
    return value


def _encode_r(opcode: int, funct3: int, funct7: int, rd: int, rs1: int, rs2: int) -> int:
    return (
        (funct7 << 25)
        | (_register(rs2, "rs2") << 20)
        | (_register(rs1, "rs1") << 15)
        | (funct3 << 12)
        | (_register(rd, "rd") << 7)
        | opcode
    )


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


def _encode_b(funct3: int, rs1: int, rs2: int, imm13: int) -> int:
    imm = _signed_imm13_branch(imm13)
    bit_12 = (imm >> 12) & 1
    bit_11 = (imm >> 11) & 1
    bit_10_5 = (imm >> 5) & 0x3F
    bit_4_1 = (imm >> 1) & 0xF
    return (
        (bit_12 << 31)
        | (bit_10_5 << 25)
        | (_register(rs2, "rs2") << 20)
        | (_register(rs1, "rs1") << 15)
        | (funct3 << 12)
        | (bit_4_1 << 8)
        | (bit_11 << 7)
        | OPCODE_BRANCH
    )


def _encode_u(opcode: int, rd: int, imm20: int) -> int:
    return (_unsigned_imm20(imm20) << 12) | (_register(rd, "rd") << 7) | opcode


def _encode_j(rd: int, imm21: int) -> int:
    imm = _signed_imm21_jump(imm21)
    bit_20 = (imm >> 20) & 1
    bit_19_12 = (imm >> 12) & 0xFF
    bit_11 = (imm >> 11) & 1
    bit_10_1 = (imm >> 1) & 0x3FF
    return (
        (bit_20 << 31)
        | (bit_10_1 << 21)
        | (bit_11 << 20)
        | (bit_19_12 << 12)
        | (_register(rd, "rd") << 7)
        | OPCODE_JAL
    )


# --- Public Encoders ---

# 1. Upper Immediate / Jump
def encode_lui(rd: int, imm20: int) -> int:
    return _encode_u(OPCODE_LUI, rd, imm20)

def encode_auipc(rd: int, imm20: int) -> int:
    return _encode_u(OPCODE_AUIPC, rd, imm20)

def encode_jal(rd: int, imm21: int) -> int:
    return _encode_j(rd, imm21)

def encode_jalr(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_JALR, 0b000, rd, rs1, imm12)

# 2. Branches
def encode_beq(rs1: int, rs2: int, imm13: int) -> int:
    return _encode_b(0b000, rs1, rs2, imm13)

def encode_bne(rs1: int, rs2: int, imm13: int) -> int:
    return _encode_b(0b001, rs1, rs2, imm13)

def encode_blt(rs1: int, rs2: int, imm13: int) -> int:
    return _encode_b(0b100, rs1, rs2, imm13)

def encode_bge(rs1: int, rs2: int, imm13: int) -> int:
    return _encode_b(0b101, rs1, rs2, imm13)

def encode_bltu(rs1: int, rs2: int, imm13: int) -> int:
    return _encode_b(0b110, rs1, rs2, imm13)

def encode_bgeu(rs1: int, rs2: int, imm13: int) -> int:
    return _encode_b(0b111, rs1, rs2, imm13)

# 3. Loads
def encode_lb(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_LOAD, 0b000, rd, rs1, imm12)

def encode_lh(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_LOAD, 0b001, rd, rs1, imm12)

def encode_lw(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_LOAD, 0b010, rd, rs1, imm12)

def encode_lbu(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_LOAD, 0b100, rd, rs1, imm12)

def encode_lhu(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_LOAD, 0b101, rd, rs1, imm12)

# 4. Stores
def encode_sb(rs2: int, rs1: int, imm12: int) -> int:
    return _encode_s(OPCODE_STORE, 0b000, rs2, rs1, imm12)

def encode_sh(rs2: int, rs1: int, imm12: int) -> int:
    return _encode_s(OPCODE_STORE, 0b001, rs2, rs1, imm12)

def encode_sw(rs2: int, rs1: int, imm12: int) -> int:
    return _encode_s(OPCODE_STORE, 0b010, rs2, rs1, imm12)

# 5. Immediate Arithmetic & Logic
def encode_addi(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_OP_IMM, 0b000, rd, rs1, imm12)

def encode_slti(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_OP_IMM, 0b010, rd, rs1, imm12)

def encode_sltiu(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_OP_IMM, 0b011, rd, rs1, imm12)

def encode_xori(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_OP_IMM, 0b100, rd, rs1, imm12)

def encode_ori(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_OP_IMM, 0b110, rd, rs1, imm12)

def encode_andi(rd: int, rs1: int, imm12: int) -> int:
    return _encode_i(OPCODE_OP_IMM, 0b111, rd, rs1, imm12)

def encode_slli(rd: int, rs1: int, shamt: int) -> int:
    return _encode_r(OPCODE_OP_IMM, 0b001, 0b0000000, rd, rs1, _shamt5(shamt))

def encode_srli(rd: int, rs1: int, shamt: int) -> int:
    return _encode_r(OPCODE_OP_IMM, 0b101, 0b0000000, rd, rs1, _shamt5(shamt))

def encode_srai(rd: int, rs1: int, shamt: int) -> int:
    return _encode_r(OPCODE_OP_IMM, 0b101, 0b0100000, rd, rs1, _shamt5(shamt))

# 6. Register-Register Arithmetic & Logic
def encode_add(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b000, 0b0000000, rd, rs1, rs2)

def encode_sub(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b000, 0b0100000, rd, rs1, rs2)

def encode_sll(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b001, 0b0000000, rd, rs1, rs2)

def encode_slt(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b010, 0b0000000, rd, rs1, rs2)

def encode_sltu(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b011, 0b0000000, rd, rs1, rs2)

def encode_xor(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b100, 0b0000000, rd, rs1, rs2)

def encode_srl(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b101, 0b0000000, rd, rs1, rs2)

def encode_sra(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b101, 0b0100000, rd, rs1, rs2)

def encode_or(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b110, 0b0000000, rd, rs1, rs2)

def encode_and(rd: int, rs1: int, rs2: int) -> int:
    return _encode_r(OPCODE_OP, 0b111, 0b0000000, rd, rs1, rs2)

# 7. System / Sync
def encode_fence() -> int:
    return 0x0000000F


def format_hex(words: Iterable[int], *, start_pc: int = 0) -> str:
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
