# /// script
# requires-python = ">=3.10"
# dependencies = ["yt-dlp>=2025.1"]
# ///
"""抓取视频元数据与法语字幕，或用 faster-whisper 生成法语逐字稿。"""

import argparse
import html
import json
import re
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "sources"
LANG_PREF = ["fr-orig", "fr", "fr-FR", "fr-CA"]


def run(command: list[str], timeout: int = 300) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        sys.exit(f"命令超时：{' '.join(command[:3])}")


def timestamp(seconds: float) -> str:
    value = max(0, int(seconds))
    return f"{value // 3600:02d}:{value % 3600 // 60:02d}:{value % 60:02d}"


def anchor(seconds: float) -> str:
    stamp = timestamp(seconds)
    return f'\n[{stamp}] <a id="{stamp.replace(":", "")}"></a>'


def parse_vtt(path: Path, interval: int = 60) -> str:
    cue = re.compile(r"(?:(\d+):)?(\d+):(\d+)[.,](\d+)\s+-->")
    tags = re.compile(r"<[^>]+>")
    output: list[str] = []
    current = 0.0
    next_anchor = 0.0
    previous = ""
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = cue.search(raw)
        if match:
            hours, minutes, seconds, millis = match.groups()
            current = int(hours or 0) * 3600 + int(minutes) * 60 + int(seconds) + int(millis) / 1000
            continue
        line = html.unescape(tags.sub("", raw)).strip()
        if not line or line == "WEBVTT" or line.startswith(("Kind:", "Language:", "NOTE", "STYLE")):
            continue
        if line.isdigit() or line == previous:
            continue
        if current >= next_anchor:
            output.append(anchor(current))
            next_anchor = current + interval
        output.append(line)
        previous = line
    return "\n".join(output).strip()


def choose_language(info: dict) -> tuple[str | None, str | None]:
    manual = info.get("subtitles") or {}
    automatic = info.get("automatic_captions") or {}
    for language in LANG_PREF:
        if language in manual:
            return language, "manual"
    for language in LANG_PREF:
        if language in automatic:
            return language, "automatic"
    for language in [*manual, *automatic]:
        if language.startswith("fr"):
            return language, "manual" if language in manual else "automatic"
    return None, None


def transcribe(url: str, temp: Path, model_name: str) -> tuple[str, str]:
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        sys.exit("--transcribe 需要：uv run --with faster-whisper scripts/fetch.py URL --kol SLUG --transcribe")
    audio_template = str(temp / "audio.%(ext)s")
    result = run(["yt-dlp", "-f", "bestaudio/best", "-x", "--audio-format", "wav", "-o", audio_template, url], 1800)
    if result.returncode:
        sys.exit(result.stderr)
    files = list(temp.glob("audio.*"))
    if not files:
        sys.exit("音频下载后未找到输出文件。")
    print(f"使用 {model_name} 转录法语音频……")
    model = WhisperModel(model_name, device="auto", compute_type="auto")
    segments, _ = model.transcribe(str(files[0]), language="fr", vad_filter=True)
    output, next_anchor = [], 0.0
    for segment in segments:
        if segment.start >= next_anchor:
            output.append(anchor(segment.start))
            next_anchor = segment.start + 60
        output.append(segment.text.strip())
    return "\n".join(output).strip(), f"whisper:{model_name}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--kol", required=True)
    parser.add_argument("--transcribe", action="store_true")
    parser.add_argument("--model", default="large-v3-turbo")
    args = parser.parse_args()

    result = run(["yt-dlp", "--dump-single-json", "--skip-download", args.url])
    if result.returncode:
        sys.exit(result.stderr)
    info = json.loads(result.stdout)
    video_id = str(info.get("id") or "unknown")
    upload = str(info.get("upload_date") or "00000000")

    with tempfile.TemporaryDirectory(prefix="fr-kol-") as raw_temp:
        temp = Path(raw_temp)
        language, source_type = choose_language(info)
        text = ""
        subtitle_label = ""
        if language:
            command = [
                "yt-dlp", "--skip-download", "--write-subs", "--write-auto-subs",
                "--sub-langs", language, "--sub-format", "vtt",
                "-o", str(temp / "%(id)s.%(ext)s"), args.url,
            ]
            subtitles = run(command)
            if subtitles.returncode:
                sys.exit(subtitles.stderr)
            candidates = list(temp.glob("*.vtt"))
            if candidates:
                text = parse_vtt(candidates[0])
                subtitle_label = f"{source_type}:{language}"
        if not text and args.transcribe:
            text, subtitle_label = transcribe(args.url, temp, args.model)
        if not text:
            sys.exit("未找到法语字幕。可加 --transcribe 进行本地转录。")

    title = str(info.get("title") or "").replace('"', "'")
    channel = str(info.get("channel") or info.get("uploader") or "").replace('"', "'")
    duration = round(float(info.get("duration") or 0) / 60)
    destination = SOURCES / args.kol / f"{upload}-{video_id}"
    destination.mkdir(parents=True, exist_ok=False)
    metadata = "\n".join([
        "---", f'title: "{title}"', f"url: {info.get('webpage_url') or args.url}",
        f"video_id: {video_id}", f"kol: {args.kol}", f'channel: "{channel}"',
        f"upload_date: {upload}", f"duration_minutes: {duration}",
        "language: fr", f"subtitle: {subtitle_label}", f"fetched: {date.today().isoformat()}", "---",
    ])
    (destination / "transcript.md").write_text(f"{metadata}\n\n{text}\n", encoding="utf-8")

    seen_path = SOURCES / "seen.txt"
    seen = set(seen_path.read_text(encoding="utf-8").split()) if seen_path.exists() else set()
    if video_id not in seen:
        with seen_path.open("a", encoding="utf-8") as handle:
            handle.write(f"{video_id}\n")
    print(f"完成：{destination / 'transcript.md'}")


if __name__ == "__main__":
    main()
