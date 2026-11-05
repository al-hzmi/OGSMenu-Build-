#!/usr/bin/env python3
"""Read-only ARM64 Mach-O instruction disassembly using installed libLLVM.

No IPA rewriting, runtime instrumentation, or code execution of the game.
RVA arguments refer to the ORIGINAL fps 3.4.0 binary, not dylib addresses.
"""

import argparse
import ctypes
import hashlib
from pathlib import Path


EXPECTED_SHA256 = "ad1794ad50d976e042bbbe0c604a4e8bbb3fe8092787ee9ce24d07e7a530ac2f"
IMAGE_BASE = 0x100000000


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("game", type=Path)
    parser.add_argument("start", type=lambda x: int(x, 0), help="RVA")
    parser.add_argument("end", type=lambda x: int(x, 0), help="exclusive RVA")
    opts = parser.parse_args()

    data = opts.game.read_bytes()
    if hashlib.sha256(data).hexdigest() != EXPECTED_SHA256:
        parser.error("Refusing unknown binary SHA-256")
    if opts.start < 0x43F0 or opts.end > 0x1D3EDA8 or (
            opts.start & 3) or (opts.end & 3) or opts.end <= opts.start:
        parser.error("Invalid executable range/alignment")
    if opts.end - opts.start > 0x4000:
        parser.error("Limit each disassembly to 16 KiB")

    llvm = ctypes.CDLL("libLLVM.so.20.1")
    for name in ("LLVMInitializeAArch64TargetInfo", "LLVMInitializeAArch64Target",
                 "LLVMInitializeAArch64TargetMC", "LLVMInitializeAArch64Disassembler"):
        getattr(llvm, name)()
    llvm.LLVMCreateDisasm.argtypes = [ctypes.c_char_p, ctypes.c_void_p,
                                     ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
    llvm.LLVMCreateDisasm.restype = ctypes.c_void_p
    llvm.LLVMDisasmInstruction.argtypes = [ctypes.c_void_p, ctypes.c_void_p,
                                          ctypes.c_uint64, ctypes.c_uint64,
                                          ctypes.c_char_p, ctypes.c_size_t]
    llvm.LLVMDisasmInstruction.restype = ctypes.c_size_t
    llvm.LLVMDisasmDispose.argtypes = [ctypes.c_void_p]
    context = llvm.LLVMCreateDisasm(b"arm64-apple-ios", None, 0, None, None)
    if not context:
        raise RuntimeError("Could not initialize ARM64 LLVM disassembler")
    try:
        for pc in range(opts.start, opts.end, 4):
            instruction = ctypes.create_string_buffer(data[pc:pc+4])
            description = ctypes.create_string_buffer(255)
            length = llvm.LLVMDisasmInstruction(context, instruction, 4,
                                                 IMAGE_BASE + pc,
                                                 description, len(description))
            if length != 4:
                print(f"{pc:#010x}: INVALID {data[pc:pc+4].hex()}")
                continue
            print(f"{pc:#010x}: {description.value.decode('utf-8', 'replace').strip()}")
    finally:
        llvm.LLVMDisasmDispose(context)


if __name__ == "__main__":
    main()
