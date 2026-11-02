from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps


@dataclass(frozen=True)
class PreparedImage:
    rgb: np.ndarray
    original_width: int
    original_height: int
    scale: float


def read_image(path: Path, max_side: int) -> PreparedImage:
    with Image.open(path) as image:
        image = ImageOps.exif_transpose(image)
        original_width, original_height = image.size
        longest = max(original_width, original_height)
        if longest <= max_side:
            rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
            return PreparedImage(rgb, original_width, original_height, 1.0)

        scale = max_side / float(longest)
        target_w = max(1, int(round(original_width * scale)))
        target_h = max(1, int(round(original_height * scale)))
        resized_img = image.resize((target_w, target_h), Image.Resampling.BILINEAR).convert("RGB")
        rgb = np.asarray(resized_img, dtype=np.uint8)
        return PreparedImage(rgb, original_width, original_height, scale)


def png_base64(rgb_or_gray: np.ndarray) -> str:
    import base64

    if rgb_or_gray.ndim == 2:
        encoded_source = rgb_or_gray
    else:
        encoded_source = cv2.cvtColor(rgb_or_gray, cv2.COLOR_RGB2BGR)
    ok, buffer = cv2.imencode(".png", encoded_source, [cv2.IMWRITE_PNG_COMPRESSION, 3])
    if not ok:
        return ""
    return base64.b64encode(buffer.tobytes()).decode("ascii")
