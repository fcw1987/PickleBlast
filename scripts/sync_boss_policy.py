#!/usr/bin/env python3
"""Keep native DEBUG evidence controls identical to the host evaluation policy."""
from pathlib import Path
import argparse
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
expected = ('// Generated from scripts/BossEvaluationPolicy.swift for identical native evidence controls.\n'
            '#if DEBUG\n' + (root/'scripts/BossEvaluationPolicy.swift').read_text() + '\n#endif\n')
destination = root/'WatchApp/BossValidationPolicy.swift'
if args.check:
    if not destination.exists() or destination.read_text() != expected:
        raise SystemExit('Native DEBUG policy differs from host; run scripts/sync_boss_policy.py')
    print('PASS: host and native DEBUG evaluation policies match.')
else:
    destination.write_text(expected)
