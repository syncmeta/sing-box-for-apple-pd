#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/testflight-dev.sh [options]

Sync the TestFlight config branch with official dev, archive SFI, and optionally
upload the archive to App Store Connect.

Options:
  --upload                 Upload the archive after a successful build.
  --build-number VALUE     Override CURRENT_PROJECT_VERSION. Defaults to YYYYMMDDHHMM.
  --rebuild-libbox         Rebuild Libbox.xcframework from SagerNet/sing-box.
  --core-ref REF           Core ref for --rebuild-libbox. Defaults to main.
  --core-dir PATH          Core checkout path. Defaults to /private/tmp/sing-box-core-for-apple.
  --no-sync                Skip fetch, fork dev push, and rebase.
  --no-push-dev            Do not fast-forward origin/dev to upstream/dev.
  --no-rebase              Do not rebase the current branch onto upstream/dev.
  --no-archive             Skip xcodebuild archive.
  --allow-dirty            Allow running with local uncommitted changes.
  -h, --help               Show this help.

Environment overrides:
  ORIGIN_REMOTE=origin
  UPSTREAM_REMOTE=upstream
  FORK_BRANCH=dev
  UPSTREAM_BRANCH=dev
  SCHEME=SFI
  PROJECT=sing-box.xcodeproj
  CONFIGURATION=Release
  ARCHIVE_PATH=build/SFI-dev.xcarchive
  DERIVED_DATA=build/DerivedData
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git checkout"
cd "$repo_root"

origin_remote="${ORIGIN_REMOTE:-origin}"
upstream_remote="${UPSTREAM_REMOTE:-upstream}"
fork_branch="${FORK_BRANCH:-dev}"
upstream_branch="${UPSTREAM_BRANCH:-dev}"
scheme="${SCHEME:-SFI}"
project="${PROJECT:-sing-box.xcodeproj}"
configuration="${CONFIGURATION:-Release}"
archive_path="${ARCHIVE_PATH:-build/SFI-dev.xcarchive}"
derived_data="${DERIVED_DATA:-build/DerivedData}"
build_number="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
core_dir="${SING_BOX_CORE_DIR:-/private/tmp/sing-box-core-for-apple}"
core_ref="${SING_BOX_CORE_REF:-main}"

do_sync=1
do_push_dev=1
do_rebase=1
do_archive=1
do_upload=0
do_rebuild_libbox=0
allow_dirty=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upload)
      do_upload=1
      shift
      ;;
    --build-number)
      [[ $# -ge 2 ]] || die "--build-number requires a value"
      build_number="$2"
      shift 2
      ;;
    --rebuild-libbox)
      do_rebuild_libbox=1
      shift
      ;;
    --core-ref)
      [[ $# -ge 2 ]] || die "--core-ref requires a value"
      core_ref="$2"
      shift 2
      ;;
    --core-dir)
      [[ $# -ge 2 ]] || die "--core-dir requires a value"
      core_dir="$2"
      shift 2
      ;;
    --no-sync)
      do_sync=0
      do_push_dev=0
      do_rebase=0
      shift
      ;;
    --no-push-dev)
      do_push_dev=0
      shift
      ;;
    --no-rebase)
      do_rebase=0
      shift
      ;;
    --no-archive)
      do_archive=0
      shift
      ;;
    --allow-dirty)
      allow_dirty=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

current_branch="$(git branch --show-current)"
if [[ -z "$current_branch" ]]; then
  die "detached HEAD; switch to your TestFlight config branch first"
fi
if [[ "$current_branch" == "$fork_branch" ]]; then
  die "current branch is $fork_branch; run this from the TestFlight config branch, not plain dev"
fi

if [[ "$allow_dirty" -ne 1 ]]; then
  git diff --quiet || die "working tree has unstaged changes; commit/stash them or pass --allow-dirty"
  git diff --cached --quiet || die "index has staged changes; commit/stash them or pass --allow-dirty"
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || die "working tree has untracked files; commit/stash/remove them or pass --allow-dirty"
fi

upstream_ref="$upstream_remote/$upstream_branch"
origin_ref="$origin_remote/$fork_branch"

if [[ "$do_sync" -eq 1 ]]; then
  run git fetch "$upstream_remote" "$upstream_branch"
  run git fetch "$origin_remote" "$fork_branch"

  if [[ "$do_push_dev" -eq 1 ]]; then
    if git merge-base --is-ancestor "$origin_ref" "$upstream_ref"; then
      run git push "$origin_remote" "$upstream_ref:refs/heads/$fork_branch"
    else
      die "$origin_ref is not an ancestor of $upstream_ref; inspect before updating fork dev"
    fi
  fi

  if [[ "$do_rebase" -eq 1 ]]; then
    run git rebase "$upstream_ref"
  fi

  run git submodule update --init --recursive
fi

if [[ "$do_rebuild_libbox" -eq 1 ]]; then
  command -v go >/dev/null || die "go is required to rebuild Libbox.xcframework"
  command -v xcodebuild >/dev/null || die "Xcode command line tools are required"

  go_bin="$(go env GOPATH)/bin"
  export PATH="$go_bin:$PATH"

  if ! command -v gomobile >/dev/null || ! command -v gobind >/dev/null; then
    run go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.12
    run go install github.com/sagernet/gomobile/cmd/gobind@v0.1.12
    run gomobile init
  fi

  if [[ ! -d "$core_dir/.git" ]]; then
    run git clone https://github.com/SagerNet/sing-box.git "$core_dir"
  fi

  run git -C "$core_dir" fetch --tags origin
  run git -C "$core_dir" checkout "$core_ref"
  if git -C "$core_dir" symbolic-ref -q HEAD >/dev/null; then
    run git -C "$core_dir" pull --ff-only
  fi

  run env PATH="$PATH" bash -lc "cd '$core_dir' && go run ./cmd/internal/build_libbox -target apple -platform ios"

  libbox_candidate=""
  for candidate in "$core_dir/Libbox.xcframework" "/private/tmp/sing-box-for-apple/Libbox.xcframework"; do
    if [[ -d "$candidate" ]]; then
      libbox_candidate="$candidate"
      break
    fi
  done
  [[ -n "$libbox_candidate" ]] || die "Libbox.xcframework was not produced"

  run rm -rf "$repo_root/Libbox.xcframework"
  run ditto "$libbox_candidate" "$repo_root/Libbox.xcframework"
fi

[[ -d Libbox.xcframework ]] || die "Libbox.xcframework is missing; rerun with --rebuild-libbox"

run plutil -lint "$project/project.pbxproj" SFI/Upload.plist SFI/SFI.entitlements Extension/Extension.entitlements IntentsExtension/IntentsExtension.entitlements FileProviderExtension/FileProviderExtension.entitlements WidgetExtension/WidgetExtension.entitlements

if [[ "$do_archive" -eq 1 ]]; then
  run rm -rf "$archive_path"
  run xcodebuild archive \
    -project "$project" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination generic/platform=iOS \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$build_number"

  echo "Archive created: $archive_path"
  echo "Build number: $build_number"
fi

if [[ "$do_upload" -eq 1 ]]; then
  run xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportOptionsPlist SFI/Upload.plist \
    -allowProvisioningUpdates
fi
