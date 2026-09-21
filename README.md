# 🇫🇷 France KOL Wiki

面向中文读者的法国公共议题长视频知识库。项目持续收录法国政治、经济、科技、军事、教育、医疗、社会与民生领域的 YouTube 深度访谈、演讲和圆桌，保存法语原始转录，并产出可溯源的中文翻译与结构化总结。

> 这里记录的是“谁在何时、什么语境下说了什么”，不是把任何 KOL 的观点包装成事实。

## 开始浏览

- **[在线浏览 France KOL Wiki](https://nolimitkun.github.io/fr-kol-wiki/)**（GitHub Pages）
- [Wiki 首页](wiki/index.md)
- [编辑与数据规范](SCHEMA.md)
- [关注频道](watchlist.yaml)

## 信息架构

| 层 | 目录 | 内容 |
|---|---|---|
| 原始资料 | `sources/` | 视频元数据、法语逐字稿、真实时间戳；只增不改 |
| 知识库 | `wiki/` | 视频中文摘要、人物/机构页、领域页、专题页 |
| 规范 | `SCHEMA.md`、`watchlist.yaml` | 采编规则、分类法和频道名单 |

与临时 RAG 问答不同，本项目提前把材料翻译、归纳、交叉链接，并在专题页中呈现不同政治光谱、职业背景和机构属性的观点。

## 内容范围

一级领域固定为：政治、经济、科技、军事与外交、教育、医疗、社会与民生、环境与能源。具体议题（如养老金改革、核能、欧洲战略自主、人工智能监管）放在 `wiki/topics/`，可跨领域关联。

## 快速开始

需要 Python 3.10+、[uv](https://docs.astral.sh/uv/) 和 `yt-dlp` 可用的网络环境。

```bash
# 查看关注频道最近的候选长视频
uv run scripts/discover.py

# 抓取法语字幕并保存不可变原文
uv run scripts/fetch.py 'https://www.youtube.com/watch?v=VIDEO_ID' --kol thinkerview

# 没有字幕时，本地 Whisper 转录
uv run --with faster-whisper scripts/fetch.py URL --kol thinkerview --transcribe

# 为一个 source 生成待编辑的视频页骨架
uv run scripts/scaffold.py sources/thinkerview/YYYYMMDD-VIDEO_ID/transcript.md

# 内容巡检 / 本地预览
uv run scripts/lint.py
uv run --with mkdocs-material --with mkdocs-literate-nav mkdocs serve
```

自动翻译只能作为初稿。涉及数字、制度名称、法律术语、否定句和说话人归属时，必须回看法语原文和上下文；观点引用必须指向 `sources/` 中真实存在的 `[HH:MM:SS]` 锚点。

## 本地每日收录

`automation/` 提供本地日更方案：每天扫描关注频道，最多挑选 2 条高质量长视频；有字幕时直接抓取，没有字幕时调用 NVIDIA GPU 和 `faster-whisper large-v3-turbo` 转录。Codex 按本项目的白话风格翻译、归纳、交叉链接并运行完整校验，最后创建待审 PR，不会自动合并；没有合适候选时不产生提交。

任务使用独立的 `~/workspace/fr-kol-wiki-nightly` 克隆，不会碰正在编辑的工作区。systemd 模板默认每天巴黎时间 08:00 运行，关机或睡眠错过后会在恢复时补跑。安装后的日志位于 `~/.local/state/fr-kol-wiki-nightly/logs/`。

## 版权与立场

原视频与字幕版权归原作者及发布方所有。本库仅保存研究、引用与评论所需的文本，并链接原视频。人物、机构和观点入库不代表项目认同；内容页应清楚区分发言者观点、编辑归纳和经外部来源核验的事实。
