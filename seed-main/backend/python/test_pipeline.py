"""Quick benchmark: compare YOLO-only vs YOLO+GrabCut+EdgeSnap."""
import base64
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from grain_pipeline.pipeline import analyze_image

ROOT = pathlib.Path(__file__).resolve().parents[2]
IMAGE = ROOT / "test_images" / "sample.jpg"
OUT_DIR = ROOT / "test_outputs"
OUT_DIR.mkdir(exist_ok=True)


def mean_solidity(result):
    ms = result["measurements"]
    if not ms:
        return 0.0
    return sum(m.get("solidity", 0) for m in ms) / len(ms)

def mean_extent(result):
    ms = result["measurements"]
    if not ms:
        return 0.0
    return sum(m.get("extent", 0) for m in ms) / len(ms)

def save_img(result, key, filename):
    data = result.get(key, "")
    if data:
        (OUT_DIR / filename).write_bytes(base64.b64decode(data))
        print(f"  saved: {OUT_DIR / filename}")

def run(label, params):
    t0 = time.perf_counter()
    r  = analyze_image(IMAGE, params)
    dt = time.perf_counter() - t0
    ms = r["measurements"]
    print(f"\n=== {label} ===")
    print(f"  count        : {r['summary']['count']}")
    print(f"  mean_solidity: {mean_solidity(r):.4f}  (higher = less boxy)")
    print(f"  mean_extent  : {mean_extent(r):.4f}   (lower = less boxy)")
    print(f"  time         : {dt:.1f}s")
    return r, dt


# 1. Baseline: YOLO ONNX only
r_base, _ = run("YOLO ONNX only (baseline)", {
    "enableGrabCut":     False,
    "enableEdgeSnap":    False,
    "maskContourSmooth": 0,
    "enableTiledInference": True,
})
save_img(r_base, "overlay_png_base64",  "01_yolo_only_overlay.png")
save_img(r_base, "sam_mask_png_base64", "01_yolo_only_mask.png")

# 2. GrabCut + EdgeSnap
r_cpu, _ = run("YOLO ONNX + GrabCut + EdgeSnap", {
    "enableGrabCut":     True,
    "enableEdgeSnap":    True,
    "maskContourSmooth": 1.0,
    "enableTiledInference": True,
})
save_img(r_cpu, "overlay_png_base64",  "02_grabcut_edgesnap_overlay.png")
save_img(r_cpu, "sam_mask_png_base64", "02_grabcut_edgesnap_mask.png")

print("\n=== Summary ===")
print(f"  Solidity YOLO-only  : {mean_solidity(r_base):.4f}")
print(f"  Solidity GrabCut    : {mean_solidity(r_cpu):.4f}")
print(f"  Extent   YOLO-only  : {mean_extent(r_base):.4f}")
print(f"  Extent   GrabCut    : {mean_extent(r_cpu):.4f}")
print(f"\nImages saved to: {OUT_DIR}")
