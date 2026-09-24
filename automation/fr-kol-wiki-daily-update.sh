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
LAST_MESSAGE="$STATE_DIR/last-message.md"
RUN_DATE="$(date +%Y%m%d)"
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/$RUN_DATE.log"

mkdir -p "$LOG_DIR"
find "$LOG_DIR" -name '*.log' -mtime +30 -delete
exec >>"$LOG" 2>&1
echo "=== run started $(date -Is) ==="

if [ ! -f "$PROMPT" ]; then
  echo "!! missing prompt: $PROMPT"
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

codex --enable use_legacy_landlock --search exec \
  --ignore-user-config \
  --ephemeral \
  --cd "$REPO" \
  --model gpt-5.6-sol \
  --output-last-message "$LAST_MESSAGE" \
  -c 'approval_policy="never"' \
  -c 'default_permissions="daily-ingestion"' \
  -c 'features.network_proxy=true' \
  -c 'permissions.daily-ingestion.extends=":workspace"' \
  -c 'permissions.daily-ingestion.network.enabled=true' \
  -c 'permissions.daily-ingestion.network.domains."*"="allow"' \
  - <"$PROMPT"

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

modified_sources="$(git diff HEAD --name-only --diff-filter=M -- sources/ | grep -Ev '^sources/(seen|skipped)\.txt$' || true)"
deleted_sources="$(git diff HEAD --name-only --diff-filter=D -- sources/ || true)"
if [ -n "$modified_sources" ] || [ -n "$deleted_sources" ]; then
  echo "!! immutable source files were modified or deleted"
  echo "$modified_sources"
  echo "$deleted_sources"
  exit 1
fi

if [ -z "$(git status --porcelain)" ]; then
  echo "No suitable video found; no changes."
  echo "=== run finished $(date -Is) ==="
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
echo "=== run finished $(date -Is) ==="
