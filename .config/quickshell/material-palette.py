#!/usr/bin/env python3
"""Build a wallpaper-led dark palette while retaining the shell's semantic roles."""
from dataclasses import dataclass
import json
import math
import sys

import numpy as np
from PIL import Image, ImageOps
from material_color_utilities import Hct, TonalPalette, get_contrast_ratio


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def hue_distance(first, second):
    return abs((first - second + 180) % 360 - 180)


@dataclass(frozen=True)
class Swatch:
    color: str
    population: float
    hue: float
    chroma: float
    tone: float


def image_swatches(image):
    # JPEG can decode directly at a smaller resolution. Quantize only this
    # bounded sample; no wallpaper-sized arrays or persistent image caches.
    image.draft("RGB", (256, 256))
    sample = ImageOps.exif_transpose(image)
    sample.thumbnail((256, 256), Image.Resampling.LANCZOS)
    pixels = np.asarray(sample.convert("RGBA"), dtype=np.uint8).reshape(-1, 4)
    rgb = pixels[pixels[:, 3] >= 192, :3]
    if not len(rgb):
        rgb = np.zeros((1, 3), dtype=np.uint8)
    packed = Image.fromarray(rgb.reshape(-1, 1, 3))
    quantized = packed.quantize(colors=64, method=Image.Quantize.MEDIANCUT)
    palette = quantized.getpalette()
    swatches = []
    for count, index in quantized.getcolors() or []:
        components = palette[index * 3:index * 3 + 3]
        color = "#%02x%02x%02x" % tuple(components)
        hct = Hct(color)
        swatches.append(Swatch(color, count / len(rgb), hct.hue, hct.chroma, hct.tone))
    return sorted(swatches, key=lambda swatch: (-swatch.population, swatch.color))


def color_candidates(swatches):
    # Near-neutral pixel noise must not invent a hue, but muted real colors
    # and small contrasting details should survive a large black background.
    return [s for s in swatches if s.chroma >= 10 and s.tone >= 5
            and s.population >= 0.00075]


def accent_score(swatch, candidates):
    nearby = sum(s.population for s in candidates
                 if hue_distance(s.hue, swatch.hue) <= 18)
    visibility = 0.45 + 0.55 * min(1, swatch.tone / 48)
    if swatch.tone > 90:
        visibility *= 0.6
    # Area matters, but cannot drown a visible red detail in a muted blue sky.
    return nearby ** 0.35 * swatch.chroma ** 1.2 * visibility


def atmosphere(swatches, primary):
    mean_tone = sum(s.population * s.tone for s in swatches)
    chromatic = [s for s in swatches if s.chroma >= 10 and s.tone >= 5]
    coverage = sum(s.population for s in chromatic)
    chroma_mass = sum(s.population * clamp((s.chroma - 4) / 65)
                      * min(1, s.tone / 22) for s in swatches)
    foreground = sum(s.population for s in swatches if s.tone >= 10)
    foreground_color = sum(s.population for s in chromatic if s.tone >= 10)
    foreground_ratio = foreground_color / max(foreground, 0.001)
    intensity = clamp(0.65 * math.sqrt(chroma_mass) + 0.35 * foreground_ratio)

    # This second source describes the image's atmosphere, independently of its
    # attention-grabbing accent: e.g. navy surroundings with orange branches.
    tinted = [s for s in swatches if s.chroma >= 5 and s.tone >= 3]
    if tinted:
        def family_weight(candidate):
            return sum(s.population * max(0, s.chroma - 3) ** 0.7
                       for s in tinted if hue_distance(s.hue, candidate.hue) <= 25)
        dominant = max(tinted, key=lambda s: (family_weight(s), s.population))
        family = [s for s in tinted if hue_distance(s.hue, dominant.hue) <= 25]
        weights = [s.population * max(0, s.chroma - 3) ** 0.7 for s in family]
        hue = math.degrees(math.atan2(
            sum(w * math.sin(math.radians(s.hue)) for s, w in zip(family, weights)),
            sum(w * math.cos(math.radians(s.hue)) for s, w in zip(family, weights)))) % 360
    else:
        hue = primary.hue
    return hue, intensity, coverage, mean_tone


def readable(palette, tone, backgrounds, minimum):
    # HCT's tone is perceptual lightness. Check the actual gamut-mapped RGB
    # values, rather than assuming every requested color has enough contrast.
    for value in np.arange(tone, 100.01, 0.5):
        color = palette.get(float(value))
        if all(get_contrast_ratio(color, background) >= minimum for background in backgrounds):
            return color
    return palette.get(100)


def foreground_for(background, palette):
    dark, light = palette.get(6), palette.get(98)
    return max((dark, light), key=lambda color: get_contrast_ratio(color, background))


def generate_palette(image):
    swatches = image_swatches(image)
    candidates = color_candidates(swatches)
    neutral = not candidates
    if neutral:
        primary = max(swatches, key=lambda s: s.population)
        background_hue, intensity, coverage = 0.0, 0.0, 0.0
        mean_tone = sum(s.population * s.tone for s in swatches)
    else:
        primary = max(candidates, key=lambda s: (accent_score(s, candidates), s.population, s.color))
        background_hue, intensity, coverage, mean_tone = atmosphere(swatches, primary)

    primary_hue = 0.0 if neutral else primary.hue
    # Preserve both source saturation and the balance between color and neutral
    # space. A sparse red detail gives a restrained palette; a red composition
    # gives deeper, richer accents and distinctly warm dark surfaces.
    primary_chroma = 0 if neutral else clamp(primary.chroma * (0.72 + 0.48 * intensity), 8, 100)
    primary_tone = 79 if neutral else clamp(80 - 18 * intensity + 0.06 * (primary.tone - 50), 64, 82)
    surface_chroma = 0 if neutral else 1.0 + 25 * intensity
    base_tone = 6.5 + 4.5 * mean_tone / 100

    base = TonalPalette(background_hue, surface_chroma)
    text_palette = TonalPalette(background_hue, min(7, surface_chroma * 0.3))
    accent = TonalPalette(primary_hue, primary_chroma)
    container = TonalPalette(primary_hue, primary_chroma * 0.65)

    # Prefer other actual image colors over a fixed hue rotation. Monochrome
    # images retain a monochrome secondary/tertiary palette.
    others = sorted((s for s in candidates if hue_distance(s.hue, primary_hue) >= 30),
                    key=lambda s: accent_score(s, candidates), reverse=True)
    secondary_source = others[0] if others else primary
    third = next((s for s in others if hue_distance(s.hue, secondary_source.hue) >= 30), None)
    secondary = TonalPalette(0 if neutral else secondary_source.hue,
        0 if neutral else min(64, secondary_source.chroma * (0.5 if others else 0.45)))
    tertiary = TonalPalette(0 if neutral else third.hue if third else background_hue,
        0 if neutral else min(55, third.chroma * 0.55) if third else surface_chroma * 1.4)

    p = {
        "bgDim": base.get(max(2, base_tone - 1)), "bg0": base.get(base_tone),
        "surface": base.get(base_tone + 4), "surfaceAlt": base.get(base_tone + 8),
        "surfaceRaised": base.get(base_tone + 12), "notchBg": base.get(max(2, base_tone - 3.5)),
        "border": base.get(base_tone + 26),
        "accentDark": container.get(25 + 6 * intensity),
        "accentSoft": TonalPalette(primary_hue, surface_chroma * 1.3).get(base_tone + 16),
    }
    surfaces = [p[key] for key in ("bg0", "surface", "surfaceAlt", "surfaceRaised", "accentSoft")]
    p["text"] = readable(text_palette, 91, surfaces, 7)
    p["textBright"] = readable(text_palette, 96, surfaces, 7)
    p["muted"] = readable(text_palette, 77, surfaces, 4.5)
    p["mutedStrong"] = readable(text_palette, 63, surfaces[:-1], 4.5)
    p["accent"] = readable(accent, primary_tone, surfaces, 3)
    p["onAccent"] = foreground_for(p["accent"], text_palette)
    p["onAccentContainer"] = readable(text_palette, 94, [p["accentDark"]], 4.5)
    p["aqua"] = readable(secondary, max(74, primary_tone), surfaces, 3)
    p["purple"] = readable(tertiary, max(77, primary_tone), surfaces, 3)

    # Errors and status colors keep their meaning. Their saturation/lightness
    # follow the image; hue harmonization stays within 12 degrees of the role.
    for name, seed in (("red", "#d93025"), ("green", "#4caf50"), ("blue", "#4285f4"),
                       ("yellow", "#ffca28"), ("orange", "#ff9800")):
        color = Hct(seed)
        delta = (primary_hue - color.hue + 180) % 360 - 180
        hue = color.hue if neutral else (color.hue + math.copysign(min(abs(delta) * 0.35, 12), delta)) % 360
        chroma = min(78, color.chroma * (0.62 + 0.25 * intensity))
        status = TonalPalette(hue, chroma)
        p[name] = readable(status, 78 - 5 * intensity, surfaces, 3)
        p[name + "Dark"] = status.get(28)
    p.update(
        onError=foreground_for(p["red"], text_palette),
        onErrorContainer=readable(text_palette, 94, [p["redDark"]], 4.5),
        purpleDark=tertiary.get(28), surfaceDark=p["notchBg"], greenSurface=p["greenDark"],
        redBright=TonalPalette(Hct(p["red"]).hue, Hct(p["red"]).chroma).get(84),
        textLight=p["textBright"], textWarm=p["text"], blackOverlay="#B3" + p["bg0"][1:],
        gray0=p["mutedStrong"], gray1=p["muted"], gray2=p["text"],
    )
    return {
        "seed": primary.color, "picking": "neutral" if neutral else "image-adaptive",
        "colors": p,
        "analysis": {
            "version": 2, "colored_fraction": round(coverage, 4), "intensity": round(intensity, 4),
            "mean_tone": round(mean_tone, 2), "background_hue": round(background_hue, 2),
            "surface_chroma": round(surface_chroma, 2), "source_chroma": round(primary.chroma, 2),
            "accent_tone": round(Hct(p["accent"]).tone, 2),
            "secondary_source": secondary_source.color, "tertiary_source": third.color if third else None,
        },
    }


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        raise SystemExit("usage: material-palette.py WALLPAPER")
    path = args[0]
    with Image.open(path) as image:
        result = generate_palette(image)
    print(json.dumps({"wallpaper": path, **result}))


if __name__ == "__main__":
    main()
