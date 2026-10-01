# Continuous integration

`.github/workflows/validation.yml` runs on pushes to `main` and manual dispatch. It uses the standard GitHub-hosted `macos-26` runner and its selected Xcode. No fixed simulator model or runtime version is required. Hosted results are separate from local validation; the configuration alone does not establish a passing run.

`scripts/ci_watch.sh` requires `scripts/validate.sh` to pass, covering runtime resource integrity, importer safety fixtures, Swift package tests, Release package compilation, project reproducibility, source-tree scanning, documentation links, policy consistency, and an unsigned generic watchOS Release build. It then requires an unsigned generic watchOS Debug build. Missing full Xcode, asset failures, source violations, and build failures fail the job.

The script discovers available Apple Watch simulators and selects a device from the newest installed Watch runtime. When available, it runs the native Boss Rally navigation, pause, resume, and Home UI test. If no Watch runtime/device is available, the log and job summary explicitly report the UI check as skipped. Discovery errors and actual test failures fail CI; they are never reported as a skip. A successful job with skipped UI does not establish simulator coverage.

Run the same route locally with full Xcode:

```sh
bash scripts/ci_watch.sh
```

An existing `DEVELOPER_DIR` selection is honored. The scripts do not change global Xcode selection or choose a signing team. Builds and tests use `CODE_SIGNING_ALLOWED=NO`; products, inventory, logs and result bundles remain under ignored `.build`. No artifacts are uploaded.

The workflow grants only `contents: read`, checks out a shallow source revision with credentials disabled, and uses no secrets, privileged event, cache, deployment, or self-hosted/larger runner. Its 45-minute job cancels older runs for the same branch. The sole action is pinned to `actions/checkout` v7.0.1 commit `3d3c42e5aac5ba805825da76410c181273ba90b1`; its MIT license does not grant rights to this project's artwork or code.

Official sources checked October 1, 2026:

- [Checkout v7.0.1 release](https://github.com/actions/checkout/releases/tag/v7.0.1) and [release commit](https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1).
- [Standard runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), listing `macos-26` as a standard Apple silicon runner. Standard hosted runners are free for public repositories; private repositories use account minutes and can incur charges.
- [macOS 26 runner image manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), currently listing default Xcode 26.6 and watchOS 26.5 SDKs. Runner images evolve; each job records its actual Xcode version.

Review hosted check results before relying on them for branch protection. Repository visibility, license, protection, alerts and confidential vulnerability reporting are owner-managed GitHub settings.
