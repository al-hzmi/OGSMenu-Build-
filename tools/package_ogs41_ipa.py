#!/usr/bin/env python3
"""Build OGS41 from the exact supplied OGS34 IPA and ARM64 OGS41 dylib.

OGS41 reuses the independently verified OGS40 native KillPlayer bridge and
both older pre-sign damage bridges. It patches no additional game instructions.
Output is unsigned and needs a legitimate installation signature.
"""

import argparse
import copy
from pathlib import Path
import os
import tempfile
import zipfile

from package_ogs40_ipa import (
    GAME, LIB, ORIGINAL_LIB_SHA256, digest, patch_kill_bridge, verify_dylib,
)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("dylib", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        raise ValueError("Cannot overwrite source IPA")
    lib = args.dylib.read_bytes()
    verify_dylib(lib)
    with zipfile.ZipFile(args.source) as source:
        names = source.namelist()
        if names.count(GAME) != 1 or names.count(LIB) != 1:
            raise ValueError("Unexpected IPA structure")
        if digest(source.read(LIB)) != ORIGINAL_LIB_SHA256:
            raise ValueError("Unexpected source OGS dylib")
        patched_game = patch_kill_bridge(source.read(GAME))
        fd, temp = tempfile.mkstemp(prefix="ogs41-", suffix=".ipa",
                                    dir=args.output.parent)
        os.close(fd)
        try:
            with zipfile.ZipFile(temp, "w") as dest:
                for info in source.infolist():
                    replacement = patched_game if info.filename == GAME else (
                        lib if info.filename == LIB else source.read(info.filename))
                    dest.writestr(copy.copy(info), replacement)
            with zipfile.ZipFile(temp) as dest:
                if dest.testzip() is not None or dest.namelist() != names:
                    raise ValueError("IPA CRC or manifest mismatch")
                for name in names:
                    expected = patched_game if name == GAME else (
                        lib if name == LIB else source.read(name))
                    if digest(dest.read(name)) != digest(expected):
                        raise ValueError("IPA member differs: " + name)
            os.replace(temp, args.output)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
    print("OGS41 IPA created:", args.output)
    print("Game SHA256", digest(patched_game))
    print("Dylib SHA256", digest(lib))
    print("Unchanged entries", len(names) - 2)
    print("Unsigned; needs re-signing before installation")


if __name__ == "__main__":
    main()
