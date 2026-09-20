# France KOL Wiki — 数据与编辑规范

## 目标

把法国公共议题长视频整理成面向中文读者、可检索、可比较、可追溯的知识库。每条重要结论都回答四个问题：谁说的、何时说的、原话在哪里、这是观点还是事实。

## 三层模型

```text
watchlist.yaml                 # 频道、机构属性、主要领域和最低时长
sources/                       # 不可变原始层
  seen.txt
  skipped.txt
  <channel-slug>/<YYYYMMDD>-<video-id>/transcript.md
wiki/                          # 可持续修订的知识层
  index.md
  log.md
  videos/<YYYYMMDD>-<channel>-<slug>.md
  people/<person>.md
  organizations/<org>.md
  domains/<domain>.md
  topics/<topic>.md
scripts/                       # 发现、抓取、建页、巡检、导航
```

`sources/` 一旦写入不修改。转录错误、说话人判断和翻译勘误记录在对应视频页，避免历史引用失效。

## 内容工作流

### 1. Discover

`uv run scripts/discover.py` 并发扫描 `watchlist.yaml`。收录 20–30 分钟以上、具有完整论证的访谈、演讲、辩论和圆桌；跳过 Shorts、预告、重复上传、纯宣传片与缺少实质内容的直播等待画面。

主动放弃的候选写入 `sources/skipped.txt`：

```text
VIDEO_ID  # 12 分钟新闻快讯，不是长访谈
```

### 2. Fetch

`fetch.py` 优先抓取法语人工字幕，其次法语自动字幕；没有字幕时用 `--transcribe` 调用 faster-whisper。输出必须包含标题、URL、频道、发布日期、时长、字幕来源和语言。

### 3. Translate & Synthesize

完整阅读逐字稿后建立视频页，至少包括：

1. 一句话结论和 200–400 字摘要；
2. 说话人及身份（身份以视频发布日期为准）；
3. 核心观点，逐条附来源时间戳；
4. 关键数字与可核验断言；
5. 争议、反方观点与主持人追问；
6. 法中术语表；
7. 与人物、机构、领域和专题页的双向链接。

中文应忠实、自然，但不得抹平语气和不确定性：`peut` 不译成“一定”，`selon moi` 必须保留“他/她认为”。重要概念第一次出现时采用 `中文（français）`。

### 4. Cross-link

- 人物页：背景、公开身份、立场时间线、不同主题下的观点；
- 机构页：媒体、政党、智库、大学、企业或政府机构的属性；
- 领域页：八个稳定入口，只做导航和跨专题综述；
- 专题页：围绕具体问题并列不同来源的共识、分歧和变化。

## 来源与时间戳

- 每条实质性观点格式：`（[视频页](../videos/xxx.md)，[00:18:42](../../sources/.../transcript.md#001842)）`。
- 时间戳必须逐字来自转录稿的行首锚点，统一使用 `HH:MM:SS`。
- 法语直引应短而必要，同时给出中文翻译；大段内容使用转述。
- 视频发布日和事件发生日不是一回事，正文使用绝对日期。
- 转载频道不能自动视为原始来源，需记录原发布方。

## 观点、事实与核验

视频页用下列标签区分信息性质：

- `观点`：发言者的判断、价值偏好或预测；
- `事实性断言`：理论上可被外部证据证伪；
- `编辑核验`：编辑使用一手官方资料完成的核查；
- `待核验`：重要但尚未交叉验证的说法。

政治内容额外记录 `viewpoint`，只能使用可描述的公开身份或自我定位，不凭编辑印象给人贴“极左/极右”等标签。选举、现任职务、预算、法律、医疗建议等时效或高风险信息，必须用法国政府、INSEE、Assemblée nationale、Sénat、Cour des comptes、Santé publique France 等一手来源复核，并写明核验日期。

## Frontmatter

视频页：

```yaml
---
title: "中文标题"
date: 2026-09-20
source_language: fr
status: draft          # draft | reviewed | verified
channel: thinkerview
people: []
organizations: []
domains: [politics]
topics: []
viewpoint: []
updated: 2026-09-20
---
```

## 完成标准

一篇视频页只有满足以下条件才能从 `draft` 改为 `reviewed`：完整读稿、身份确认、时间戳可定位、数字复核、术语统一、至少一个领域入链、索引已收录。`verified` 还要求另一位编辑或独立模型逐项对照原文复审。
