# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""输出当前知识库的简要统计。"""

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def count(folder: str) -> int:
    return len(list((ROOT / "wiki" / folder).glob("*.md")))


config = yaml.safe_load((ROOT / "watchlist.yaml").read_text(encoding="utf-8"))
print(f"频道：{len(config.get('kols', []))}")
print(f"原始转录：{len(list((ROOT / 'sources').glob('*/*/transcript.md')))}")
for name in ("videos", "people", "organizations", "domains", "topics"):
    print(f"{name}：{count(name)}")
