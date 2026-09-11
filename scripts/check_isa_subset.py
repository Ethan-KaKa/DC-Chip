#!/usr/bin/env python3
"""
check_isa_subset.py

Automated ISA subset auditor for DC-Chip v0.2.
Validates that every instruction in a given objdump disassembly text (.txt)
strictly belongs to the 8-instruction RV32E subset:
  - add, addi, lui, lw, lbu, sw, sb, jalr
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

            if opcode == 0x33:  # R-type
                if funct3 == 0 and funct7 == 0:  # add
                    if rd >= 16 or rs1 >= 16 or rs2 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1}, rs2=x{rs2})"
                else:
                    fail_reason = f"unsupported R-type instruction (funct3={funct3:#x}, funct7={funct7:#x})"

            elif opcode == 0x13:  # I-type arithmetic
                if funct3 == 0:  # addi
                    if rd >= 16 or rs1 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1})"
                else:
                    fail_reason = f"unsupported OP-IMM instruction (funct3={funct3:#x})"

            elif opcode == 0x37:  # lui
                if rd >= 16:
                    fail_reason = f"register out of bounds for RV32E (rd=x{rd})"

            elif opcode == 0x03:  # load
                if funct3 == 0x2:  # lw
                    if rd >= 16 or rs1 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1})"
                elif funct3 == 0x4:  # lbu
                    if rd >= 16 or rs1 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1})"
                else:
                    fail_reason = f"unsupported LOAD instruction (funct3={funct3:#x})"

            elif opcode == 0x23:  # store
                if funct3 == 0x2:  # sw
                    if rs1 >= 16 or rs2 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rs1=x{rs1}, rs2=x{rs2})"
                elif funct3 == 0x0:  # sb
                    if rs1 >= 16 or rs2 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rs1=x{rs1}, rs2=x{rs2})"
                else:
                    fail_reason = f"unsupported STORE instruction (funct3={funct3:#x})"

            elif opcode == 0x67:  # jalr
                if funct3 == 0:
                    if rd >= 16 or rs1 >= 16:
                        fail_reason = f"register out of bounds for RV32E (rd=x{rd}, rs1=x{rs1})"
                else:
                    fail_reason = f"unsupported JALR instruction (funct3={funct3:#x})"

            elif opcode == 0x6F:
                fail_reason = "instruction 'jal' (0x6F) is not in the v0.2 8-instruction subset"
            elif opcode == 0x17:
                fail_reason = "instruction 'auipc' (0x17) is not in the v0.2 8-instruction subset"
            elif opcode == 0x63:
                fail_reason = f"branch instruction (0x63, funct3={funct3:#x}) is not in the v0.2 8-instruction subset"
            elif opcode == 0x73:
                fail_reason = "SYSTEM instruction (0x73) is not in the v0.2 8-instruction subset"
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
