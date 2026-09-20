# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""为 mkdocs-literate-nav 生成 SUMMARY.md。"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "_docs"

SECTIONS = [
    ("领域", "domains"),
    ("专题", "topics"),
    ("人物", "people"),
    ("机构", "organizations"),
    ("视频", "videos"),
]


def title(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return path.stem


def main() -> None:
    lines = ["- [首页](index.md)", "- [内容索引](wiki/index.md)"]
    for label, folder in SECTIONS:
        files = sorted((DOCS / "wiki" / folder).glob("*.md"))
        if not files:
            continue
        lines.append(f"- {label}")
        lines.extend(f"    - [{title(path)}](wiki/{folder}/{path.name})" for path in files)
    (DOCS / "SUMMARY.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
