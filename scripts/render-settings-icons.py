"""Build settings icons from the installed game's existing artwork."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

WHITE = (226, 226, 226)
# Muted edge tones sampled from the supplied vanilla signal palette.
BLUE = (88, 135, 163)
YELLOW = (188, 168, 62)
GREEN = (72, 163, 79)
RED = (189, 55, 70)

ICONS = [
    ("ore_filtering", "base/graphics/icons/signal/signal-mining.png", YELLOW, (26, 37, 38, 55), "signal"),
    ("avoid_water", "base/graphics/icons/signal/signal-liquid.png", BLUE, (0, 42, 64, 56), "signal"),
    ("avoid_cliffs", "base/graphics/icons/signal/signal-alert.png", RED, None, "warning"),
    ("belt_planner", "base/graphics/icons/arrows/signal-output.png", YELLOW, (42, 23, 57, 42), "signal"),
    ("belt_merge", "base/graphics/icons/arrows/signal-shuffle.png", YELLOW, (38, 35, 60, 55), "signal"),
    ("module", "core/graphics/icons/mip/empty-module-slot.png", BLUE, (18, 40, 46, 48), "signal"),
    ("lamp", "base/graphics/icons/signal/signal-sun.png", YELLOW, (23, 23, 41, 41), "signal"),
    ("pipe", "base/graphics/icons/signal/signal-liquid.png", BLUE, (0, 42, 64, 56), "signal"),
    ("deconstruction", "base/graphics/icons/signal/signal-lock.png", YELLOW, (22, 42, 42, 51), "signal"),
    ("landfill", "base/graphics/icons/signal/signal-white-flag.png", GREEN, (28, 25, 51, 33), "signal"),
    ("coverage", "base/graphics/icons/signal/signal-stack-size.png", YELLOW, (0, 40, 64, 64), "signal"),
    ("start", "base/graphics/icons/arrows/signal-input.png", BLUE, (0, 16, 40, 48), "signal"),
    ("print_placement_info", None, BLUE, None, "statistics"),
    ("display_lane_filling", None, GREEN, None, "lane_filling"),
    ("force_pipe_placement", "base/graphics/icons/signal/signal-lightning.png", YELLOW, (24, 18, 44, 38), "signal"),
    ("advanced", "mod:advanced-settings.png", YELLOW, (29, 23, 35, 29), "signal"),
    ("quality", "base/graphics/icons/signal/signal-star.png", YELLOW, None, "native"),
    ("entity_filtering", "mod:entity_filtering_mode_enabled.png", BLUE, (26, 26, 38, 38), "signal"),
    ("undo", "base/graphics/icons/arrows/signal-anticlockwise-circle-arrow.png", YELLOW, (39, 14, 64, 48), "signal"),
    ("blueprint_add", "base/graphics/icons/shortcut-toolbar/mip/new-blueprint-x56.png", BLUE, (17, 17, 47, 47), "signal"),
    ("avoid_obstacles", "base/graphics/icons/signal/signal-no-entry.png", RED, None, "avoidance"),
]


def load_primary(path):
    source = Image.open(path).convert("RGBA")
    size = min(source.size)
    return source.crop((0, 0, size, size)).resize((64, 64), Image.Resampling.LANCZOS)


def color_signal(source, accent, zone):
    white = Image.new("L", source.size)
    for y in range(64):
        for x in range(64):
            red, green, blue, alpha = source.getpixel((x, y))
            if min(red, green, blue) > 160 and alpha > 100:
                white.putpixel((x, y), 255)
    if zone:
        inner = white.filter(ImageFilter.MinFilter(5))
        if not inner.crop(zone).getbbox():
            inner = white
        for y in range(zone[1], zone[3]):
            for x in range(zone[0], zone[2]):
                if inner.getpixel((x, y)):
                    source.putpixel((x, y), (*accent, source.getpixel((x, y))[3]))
    return source


def draw_setting_icon(kind, accent):
    scale = 4
    image = Image.new("RGBA", (64 * scale, 64 * scale))
    draw = ImageDraw.Draw(image)

    def box(bounds, fill, width=0):
        coordinates = tuple(round(value * scale) for value in bounds)
        draw.rectangle(coordinates, fill=None if width else fill,
                       outline=fill if width else None, width=width * scale)

    if kind == "statistics":
        draw.line([(8 * scale, 7 * scale), (8 * scale, 56 * scale),
                   (56 * scale, 56 * scale)], fill=WHITE, width=4 * scale)
        box((17, 34, 24, 50), WHITE)
        box((31, 22, 38, 50), WHITE)
        box((45, 10, 52, 50), WHITE)
        box((33, 27, 36, 47), accent)
    elif kind == "lane_filling":
        for top in (10, 36):
            box((7, top, 57, top + 18), WHITE, width=3)
            draw.polygon([(45 * scale, (top + 5) * scale),
                          (52 * scale, (top + 9) * scale),
                          (45 * scale, (top + 13) * scale)], fill=WHITE)
        box((13, 15, 18, 23), WHITE)
        box((23, 15, 28, 23), WHITE)
        box((33, 15, 38, 23), accent)
        box((13, 41, 18, 49), accent)
    else:
        raise ValueError(f"Unknown icon kind: {kind}")

    # Match the stock signal pictograms' dark keyline rather than adding a panel.
    keyline = Image.new("RGBA", image.size, (29, 29, 29, 0))
    keyline.putalpha(image.getchannel("A").filter(ImageFilter.MaxFilter(4 * scale + 1)))
    keyline.alpha_composite(image)
    return keyline.resize((64, 64), Image.Resampling.LANCZOS)


def normalize_visual_size(image, extent=56):
    # Sprite dimensions alone do not account for padding in native placeholder icons.
    bounds = image.getchannel("A").point(lambda value: 255 if value >= 128 else 0).getbbox()
    if not bounds:
        raise ValueError("Icon has no visible pixels")
    width, height = bounds[2] - bounds[0], bounds[3] - bounds[1]
    ratio = extent / max(width, height)
    padding = 2
    crop = image.crop((bounds[0] - padding, bounds[1] - padding,
                       bounds[2] + padding, bounds[3] + padding))
    for _ in range(3):
        size = (round(crop.width * ratio), round(crop.height * ratio))
        resized = crop.resize(size, Image.Resampling.LANCZOS)
        result = Image.new("RGBA", (64, 64))
        result.alpha_composite(resized, ((64 - size[0]) // 2, (64 - size[1]) // 2))
        measured = result.getchannel("A").point(lambda value: 255 if value >= 128 else 0).getbbox()
        visible_extent = max(measured[2] - measured[0], measured[3] - measured[1])
        if visible_extent == extent:
            break
        ratio *= extent / visible_extent
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio-data", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    atlas = Image.new("RGBA", (len(ICONS) * 64, 64))
    for column, (name, relative, accent, zone, kind) in enumerate(ICONS):
        if relative is None:
            image = draw_setting_icon(kind, accent)
        else:
            path = root / "graphics" / relative[4:] if relative.startswith("mod:") else args.factorio_data / relative
            image = load_primary(path)
        if kind == "signal":
            image = color_signal(image, accent, zone)
        elif kind in ("info", "warning"):
            # Recolor the stock black letter, retaining its exact native silhouette.
            for y in range(16, 51):
                for x in range(23, 42):
                    red, green, blue, alpha = image.getpixel((x, y))
                    if alpha > 200 and max(red, green, blue) < 80:
                        image.putpixel((x, y), (*WHITE, alpha))
        if kind in ("native", "info", "warning", "avoidance"):
            colored = Image.new("L", (64, 64))
            for y in range(64):
                for x in range(64):
                    red, green, blue, alpha = image.getpixel((x, y))
                    if alpha > 20 and max(red, green, blue) - min(red, green, blue) > 35:
                        colored.putpixel((x, y), 255)
                        image.putpixel((x, y), (*accent, alpha))
                        if kind == "avoidance" and (x-31.5)**2+(y-31.5)**2 >= 20**2:
                            image.putpixel((x, y), (*WHITE, alpha))
            if name == "quality":
                inner = colored.filter(ImageFilter.MinFilter(5))
                for y in range(64):
                    for x in range(64):
                        if colored.getpixel((x, y)) and not inner.getpixel((x, y)):
                            image.putpixel((x, y), (*WHITE, image.getpixel((x, y))[3]))
        image = normalize_visual_size(image)
        atlas.paste(image, (column * 64, 0))
        print(f"{name}: {relative or kind}")
    atlas.save(root / "graphics" / "settings-icons.png")


if __name__ == "__main__":
    main()
