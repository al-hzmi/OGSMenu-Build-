#!/usr/bin/env python3
"""Repackage the exact OGS46 source IPA with the newly built OGS49 dylib.

All 171 other original ZIP members are verified byte-for-byte. The resulting
IPA is unsigned and must be re-signed by its owner before device installation.
"""
import argparse
import copy
import hashlib
import os
import tempfile
import zipfile
from pathlib import Path
from package_ogs40_ipa import verify_dylib

GAME = 'Payload/fps.app/fps'
META = 'Payload/fps.app/Data/Managed/Metadata/global-metadata.dat'
LIB = 'Payload/fps.app/Frameworks/OGSMenu.dylib'
EXPECTED = {
    GAME: '766b1cfe693304faab1160b7696ce803780f0087ca50a17c9d94fc3e73ed10dc',
    META: '80f36c11ca253385d693a505b2693c442c4e0c981f665e285587c6cfdd403faf',
    LIB: 'b6902708af659d2a77e929c368a68857b16629dd6bdaa110618f2a1c8d617f41',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def package(source, dylib, output):
    if source.resolve() == output.resolve():
        raise ValueError('refusing to overwrite the original game IPA')
    replacement = dylib.read_bytes()
    verify_dylib(replacement)
    with zipfile.ZipFile(source) as src:
        names = src.namelist()
        if len(names) != 172 or len(set(names)) != 172 or src.testzip() is not None:
            raise ValueError('unsupported or damaged original game IPA')
        for name, sha in EXPECTED.items():
            if digest(src.read(name)) != sha:
                raise ValueError('input IPA identity mismatch: ' + name)
        fd, temporary = tempfile.mkstemp(prefix='ogs49-', suffix='.ipa', dir=output.parent)
        os.close(fd)
        try:
            with zipfile.ZipFile(temporary, 'w') as dest:
                for info in src.infolist():
                    dest.writestr(copy.copy(info),
                                  replacement if info.filename == LIB else src.read(info.filename))
            with zipfile.ZipFile(temporary) as dest:
                if dest.namelist() != names or dest.testzip() is not None:
                    raise ValueError('output ZIP validation failed')
                for name in names:
                    expected = replacement if name == LIB else src.read(name)
                    if dest.read(name) != expected:
                        raise ValueError('unexpected modification to ' + name)
            os.replace(temporary, output)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    print('PASS OGS49: OGSMenu.dylib replaced, all 171 other IPA entries unchanged')
    print('dylib SHA256:', digest(replacement))
    print('IPA SHA256:', digest(output.read_bytes()))
    print('UNSIGNED: no installation or live-device verification performed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('dylib', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.source, args.dylib, args.output)
