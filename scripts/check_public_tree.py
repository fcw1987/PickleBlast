#!/usr/bin/env python3
"""Check proposed public files; this does not approve licenses or Git history."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
if (ROOT / '.git').exists():
    result = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT,
                            check=True, capture_output=True)
    paths = sorted({ROOT / p.decode() for p in result.stdout.split(b'\0') if p})
else:
    # A source ZIP has no Git metadata or ignored development workspace.
    paths = [p for p in ROOT.rglob('*') if p.is_file()
             and not any(part in {'.build', '.swiftpm', '__pycache__'}
                         for part in p.relative_to(ROOT).parts)]

if not paths:
    raise SystemExit('FAIL: no proposed public files found; an empty scan cannot approve a source tree.')

patterns = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'credential token': rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16})',
    'personal home path': rb'/Users/[A-Za-z0-9_.-]+/',
    'device identifier': rb'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b',
    'fixed signing team': rb'DEVELOPMENT_TEAM\s*=\s*"?[A-Z0-9]{10}\b',
}
forbidden_suffixes = {'.p12', '.p8', '.mobileprovision', '.provisionprofile',
                      '.key', '.xcuserstate', '.mov', '.mp4', '.xcresult',
                      '.xcarchive', '.dsym', '.app', '.ipa'}
failures = []
for path in paths:
    relative = path.relative_to(ROOT)
    if not path.exists():
        failures.append((str(relative), 'tracked input missing'))
        continue
    if path.is_symlink():
        failures.append((str(relative), 'symlink in public inputs'))
        continue
    if (any(Path(part).suffix.lower() in forbidden_suffixes for part in relative.parts)
            or any(part in {'.build', '.swiftpm', 'DerivedData', 'build'} for part in relative.parts)
            or path.name == 'Signing.local.xcconfig'
            or path.name.startswith('.env') or 'xcuserdata' in relative.parts
            or 'PickleBlast_Final_Approved_Art' in relative.parts
            or relative.parts[:2] == ('docs', 'evidence')
            or path.name.lower().startswith(('task_prompt_', 'internal_report_'))
            or any(part in {'.private', '.internal'} for part in relative.parts)):
        failures.append((str(relative), 'private/obsolete development input'))
    if path.stat().st_size > 20 * 1024 * 1024:
        failures.append((str(relative), 'unexpectedly large publication file'))
        continue
    data = path.read_bytes()
    for label, pattern in patterns.items():
        if re.search(pattern, data):
            failures.append((str(relative), label))
if failures:
    for relative, label in failures:
        print(f'FAIL: {relative}: {label}')  # Never print matching private values.
    raise SystemExit(1)
print(f'PASS: {len(paths)} proposed public files; private paths/signing/token patterns absent.')
print('Scope: current files only; history, ownership and licenses require separate review.')
