#!/usr/bin/env python3
"""Generate DMG background images for Clearly installer using ImageMagick."""
import subprocess, os, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Lucide chevron-right icon as SVG
CHEVRON_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>'


def generate(width, height, output_path):
    scale = width / 660
    icon_size = int(80 * scale)

    # Chevron centered between the two icon positions (x=170 and x=490), at icon y=170
    cx = int(330 * scale) - icon_size // 2
    cy = int(188 * scale) - icon_size // 2

    with tempfile.NamedTemporaryFile(suffix=".svg", mode="w", delete=False) as f:
        f.write(CHEVRON_SVG)
        svg_path = f.name

    try:
        cmd = [
            "magick",
            "-size", f"{width}x{height}", "xc:#f0f0f0",
            "(",
                "-background", "none",
                "-density", "300",
                svg_path,
                "-resize", f"{icon_size}x{icon_size}",
            ")",
            "-gravity", "none",
            "-geometry", f"+{cx}+{cy}",
            "-composite",
            output_path,
        ]
        subprocess.run(cmd, check=True)
        print(f"  {output_path} ({width}x{height})")
    finally:
        os.unlink(svg_path)


if __name__ == "__main__":
    os.chdir(os.path.join(SCRIPT_DIR, ".."))
    print("Generating DMG backgrounds...")
    generate(660, 400, "scripts/dmg-background.png")
    generate(1320, 800, "scripts/dmg-background@2x.png")
    print("Done.")
