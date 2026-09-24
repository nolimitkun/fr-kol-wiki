#!/usr/bin/env bash
# 在独立克隆中执行：发现候选 → 字幕/GPU 转录 → Codex 整理 → 校验 → 提 PR。
set -euo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"

REMOTE="https://github.com/nolimitkun/fr-kol-wiki.git"
REPO="$HOME/workspace/fr-kol-wiki-nightly"
STATE_DIR="$HOME/.local/state/fr-kol-wiki-nightly"
LOG_DIR="$STATE_DIR/logs"
PROMPT="$HOME/.local/share/fr-kol-wiki-automation/daily-prompt.md"
SELECT_PROMPT="$HOME/.local/share/fr-kol-wiki-automation/selection-prompt.md"
LAST_MESSAGE="$STATE_DIR/last-message.md"
SELECTION="$STATE_DIR/selection.txt"
CANDIDATES="$STATE_DIR/candidates.txt"
BEFORE_SOURCES="$STATE_DIR/sources-before.txt"
AFTER_SOURCES="$STATE_DIR/sources-after.txt"
NEW_SOURCES="$STATE_DIR/new-sources.txt"
RUN_DATE="$(date +%Y%m%d)"
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/$RUN_DATE.log"
SUCCESS_MARKER="$STATE_DIR/success-$RUN_DATE"

mkdir -p "$LOG_DIR"
find "$LOG_DIR" -name '*.log' -mtime +30 -delete
find "$STATE_DIR" -maxdepth 1 -name 'success-*' -mtime +30 -delete
exec >>"$LOG" 2>&1
echo "=== run started $(date -Is) ==="

if [ "${FORCE_RUN:-0}" != "1" ] && [ -e "$SUCCESS_MARKER" ]; then
  echo "Already completed successfully today; skipping. Set FORCE_RUN=1 to rerun."
  echo "=== run finished $(date -Is) ==="
  exit 0
fi

finish_successfully() {
  touch "$SUCCESS_MARKER"
  echo "=== run finished $(date -Is) ==="
}

if [ ! -f "$PROMPT" ] || [ ! -f "$SELECT_PROMPT" ]; then
  echo "!! missing automation prompt"
  exit 1
fi

tries=0
until git ls-remote "$REMOTE" -h refs/heads/main >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -ge 20 ]; then
    echo "!! network not ready after about 10 minutes"
    exit 1
  fi
  echo "network not ready (try $tries), sleeping 30s"
  sleep 30
done

open_daily_pr="$(gh pr list \
  --repo nolimitkun/fr-kol-wiki \
  --state open \
  --limit 100 \
  --json headRefName,url \
  --jq '.[] | select(.headRefName | startswith("automation/daily-ingestion-")) | .url')"
open_daily_branches="$(gh pr list \
  --repo nolimitkun/fr-kol-wiki \
  --state open \
  --limit 100 \
  --json headRefName \
  --jq '.[] | select(.headRefName | startswith("automation/daily-ingestion-")) | .headRefName')"
if [ "${FORCE_RUN:-0}" != "1" ] && [ -n "$open_daily_pr" ]; then
  echo "An earlier daily ingestion PR is still open; waiting for review:"
  echo "$open_daily_pr"
  finish_successfully
  exit 0
fi

if [ ! -d "$REPO/.git" ]; then
  mkdir -p "$(dirname "$REPO")"
  git clone "$REMOTE" "$REPO"
fi

# 这是专用于自动化的克隆；每次从 origin/main 的干净状态开始。
git -C "$REPO" fetch --prune origin
git -C "$REPO" checkout -q main
git -C "$REPO" reset --hard origin/main
git -C "$REPO" clean -fd
rm -rf "$REPO/_docs" "$REPO/site"

cd "$REPO"
BASE_SHA="$(git rev-parse HEAD)"

run_codex() {
  codex exec \
    --ignore-user-config \
    --ephemeral \
    --cd "$REPO" \
    --model gpt-5.6-sol \
    -c 'approval_policy="never"' \
    -c 'default_permissions="daily-ingestion"' \
    -c 'permissions.daily-ingestion.extends=":workspace"' \
    -c 'permissions.daily-ingestion.network.enabled=false' \
    "$@"
}

# 网络操作由这个受信任的外层脚本执行；Codex 的 shell 保持断网。
seen_backup=""
if [ -n "$open_daily_branches" ]; then
  seen_backup="$STATE_DIR/seen-before-open-pr-overlay.txt"
  cp sources/seen.txt "$seen_backup"
  while IFS= read -r branch; do
    git show "origin/$branch:sources/seen.txt" || true
  done <<<"$open_daily_branches" >>sources/seen.txt
  sort -u -o sources/seen.txt sources/seen.txt
fi
uv run scripts/discover.py -n 15 >"$CANDIDATES"
if [ -n "$seen_backup" ]; then
  mv "$seen_backup" sources/seen.txt
fi
if ! grep -q 'watch?v=' "$CANDIDATES"; then
  echo "No unseen candidates; no changes."
  finish_successfully
  exit 0
fi

{
  cat "$SELECT_PROMPT"
  printf '\n\n## 候选列表\n\n'
  cat "$CANDIDATES"
} | run_codex --output-last-message "$SELECTION" -

if [ -n "$(git status --porcelain)" ]; then
  echo "!! selection phase changed the repository"
  exit 1
fi

mapfile -t selected_lines < <(sed '/^[[:space:]]*$/d' "$SELECTION")
if [ "${#selected_lines[@]}" -eq 1 ] && [ "${selected_lines[0]}" = "NONE" ]; then
  echo "No suitable video selected; no changes."
  finish_successfully
  exit 0
fi
if [ "${#selected_lines[@]}" -lt 1 ] || [ "${#selected_lines[@]}" -gt 2 ]; then
  echo "!! invalid selection count: ${#selected_lines[@]}"
  exit 1
fi

find sources -path '*/transcript.md' -print | sort >"$BEFORE_SOURCES"
fetched=0
for line in "${selected_lines[@]}"; do
  IFS=$'\t' read -r video_id channel_slug extra <<<"$line"
  if [[ ! "$video_id" =~ ^[A-Za-z0-9_-]{11}$ ]] || \
     [[ ! "$channel_slug" =~ ^[a-z0-9-]+$ ]] || \
     [ -n "${extra:-}" ]; then
    echo "!! invalid selection line: $line"
    exit 1
  fi
  if ! grep -F "watch?v=$video_id" "$CANDIDATES" | grep -Fq -- "--kol $channel_slug"; then
    echo "!! selection is not in the discovered candidate list: $line"
    exit 1
  fi

  url="https://www.youtube.com/watch?v=$video_id"
  if uv run scripts/fetch.py "$url" --kol "$channel_slug"; then
    fetched=$((fetched + 1))
    continue
  fi

  echo "No usable French captions for $video_id; trying RTX 5090 transcription."
  if uv run \
    --with faster-whisper \
    --with nvidia-cublas-cu12 \
    --with nvidia-cudnn-cu12 \
    scripts/fetch.py "$url" --kol "$channel_slug" \
    --transcribe --model large-v3-turbo; then
    fetched=$((fetched + 1))
  else
    echo "!! failed to fetch or transcribe $video_id; continuing"
  fi
done

if [ "$fetched" -eq 0 ]; then
  echo "No selected video could be fetched; no changes."
  finish_successfully
  exit 0
fi

find sources -path '*/transcript.md' -print | sort >"$AFTER_SOURCES"
comm -13 "$BEFORE_SOURCES" "$AFTER_SOURCES" >"$NEW_SOURCES"
if [ ! -s "$NEW_SOURCES" ]; then
  echo "!! fetch reported success but no new transcript was found"
  exit 1
fi

{
  cat "$PROMPT"
  printf '\n\n## 本次新增逐字稿\n\n'
  cat "$NEW_SOURCES"
} | run_codex --output-last-message "$LAST_MESSAGE" -

if [ "$(git rev-parse HEAD)" != "$BASE_SHA" ]; then
  echo "!! Codex changed Git history; refusing to push"
  exit 1
fi

unexpected="$(git status --porcelain | awk '{print $2}' | grep -Ev '^(sources/|wiki/)' || true)"
if [ -n "$unexpected" ]; then
  echo "!! changes outside sources/ and wiki/:"
  echo "$unexpected"
  exit 1
fi

immutable_source_changes="$(
  git diff HEAD --name-status --find-renames -- sources/ |
    awk '
      $1 == "A" { next }
      $1 == "M" && ($2 == "sources/seen.txt" || $2 == "sources/skipped.txt") { next }
      { print }
    '
)"
if [ -n "$immutable_source_changes" ]; then
  echo "!! immutable source files were changed"
  echo "$immutable_source_changes"
  exit 1
fi

if [ -z "$(git status --porcelain)" ]; then
  echo "No suitable video found; no changes."
  finish_successfully
  exit 0
fi

uv run scripts/lint.py
mkdir -p _docs
cp README.md _docs/index.md
cp SCHEMA.md watchlist.yaml _docs/
cp -r wiki sources _docs/
uv run scripts/gen_nav.py
DISABLE_MKDOCS_2_WARNING=true uv run \
  --with 'mkdocs>=1.6,<2' \
  --with 'mkdocs-material>=9,<10' \
  --with 'mkdocs-literate-nav>=0.6,<1' \
  mkdocs build --strict

BRANCH="automation/daily-ingestion-$RUN_STAMP"
git switch -c "$BRANCH"
git config user.name "fr-kol-wiki automation"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add sources wiki
git commit -m "content: 每日视频筛选 $RUN_DATE"
git push --set-upstream origin "$BRANCH"

PR_URL="$(gh pr create \
  --base main \
  --head "$BRANCH" \
  --title "content: 每日视频筛选 $RUN_DATE" \
  --body "本地 Codex 每日筛选并整理的内容，必要时使用 RTX 5090 转录。已通过 Wiki lint 与 MkDocs strict build；请人工复核翻译、说话人归属、数字和时间戳后再合并。")"

echo "Created PR: $PR_URL"
finish_successfully
