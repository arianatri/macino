#!/usr/bin/env python3
"""Offline runtime and portable dependency audit; never transfers user files."""
import json
import pathlib
import re
import subprocess
import sys
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'build/macino.app').resolve()
android = root / 'Contents/Resources/Android'
for name in ('macino-mtp', 'libmtp.9.dylib', 'libusb-1.0.0.dylib', 'scrcpy', 'adb'):
    binary = android / name
    subprocess.run(['codesign', '--verify', '--strict', str(binary)], check=True)
    arch = subprocess.check_output(['lipo', '-archs', str(binary)], text=True)
    assert 'arm64' in arch
    info = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
    versions = re.findall(r'\bminos\s+(\d+(?:\.\d+)*)', info)
    assert versions and all(tuple(map(int, value.split('.'))) <= (14, 0) for value in versions), info
    linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    for line in linked.splitlines():
        if '(compatibility version' in line:
            path = line.strip().split(' (')[0]
            assert path.startswith(('/System/', '/usr/lib/', '@loader_path/')), linked
    print(f'PASS Android bundled {name}: signed arm64, macOS <= 14, no Homebrew runtime links')
def mtp(q):
    run = subprocess.run([str(android / 'macino-mtp')], input=json.dumps(q), capture_output=True, text=True, timeout=15)
    return run, json.loads(run.stdout)
run, response = mtp({'operation': 'version'})
assert response['version'] == '1.1.23' and run.returncode == 0
run = subprocess.run([str(android / 'macino-mtp')], input='not JSON', capture_output=True, text=True, timeout=5)
assert run.returncode != 0 and 'error' in json.loads(run.stdout)
print('PASS MTP version and invalid request return clean JSON')
# No USB operations in this audit: real phones require a separate manual test.
version = subprocess.check_output([str(android/'adb'), 'version'], text=True, timeout=10)
assert 'Android Debug Bridge' in version
version = subprocess.check_output([str(android/'scrcpy'), '--version'], text=True, timeout=10)
assert '5.0.1' in version
help_text = subprocess.check_output([str(android/'scrcpy'), '--help'], text=True, timeout=10)
for flag in ('--no-control', '--no-audio', '--no-clipboard-autosync', '--serial'):
    assert flag in help_text
assert (android/'scrcpy-server').stat().st_size > 10000
print('PASS bundled adb, scrcpy, server and view-only mirroring options')
