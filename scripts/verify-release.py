#!/usr/bin/env python3
"""Verify standalone universal app contents, architecture and system-only dylibs."""
import json, pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'app.launchdock.LaunchDock'
assert info['LSMinimumSystemVersion'] == '26.0'
assert info['CFBundlePackageType'] == 'APPL'
assert (app/'Contents/Resources'/info['CFBundleIconFile']).is_file()
main = app/'Contents/MacOS'/info['CFBundleExecutable']
architectures = subprocess.check_output(['lipo', '-archs', str(main)], text=True).split()
assert set(architectures) == {'arm64','x86_64'}, architectures
subprocess.run(['codesign','--verify','--deep','--strict',str(app)], check=True)
macho_magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}
dependencies = {}
for path in app.rglob('*'):
    if not path.is_file(): continue
    with path.open('rb') as stream: magic = stream.read(4)
    if magic not in macho_magic: continue
    by_arch = {}
    for arch in ('arm64','x86_64'):
        output = subprocess.check_output(['otool','-arch',arch,'-L',str(path)], text=True)
        libraries = [line.strip().split(' (',1)[0] for line in output.splitlines() if line.startswith('\t')]
        assert libraries, f'No load commands: {path}'
        assert all(lib.startswith(('/System/Library/','/usr/lib/')) for lib in libraries), libraries
        by_arch[arch] = libraries
    dependencies[str(path.relative_to(app))] = by_arch
assert dependencies, 'No Mach-O executable found'
report = {'app':str(app), 'version':info.get('LaunchDockDisplayVersion',info['CFBundleShortVersionString']),
          'bundleVersion':info['CFBundleShortVersionString'],
          'minimumMacOS':info['LSMinimumSystemVersion'], 'architectures':architectures,
          'externalDependencies':[], 'libraries':dependencies,
          'signature':'ad-hoc', 'notarized':False}
print(json.dumps(report, ensure_ascii=False, indent=2))
