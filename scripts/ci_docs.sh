#!/bin/bash
# Lightweight public copy/site checks. No Swift, artwork imports, or Watch builds.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_docs.py
python3 scripts/check_site.py
python3 scripts/test_site.py
python3 scripts/sync_privacy.py --check
python3 scripts/test_sync_privacy.py
python3 scripts/check_public_tree.py
python3 scripts/test_public_tree.py
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### Documentation validation passed\n\nLinks, website/store drafts, privacy synchronization and public-tree regressions passed. No app/build inputs changed; artwork and native Watch checks were not needed.\n' >> "$GITHUB_STEP_SUMMARY"
fi
