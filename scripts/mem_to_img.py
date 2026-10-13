"""
mem_to_img.py - image reconstruction (step 3 of the loopback test)

Reads the AXI4-Stream pixels captured by the testbench (sim_data/output.mem),
rebuilds the grayscale image and compares it pixel by pixel with
sim_data/input.mem.

Writes:
    sim_data/output_reconstructed.png

Usage:
    python scripts/mem_to_img.py
"""
import os
import sys
from PIL import Image

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR    = os.path.join(PROJECT_DIR, "sim_data")


def read_hex(name):
    path = os.path.join(DATA_DIR, name)
    if not os.path.exists(path):
        sys.exit(f"Missing {path} - run the previous step first.")
    with open(path) as f:
        return [int(line, 16) for line in f if line.strip()]


def main():
    width, height = read_hex("dims.mem")[:2]
    sent     = read_hex("input.mem")
    received = read_hex("output.mem")
    total    = width * height

    img = Image.new("L", (width, height))
    img.putdata(received[:total] + [0] * max(0, total - len(received)))
    out_png = os.path.join(DATA_DIR, "output_reconstructed.png")
    img.save(out_png)

    mismatches = [i for i in range(min(len(sent), len(received))) if sent[i] != received[i]]

    print(f"Image size        : {width} x {height} = {total} pixels")
    print(f"Pixels sent       : {len(sent)}")
    print(f"Pixels received   : {len(received)}")
    print(f"Mismatched pixels : {len(mismatches)}")
    for i in mismatches[:10]:
        print(f"  pixel {i} (x={i % width}, y={i // width}): sent {sent[i]:02X}, got {received[i]:02X}")
    print(f"Reconstructed     : {out_png}")

    if len(received) == len(sent) == total and not mismatches:
        print("RESULT: MATCH - reconstructed image is identical to the input")
    else:
        print("RESULT: MISMATCH")
        sys.exit(1)


if __name__ == "__main__":
    main()
