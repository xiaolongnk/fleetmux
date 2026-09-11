#!/usr/bin/env python3
"""Measure rendered tmux pane-border contrast from a visual-harness PNG."""

from __future__ import annotations

import argparse
import collections
import math
import subprocess
from pathlib import Path


def relative_luminance(rgb: tuple[int, int, int]) -> float:
    channels = []
    for value in rgb:
        channel = value / 255
        channels.append(
            channel / 12.92
            if channel <= 0.04045
            else ((channel + 0.055) / 1.055) ** 2.4
        )
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    darker, lighter = sorted((relative_luminance(a), relative_luminance(b)))
    return (lighter + 0.05) / (darker + 0.05)


def distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return math.sqrt(sum((left - right) ** 2 for left, right in zip(a, b)))


def load_rgb(path: Path) -> tuple[int, int, bytes]:
    dimensions = subprocess.check_output(
        ["magick", "identify", "-format", "%w %h", str(path)], text=True
    )
    width, height = (int(value) for value in dimensions.split())
    pixels = subprocess.check_output(
        ["magick", str(path), "-alpha", "off", "-depth", "8", "rgb:-"]
    )
    expected = width * height * 3
    if len(pixels) != expected:
        raise RuntimeError(f"expected {expected} RGB bytes, received {len(pixels)}")
    return width, height, pixels


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    width, height, pixels = load_rgb(args.image)

    def pixel(x: int, y: int) -> tuple[int, int, int]:
        offset = (y * width + x) * 3
        return tuple(pixels[offset : offset + 3])  # type: ignore[return-value]

    # The deterministic fixture places its only full-height vertical rule near
    # the centre. Choose the left edge of the strongest continuous rule.
    scores = []
    for x in range(int(width * 0.4), int(width * 0.65)):
        score = sum(
            sum(abs(a - b) for a, b in zip(pixel(x, y), pixel(x - 8, y))) > 20
            for y in range(int(height * 0.03), int(height * 0.93))
        )
        scores.append((score, x))
    best_score = max(score for score, _ in scores)
    divider_x = min(x for score, x in scores if score == best_score)

    print(f"image={args.image} divider_x={divider_x} continuity={best_score}")
    for name, start, end in (("active", 0.05, 0.45), ("inactive", 0.55, 0.90)):
        rows = range(int(height * start), int(height * end))
        background = collections.Counter(
            pixel(x, y)
            for x in range(divider_x - 24, divider_x - 12)
            for y in rows
        ).most_common(1)[0][0]
        border_pixels = collections.Counter(
            pixel(x, y)
            for x in range(divider_x, divider_x + 2)
            for y in rows
        )
        border = next(
            rgb for rgb, _ in border_pixels.most_common() if distance(rgb, background) > 5
        )
        print(
            f"{name} rendered_border={border} rendered_background={background} "
            f"contrast={contrast(border, background):.2f}:1"
        )


if __name__ == "__main__":
    main()
