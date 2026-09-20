# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6", "yt-dlp>=2025.1"]
# ///
"""列出 watchlist 中尚未处理且达到时长门槛的最新视频。"""

import argparse
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def ids_from(path: Path) -> set[str]:
    if not path.exists():
        return set()
    result = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            result.add(line)
    return result


def scan(kol: dict, limit: int) -> tuple[dict, subprocess.CompletedProcess | None]:
    try:
        result = subprocess.run(
            [
                "yt-dlp", "--flat-playlist", "--playlist-end", str(limit),
                "--print", "%(id)s\t%(duration)s\t%(upload_date)s\t%(title)s",
                kol["channel"],
            ],
            capture_output=True, text=True, timeout=180,
        )
        return kol, result
    except subprocess.TimeoutExpired:
        return kol, None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("-n", "--limit", type=int, default=15)
    args = parser.parse_args()

    config = yaml.safe_load((ROOT / "watchlist.yaml").read_text(encoding="utf-8"))
    kols = config.get("kols", [])
    seen = ids_from(ROOT / "sources" / "seen.txt")
    skipped = ids_from(ROOT / "sources" / "skipped.txt")

    with ThreadPoolExecutor(max_workers=min(8, len(kols) or 1)) as pool:
        results = list(pool.map(lambda item: scan(item, args.limit), kols))

    total = 0
    for kol, result in results:
        print(f"\n## {kol['name']} ({kol['slug']})")
        if result is None:
            print("  !! 超时")
            continue
        if result.returncode:
            last = result.stderr.strip().splitlines()
            print(f"  !! {last[-1] if last else '抓取失败'}")
            continue
        found = 0
        threshold = int(kol.get("min_minutes", 20)) * 60
        for row in result.stdout.splitlines():
            parts = (row.split("\t", 3) + ["", "", "", ""])[:4]
            video_id, duration, upload_date, title = parts
            if not video_id or video_id in seen or video_id in skipped:
                continue
            try:
                seconds = float(duration)
            except (TypeError, ValueError):
                seconds = 0
            if seconds and seconds < threshold:
                continue
            minutes = f"{round(seconds / 60)}m" if seconds else "?m"
            shown_date = "????????" if upload_date in {"", "NA"} else upload_date
            print(f"  [{shown_date} {minutes:>4}] {title}")
            print(f"    uv run scripts/fetch.py 'https://www.youtube.com/watch?v={video_id}' --kol {kol['slug']}")
            found += 1
        if not found:
            print("  （没有新候选）")
        total += found
    print(f"\n共 {total} 个候选视频。")


if __name__ == "__main__":
    main()
