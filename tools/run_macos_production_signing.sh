#!/usr/bin/env bash
set -euo pipefail

repo="${APL_GITHUB_REPOSITORY:-arvectum2/proxy-launcher}"
runner_root="${APL_MACOS_RUNNER_ROOT:-$HOME/actions-runner-proxy-launcher}"
source_sha="${1:-}"

if [[ -z "$source_sha" ]]; then
  source_sha="$(gh api "repos/$repo/git/ref/heads/main" --jq '.object.sha')"
fi
[[ "$source_sha" =~ ^[0-9a-fA-F]{40}$ ]] || {
  echo "source SHA must be a full 40-character commit SHA" >&2
  exit 2
}
source_sha="$(printf '%s' "$source_sha" | tr '[:upper:]' '[:lower:]')"
main_sha="$(gh api "repos/$repo/git/ref/heads/main" --jq '.object.sha' | tr '[:upper:]' '[:lower:]')"
[[ "$source_sha" == "$main_sha" ]] || {
  echo "refusing non-current-main source: $source_sha (main=$main_sha)" >&2
  exit 3
}

[[ -x "$runner_root/config.sh" && -x "$runner_root/run.sh" ]] || {
  echo "GitHub Actions runner installation missing: $runner_root" >&2
  exit 4
}
if [[ -e "$runner_root/.runner" ]]; then
  echo "refusing to reuse an already-registered runner: $runner_root" >&2
  exit 5
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
short_sha="${source_sha:0:12}"
runner_name="arvectum-macmini-signing-$short_sha-$stamp"
runner_label="apl-signing-$short_sha-$stamp"
runner_log="$runner_root/ephemeral-$stamp.log"
runner_pid=""

cleanup() {
  local rc=$?
  if [[ -n "$runner_pid" ]]; then
    kill "$runner_pid" >/dev/null 2>&1 || true
    wait "$runner_pid" >/dev/null 2>&1 || true
  fi
  if [[ -e "$runner_root/.runner" ]]; then
    local remove_token
    remove_token="$(gh api -X POST "repos/$repo/actions/runners/remove-token" --jq '.token' 2>/dev/null || true)"
    if [[ -n "$remove_token" ]]; then
      (cd "$runner_root" && ./config.sh remove --token "$remove_token" >/dev/null 2>&1) || true
    fi
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM
registration_token="$(gh api -X POST "repos/$repo/actions/runners/registration-token" --jq '.token')"
(
  cd "$runner_root"
  ./config.sh --unattended --ephemeral --disableupdate     --url "https://github.com/$repo"     --token "$registration_token"     --name "$runner_name"     --labels "$runner_label"
)

(
  cd "$runner_root"
  ./run.sh >"$runner_log" 2>&1
) &
runner_pid=$!

for _ in $(seq 1 60); do
  status="$(gh api "repos/$repo/actions/runners"     --jq ".runners[] | select(.name == \"$runner_name\") | .status" 2>/dev/null || true)"
  [[ "$status" == "online" ]] && break
  sleep 1
done
[[ "$status" == "online" ]] || {
  echo "ephemeral runner failed to become online" >&2
  tail -80 "$runner_log" >&2 || true
  exit 6
}
gh workflow run macos-production-signing.yml   --repo "$repo"   --ref main   -f "source_sha=$source_sha"   -f "runner_label=$runner_label"

run_id=""
for _ in $(seq 1 60); do
  run_id="$(gh run list --repo "$repo"     --workflow macos-production-signing.yml     --branch main     --event workflow_dispatch     --limit 20     --json databaseId,headSha     --jq ".[] | select((.headSha|ascii_downcase) == \"$source_sha\") | .databaseId"     | head -1)"
  [[ -n "$run_id" ]] && break
  sleep 2
done
[[ -n "$run_id" ]] || {
  echo "could not resolve dispatched macOS production-signing run" >&2
  exit 7
}

echo "runner_name=$runner_name"
echo "runner_label=$runner_label"
echo "workflow_run_id=$run_id"
gh run watch "$run_id" --repo "$repo" --exit-status
wait "$runner_pid" || true
runner_pid=""
echo "macOS production signing completed for $source_sha"
