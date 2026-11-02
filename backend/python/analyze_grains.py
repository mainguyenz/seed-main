from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Ensure UTF-8 console output on Windows
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

from grain_pipeline.pipeline import analyze_image


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze seed grains with YOLO segmentation pipeline.")
    parser.add_argument("--image", required=True, help="Path to JPG/PNG image.")
    parser.add_argument("--params-json", default="{}", help="JSON object with pipeline parameters.")
    args = parser.parse_args()

    try:
        params = json.loads(args.params_json or "{}")
        if not isinstance(params, dict):
            raise ValueError("params-json must be a JSON object")
        data = analyze_image(Path(args.image), params)
        print(json.dumps({"ok": True, "data": data}, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
