#!/usr/bin/env python3
"""Audit the shipped app/installer architecture and deployment minimum."""
import pathlib
import plistlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
for bundle_name in ('macino.app',):
    bundle = root / 'build' / bundle_name
    with (bundle / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    assert info.get('LSUIElement') is not True, 'macino must remain discoverable as an application'
    assert info.get('LSBackgroundOnly') is not True
    binary = bundle / 'Contents/MacOS' / info['CFBundleExecutable']
    arches = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    assert 'arm64' in arches, f'{bundle_name}: native Apple Silicon slice missing'
    commands = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
    minimums = re.findall(r'\bminos\s+(\d+(?:\.\d+)*)', commands)
    assert minimums and all(tuple(map(int, v.split('.'))) <= (14, 0) for v in minimums), commands
    assert tuple(map(int, info['LSMinimumSystemVersion'].split('.'))) <= (14, 0)
    print(f'PASS {bundle_name}: {", ".join(arches)}, Mach-O minimum {", ".join(minimums)}, Info.plist minimum {info["LSMinimumSystemVersion"]}')
print('Binary compatibility audit passed; older-OS and other-chip runtime tests remain separate.')
