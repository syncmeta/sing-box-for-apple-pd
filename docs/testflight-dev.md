# TestFlight dev workflow

This repo is configured for a personal TestFlight build with:

- `origin`: your fork
- `upstream`: `https://github.com/SagerNet/sing-box-for-apple.git`
- app bundle id, app group, iCloud container, and Apple team set in the Xcode project

## Worktree note

If another local worktree has the local `dev` branch checked out, Git will not
let this worktree check out that same local branch at the same time.

The helper script does not need to check out local `dev`. It fetches
`upstream/dev`, fast-forwards `origin/dev`, and rebases the current TestFlight
config branch directly onto `upstream/dev`.

If you later want to free the local `dev` branch, run one of these manually:

```bash
git -C /path/to/other/worktree switch main
```

or, if you no longer need that directory:

```bash
git worktree remove /path/to/other/worktree
```

## Normal update and upload

Run this from the TestFlight config branch, currently `codex/dev-testflight`:

```bash
git switch codex/dev-testflight
scripts/testflight-dev.sh --upload
```

The script will:

1. fetch official `upstream/dev`
2. fast-forward your fork's `origin/dev`
3. rebase the current TestFlight config branch onto `upstream/dev`
4. update submodules
5. verify the plist/entitlement files
6. archive `SFI`
7. upload to App Store Connect when `--upload` is passed

The build number defaults to `YYYYMMDDHHMM`, which avoids reusing a TestFlight
build number. To set it yourself:

```bash
scripts/testflight-dev.sh --build-number 2026060602 --upload
```

## If Libbox changes

If the build fails with Libbox protocol/API errors, rebuild the ignored
`Libbox.xcframework`:

```bash
scripts/testflight-dev.sh --rebuild-libbox --upload
```

By default this rebuilds from `SagerNet/sing-box` at `main`. To pin a specific
core ref:

```bash
scripts/testflight-dev.sh --rebuild-libbox --core-ref v1.13.13 --upload
```

## Archive without uploading

For a dry run:

```bash
scripts/testflight-dev.sh
```

The archive path defaults to:

```text
build/SFI-dev.xcarchive
```

## Safety

The script refuses to run with a dirty working tree by default, because rebase
and release builds should start from a known state. Commit or stash local
changes first. For one-off local testing only:

```bash
scripts/testflight-dev.sh --allow-dirty
```
