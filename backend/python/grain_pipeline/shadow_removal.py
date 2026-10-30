"""Shadow detection and removal module for grain images.

Adapted from shadow_removal.py to run cleanly and headlessly in the pipeline.
"""
from __future__ import annotations

import cv2
import numpy as np

from .config import bool_param, float_param, int_param


def detect_and_remove_shadow(
    rgb: np.ndarray,
    params: dict | None = None,
) -> tuple[np.ndarray, np.ndarray, dict]:
    """Detect and remove shadows from an RGB grain image.

    Parameters
    ----------
    rgb : np.ndarray
        RGB image of shape (H, W, 3) and uint8 type.
    params : dict, optional
        Pipeline parameter dictionary.

    Returns
    -------
    tuple[np.ndarray, np.ndarray, dict]
        (shadow_removed_rgb, shadow_mask, stats_dict)
    """
    if params is None:
        params = {}

    blur_ksize = int_param(params, "shadowBlurKsize", 5, 3, 31)
    if blur_ksize % 2 == 0:
        blur_ksize += 1

    morph_ksize = int_param(params, "shadowMorphKsize", 5, 3, 31)
    if morph_ksize % 2 == 0:
        morph_ksize += 1

    shadow_blur_ksize = int_param(params, "shadowRemovalBlurKsize", 61, 3, 201)
    if shadow_blur_ksize % 2 == 0:
        shadow_blur_ksize += 1

    max_gain = float_param(params, "shadowMaxGain", 3.0, 1.0, 10.0)
    feather = int_param(params, "shadowFeather", 9, 0, 50)

    # 1. Convert RGB to BGR for OpenCV processing
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)

    # 2. Grain mask via HSV (identifies pixels that belong to rice/grain)
    # Rice grains typically have yellow/brown/cream color
    hsv_grain_lower = np.array([5, 0, 30], dtype=np.uint8)
    hsv_grain_upper = np.array([40, 255, 255], dtype=np.uint8)

    hsv_img = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    grain_mask = cv2.inRange(hsv_img, hsv_grain_lower, hsv_grain_upper)

    # 3. Dark mask via Otsu thresholding
    gray_img = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray_img, (blur_ksize, blur_ksize), 0)
    _, dark_mask = cv2.threshold(
        blurred, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
    )

    # 4. Shadow mask = Dark regions that are NOT grain
    not_grain = cv2.bitwise_not(grain_mask)
    shadow_mask = cv2.bitwise_and(dark_mask, not_grain)

    # 5. Clean mask with morphological operations
    kernel_clean = np.ones((morph_ksize, morph_ksize), np.uint8)
    shadow_mask = cv2.morphologyEx(shadow_mask, cv2.MORPH_OPEN, kernel_clean)
    shadow_mask = cv2.morphologyEx(shadow_mask, cv2.MORPH_CLOSE, kernel_clean)

    # Dilate slightly to cover shadow boundaries
    kernel_dilate = np.ones((5, 5), np.uint8)
    mask_final = cv2.dilate(shadow_mask, kernel_dilate, iterations=1)

    shadow_pct = float(mask_final.mean() / 255.0 * 100.0)
    grain_pct = float(grain_mask.mean() / 255.0 * 100.0)

    # 6. Apply shadow removal if any shadow was detected
    if shadow_pct > 0.05:
        removed_bgr = _remove_shadow_core(
            bgr,
            mask_final,
            blur_ksize=shadow_blur_ksize,
            max_gain=max_gain,
            feather=feather,
        )
        removed_rgb = cv2.cvtColor(removed_bgr, cv2.COLOR_BGR2RGB)
        applied = True
    else:
        removed_rgb = rgb.copy()
        applied = False

    stats = {
        "enabled": True,
        "applied": applied,
        "shadow_pct": round(shadow_pct, 2),
        "grain_pct": round(grain_pct, 2),
    }

    return removed_rgb, mask_final, stats


def _remove_shadow_core(
    image_bgr: np.ndarray,
    mask: np.ndarray,
    blur_ksize: int = 61,
    max_gain: float = 3.0,
    feather: int = 9,
) -> np.ndarray:
    """Core shadow removal by estimating background luminance in HSV space."""
    if image_bgr.ndim != 3 or image_bgr.shape[2] != 3:
        raise ValueError("image_bgr must be a 3-channel image.")

    hsv_f = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    h, s, v = cv2.split(hsv_f)

    # Local background luminance estimation
    k = max(3, blur_ksize | 1)
    kernel_morph = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    v_bg = cv2.morphologyEx(v, cv2.MORPH_CLOSE, kernel_morph)
    v_bg = cv2.GaussianBlur(v_bg, (0, 0), sigmaX=k / 6.0)

    # Gain multiplier
    eps = 1e-3
    gain = np.clip(v_bg / (v + eps), 1.0, max_gain)
    v_new = np.clip(v * gain, 0, 255)

    v_out = v.copy()
    v_out[mask > 0] = v_new[mask > 0]

    hsv_out = cv2.merge([h, s, v_out]).astype(np.uint8)
    result_bgr = cv2.cvtColor(hsv_out, cv2.COLOR_HSV2BGR)

    # Feathering to prevent harsh edges
    if feather > 0:
        mask_f = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), sigmaX=float(feather)) / 255.0
        mask_f = mask_f[..., np.newaxis]
        blended = (
            result_bgr.astype(np.float32) * mask_f
            + image_bgr.astype(np.float32) * (1.0 - mask_f)
        )
        return np.clip(blended, 0, 255).astype(np.uint8)

    return result_bgr

