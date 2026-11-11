"""Bake the Godot combat atlas from a checkout of patch-gg/pixelfx (Node 18+, Pillow)."""
import argparse
import json
import math
from pathlib import Path
import subprocess
import tempfile

from PIL import Image

EFFECTS = """
melee/sword-slash melee/thrust melee/spin-slash melee/heavy-cleave melee/double-slash melee/whip-crack
impacts/blunt-hit impacts/hit-spark impacts/crit-hit impacts/shield-block impacts/ground-slam
lightning/lightning-strike nature/poison-cloud fire/campfire holy/heal holy/divine-shield
spawn/poof arcane/portal arcane/blink-out arcane/magic-circle-cast
status/poisoned status/slowed status/stunned holy/blessing
""".split()
LOOPS = {"campfire", "poison-cloud", "portal"}
PALETTES = {
    "sword-slash": ["#152536", "#284b54", "#426e74", "#70a89f", "#a5d5bc", "#ecedd3", "#fff9db"],
    "heavy-cleave": ["#301922", "#68232a", "#a44131", "#cd7841", "#eebe73", "#fff0be", "#fff9eb"],
}


def pack(metadata, output):
    data = json.loads(metadata.read_text(encoding="utf8"))
    name = metadata.stem
    atlas = Image.open(metadata.with_suffix(".png")).convert("RGBA")
    cells = []
    for frame in data["frames"]:
        r = frame["frame"]
        cells.append(atlas.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])))
    bounds = [im.getchannel("A").point(lambda a: 255 if a > 12 else 0).getbbox() for im in cells]
    bounds = [b for b in bounds if b]
    # Crop every frame to the same rectangle to preserve the motion between frames.
    crop = (min(b[0] for b in bounds), min(b[1] for b in bounds),
            max(b[2] for b in bounds), max(b[3] for b in bounds))
    w, h = crop[2] - crop[0], crop[3] - crop[1]
    cols = math.ceil(math.sqrt(len(cells)))
    sheet = Image.new("RGBA", (w * cols, h * math.ceil(len(cells) / cols)))
    regions, frames = [], []
    for i, im in enumerate(cells):
        x, y = i % cols * w, i // cols * h
        sheet.paste(im.crop(crop), (x, y))
        resource_id = name.replace("-", "_")
        frame_id = f"{resource_id}_{i}"
        regions.append(f'[sub_resource type="AtlasTexture" id="{frame_id}"]\natlas = ExtResource("{resource_id}")\nregion = Rect2({x}, {y}, {w}, {h})')
        frames.append(f'{{"duration": 1.0, "texture": SubResource("{frame_id}")}}')
    sheet.save(output / f"{name}.png", optimize=True)
    loop = "true" if name in LOOPS else "false"
    fps = data["meta"]["pixelfx"]["fps"]
    clip = f'{{"name": &"{name}", "loop": {loop}, "speed": {fps}.0, "frames": [\n' + ",\n".join(frames) + "\n]}"
    return regions, clip


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pixelfx", type=Path, help="PixelFX checkout; revision in assets/effects/CREDITS.md")
    args = parser.parse_args()
    renderer = args.pixelfx.resolve() / "tools/render.mjs"
    output = Path(__file__).resolve().parents[1] / "assets/effects"
    headers, regions, clips = [], [], []
    with tempfile.TemporaryDirectory() as tmp:
        for effect in EFFECTS:
            name = effect.split("/")[1]
            options = {"palette": PALETTES[name]} if name in PALETTES else {}
            subprocess.run(["node", str(renderer), effect, "--sheet", "--no-actor", "--fps", "16",
                            "--max", "3", "--zoom", "1", "--opts", json.dumps(options), "--out", tmp], check=True)
            parts, clip = pack(Path(tmp) / effect / f"{name}.json", output)
            resource_id = name.replace("-", "_")
            headers.append(f'[ext_resource type="Texture2D" path="res://assets/effects/{name}.png" id="{resource_id}"]')
            regions.extend(parts)
            clips.append(clip)
    text = '[gd_resource type="SpriteFrames" format=3]\n\n' + "\n".join(headers)
    text += "\n\n" + "\n\n".join(regions) + "\n\n[resource]\nanimations = [\n" + ",\n".join(clips) + "\n]\n"
    (output / "combat.tres").write_text(text, encoding="utf8")


if __name__ == "__main__":
    main()
