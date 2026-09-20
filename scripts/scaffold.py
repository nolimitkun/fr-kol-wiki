# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""根据 transcript.md 建立中文视频页骨架；不会覆盖已有页面。"""

import argparse
import re
import unicodedata
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def field(text: str, name: str, default: str = "") -> str:
    match = re.search(rf"^{re.escape(name)}:\s*[\"']?(.*?)[\"']?\s*$", text, re.MULTILINE)
    return match.group(1) if match else default


def slugify(value: str) -> str:
    ascii_text = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", ascii_text).strip("-")[:60]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("transcript", type=Path)
    parser.add_argument("--slug")
    args = parser.parse_args()
    source = args.transcript.resolve()
    text = source.read_text(encoding="utf-8")
    title = field(text, "title", "待翻译标题")
    channel = field(text, "kol", "unknown")
    upload = field(text, "upload_date", "00000000")
    video_id = field(text, "video_id", source.parent.name.split("-", 1)[-1])
    slug = args.slug or slugify(title) or video_id
    output = ROOT / "wiki" / "videos" / f"{upload}-{channel}-{slug}.md"
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise SystemExit(f"已存在：{output}")
    relative_source = Path("../../sources") / source.parent.parent.name / source.parent.name / "transcript.md"
    today = date.today().isoformat()
    body = f'''---
title: "{title}（待译）"
date: {upload[:4]}-{upload[4:6]}-{upload[6:8]}
source_language: fr
status: draft
channel: {channel}
people: []
organizations: []
domains: []
topics: []
viewpoint: []
updated: {today}
---

# {title}（待译）

- 原视频：[YouTube]({field(text, "url")})
- 原始资料：[法语逐字稿]({relative_source.as_posix()})
- 发布日期：{upload[:4]}-{upload[4:6]}-{upload[6:8]}
- 审校状态：`draft`

## 一句话结论

> 待完整阅读逐字稿后填写。

## 摘要

待填写。

## 说话人

- 待确认主持人、嘉宾及其在视频发布日期时的身份。

## 核心观点

1. **待归纳。**（[00:00:00]({relative_source.as_posix()}#000000)）

## 关键数字与事实核验

| 原视频断言 | 性质 | 核验结果 | 来源 |
|---|---|---|---|
| 待填写 | 待核验 | — | — |

## 争议与反方观点

待填写。

## 法中术语表

| Français | 中文 | 语境说明 |
|---|---|---|
| 待填写 | 待填写 | 待填写 |

## 相关页面

- 领域：待填写
- 专题：待填写
- 人物与机构：待填写
'''
    output.write_text(body, encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
