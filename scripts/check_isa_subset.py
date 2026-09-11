#!/usr/bin/env python3
"""
check_isa_subset.py

Automated ISA subset auditor for DC-Chip RV32E.
Validates that every instruction in a given objdump disassembly text (.txt)
strictly belongs to the standard 37-instruction RV32E Base Integer Instruction Set
and only references registers x0..x15.
"""

import sys
import re

LINE_PATTERN = re.compile(
    r"^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]{8})\s+(.*)$"
)

SECTION_PATTERN = re.compile(
    r"^Disassembly of section (.*):$"
)

def audit_file(filepath):
    errors = []
    current_section = ""
    instruction_count = 0

    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        for line_num, line in enumerate(f, 1):
            line_str = line.rstrip()

            sec_match = SECTION_PATTERN.match(line_str)
            if sec_match:
                current_section = sec_match.group(1)
                continue

            # Only audit executable text sections
            if not (current_section.startswith(".text") or current_section == ".init" or current_section == ".entry"):
                continue

            inst_match = LINE_PATTERN.match(line_str)
            if not inst_match:
                continue

            instruction_count += 1
            pc_str = inst_match.group(1)
            hex_str = inst_match.group(2)
            disasm = inst_match.group(3).strip()

            inst = int(hex_str, 16)
            opcode = inst & 0x7F
            rd = (inst >> 7) & 0x1F
            funct3 = (inst >> 12) & 0x07
            rs1 = (inst >> 15) & 0x1F
            rs2 = (inst >> 20) & 0x1F
            funct7 = (inst >> 25) & 0x7F

            pc = int(pc_str, 16)
            fail_reason = None

            if opcode == 0x33:  # R-type arithmetic/logical
                if funct3 == 0 and funct7 == 0x00:  # add
                    pass
                elif funct3 == 0 and funct7 == 0x20:  # sub
                    pass
                elif funct3 == 1 and funct7 == 0x00:  # sll
                    pass
                elif funct3 == 2 and funct7 == 0x00:  # slt
                    pass
                elif funct3 == 3 and funct7 == 0x00:  # sltu
                    pass
                elif funct3 == 4 and funct7 == 0x00:  # xor
                    pass
                elif funct3 == 5 and funct7 == 0x00:  # srl
                    pass
                elif funct3 == 5 and funct7 == 0x20:  # sra
                    pass
                elif funct3 == 6 and funct7 == 0x00:  # or
                    pass
                elif funct3 == 7 and funct7 == 0x00:  # and
                    pass
                else:
                    fail_reason = f"unsupported R-type instruction (funct3={funct3:#x}, funct7={funct7:#x})"

                if not fail_reason and (rd >= 16 or rs1 >= 16 or rs2 >= 16):
                    fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1}, rs2=x{rs2})"

            elif opcode == 0x13:  # I-type arithmetic/logical
                shamt = rs2  # inst[24:20]
                if funct3 in (0, 2, 3, 4, 6, 7):  # addi, slti, sltiu, xori, ori, andi
                    pass
                elif funct3 == 1:  # slli
                    if funct7 != 0x00:
                        fail_reason = f"invalid funct7 for slli ({funct7:#x})"
                elif funct3 == 5:  # srli, srai
                    if funct7 != 0x00 and funct7 != 0x20:
                        fail_reason = f"invalid funct7 for srli/srai ({funct7:#x})"
                else:
                    fail_reason = f"unsupported OP-IMM instruction (funct3={funct3:#x})"

                if not fail_reason and (rd >= 16 or rs1 >= 16):
                    fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1})"

            elif opcode == 0x37:  # lui
                if rd >= 16:
                    fail_reason = f"register out of bounds for RV32E (rd=x{rd})"

            elif opcode == 0x17:  # auipc
                if rd >= 16:
                    fail_reason = f"register out of bounds for RV32E (rd=x{rd})"

            elif opcode == 0x6F:  # jal
                if rd >= 16:
                    fail_reason = f"register out of bounds for RV32E (rd=x{rd})"

            elif opcode == 0x67:  # jalr
                if funct3 == 0:
                    if rd >= 16 or rs1 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1})"
                else:
                    fail_reason = f"unsupported JALR instruction (funct3={funct3:#x})"

            elif opcode == 0x63:  # B-type branch
                if funct3 in (0, 1, 4, 5, 6, 7):  # beq, bne, blt, bge, bltu, bgeu
                    if rs1 >= 16 or rs2 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rs1=x{rs1}, rs2=x{rs2})"
                else:
                    fail_reason = f"unsupported BRANCH instruction (funct3={funct3:#x})"

            elif opcode == 0x03:  # load
                if funct3 in (0, 1, 2, 4, 5):  # lb, lh, lw, lbu, lhu
                    if rd >= 16 or rs1 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1})"
                else:
                    fail_reason = f"unsupported LOAD instruction (funct3={funct3:#x})"

            elif opcode == 0x23:  # store
                if funct3 in (0, 1, 2):  # sb, sh, sw
                    if rs1 >= 16 or rs2 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rs1=x{rs1}, rs2=x{rs2})"
                else:
                    fail_reason = f"unsupported STORE instruction (funct3={funct3:#x})"

            elif opcode == 0x0F:  # fence
                if funct3 == 0:
                    if rd >= 16 or rs1 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1})"
                else:
                    fail_reason = f"unsupported MISC-MEM instruction (funct3={funct3:#x})"

            else:
                fail_reason = f"unsupported opcode {opcode:#04x}"

            if fail_reason:
                errors.append(
                    f"{filepath}:{line_num}: pc=0x{pc:08x} inst=0x{hex_str} ({disasm}): {fail_reason}"
                )

    return errors, instruction_count

def main():
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <disasm_file1.txt> [disasm_file2.txt ...]", file=sys.stderr)
        sys.exit(1)

    all_passed = True
    total_insts = 0

    for path in sys.argv[1:]:
        errors, inst_count = audit_file(path)
        total_insts += inst_count
        if errors:
            all_passed = False
            print(f"check_isa_subset: FAIL {path} ({len(errors)} violation(s)):", file=sys.stderr)
            for err in errors:
                print(f"  {err}", file=sys.stderr)
        else:
            print(f"check_isa_subset: PASS {path} ({inst_count} instructions audited)")

    if not all_passed:
        sys.exit(1)
    print(f"check_isa_subset: ALL PASSED ({total_insts} instructions across {len(sys.argv) - 1} file(s))")

if __name__ == "__main__":
    main()
