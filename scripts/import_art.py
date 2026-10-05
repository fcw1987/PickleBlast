#!/usr/bin/env python3
"""Import the approved handoff without modifying it. Python stdlib + macOS sips only."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from functools import lru_cache
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PickleBlast_Final_Approved_Art"
OUTPUT = ROOT / "WatchApp/Art"
ICON_OUTPUT = ROOT / "WatchApp/Assets.xcassets/AppIcon.appiconset"
BACKGROUND_APPROVED = ROOT / "ArtSources/Backgrounds/PickleblastBackground.png"
BACKGROUND_CLEAN = ROOT / "ArtSources/Backgrounds/PickleblastBackground-Atmosphere.png"
BACKGROUND_APPROVED_SHA256 = "ddef9be67835df0eb04f30a45691f987e60eeedaf1ffd748f060f7518ebefeb2"
BACKGROUND_CLEAN_SHA256 = "fb5e8d6db7a0b6e5728743003fc010d0c54e0dafb0f9d57010642f4f8432bfd3"
BACKGROUND_RUNTIME_SIZE = [512, 512]
B3_SOURCE_ROOT = ROOT / "ArtSources/Backgrounds/B3"
RETIRED_MANAGED_ART_PATHS = {"Arena.atlas/gameplay_background.png", "Arena.atlas/court_slate_b3.png"}
CLIPS = {"idle": (72, 1.5, True, None), "move_left": (32, .64, True, None),
         "move_right": (32, .64, True, None), "forehand": (49, .64, False, 20),
         "backhand": (49, .68, False, 20), "block": (37, .45, False, 16)}
CHARACTERS = {"player": ("Player/Runtime128/Player.atlas", "player_animation_manifest.json", "Player"),
              "wall": ("Bosses/Runtime128/BossWall.atlas", "boss_animation_manifest.json", "BossWall"),
              "banger": ("Bosses/Runtime128/BossBanger.atlas", "boss_animation_manifest.json", "BossBanger"),
              "poacher": ("Bosses/Runtime128/BossPoacher.atlas", "boss_animation_manifest.json", "BossPoacher"),
              "dinker": ("Bosses/Runtime128/BossDinker.atlas", "boss_animation_manifest.json", "BossDinker"),
              "lobber": ("Bosses/Runtime128/BossLobber.atlas", "boss_animation_manifest.json", "BossLobber")}
ANCHOR = [.5, .12109375]
CANVAS = [512, 512]
TRACKED_PADDLE_SEEDS = {
    # Centers were read from each approved character's own frame pixels.
    # Contact clips seed at their authored contact frame; other clips seed at
    # the first frame so the paddle is tracked in both playback directions.
    "dinker": {"idle": (41, 73), "move_left": (41, 73), "move_right": (41, 73),
               "forehand": (41, 73), "backhand": (81, 73), "block": (54, 73)},
    "lobber": {"idle": (40, 73), "move_left": (40, 73), "move_right": (40, 73),
               "forehand": (40, 73), "backhand": (80, 73), "block": (53, 73)}}
FIXTURES = ROOT / "scripts/fixtures/art_import"
MAX_JSON_BYTES = 4 * 1024 * 1024
MAX_PNG_BYTES = 16 * 1024 * 1024
MAX_IMAGE_SIDE = 4096
MAX_DECODED_BYTES = 64 * 1024 * 1024


class ArtError(ValueError):
    """A required part of the approved source contract is missing or inconsistent."""


def require(condition, message):
    if not condition:
        raise ArtError(message)


def bounded_bytes(path, limit, description):
    try:
        with path.open("rb") as handle:
            data = handle.read(limit + 1)
    except OSError as error:
        raise ArtError(f"Cannot read required {description}: {path}") from error
    require(len(data) <= limit, f"{description} exceeds size limit: {path}")
    return data


def read_json(path):
    try:
        return json.loads(bounded_bytes(path, MAX_JSON_BYTES, "metadata"),
                          parse_constant=lambda value: require(False, "Invalid coordinate: nonfinite JSON value " + value))
    except (OSError, ValueError) as error:
        raise ArtError(f"Cannot read required metadata {path}: {error}") from error


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(64 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def png_pixels(path):
    """Read noninterlaced 8-bit RGB/RGBA PNGs, including every standard row filter."""
    data = bounded_bytes(path, MAX_PNG_BYTES, "PNG")
    require(data[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG: {path}")
    offset, compressed, header, ended = 8, bytearray(), None, False
    while offset < len(data):
        require(offset + 12 <= len(data), f"Truncated PNG: {path}")
        size = struct.unpack(">I", data[offset:offset + 4])[0]
        require(offset + size + 12 <= len(data), f"Truncated PNG chunk: {path}")
        kind, payload = data[offset + 4:offset + 8], data[offset + 8:offset + 8 + size]
        crc = data[offset + 8 + size:offset + 12 + size]
        require(len(crc) == 4 and struct.unpack(">I", crc)[0] == zlib.crc32(kind + payload),
                f"PNG checksum mismatch: {path}")
        if kind == b"IHDR":
            require(header is None and offset == 8 and size == 13, f"Invalid PNG header: {path}")
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            require(header is not None, f"PNG pixel stream precedes header: {path}")
            compressed.extend(payload)
        elif kind == b"IEND":
            require(size == 0 and offset + 12 == len(data), f"Invalid PNG end: {path}")
            ended = True
            break
        offset += size + 12
    require(header is not None and ended, f"PNG is missing header or end: {path}")
    width, height, depth, color, compression, filtering, interlace = header
    require(0 < width <= MAX_IMAGE_SIDE and 0 < height <= MAX_IMAGE_SIDE and depth == 8 and color in (2, 6)
            and (compression, filtering, interlace) == (0, 0, 0), f"Unsupported PNG layout: {path}")
    channels = 4 if color == 6 else 3
    row_size = width * channels
    expected = (row_size + 1) * height
    require(expected <= MAX_DECODED_BYTES, f"PNG decoded size exceeds limit: {path}")
    try:
        decoder = zlib.decompressobj()
        raw = decoder.decompress(compressed, expected + 1)
    except zlib.error as error:
        raise ArtError(f"Invalid PNG pixel stream: {path}") from error
    require(len(raw) == expected and decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data,
            f"PNG pixel length mismatch: {path}")
    previous = bytearray(row_size)
    pixels = bytearray()
    for y in range(height):
        start = y * (row_size + 1)
        method = raw[start]
        row = bytearray(raw[start + 1:start + 1 + row_size])
        require(method in range(5), f"Invalid PNG filter: {path}")
        for x in range(row_size):
            a = row[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            if method == 1:
                prediction = a
            elif method == 2:
                prediction = b
            elif method == 3:
                prediction = (a + b) // 2
            elif method == 4:
                p = a + b - c
                distances = (abs(p - a), abs(p - b), abs(p - c))
                prediction = (a, b, c)[distances.index(min(distances))]
            else:
                prediction = 0
            row[x] = (row[x] + prediction) & 255
        pixels.extend(row)
        previous = row
    return width, height, channels, pixels


def pixel_info(path):
    width, height, channels, pixels = png_pixels(path)
    if channels == 3:
        bounds, extrema = [0, 0, width, height], [255, 255]
    else:
        alpha = pixels[3::4]
        nonzero = [i for i, value in enumerate(alpha) if value]
        require(nonzero, f"Empty transparent image: {path}")
        bounds = [min(i % width for i in nonzero), min(i // width for i in nonzero),
                  max(i % width for i in nonzero) + 1, max(i // width for i in nonzero) + 1]
        extrema = [min(alpha), max(alpha)]
    return {"pixelSize": [width, height], "alphaBounds": bounds, "alphaExtrema": extrema,
            "estimatedDecodedRGBABytes": width * height * 4}


def write_png(path, width, height, channels, pixels):
    """Canonical lossless encoding strips variable metadata, keeping technical conversions repeatable."""
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    rows = b"".join(b"\0" + pixels[y * width * channels:(y + 1) * width * channels] for y in range(height))
    content = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8,
               6 if channels == 4 else 2, 0, 0, 0)) + chunk(b"sRGB", b"\0")
               + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))
    path.write_bytes(content)


def convert_png(source, destination, size, opaque=False):
    require(shutil.which("sips") is not None, "Technical image resizing requires macOS sips")
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["sips", "--resampleHeightWidth", str(size[1]), str(size[0]), str(source),
                    "--out", str(destination)], check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.PIPE)
    width, height, channels, pixels = png_pixels(destination)
    require([width, height] == list(size), f"Incorrect conversion size: {destination}")
    if opaque and channels == 4:
        require(all(value == 255 for value in pixels[3::4]), f"Required opaque image has transparency: {source}")
        pixels = bytes(value for i, value in enumerate(pixels) if i % 4 != 3)
        channels = 3
    write_png(destination, width, height, channels, pixels)


def vector(value, length, context, bounds=None):
    require(isinstance(value, list) and len(value) == length
            and all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) for x in value),
            f"Invalid coordinate: {context}")
    if bounds:
        require(all(bounds[0] <= x <= bounds[1] for x in value), f"Out-of-canvas coordinate: {context}")
    return value


def character_manifest(source):
    """Validate supplied Player/Wall metadata and derive the approved additional boss attachments."""
    reject_symlinks(source)
    result, mappings = {}, []
    for character, (directory, manifest_name, atlas) in CHARACTERS.items():
        if character not in ("player", "wall"):
            continue
        manifest = read_json(source / "Docs" / manifest_name)
        clips = manifest["animations"] if character == "player" else manifest["bosses"]["wall"]["animations"]
        require(set(clips) == set(CLIPS), f"{character}: required clip set differs")
        character_data = {"atlas": atlas, "canvasSize": CANVAS, "anchor": ANCHOR, "clips": {}}
        expected_files = set()
        if character == "player":
            locomotion = manifest["locomotion"]
            require(locomotion["stride_in_source_coordinates"] == 26 and locomotion["source_canvas_width"] == 512,
                    "Player locomotion stride contract differs")
        for clip, (count, duration, loop, contact) in CLIPS.items():
            context = f"{character}/{clip}"
            specification = clips[clip]
            legacy_metadata = f"Docs/{clip}_frames.json" if character == "player" else f"Docs/Frames/wall/{clip}.json"
            actual_metadata = f"Docs/player_{clip}_frames.json" if character == "player" else f"Docs/boss_{clip}.json"
            require(specification["metadata"] == legacy_metadata, f"{context}: unexpected metadata mapping")
            require(specification.get("source_canvas", manifest.get("source_canvas")) == CANVAS
                    and specification.get("spritekit_anchor", manifest.get("spritekit_anchor")) == ANCHOR,
                    f"{context}: source canvas or anchor differs")
            require(specification["duration_seconds"] == duration and specification["loop"] is loop,
                    f"{context}: duration or loop contract differs")
            require(specification["contact_index_zero_based"] == contact, f"{context}: contact index differs")
            names, timestamps = specification["files"], specification["timestamps_seconds"]
            frames = read_json(source / actual_metadata)
            require(len(names) == len(timestamps) == len(frames) == count, f"{context}: frame count differs")
            require(all(isinstance(t, (int, float)) and not isinstance(t, bool) and math.isfinite(t) for t in timestamps)
                    and timestamps[0] == 0 and all(a < b for a, b in zip(timestamps, timestamps[1:])),
                    f"{context}: timestamps must increase strictly from zero")
            require(timestamps[-1] < duration if loop else timestamps[-1] == duration,
                    f"{context}: timestamp endpoint does not match loop/duration")
            require(specification["contact_time_seconds"] == (None if contact is None else timestamps[contact]),
                    f"{context}: contact time/index mismatch")
            stride = (-26 if clip == "move_left" else 26) if clip.startswith("move_") else None
            if character == "wall" and stride is not None:
                require(specification["cycle_travel_source_pixels"] == stride, f"{context}: stride differs")
            normalized = {"duration": duration, "loop": loop, "contactIndex": contact,
                          "strideSourcePixels": stride, "frames": []}
            for index, (name, timestamp, frame) in enumerate(zip(names, timestamps, frames)):
                require(isinstance(frame, dict), f"{context}: invalid frame metadata")
                prefix = "player" if character == "player" else "boss_wall"
                require(name == f"{prefix}_{clip}_{index + 1:03}.png", f"{context}: invalid filename/index: {name}")
                identity_matches = frame.get("character") == "wall" if character == "wall" else frame.get("character", "player") == "player"
                require(frame["filename"] == name and frame["index"] == index and frame["clip"] == clip
                        and identity_matches, f"{context}: metadata frame identity mismatch")
                require(frame["timestamp_seconds"] == timestamp, f"{context}: metadata timestamp mismatch")
                require(abs(frame["time_normalized"] - timestamp / duration) < 1e-6,
                        f"{context}: normalized frame time mismatch")
                require(frame["root_px"] == [256, 450], f"{context}: root registration differs")
                for field in ("root", "paddle_center", "wrist"):
                    point = vector(frame[field + "_px"], 2, context + "/" + field, (0, 512))
                    unit = vector(frame[field + "_normalized"], 2, context + "/" + field + " normalized", (0, 1))
                    require(all(abs(a / 512 - b) < 1e-7 for a, b in zip(point, unit)),
                            f"{context}: attachment normalization mismatch")
                basis_x = vector(frame["paddle_basis_x"], 2, context + "/basis_x")
                basis_y = vector(frame["paddle_basis_y"], 2, context + "/basis_y")
                require(abs(basis_x[0] * basis_y[1] - basis_x[1] * basis_y[0]) > 1e-5,
                        f"{context}: degenerate paddle transform")
                bounds = vector(frame["bounds512"], 4, context + "/bounds", (0, 512))
                require(bounds[0] < bounds[2] and bounds[1] < bounds[3], f"{context}: empty art bounds")
                source_path = source / directory / name
                require(source_path.is_file(), f"Missing required frame: {source_path}")
                header = bounded_bytes(source_path, MAX_PNG_BYTES, "PNG")[:24]
                require(len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", header[16:24]) == (128, 128),
                        f"{context}: required runtime PNG is not 128x128: {name}")
                expected_files.add(name)
                normalized["frames"].append({"name": source_path.stem, "timestamp": timestamp,
                    "paddleCenter": frame["paddle_center_px"], "wrist": frame["wrist_px"], "bounds": bounds})
            character_data["clips"][clip] = normalized
            mappings.append({"character": character, "clip": clip, "legacyMetadata": legacy_metadata,
                             "sourceMetadata": actual_metadata, "sourceMetadataSHA256": digest(source / actual_metadata),
                             "sourceDirectory": directory, "atlas": atlas})
        require({p.name for p in (source / directory).glob("*.png")} == expected_files,
                f"{character}: runtime atlas contains unlisted/missing frames")
        result[character] = character_data
    add_derived_bosses(source, result, mappings)
    return result, mappings



def paddle_core(image, center, context):
    """Deterministic connected blue paddle-head component near the shared pose anchor."""
    width, height, channels, pixels = image
    require((width, height, channels) == (128, 128, 4), f"{context}: required runtime PNG is not 128x128 RGBA")
    cx, cy = center
    candidates = set()
    for y in range(max(0, int(cy) - 12), min(height, int(cy) + 13)):
        for x in range(max(0, int(cx) - 12), min(width, int(cx) + 13)):
            offset = (y * width + x) * 4
            r, g, b, a = pixels[offset:offset + 4]
            if a > 100 and b > r + 20 and b > g + 10 and b > 40:
                candidates.add((x, y))
    components = []
    while candidates:
        seed = min(candidates)
        candidates.remove(seed)
        component, queue = {seed}, [seed]
        while queue:
            x, y = queue.pop()
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in candidates:
                    candidates.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        if len(component) >= 5:
            components.append(component)
    require(bool(components), f"{context}: cannot identify approved paddle core")
    return min(components, key=lambda part: (min((x - cx)**2 + (y - cy)**2 for x, y in part), -len(part), min(part)))


def derived_boss_frame(source, character, clip, index, template, images):
    wall_name = template["name"] + ".png"
    name = f"boss_{character}_{clip}_{index + 1:03}.png"
    wall_path = source / CHARACTERS["wall"][0] / wall_name
    target_path = source / CHARACTERS[character][0] / name
    require(target_path.is_file(), f"Missing required frame: {target_path}")
    if wall_name not in images:
        images[wall_name] = png_pixels(wall_path)
    image = png_pixels(target_path)
    center = [value / 4 for value in template["paddleCenter"]]
    reference = paddle_core(images[wall_name], center, wall_name)
    target = paddle_core(image, center, name)
    def centroid(points):
        return [sum(p[axis] for p in points) / len(points) for axis in (0, 1)]
    delta = [b - a for a, b in zip(centroid(reference), centroid(target))]
    shifted = {(x - round(delta[0]), y - round(delta[1])) for x, y in target}
    overlap = len(reference & shifted) / len(reference | shifted)
    require(math.hypot(*delta) <= 6 and overlap >= .50, f"{name}: derived paddle registration exceeds verified pose envelope")
    alpha_points = [(i % 128, i // 128) for i, a in enumerate(image[3][3::4]) if a]
    require(bool(alpha_points), f"{name}: empty image")
    bounds = [min(x for x, y in alpha_points) * 4, min(y for x, y in alpha_points) * 4,
              (max(x for x, y in alpha_points) + 1) * 4, (max(y for x, y in alpha_points) + 1) * 4]
    return {"name": Path(name).stem, "timestamp": template["timestamp"],
            "paddleCenter": [round(a + b * 4, 6) for a, b in zip(template["paddleCenter"], delta)],
            "wrist": template["wrist"], "bounds": bounds}, {"maximumShift128": math.hypot(*delta), "alignedCoreOverlap": overlap}


@lru_cache(maxsize=12)
def tracked_paddle_centers(images, character, clip, contact_index):
    """Track the embedded paddle from that character's own pixels, never a Wall pose map.

    The first idle image was visually calibrated per approved character. Subsequent
    centers follow a small pixel patch around the face, using only adjacent frames.
    A color check catches missing or replaced paddles even when a flat image would
    otherwise produce a deceptively perfect match.
    """
    seed = TRACKED_PADDLE_SEEDS[character][clip]
    palette = {
        "dinker": lambda r, g, b, a: a > 100 and g > r + 10 and b > r + 15 and g > 50,
        "lobber": lambda r, g, b, a: a > 100 and r > g + 10 and b > g + 20 and r > 50,
    }[character]
    radius, search = 7, 6

    def accent_count(image, center):
        x0, y0 = center
        count = 0
        for y in range(y0 - 5, y0 + 6):
            for x in range(x0 - 5, x0 + 6):
                offset = (y * 128 + x) * 4
                if palette(*image[offset:offset + 4]):
                    count += 1
        return count

    def match_score(first, second, center, candidate):
        x0, y0 = center
        x1, y1 = candidate
        total = 0
        sample_offsets = range(-radius, radius + 1, 2)
        for dy in sample_offsets:
            for dx in sample_offsets:
                first_offset = ((y0 + dy) * 128 + x0 + dx) * 4
                second_offset = ((y1 + dy) * 128 + x1 + dx) * 4
                first_alpha, second_alpha = first[first_offset + 3], second[second_offset + 3]
                total += 2 * abs(first_alpha - second_alpha)
                visible = min(first_alpha, second_alpha) / 255
                total += sum(abs(first[first_offset + channel] - second[second_offset + channel])
                             for channel in range(3)) * visible
        return total / (len(sample_offsets) ** 2)

    anchor_index = contact_index if contact_index is not None else 0
    centers = [None] * len(images)
    centers[anchor_index] = seed
    scores = [0.0] * len(images)
    accents = [0] * len(images)

    def signature(image, center):
        count = accent_count(image, center)
        require(count >= 1, f"{character}/{clip}: tracked paddle lost its approved color signature")
        return count

    accents[anchor_index] = signature(images[anchor_index], seed)
    directions = (range(anchor_index + 1, len(images)), range(anchor_index - 1, -1, -1))
    for indices in directions:
        for index in indices:
            previous_index = index - 1 if index > anchor_index else index + 1
            previous = images[previous_index]
            current = images[index]
            center = centers[previous_index]
            candidates = []
            for dx in range(-search, search + 1):
                for dy in range(-search, search + 1):
                    candidate = (center[0] + dx, center[1] + dy)
                    if radius <= candidate[0] < 128 - radius and radius <= candidate[1] < 128 - radius:
                        candidates.append((match_score(previous, current, center, candidate), candidate))
            score, selected = min(candidates)
            require(score <= 260, f"{character}/{clip}/{index + 1:03}: approved paddle tracking lost image registration ({score:.1f})")
            require(24 <= selected[0] <= 104 and 48 <= selected[1] <= 94,
                    f"{character}/{clip}: paddle left its verified pixel envelope")
            centers[index] = selected
            scores[index] = score
            accents[index] = signature(current, selected)
    return tuple(centers), tuple(scores), tuple(accents)


def detected_wrist(image, center, context):
    """Find the warm skin pixels at the hand joined to the embedded paddle."""
    x0, y0 = center
    candidates = set()
    for y in range(max(0, y0 - 24), min(128, y0 + 25)):
        for x in range(max(0, x0 - 24), min(128, x0 + 25)):
            offset = (y * 128 + x) * 4
            r, g, b, alpha = image[offset:offset + 4]
            if alpha > 100 and (x - x0) ** 2 + (y - y0) ** 2 <= 576 \
                    and r > g * 1.12 and g > b * 1.1 and r > 65 and g > 35 and b < 190:
                candidates.add((x, y))
    components = []
    while candidates:
        seed = min(candidates)
        candidates.remove(seed)
        component, queue = {seed}, [seed]
        while queue:
            x, y = queue.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    neighbor = (x + dx, y + dy)
                    if (dx or dy) and neighbor in candidates:
                        candidates.remove(neighbor)
                        component.add(neighbor)
                        queue.append(neighbor)
        if len(component) >= 2:
            components.append(component)
    if not components:
        # A few approved poses fully cover the hand with the paddle grip. The
        # attachment point remains the character-specific visible paddle center.
        return [x0 * 4, y0 * 4]
    points = min(components, key=lambda component: (
        (sum(x for x, _ in component) / len(component) - x0) ** 2
        + (sum(y for _, y in component) / len(component) - y0) ** 2,
        -len(component)))
    return [sum(x for x, _ in points) / len(points) * 4,
            sum(y for _, y in points) / len(points) * 4]


def tracked_boss_frames(source, character, clip, spec, directory):
    """Build clip metadata from the approved character images and that character's timing."""
    names = [f"boss_{character}_{clip}_{index + 1:03}.png" for index in range(CLIPS[clip][0])]
    require(spec["files"] == names, f"{character}/{clip}: invalid filename/index")
    timestamps = spec["timestamps_seconds"]
    count, duration, loop, contact = CLIPS[clip]
    require(spec["duration_seconds"] == duration and spec["loop"] is loop,
            f"{character}/{clip}: duration or loop contract differs")
    require(spec["contact_index_zero_based"] == contact,
            f"{character}/{clip}: contact index differs")
    require(len(timestamps) == count and all(isinstance(t, (int, float)) and not isinstance(t, bool)
            and math.isfinite(t) for t in timestamps) and timestamps[0] == 0
            and all(a < b for a, b in zip(timestamps, timestamps[1:])),
            f"{character}/{clip}: timestamps must increase strictly from zero")
    require(timestamps[-1] < duration if loop else timestamps[-1] == duration,
            f"{character}/{clip}: timestamp endpoint does not match loop/duration")
    require(spec["contact_time_seconds"] == (None if contact is None else timestamps[contact]),
            f"{character}/{clip}: contact time/index mismatch")
    stride = (-26 if clip == "move_left" else 26) if clip.startswith("move_") else None
    if stride is not None:
        require(spec["cycle_travel_source_pixels"] == stride,
                f"{character}/{clip}: stride differs")
    images = []
    for name in names:
        path = source / directory / name
        require(path.is_file(), f"Missing required frame: {path}")
        image = png_pixels(path)
        require(image[:3] == (128, 128, 4), f"{character}/{clip}: required runtime PNG is not 128x128 RGBA")
        images.append(bytes(image[3]))
    centers, scores, accents = tracked_paddle_centers(tuple(images), character, clip, contact)
    frames = []
    for index, (name, timestamp, image, center) in enumerate(zip(names, timestamps, images, centers)):
        alpha = image[3::4]
        alpha_points = [(pixel % 128, pixel // 128) for pixel, value in enumerate(alpha) if value]
        require(bool(alpha_points), f"{character}/{clip}: empty approved frame: {name}")
        bounds = [min(x for x, _ in alpha_points) * 4, min(y for _, y in alpha_points) * 4,
                  (max(x for x, _ in alpha_points) + 1) * 4,
                  (max(y for _, y in alpha_points) + 1) * 4]
        frames.append({"name": Path(name).stem, "timestamp": timestamp,
                       "paddleCenter": [center[0] * 4, center[1] * 4],
                       "wrist": detected_wrist(image, center, f"{character}/{clip}/{name}"),
                       "bounds": bounds})
    return {"duration": duration, "loop": loop, "contactIndex": contact,
            "strideSourcePixels": stride, "frames": frames}, {
                "maximumTrackingError": max(scores, default=0),
                "meanTrackingError": sum(scores) / len(scores) if scores else 0,
                "minimumAccentPixels": min(accents),
                "calibratedPixelAnchor": list(TRACKED_PADDLE_SEEDS[character][clip]),
                "minimumAccentPixels": min(accents)}


def add_derived_bosses(source, result, mappings):
    """The handoff has no per-frame attachment JSON for these bosses.

    Preserve their exact approved images/timing. Register their own detected paddle
    heads against the verified Wall pose. Wrist is an unused shared-template datum;
    runtime renders one intact frame and never moves or stretches a separate limb.
    """
    manifest = read_json(source / "Docs/boss_animation_manifest.json")
    require(manifest["source_canvas"] == CANVAS and manifest["spritekit_anchor"] == ANCHOR,
            "Boss source canvas or anchor differs")
    images = {}
    for character in ("banger", "poacher"):
        directory, _, atlas = CHARACTERS[character]
        clips = manifest["bosses"][character]["animations"]
        require(set(clips) == set(CLIPS), f"{character}: required clip set differs")
        data = {"atlas": atlas, "canvasSize": CANVAS, "anchor": ANCHOR, "clips": {}}
        expected = set()
        for clip, (count, duration, loop, contact) in CLIPS.items():
            spec, template = clips[clip], result["wall"]["clips"][clip]
            context = f"{character}/{clip}"
            legacy = f"Docs/Frames/{character}/{clip}.json"
            require(spec["metadata"] == legacy, f"{context}: unexpected metadata mapping")
            require(spec["duration_seconds"] == duration and spec["loop"] is loop,
                    f"{context}: duration or loop contract differs")
            require(spec["contact_index_zero_based"] == contact and spec["contact_time_seconds"] ==
                    (None if contact is None else template["frames"][contact]["timestamp"]), f"{context}: contact index/time differs")
            require(spec["timestamps_seconds"] == [f["timestamp"] for f in template["frames"]], f"{context}: timestamps differ from approved shared pose")
            names = [f"boss_{character}_{clip}_{i + 1:03}.png" for i in range(count)]
            require(spec["files"] == names, f"{context}: invalid filename/index")
            stride = template["strideSourcePixels"]
            if stride is not None:
                require(spec["cycle_travel_source_pixels"] == stride, f"{context}: stride differs")
            frames, measurements = [], []
            for i, frame in enumerate(template["frames"]):
                derived, measurement = derived_boss_frame(source, character, clip, i, frame, images)
                frames.append(derived); measurements.append(measurement)
            expected.update(names)
            data["clips"][clip] = {"duration": duration, "loop": loop, "contactIndex": contact,
                                    "strideSourcePixels": stride, "frames": frames}
            mappings.append({"character": character, "clip": clip, "legacyMetadata": legacy,
                "sourceMetadata": f"Docs/boss_{clip}.json", "sourceMetadataSHA256": digest(source / f"Docs/boss_{clip}.json"),
                "sourceDirectory": directory, "atlas": atlas, "registration": "image-derived paddle-core centroid relative to shared Wall pose; own alpha bounds; template wrist unused at runtime",
                "maximumShift128": max(m["maximumShift128"] for m in measurements),
                "minimumAlignedCoreOverlap": min(m["alignedCoreOverlap"] for m in measurements)})
        require({p.name for p in (source / directory).glob("*.png")} == expected, f"{character}: runtime atlas contains unlisted/missing frames")
        result[character] = data

    # Dinker and Lobber exports do not include the per-frame attachment JSON
    # supplied for Wall. Track each approved character's paddle in its own
    # images and keep the original v4.2 timestamps and contact indices.
    for character in ("dinker", "lobber"):
        directory, _, atlas = CHARACTERS[character]
        source_boss = manifest["bosses"][character]
        require(source_boss["name"] == "The " + character.title()
                and source_boss["atlas"] == atlas + ".atlas",
                f"{character}: approved character identity differs")
        clips = source_boss["animations"]
        require(set(clips) == set(CLIPS), f"{character}: required clip set differs")
        data = {"atlas": atlas, "canvasSize": CANVAS, "anchor": ANCHOR, "clips": {}}
        expected = set()
        for clip in CLIPS:
            spec = clips[clip]
            context = f"{character}/{clip}"
            legacy = f"Docs/Frames/{character}/{clip}.json"
            require(spec["metadata"] == legacy, f"{context}: unexpected metadata mapping")
            animation, tracking = tracked_boss_frames(source, character, clip, spec, directory)
            data["clips"][clip] = animation
            expected.update(frame["name"] + ".png" for frame in animation["frames"])
            mappings.append({"character": character, "clip": clip, "legacyMetadata": legacy,
                "sourceMetadata": f"Docs/boss_animation_manifest.json#/bosses/{character}/animations/{clip}",
                "sourceMetadataSHA256": digest(source / "Docs/boss_animation_manifest.json"),
                "sourceDirectory": directory, "atlas": atlas,
                "registration": "own-image paddle-template tracking from the character's calibrated pixel anchor; own detected hand pixels and alpha bounds",
                **tracking})
        require({p.name for p in (source / directory).glob("*.png")} == expected,
                f"{character}: runtime atlas contains unlisted/missing frames")
        result[character] = data


def supporting_allowlist():
    result = {"ball": ("Ball/ball_normal.png", "Pickleball", [128, 128]),
              "wordmark": ("Brand/pickleblast_wordmark.png", "Brand", [700, 180])}
    for color in ("cyan", "lime", "magenta"):
        for hit in (False, True):
            result["targetPaddle" + color.title() + ("Hit" if hit else "")] = (
                f"Targets/Paddles/target_paddle_{color}{'_hit' if hit else ''}.png", "Targets", [128, 128])
    for key, name in {"targetCone": "target_cone", "targetConeHit": "target_cone_hit",
                      "targetBasket": "target_basket", "targetBasketDamaged": "target_basket_damaged"}.items():
        result[key] = (f"Targets/Objects/{name}.png", "Targets", [128, 128])
    for category, prefix, count in (("Hit", "hit", 6), ("Perfect", "perfect", 6),
                                     ("WaveClear", "wave", 8), ("BossDefeat", "boss", 8)):
        for index in range(1, count + 1):
            result[f"effect{prefix.title()}{index:02}"] = (
                f"Effects/{category}/effect_{prefix}_{index:02}.png", "Effects", [128, 128])
    for suffix in ("heart_full", "heart_empty", "play", "pause", "restart", "settings", "close", "crown"):
        result["ui" + "".join(part.title() for part in suffix.split("_"))] = (f"UI/ui_{suffix}.png", "UI", [64, 64])
    return result


def icon_entries():
    images = []
    # Apple's app-icon schema assigns 24pt to 38mm and 27.5pt to 42mm Watches.
    for role, sizes in (("notificationCenter", [("38mm", 24), ("42mm", 27.5)]),
                        ("appLauncher", [("38mm", 40), ("40mm", 44), ("41mm", 46), ("44mm", 50), ("45mm", 51), ("49mm", 54)]),
                        ("quickLook", [("38mm", 86), ("42mm", 98), ("44mm", 108), ("45mm", 117), ("49mm", 129)])):
        for subtype, size in sizes:
            images.append({"idiom": "watch", "role": role, "subtype": subtype, "size": f"{size}x{size}",
                           "scale": "2x", "filename": f"icon-{int(size * 2)}.png"})
    for scale in (2, 3):
        images.append({"idiom": "watch", "role": "companionSettings", "size": "29x29", "scale": f"{scale}x",
                       "filename": f"icon-settings-{29 * scale}.png"})
    images.append({"idiom": "watch-marketing", "size": "1024x1024", "scale": "1x", "filename": "icon-1024.png"})
    return images


def environment_allowlist():
    """Only the separately authored B3 layers may enter the runtime atlas."""
    return {
        "backgroundArena": {"source": B3_SOURCE_ROOT / "arena-b3-source.png",
            "sourceSHA256": "2a88476385147cd27aa4540413b4a20f90144532d0657fa3f518b5286d8facd3",
            "sourceSize": [1254, 1254], "atlas": "Arena", "name": "arena_b3"},
        # SKShapeNode.fillTexture can sample the entire compiled atlas page.
        # Keep this material isolated: packing scenery beside it corrupts native court fills.
        "courtSlateB3": {"source": B3_SOURCE_ROOT / "court-slate-b3-source.png",
            "sourceSHA256": "7596e030f31b24aa03c8cc2342f76764cd69327edf3e6ad79bfcbc0bc2bbbdb5",
            "sourceSize": [1254, 1254], "atlas": "CourtMaterial", "name": "court_slate_b3"}}


def validate_environment_source(path, expected_hash, size):
    require(not any(parent.is_symlink() for parent in (path, *path.parents)),
            "Environment source must not use symlinks")
    require(path.is_file() and digest(path) == expected_hash,
            f"Approved environment source differs or is missing: {path.name}")
    info = pixel_info(path)
    require(info["pixelSize"] == size and info["alphaExtrema"] == [255, 255],
            f"Approved environment source dimensions or opacity differ: {path.name}")
    return info


def background_history():
    """Retain and validate the original approved masters without bundling them."""
    validate_environment_source(BACKGROUND_APPROVED, BACKGROUND_APPROVED_SHA256, [1254, 1254])
    validate_environment_source(BACKGROUND_CLEAN, BACKGROUND_CLEAN_SHA256, [1254, 1254])
    return {"approvedFilename": BACKGROUND_APPROVED.name,
        "approvedSource": str(BACKGROUND_APPROVED.relative_to(ROOT)), "approvedSHA256": BACKGROUND_APPROVED_SHA256,
        "cleanSource": str(BACKGROUND_CLEAN.relative_to(ROOT)), "cleanSHA256": BACKGROUND_CLEAN_SHA256,
        "status": "Historical approved masters retained unchanged; replaced in runtime by B3 layers."}


def environment_sources():
    result = {}
    for key, specification in sorted(environment_allowlist().items()):
        path = specification["source"]
        validate_environment_source(path, specification["sourceSHA256"], specification["sourceSize"])
        result[key] = {"source": str(path.relative_to(ROOT)), "sourceSHA256": specification["sourceSHA256"],
            "sourceSize": specification["sourceSize"], "runtimeSize": BACKGROUND_RUNTIME_SIZE,
            "destination": f"{specification['atlas']}.atlas/{specification['name']}.png"}
    return result


def generate(source, art, icons):
    historical_background = background_history()
    environment = environment_sources()
    characters, mappings = character_manifest(source)
    art.mkdir(parents=True, exist_ok=True)
    icons.mkdir(parents=True, exist_ok=True)
    manifest = {"schemaVersion": 1, "characters": characters, "supporting": {}}
    resources, selected = [], set()

    def record(source_relative, destination, kind, extra=None, source_root=source):
        source_file = source_root / source_relative
        info = pixel_info(destination)
        resources.append({"kind": kind, "source": source_relative, "sourceSHA256": digest(source_file),
            "destination": str(destination.relative_to(icons if kind == "appIcon" else art)),
            "pngBytes": destination.stat().st_size, "sha256": digest(destination), **info, **(extra or {})})
        if source_root == source:
            selected.add(source_relative)
        return info

    for character, data in characters.items():
        directory = CHARACTERS[character][0]
        destination_dir = art / (data["atlas"] + ".atlas")
        destination_dir.mkdir()
        for clip in data["clips"].values():
            for frame in clip["frames"]:
                name = frame["name"] + ".png"
                relative = f"{directory}/{name}"
                destination = destination_dir / name
                shutil.copyfile(source / relative, destination)
                info = record(relative, destination, "character", {"character": character})
                require(info["alphaExtrema"] == [0, 255], f"Character alpha contract differs: {relative}")
    for key, (relative, atlas, size) in sorted(supporting_allowlist().items()):
        source_file = source / relative
        require(source_file.is_file(), f"Missing required support asset: {relative}")
        original = pixel_info(source_file)
        require(original["pixelSize"] == ([1400, 360] if key == "wordmark" else [256, 256]),
                f"Support source dimensions differ: {relative}")
        require(original["alphaExtrema"][0] == 0, f"Support artwork has an opaque matte: {relative}")
        destination = art / (atlas + ".atlas") / source_file.name
        convert_png(source_file, destination, size)
        info = record(relative, destination, "support", {"semanticKey": key})
        manifest["supporting"][key] = {"atlas": atlas, "name": source_file.stem,
                                      "pixelSize": info["pixelSize"], "alphaBounds": info["alphaBounds"]}
    for key, specification in environment.items():
        destination = art / specification["destination"]
        convert_png(ROOT / specification["source"], destination, BACKGROUND_RUNTIME_SIZE, opaque=True)
        info = record(specification["source"], destination, "environment", {"semanticKey": key}, source_root=ROOT)
        manifest["supporting"][key] = {"atlas": destination.parent.stem, "name": destination.stem,
            "pixelSize": info["pixelSize"], "alphaBounds": info["alphaBounds"]}
    icon_source = "AppIcon/app_icon_1024.png"
    icon_info = pixel_info(source / icon_source)
    require(icon_info["pixelSize"] == [1024, 1024] and icon_info["alphaExtrema"] == [255, 255],
            "Supplied app icon must be opaque and 1024x1024")
    entries = icon_entries()
    for entry in entries:
        size = round(float(entry["size"].split("x")[0]) * int(entry["scale"][0]))
        destination = icons / entry["filename"]
        convert_png(source / icon_source, destination, [size, size], opaque=True)
        record(icon_source, destination, "appIcon")
    (icons / "Contents.json").write_bytes(json_bytes({"images": entries, "info": {"author": "xcode", "version": 1}}))
    (art / "runtime_manifest.json").write_bytes(json_bytes(manifest))
    omitted = sorted(str(path.relative_to(source)) for path in source.rglob("*.png") if str(path.relative_to(source)) not in selected)
    groups = {}
    for item in resources:
        group = item["destination"].split("/")[0] if item["kind"] != "appIcon" else "AppIcon.appiconset"
        total = groups.setdefault(group, {"images": 0, "pngBytes": 0, "estimatedDecodedRGBABytes": 0})
        for key, value in {"images": 1, "pngBytes": item["pngBytes"],
                           "estimatedDecodedRGBABytes": item["estimatedDecodedRGBABytes"]}.items():
            total[key] += value
    require(groups.get("CourtMaterial.atlas", {}).get("images") == 1,
            "CourtMaterial must remain a single-image atlas for native shape fills")
    audit = {"schemaVersion": 1, "sourcePack": "PickleBlast_Final_Approved_Art", "sourcePackModified": False,
        "approval": "Approved Player, Wall, Banger and Poacher runtime art; additional bosses explicitly selected by Boss Rally request. Paddle registration for Banger/Poacher is image-derived from their own frames and the shared Wall pose template.",
        "metadataMappings": mappings, "resources": resources, "groups": groups, "omittedOptionalPNGs": omitted,
        "backgroundSource": historical_background, "environmentSources": environment,
        "sourceManifestSHA256": {name: digest(source / "Docs" / name) for name in ("player_animation_manifest.json", "boss_animation_manifest.json")},
        "estimationNote": "Decoded RGBA estimates are width * height * 4. They exclude atlas packing, mipmaps, upload copies and renderer overhead; PNG bytes are measured.",
        "managedArtPaths": sorted(str(path.relative_to(art)) for path in art.rglob("*") if path.is_file()) + ["import_audit.json"],
        "managedIconPaths": sorted(path.name for path in icons.iterdir())}
    (art / "import_audit.json").write_bytes(json_bytes(audit))
    return manifest, audit


def reject_symlinks(root):
    require(not root.is_symlink(), "Source or output root must not be a symlink")
    if root.exists():
        require(root.is_dir(), "Source or output root must be a directory")
        require(not any(path.is_symlink() for path in root.rglob("*")),
                "Source or output tree must not contain symlinks")


def relative_resource_path(value):
    require(isinstance(value, str) and value and "\\" not in value
            and not Path(value).is_absolute() and all(part not in ("", ".", "..") for part in value.split("/")),
            "Invalid managed resource path")
    return value


def managed_path_sets():
    art = {"runtime_manifest.json", "import_audit.json"}
    art.update(f"{specification['atlas']}.atlas/{specification['name']}.png"
               for specification in environment_allowlist().values())
    for character, (_, _, atlas) in CHARACTERS.items():
        prefix = "player" if character == "player" else "boss_" + character
        for clip, (count, _, _, _) in CLIPS.items():
            art.update(f"{atlas}.atlas/{prefix}_{clip}_{index:03}.png" for index in range(1, count + 1))
    art.update(f"{atlas}.atlas/{Path(relative).name}" for relative, atlas, _ in supporting_allowlist().values())
    icons = {entry["filename"] for entry in icon_entries()} | {"Contents.json"}
    return art, icons


def install_plan(staged, destination, paths, previous_paths):
    require(isinstance(paths, list) and isinstance(previous_paths, list), "Managed resource paths must be lists")
    require(len(paths) <= 2500 and len(previous_paths) <= 2500, "Too many managed resource paths")
    current = [relative_resource_path(path) for path in paths]
    previous = [relative_resource_path(path) for path in previous_paths]
    require(len(set(current)) == len(current) and len(set(previous)) == len(previous), "Duplicate managed resource path")
    owned_art, owned_icons = managed_path_sets()
    require(set(current) <= owned_art | owned_icons, "Unexpected managed resource path")
    require(set(previous) <= owned_art | owned_icons | RETIRED_MANAGED_ART_PATHS,
            "Unexpected previous managed resource path")
    reject_symlinks(staged)
    reject_symlinks(destination)
    root = destination.resolve()
    for relative in set(current) | set(previous):
        path = root / relative
        require(path.resolve().is_relative_to(root), "Invalid managed resource path")
        require(not path.exists() or path.is_file(), "Managed resource destination is not a file")
        parent = path.parent
        while parent != root:
            require(not parent.exists() or parent.is_dir(), "Managed resource parent is not a directory")
            parent = parent.parent
    for relative in current:
        require((staged / relative).is_file(), "Missing staged managed resource")
    return current, previous


def install_tree(staged, destination, paths, previous_paths, check):
    paths, previous_paths = install_plan(staged, destination, paths, previous_paths)
    for relative in paths:
        source_file, destination_file = staged / relative, destination / relative
        if check:
            require(destination_file.is_file() and source_file.read_bytes() == destination_file.read_bytes(),
                    f"Generated resource differs or is missing; run scripts/import_art.py: {destination_file}")
        else:
            destination_file.parent.mkdir(parents=True, exist_ok=True)
            if not destination_file.is_file() or source_file.read_bytes() != destination_file.read_bytes():
                # Replacing a completed local temporary file also avoids mutating
                # another file if a destination has an existing hard link.
                with tempfile.NamedTemporaryFile(dir=destination_file.parent, prefix=".art-import-", delete=False) as handle:
                    temporary = Path(handle.name)
                try:
                    shutil.copyfile(source_file, temporary)
                    os.replace(temporary, destination_file)
                finally:
                    temporary.unlink(missing_ok=True)
    for obsolete in set(previous_paths) - set(paths):
        path = (destination / obsolete).resolve()
        require(path.is_relative_to(destination.resolve()), "Invalid previous managed resource path")
        if check:
            require(not path.exists(), f"Obsolete generated resource remains: {path}")
        elif path.is_file():
            path.unlink()


def run(source=SOURCE, output=OUTPUT, icon_output=ICON_OUTPUT, check=False):
    reject_symlinks(source)
    reject_symlinks(output)
    reject_symlinks(icon_output)
    source, output, icon_output = source.resolve(), output.resolve(), icon_output.resolve()
    require(source.is_dir(), f"Approved source pack is missing: {source}")
    require(not output.is_relative_to(source) and not icon_output.is_relative_to(source)
            and not source.is_relative_to(output) and not source.is_relative_to(icon_output),
            "Outputs must be outside immutable source pack and cannot contain it")
    require(not output.is_relative_to(icon_output) and not icon_output.is_relative_to(output), "Output trees must not overlap")
    environment_root = BACKGROUND_APPROVED.parent.resolve()
    require(all(not destination.is_relative_to(environment_root) and not environment_root.is_relative_to(destination)
                for destination in (output, icon_output)), "Outputs must not overlap immutable environment sources")
    previous = read_json(output / "import_audit.json") if (output / "import_audit.json").exists() else {}
    require(isinstance(previous, dict), "Previous import audit must be an object")
    # Complete validation/conversion in a staging directory before replacing managed output files.
    with tempfile.TemporaryDirectory(prefix="pickleblast-art-") as temporary:
        stage = Path(temporary)
        manifest, audit = generate(source, stage / "Art", stage / "Icon")
        # Validate both output trees before the first managed file can change.
        install_plan(stage / "Art", output, audit["managedArtPaths"], previous.get("managedArtPaths", []))
        install_plan(stage / "Icon", icon_output, audit["managedIconPaths"], previous.get("managedIconPaths", []))
        install_tree(stage / "Art", output, audit["managedArtPaths"], previous.get("managedArtPaths", []), check)
        install_tree(stage / "Icon", icon_output, audit["managedIconPaths"], previous.get("managedIconPaths", []), check)
    return manifest, audit


def fixture_source(destination, output=OUTPUT, fixtures=FIXTURES):
    """Reconstruct approved importer inputs without duplicating character PNGs."""
    reject_symlinks(output)
    reject_symlinks(fixtures)
    require(fixtures.is_dir(), "Approved importer fixtures are missing")
    shutil.copytree(fixtures, destination)
    for directory, _, atlas in CHARACTERS.values():
        shutil.copytree(output / (atlas + ".atlas"), destination / directory)
    return destination


def check_runtime(output=OUTPUT, icon_output=ICON_OUTPUT, fixtures=FIXTURES):
    """Verify the committed resource contract without the optional master pack."""
    reject_symlinks(output)
    reject_symlinks(icon_output)
    reject_symlinks(fixtures)
    manifest = read_json(output / "runtime_manifest.json")
    audit = read_json(output / "import_audit.json")
    require(isinstance(manifest, dict) and isinstance(audit, dict)
            and manifest.get("schemaVersion") == audit.get("schemaVersion") == 1,
            "Unsupported runtime metadata schema")
    environment = environment_sources()
    require(audit.get("backgroundSource") == background_history(), "Historical background source audit differs")
    require(audit.get("environmentSources") == environment, "Runtime environment source audit differs")
    art_paths, icon_paths = managed_path_sets()
    require(isinstance(audit.get("managedArtPaths"), list) and isinstance(audit.get("managedIconPaths"), list),
            "Missing managed runtime resource paths")
    # The source directory also contains its tracked maintainer note. Xcode's
    # resource allowlist excludes that note from the application bundle.
    actual_art = {str(path.relative_to(output)) for path in output.rglob("*") if path.is_file() and path != output / "README.md"}
    actual_icons = {str(path.relative_to(icon_output)) for path in icon_output.rglob("*") if path.is_file()}
    require(actual_art == art_paths == set(audit["managedArtPaths"]), "Runtime art membership differs from approved selection")
    require(actual_icons == icon_paths == set(audit["managedIconPaths"]), "Runtime icon membership differs from approved selection")
    require(len(audit["managedArtPaths"]) == len(art_paths) and len(audit["managedIconPaths"]) == len(icon_paths),
            "Duplicate managed runtime resource path")
    # Original metadata is a small tracked fixture. Reuse the exact runtime PNGs
    # to independently reproduce all 24 clip and own-paddle registration maps.
    with tempfile.TemporaryDirectory(prefix="pickleblast-runtime-contract-") as temporary:
        source = fixture_source(Path(temporary) / "Source", output, fixtures)
        characters, mappings = character_manifest(source)
        require(manifest.get("characters") == characters, "Runtime character metadata or paddle alignment differs")
        require(audit.get("metadataMappings") == mappings, "Runtime source metadata mappings differ")
    require(audit.get("sourceManifestSHA256") == {name: digest(fixtures / "Docs" / name)
            for name in ("player_animation_manifest.json", "boss_animation_manifest.json")},
            "Runtime source manifest hashes differ")
    require(read_json(icon_output / "Contents.json") == {"images": icon_entries(), "info": {"author": "xcode", "version": 1}},
            "Runtime icon catalog differs")
    expected_supporting = {}
    for key, (relative, atlas, size) in supporting_allowlist().items():
        expected_supporting[key] = {"atlas": atlas, "name": Path(relative).stem, "pixelSize": size,
            "alphaBounds": pixel_info(output / (atlas + ".atlas") / Path(relative).name)["alphaBounds"]}
    for key, specification in environment.items():
        destination = Path(specification["destination"])
        expected_supporting[key] = {"atlas": destination.parent.stem, "name": destination.stem,
            "pixelSize": BACKGROUND_RUNTIME_SIZE, "alphaBounds": [0, 0, *BACKGROUND_RUNTIME_SIZE]}
    require(manifest.get("supporting") == expected_supporting, "Runtime support metadata differs")
    resources = audit.get("resources")
    require(isinstance(resources, list) and len(resources) == len(art_paths) - 2 + len(icon_paths) - 1,
            "Runtime resource audit count differs")
    seen, groups = set(), {}
    source_hashes = {relative: digest(fixtures / relative) for relative, _, _ in supporting_allowlist().values()}
    source_hashes["AppIcon/app_icon_1024.png"] = digest(fixtures / "AppIcon/app_icon_1024.png")
    for item in resources:
        require(isinstance(item, dict), "Invalid runtime resource audit entry")
        relative = relative_resource_path(item.get("destination"))
        kind = item.get("kind")
        require(kind in ("character", "support", "environment", "appIcon"), "Invalid runtime resource kind")
        root = icon_output if kind == "appIcon" else output
        key = (kind == "appIcon", relative)
        require(key not in seen and relative in (icon_paths if kind == "appIcon" else art_paths)
                and relative.endswith(".png"), "Unexpected or duplicate audited runtime resource")
        seen.add(key)
        path = root / relative
        info = pixel_info(path)
        require(item.get("sha256") == digest(path) and item.get("pngBytes") == path.stat().st_size
                and all(item.get(field) == value for field, value in info.items()),
                "Runtime resource hash or image metadata differs: " + relative)
        if kind == "character":
            character = item.get("character")
            require(character in CHARACTERS and relative.startswith(CHARACTERS[character][2] + ".atlas/")
                    and item.get("source") == CHARACTERS[character][0] + "/" + Path(relative).name
                    and item.get("sourceSHA256") == item["sha256"]
                    and info["pixelSize"] == [128, 128] and info["alphaExtrema"] == [0, 255],
                    "Runtime approved character copy differs: " + relative)
        elif kind == "support":
            semantic = item.get("semanticKey")
            require(semantic in supporting_allowlist(), "Unexpected runtime supporting key")
            source_relative, atlas, size = supporting_allowlist()[semantic]
            require(relative == atlas + ".atlas/" + Path(source_relative).name
                    and item.get("source") == source_relative
                    and item.get("sourceSHA256") == source_hashes[source_relative]
                    and info["pixelSize"] == size and info["alphaExtrema"][0] == 0,
                    "Runtime support selection differs: " + relative)
        elif kind == "appIcon":
            slot = next(entry for entry in icon_entries() if entry["filename"] == relative)
            side = round(float(slot["size"].split("x")[0]) * int(slot["scale"][0]))
            require(item.get("source") == "AppIcon/app_icon_1024.png"
                    and item.get("sourceSHA256") == source_hashes["AppIcon/app_icon_1024.png"]
                    and info["pixelSize"] == [side, side] and png_pixels(path)[2] == 3,
                    "Runtime icon dimensions or opacity differ: " + relative)
        else:
            specification = environment.get(item.get("semanticKey"))
            require(specification is not None and relative == specification["destination"]
                    and item.get("source") == specification["source"]
                    and item.get("sourceSHA256") == specification["sourceSHA256"]
                    and info["pixelSize"] == BACKGROUND_RUNTIME_SIZE and png_pixels(path)[2] == 3,
                    "Runtime approved environment differs")
        group = "AppIcon.appiconset" if kind == "appIcon" else relative.split("/")[0]
        total = groups.setdefault(group, {"images": 0, "pngBytes": 0, "estimatedDecodedRGBABytes": 0})
        total["images"] += 1
        total["pngBytes"] += item["pngBytes"]
        total["estimatedDecodedRGBABytes"] += info["estimatedDecodedRGBABytes"]
    require(seen == {(False, path) for path in art_paths if path.endswith(".png")}
            | {(True, path) for path in icon_paths if path.endswith(".png")}, "Runtime audited resource membership differs")
    require(groups == audit.get("groups"), "Runtime resource group totals differ")
    require(groups.get("CourtMaterial.atlas", {}).get("images") == 1,
            "CourtMaterial must remain a single-image atlas for native shape fills")
    return manifest, audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--icon-dir", type=Path, default=ICON_OUTPUT)
    parser.add_argument("--check", action="store_true", help="Verify generated files byte-for-byte without replacing them")
    parser.add_argument("--check-runtime", action="store_true", help="Verify committed runtime assets without the optional master source pack")
    arguments = parser.parse_args()
    try:
        require(not (arguments.check and arguments.check_runtime), "Choose --check or --check-runtime")
        manifest, audit = check_runtime(arguments.output, arguments.icon_dir) if arguments.check_runtime else run(
            arguments.source, arguments.output, arguments.icon_dir, arguments.check)
    except (ArtError, KeyError, TypeError, AttributeError, IndexError, OSError, struct.error, subprocess.CalledProcessError) as error:
        parser.exit(1, f"ART IMPORT FAILED: {error}\n")
    frame_count = sum(len(clip["frames"]) for character in manifest["characters"].values() for clip in character["clips"].values())
    print(f"{'Verified' if arguments.check or arguments.check_runtime else 'Imported'} {frame_count} approved character frames, "
          f"{len(manifest['supporting'])} support textures and {len(icon_entries())} app icon images.")
    print(f"Runtime manifest: {arguments.output / 'runtime_manifest.json'}")
    print(f"Resource audit: {arguments.output / 'import_audit.json'}")


if __name__ == "__main__":
    main()
