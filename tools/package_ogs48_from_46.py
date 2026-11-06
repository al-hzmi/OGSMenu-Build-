#!/usr/bin/env python3
"""Replace only OGSMenu.dylib in the exact OGS46 candidate; output unsigned IPA.

No game executable, IL2CPP metadata, resource, entitlements or other ZIP member
is changed. The file must be re-signed before installation. This is a candidate,
not evidence of server acceptance or device behavior.
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
        raise ValueError('refusing to overwrite source IPA')
    replacement = dylib.read_bytes()
    verify_dylib(replacement)
    with zipfile.ZipFile(source) as z:
        names = z.namelist()
        if len(names) != 172 or len(set(names)) != 172 or z.testzip() is not None:
            raise ValueError('unexpected or damaged input archive')
        for path, expected in EXPECTED.items():
            if digest(z.read(path)) != expected:
                raise ValueError(f'unsupported OGS46 input: {path}')
        out_fd, temp = tempfile.mkstemp(prefix='ogs48-', suffix='.ipa', dir=output.parent)
        os.close(out_fd)
        try:
            with zipfile.ZipFile(temp, 'w') as dest:
                for info in z.infolist():
                    data = replacement if info.filename == LIB else z.read(info.filename)
                    dest.writestr(copy.copy(info), data)
            with zipfile.ZipFile(temp) as dest:
                if dest.namelist() != names or dest.testzip() is not None:
                    raise ValueError('damaged output archive')
                for path in names:
                    expected = replacement if path == LIB else z.read(path)
                    if dest.read(path) != expected:
                        raise ValueError(f'unexpected output change: {path}')
            os.replace(temp, output)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
    print('PASS OGS48 IPA: only OGSMenu.dylib replaced; original 171 members unchanged')
    print('dylib SHA256:', digest(replacement))
    print('IPA SHA256:', digest(output.read_bytes()))
    print('UNSIGNED: not tested on iOS; re-sign for device installation')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('dylib', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.source, args.dylib, args.output)
