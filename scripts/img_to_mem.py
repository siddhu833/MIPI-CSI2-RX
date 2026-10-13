"""
img_to_mem.py - TX-side data generation (step 1 of the loopback test)

Converts an image to an 8-bit grayscale (RAW8) pixel stream for the
Verilog testbench:
    sim_data/input.mem   one pixel per line, 2 hex digits, row by row
    sim_data/dims.mem    line 1 = width, line 2 = height (hex)
    sim_data/input_gray.png  the grayscale reference image

Usage:
    python scripts/img_to_mem.py [image_path]     (default: data/colour_test.jpg)
"""
import os
import sys
from PIL import Image

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR    = os.path.join(PROJECT_DIR, "sim_data")
DEFAULT_IMG = os.path.join(PROJECT_DIR, "data", "colour_test.jpg")

MAX_WC     = (1 << 14) - 1      # 14-bit CSI-2 word count used by the design
MAX_PIXELS = 1920 * 1080        # testbench memory size


def main():
    img_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IMG
    img = Image.open(img_path).convert("L")          # grayscale, 8 bits/pixel
    width, height = img.size

    if width > MAX_WC:
        sys.exit(f"Image too wide: {width} bytes per line (max {MAX_WC})")
    if width * height > MAX_PIXELS:
        sys.exit(f"Image too large: {width * height} pixels (max {MAX_PIXELS})")

    os.makedirs(DATA_DIR, exist_ok=True)
    px = img.load()
    with open(os.path.join(DATA_DIR, "input.mem"), "w") as f:
        for y in range(height):
            for x in range(width):
                f.write(f"{px[x, y]:02X}\n")

    with open(os.path.join(DATA_DIR, "dims.mem"), "w") as f:
        f.write(f"{width:X}\n{height:X}\n")

    img.save(os.path.join(DATA_DIR, "input_gray.png"))

    print(f"Source image : {os.path.abspath(img_path)}")
    print(f"Grayscale    : {width} x {height} = {width * height} pixels (RAW8)")
    print(f"Wrote        : sim_data/input.mem, sim_data/dims.mem, sim_data/input_gray.png")


if __name__ == "__main__":
    main()
