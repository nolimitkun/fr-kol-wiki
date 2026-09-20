# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""检查索引覆盖、Markdown 断链、未入库 source 与无效时间戳。"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WIKI = ROOT / "wiki"
SOURCES = ROOT / "sources"
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+['\"][^)]*['\"])?\)")


def ignored_ids() -> set[str]:
    result = set()
    path = SOURCES / "skipped.txt"
    if path.exists():
        for row in path.read_text(encoding="utf-8").splitlines():
            value = row.split("#", 1)[0].strip()
            if value:
                result.add(value)
    return result


def local_target(page: Path, href: str) -> Path | None:
    if href.startswith(("http://", "https://", "mailto:", "#")):
        return None
    clean = href.split("#", 1)[0]
    return (page.parent / clean).resolve() if clean else page.resolve()


def main() -> None:
    issues: list[str] = []
    pages = sorted(WIKI.rglob("*.md"))
    index = (WIKI / "index.md").read_text(encoding="utf-8")

    for page in pages:
        if page.name in {"index.md", "log.md"}:
            continue
        relative = page.relative_to(WIKI).as_posix()
        if relative not in index and f"({relative})" not in index:
            issues.append(f"INDEX 未收录：wiki/{relative}")

    referenced_sources: set[Path] = set()
    for page in pages:
        content = page.read_text(encoding="utf-8")
        for href in LINK.findall(content):
            target = local_target(page, href)
            if target is None:
                continue
            if not target.exists():
                issues.append(f"断链：{page.relative_to(ROOT)} -> {href}")
                continue
            if target.name == "transcript.md":
                referenced_sources.add(target)
                if "#" in href:
                    anchor = href.rsplit("#", 1)[1]
                    transcript = target.read_text(encoding="utf-8")
                    if f'id="{anchor}"' not in transcript:
                        issues.append(f"无效时间戳：{page.relative_to(ROOT)} -> {href}")

    skipped = ignored_ids()
    for transcript in sorted(SOURCES.glob("*/*/transcript.md")):
        video_id = transcript.parent.name.split("-", 1)[-1]
        if transcript.resolve() not in referenced_sources and video_id not in skipped:
            issues.append(f"已抓取但无视频页：{transcript.relative_to(ROOT)}")

    print(f"Wiki lint：{len(pages)} 个页面")
    if issues:
        print("\n".join(f"- {issue}" for issue in issues))
        sys.exit(1)
    print("✅ 无问题")


if __name__ == "__main__":
    main()
