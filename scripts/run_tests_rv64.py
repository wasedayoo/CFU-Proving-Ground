#!/usr/bin/env python3
import os
import subprocess
import glob

ISA_DIR = "/home/archlab/yfutatsugi/RV32to64/riscv-tests-build/isa"
CFU_DIR = "/home/archlab/yfutatsugi/RV32to64/CFU-Proving-Ground"
IMEM_SIZE = 32768
DMEM_SIZE = 16384

def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return res.returncode, res.stdout

def create_mem_txt(elf_file):
    run_cmd(f"riscv64-unknown-elf-objcopy -O binary --only-section=.text {elf_file} {ISA_DIR}/memi.bin")
    run_cmd(f"riscv64-unknown-elf-objcopy -O binary --only-section=.data --only-section=.rodata --only-section=.bss {elf_file} {ISA_DIR}/memd.bin")
    
    run_cmd(f"dd if={ISA_DIR}/memi.bin of={ISA_DIR}/memi.padded conv=sync bs={IMEM_SIZE}")
    run_cmd(f"dd if={ISA_DIR}/memd.bin of={ISA_DIR}/memd.padded conv=sync bs={DMEM_SIZE}")
    
    # Generate memi.txt
    res, out = run_cmd(f"hexdump -v -e '1/4 \"%08x\\n\"' {ISA_DIR}/memi.padded")
    with open(f"{CFU_DIR}/memi.txt", "w") as f:
        f.write("initial begin\n")
        for i, line in enumerate(out.strip().split('\n')):
            if line: f.write(f"    imem[{i}] = 32'h{line};\n")
        f.write("end\n")
        
    # Generate memd.txt (RV64 uses 64-bit dmem)
    res, out = run_cmd(f"hexdump -v -e '1/8 \"%016x\\n\"' {ISA_DIR}/memd.padded")
    with open(f"{CFU_DIR}/memd.txt", "w") as f:
        f.write("initial begin\n")
        for i, line in enumerate(out.strip().split('\n')):
            if line: f.write(f"    dmem[{i}] = 64'h{line};\n")
        f.write("end\n")

def main():
    print("Compiling RV64 tests (using section-start to fix relocation)...")
    run_cmd('make XLEN=64 RISCV_GCC_OPTS="-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -Wl,--section-start=.tohost=0xffffffff80000000" rv64ui rv64um', cwd=ISA_DIR)
    
    tests = sorted(glob.glob(f"{ISA_DIR}/rv64u[im]-p-*"))
    tests = [t for t in tests if not t.endswith('.dump')]
    
    passed = 0
    failed = 0
    
    for t in tests:
        name = os.path.basename(t)
        print(f"Running {name}...", end=" ", flush=True)
        
        create_mem_txt(t)
        
        # Build simulator because CFUPG code isn't changed (uses `include "mem.txt")
        rc, out = run_cmd("touch main.v && make build", cwd=CFU_DIR)
        if rc != 0:
            print("BUILD ERROR")
            failed += 1
            continue
            
        rc, out = run_cmd("timeout 5 ./obj_dir/top", cwd=CFU_DIR)
        
        # Parse output for writes (even to wrong addresses if CPU has bugs!)
        # It prints: WE: addr=0000000000000000 data=0000004600000046
        chars = []
        for line in out.split('\n'):
            if 'WE: addr=' in line and 'data=' in line:
                data_hex = line.split('data=')[1].strip()
                try:
                    # Get the lowest byte (last 2 characters)
                    val = int(data_hex[-2:], 16)
                    if val != 0:
                        chars.append(chr(val))
                except:
                    pass
                            
        result_str = "".join(chars)
        
        if "PASS" in result_str:
            print("PASS")
            passed += 1
        elif "FAIL" in result_str:
            print("FAIL")
            failed += 1
        else:
            print("UNKNOWN ERROR/HANG")
            failed += 1

    print(f"\nTotal: {passed+failed}, Passed: {passed}, Failed: {failed}")

if __name__ == "__main__":
    main()
