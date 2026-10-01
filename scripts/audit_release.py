#!/usr/bin/env python3
"""Audit a compiled development-signed Watch Release bundle; print no credentials."""
import argparse, json, plistlib, subprocess
from datetime import datetime, timezone
from pathlib import Path
def require(condition, message):
    if not condition:
        raise SystemExit('Release audit failed: ' + message)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('--expected-build', required=True, help='Expected CFBundleVersion of this release candidate, for example 4.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
app = args.app.resolve()
info=plistlib.loads((app/'Info.plist').read_bytes())
require(info['CFBundleIdentifier']=='com.pickleblast.watchapp', 'Wrong application identifier')
require(info['CFBundleVersion']==args.expected_build, 'Unexpected build number')
require(info['CFBundleSupportedPlatforms']==['WatchOS'], 'Not a Watch device bundle')
privacy=plistlib.loads((app/'PrivacyInfo.xcprivacy').read_bytes())
require(privacy==plistlib.loads((root/'WatchApp/PrivacyInfo.xcprivacy').read_bytes()), 'Privacy manifest differs from source')
manifest=json.loads((app/'runtime_manifest.json').read_text())
require(set(manifest['characters'])=={'player','wall','banger','poacher'}, 'Unexpected character selection')
expected={c['atlas']+'.atlasc' for c in manifest['characters'].values()}|{s['atlas']+'.atlasc' for s in manifest['supporting'].values()}
actual={p.name for p in app.glob('*.atlasc')}
require(expected==actual, 'Compiled atlas membership differs from manifest')
files=[p.relative_to(app).as_posix() for p in app.rglob('*') if p.is_file()]
require(not any(x.endswith(('.swift','.py','.md','.mov','.mp4','.xcresult')) or 'Approved_Art' in x or 'import_audit' in x or 'Tests' in x for x in files), 'Source or development evidence found in bundle')
strings=subprocess.check_output(['strings',str(app/'PickleBlast')]).decode(errors='replace')
for keyword in ['--validation-','VALIDATION SCRIPTED','VALIDATION PERFORMANCE','DebugValidation','debugTextureRequests','validation-lifetimes.log','pickleblast.validation','trackLifetime','BossEvaluationPolicy','BossPolicyObservation','BossPlayerPolicy']:
 require(keyword not in strings, 'DEBUG symbol or activation string found: ' + keyword)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
signature=subprocess.run(['codesign','--display','--entitlements','-','--xml',str(app)],check=True,capture_output=True)
entitlements=plistlib.loads(signature.stdout)
require(entitlements['get-task-allow'] is True, 'Not a development signature')
require(set(entitlements)=={'application-identifier','com.apple.developer.team-identifier','get-task-allow'}, 'Unexpected or missing development entitlement')
profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(app/'embedded.mobileprovision')]))
expiry = profile['ExpirationDate'].replace(tzinfo=timezone.utc)
require(expiry > datetime.now(timezone.utc), 'Development profile has expired')
report={'bundleVersion':info['CFBundleVersion'],'marketingVersion':info['CFBundleShortVersionString'],'platform':info['CFBundleSupportedPlatforms'],'expectedAtlases':sorted(expected),'signatureVerified':True,'privacyMatchesSource':True,'debugActivationAndCountersAbsent':True,'sourceAndEvidenceAbsent':True,'entitlementKeys':sorted(entitlements),'profileExpiresUTC':str(profile['ExpirationDate']),'files':files}
print(json.dumps(report, indent=2))
