#!/usr/bin/env python3
"""Summarize static and dynamic RISC-V instruction mixes for an Embench run."""

import argparse
import json
import re
from collections import Counter
from pathlib import Path


INSN_RE = re.compile(r"^\s*([0-9a-f]+):\s+[0-9a-f]+\s+([.a-zA-Z0-9_]+)")
FUNC_RE = re.compile(r"^([0-9a-f]+) <([^>]+)>:")

LOADS = {"lb", "lbu", "lh", "lhu", "lw", "lwu", "ld"}
STORES = {"sb", "sh", "sw", "sd"}
BRANCHES = {"beq", "bne", "blt", "bge", "bltu", "bgeu"}
JUMPS = {"jal", "jalr"}
SHIFTS = {
    "sll", "slli", "srl", "srli", "sra", "srai",
    "sllw", "slliw", "srlw", "srliw", "sraw", "sraiw",
}
MULTIPLIES = {"mul", "mulh", "mulhsu", "mulhu", "mulw"}
DIVIDES = {"div", "divu", "rem", "remu", "divw", "divuw", "remw", "remuw"}
ALU = {
    "lui", "auipc", "add", "addi", "sub", "slt", "slti", "sltu", "sltiu",
    "xor", "xori", "or", "ori", "and", "andi", "addw", "addiw", "subw",
}
W_OPS = {
    "addw", "addiw", "subw", "sllw", "slliw", "srlw", "srliw", "sraw",
    "sraiw", "mulw", "divw", "divuw", "remw", "remuw",
}


def category(mnemonic):
    if mnemonic in LOADS:
        return "load"
    if mnemonic in STORES:
        return "store"
    if mnemonic in BRANCHES:
        return "branch"
    if mnemonic in JUMPS:
        return "jump"
    if mnemonic in SHIFTS:
        return "shift"
    if mnemonic in MULTIPLIES:
        return "multiply"
    if mnemonic in DIVIDES:
        return "divide"
    if mnemonic in ALU:
        return "ALU"
    return "other"


def parse_disassembly(path):
    by_pc = {}
    functions = Counter()
    static_mnemonics = Counter()
    current_function = None
    for line in Path(path).read_text().splitlines():
        match = FUNC_RE.match(line)
        if match:
            current_function = match.group(2)
            continue
        match = INSN_RE.match(line)
        if not match:
            continue
        pc = int(match.group(1), 16)
        mnemonic = match.group(2)
        by_pc[pc] = (mnemonic, current_function)
        static_mnemonics[mnemonic] += 1
        if current_function is not None:
            functions[current_function] += 1
    return by_pc, functions, static_mnemonics


def summarize(disassembly, trace, cycles):
    by_pc, functions, static_mnemonics = parse_disassembly(disassembly)
    mnemonics = Counter()
    dynamic_functions = Counter()
    unknown_pcs = Counter()
    instruction_count = 0
    with Path(trace).open() as stream:
        for line in stream:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.split()
            pc = int(fields[1], 16)
            decoded = by_pc.get(pc)
            instruction_count += 1
            if decoded is None:
                unknown_pcs[f"0x{pc:x}"] += 1
            else:
                mnemonic, function = decoded
                mnemonics[mnemonic] += 1
                dynamic_functions[function] += 1

    categories = Counter()
    for mnemonic, count in mnemonics.items():
        categories[category(mnemonic)] += count
    for key in ("ALU", "branch", "jump", "load", "store", "shift",
                "multiply", "divide", "other"):
        categories.setdefault(key, 0)

    static_categories = Counter()
    for mnemonic, count in static_mnemonics.items():
        static_categories[category(mnemonic)] += count

    return {
        "cycles": cycles,
        "dynamic_instructions": instruction_count,
        "cpi": cycles / instruction_count,
        "dynamic_categories": dict(categories),
        "dynamic_w_instructions": sum(mnemonics[m] for m in W_OPS),
        "dynamic_mnemonics": dict(mnemonics.most_common()),
        "dynamic_functions": dict(dynamic_functions.most_common()),
        "unknown_dynamic_pcs": dict(unknown_pcs),
        "static_instructions": sum(functions.values()),
        "static_categories": dict(static_categories),
        "static_w_instructions": sum(static_mnemonics[m] for m in W_OPS),
        "static_mnemonics": dict(static_mnemonics.most_common()),
        "static_functions": dict(functions.most_common()),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--disassembly", required=True)
    parser.add_argument("--trace", required=True)
    parser.add_argument("--cycles", required=True, type=int)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = summarize(args.disassembly, args.trace, args.cycles)
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
