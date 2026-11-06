#!/usr/bin/env python3
"""Actual offline inference/import checks. Does not play sound or open user documents."""
import json, pathlib, subprocess, tempfile, wave, struct, re
import sys
app = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'build/macino.app').resolve()
root = app / 'Contents/Resources/Reader'
policy = '(version 1)(allow default)(deny network*)'
for name in ('macino-speech', 'macino-reader-import', 'libsherpa-onnx-c-api.dylib', 'libonnxruntime.dylib'):
    binary = root/name
    subprocess.run(['codesign', '--verify', '--strict', str(binary)], check=True)
    assert 'arm64' in subprocess.check_output(['lipo', '-archs', str(binary)], text=True)
    info = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
    versions = re.findall(r'\bminos\s+(\d+(?:\.\d+)*)', info)
    assert versions and all(tuple(map(int,v.split('.'))) <= (14,0) for v in versions)
    linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    for line in linked.splitlines():
        if '(compatibility version' in line:
            assert line.strip().startswith(('/System/', '/usr/lib/', '@loader_path/')), linked
    print('PASS Reader portable, signed arm64 macOS <= 14:', name)
main_links = subprocess.check_output(['otool', '-L', str(app/'Contents/MacOS/macino')], text=True).lower()
assert 'sherpa' not in main_links and 'onnx' not in main_links
print('PASS main app does not link speech inference libraries')
with tempfile.TemporaryDirectory(prefix='macino-reader-check-') as directory:
    work = pathlib.Path(directory)
    for lang, text in [('fa', 'سلام، این یک آزمایش خواندن متن فارسی است.'), ('en', 'Hello. This is an offline English reading test.')]:
        wav = work/(lang+'.wav')
        p = subprocess.Popen(['/usr/bin/sandbox-exec','-p',policy,str(root/'macino-speech'),str(root),lang,str(wav)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        out, err = p.communicate(text.encode(), timeout=90)
        assert p.returncode == 0, err.decode(errors='replace')[-1000:]
        with wave.open(str(wav)) as stream:
            assert stream.getnchannels() == 1 and stream.getframerate() == 22050 and stream.getnframes() > 10000
            samples = struct.unpack('<'+'h'*stream.getnframes(),stream.readframes(stream.getnframes()))
            assert max(abs(value) for value in samples) > 100
        assert p.poll() == 0
        print('PASS offline',lang,'synthesis produces non-silent audio; engine process exits')
    text='سلام دنیا. Hello world.\n'
    (work/'test.txt').write_text(text)
    (work/'unicode.txt').write_text(text,encoding='utf-16')
    for ext in ['docx','doc']:
        subprocess.run(['/usr/bin/textutil','-convert',ext,'-output',str(work/('test.'+ext)),str(work/'test.txt')],check=True,capture_output=True)
    subprocess.run(['swift','Scripts/make-reader-fixtures.swift',str(work)],check=True,capture_output=True)
    for name in ['test.txt','unicode.txt','test.docx','test.doc','text.pdf']:
        p=subprocess.run(['/usr/bin/sandbox-exec','-p',policy,str(root/'macino-reader-import')],input=json.dumps({'path':str(work/name)}),capture_output=True,text=True,timeout=60)
        value=json.loads(p.stdout)
        assert p.returncode == 0 and 'Hello' in value['text'], (name,p.stdout,p.stderr)
        print('PASS offline document import:',name)
    p=subprocess.run(['/usr/bin/sandbox-exec','-p',policy,str(root/'macino-reader-import')],input=json.dumps({'path':str(work/'scanned.pdf')}),capture_output=True,text=True,timeout=30)
    assert p.returncode != 0 and 'OCR' in json.loads(p.stdout)['error']
    print('PASS image-only PDF is rejected without OCR')
print('Reader offline runtime checks complete')
