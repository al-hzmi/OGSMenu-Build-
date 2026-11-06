#!/usr/bin/env python3
"""Verify and package an unsigned OGS50 IPA using the exact OGS46 base."""
import argparse
from pathlib import Path
from package_ogs49_from_46 import package

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('dylib', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.source, args.dylib, args.output, release='OGS50')
