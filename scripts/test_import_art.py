#!/usr/bin/env python3
"""Behavioral regression checks for the approved art import contract."""

import json
from pathlib import Path
import shutil
import tempfile
import unittest
import struct
import zlib
from unittest.mock import patch

import import_art as art


class SourceContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pickleblast-art-test-")
        self.addCleanup(self.temporary.cleanup)
        self.source = Path(self.temporary.name) / "Source"
        art.fixture_source(self.source)

    def mutate(self, name, change):
        path = self.source / "Docs" / name
        data = json.loads(path.read_text())
        change(data)
        path.write_text(json.dumps(data))

    def rejects(self, message):
        with self.assertRaisesRegex(art.ArtError, message):
            art.character_manifest(self.source)

    def test_complete_pack_maps_selected_bosses_with_exact_contact_frames(self):
        characters, mappings = art.character_manifest(self.source)
        self.assertEqual(set(characters), {"player", "wall", "banger", "poacher", "dinker", "lobber"})
        self.assertEqual(len(mappings), 36)
        player = characters["player"]
        wall = characters["wall"]
        self.assertEqual(player["anchor"], [.5, .12109375])
        self.assertEqual(wall["canvasSize"], [512, 512])
        self.assertEqual(sum(len(clip["frames"]) for clip in player["clips"].values()), 271)
        forehand = player["clips"]["forehand"]
        self.assertEqual(forehand["frames"][forehand["contactIndex"]]["name"], "player_forehand_021")
        self.assertEqual(forehand["frames"][20]["timestamp"], .2666667)
        self.assertEqual(forehand["frames"][20]["paddleCenter"], [349.53962, 237.64555])
        self.assertEqual(wall["clips"]["forehand"]["frames"][20]["timestamp"], .26666667)
        self.assertEqual(wall["clips"]["forehand"]["frames"][20]["paddleCenter"], [148.690384, 292.634666])
        self.assertEqual(player["clips"]["move_left"]["strideSourcePixels"], -26)
        self.assertEqual(wall["clips"]["move_right"]["strideSourcePixels"], 26)
        wall_mapping = next(item for item in mappings if item["character"] == "wall" and item["clip"] == "forehand")
        self.assertEqual(wall_mapping["sourceMetadata"], "Docs/boss_forehand.json")

    def test_additional_boss_paddles_use_image_derived_registration(self):
        characters, mappings = art.character_manifest(self.source)
        for boss in ("banger", "poacher"):
            data = characters[boss]
            self.assertEqual(sum(len(c["frames"]) for c in data["clips"].values()), 271)
            for clip in ("forehand", "backhand", "block"):
                sequence = data["clips"][clip]
                contact = sequence["frames"][sequence["contactIndex"]]
                wall = characters["wall"]["clips"][clip]["frames"][sequence["contactIndex"]]
                self.assertNotEqual(contact["paddleCenter"], wall["paddleCenter"])
                self.assertEqual(contact["timestamp"], wall["timestamp"])
                self.assertTrue(contact["name"].startswith("boss_" + boss + "_"))
            entries = [m for m in mappings if m["character"] == boss]
            self.assertTrue(all("image-derived" in m["registration"] for m in entries))
            self.assertTrue(all(m["maximumShift128"] <= 6 and m["minimumAlignedCoreOverlap"] >= .5 for m in entries))

    def test_dinker_and_lobber_contacts_use_their_own_pixel_registration(self):
        characters, mappings = art.character_manifest(self.source)
        expected = {
            "dinker": {"forehand": [164, 292], "backhand": [324, 292], "block": [216, 292]},
            "lobber": {"forehand": [160, 292], "backhand": [320, 292], "block": [212, 292]},
        }
        for boss, contacts in expected.items():
            self.assertEqual(characters[boss]["canvasSize"], [512, 512])
            self.assertEqual(characters[boss]["anchor"], [.5, .12109375])
            self.assertEqual(sum(len(clip["frames"]) for clip in characters[boss]["clips"].values()), 271)
            for clip, paddle_center in contacts.items():
                animation = characters[boss]["clips"][clip]
                contact = animation["frames"][animation["contactIndex"]]
                wall = characters["wall"]["clips"][clip]["frames"][animation["contactIndex"]]
                self.assertEqual(contact["paddleCenter"], paddle_center)
                self.assertNotEqual(contact["paddleCenter"], wall["paddleCenter"])
                self.assertEqual(contact["timestamp"], wall["timestamp"])
            entries = [item for item in mappings if item["character"] == boss]
            self.assertEqual(len(entries), 6)
            self.assertTrue(all("own-image" in item["registration"] for item in entries))
            self.assertTrue(all(item["minimumAccentPixels"] > 0 for item in entries))
            self.assertTrue(all(item["sourceMetadata"].startswith(
                f"Docs/boss_animation_manifest.json#/bosses/{boss}/animations/") for item in entries))

    def test_new_boss_missing_paddle_cannot_silently_inherit_wall_contact(self):
        for boss in ("banger", "dinker", "lobber"):
            with self.subTest(boss=boss):
                path = self.source / f"Bosses/Runtime128/Boss{boss.title()}.atlas/boss_{boss}_idle_001.png"
                original = path.read_bytes()
                try:
                    art.write_png(path, 128, 128, 4, bytes([255, 0, 0, 255]) * (128 * 128))
                    message = ("tracked paddle lost its approved color signature" if boss in ("dinker", "lobber")
                               else "cannot identify approved paddle core")
                    self.rejects(message)
                finally:
                    path.write_bytes(original)

    def test_new_boss_filename_cannot_escape_approved_atlas(self):
        self.mutate("boss_animation_manifest.json", lambda d: d["bosses"]["banger"]["animations"]["idle"]["files"].__setitem__(0, "../../other.png"))
        self.rejects("invalid filename/index")

    def test_missing_required_frame_fails_before_import(self):
        (self.source / "Player/Runtime128/Player.atlas/player_forehand_021.png").unlink()
        self.rejects("Missing required frame")

    def test_wall_cannot_reuse_flattened_metadata_from_another_character(self):
        self.mutate("boss_forehand.json", lambda data: data[20].update(character="banger"))
        self.rejects("frame identity mismatch")

    def test_wall_metadata_requires_explicit_character_identity(self):
        self.mutate("boss_idle.json", lambda data: data[0].pop("character"))
        self.rejects("frame identity mismatch")

    def test_clip_identity_is_validated(self):
        self.mutate("player_backhand_frames.json", lambda data: data[0].update(clip="forehand"))
        self.rejects("frame identity mismatch")

    def test_old_metadata_mapping_cannot_point_to_an_arbitrary_file(self):
        self.mutate("boss_animation_manifest.json", lambda data: data["bosses"]["wall"]["animations"]["idle"].update(metadata="Docs/Frames/banger/idle.json"))
        self.rejects("unexpected metadata mapping")

    def test_nonmonotonic_timestamps_fail(self):
        self.mutate("player_animation_manifest.json", lambda data: data["animations"]["forehand"]["timestamps_seconds"].__setitem__(3, 0))
        self.rejects("timestamps must increase strictly")

    def test_frame_timestamp_must_match_manifest(self):
        self.mutate("player_forehand_frames.json", lambda data: data[20].update(timestamp_seconds=.27))
        self.rejects("metadata timestamp mismatch")

    def test_contact_index_is_zero_based_and_contract_is_not_silently_shifted(self):
        self.mutate("player_animation_manifest.json", lambda data: data["animations"]["forehand"].update(contact_index_zero_based=21))
        self.rejects("contact index differs")

    def test_contact_time_must_match_the_contact_frame(self):
        self.mutate("boss_animation_manifest.json", lambda data: data["bosses"]["wall"]["animations"]["block"].update(contact_time_seconds=.2125))
        self.rejects("contact time/index mismatch")

    def test_loop_and_canvas_are_not_inferred_from_file_count(self):
        self.mutate("player_animation_manifest.json", lambda data: data["animations"]["idle"].update(loop=False))
        self.rejects("duration or loop contract differs")

    def test_texture_resolution_is_checked(self):
        path = self.source / "Player/Runtime128/Player.atlas/player_idle_001.png"
        art.write_png(path, 64, 64, 4, bytes([1, 2, 3, 255]) * (64 * 64))
        self.rejects("required runtime PNG is not 128x128")

    def test_anchor_cannot_confuse_png_and_spritekit_origins(self):
        self.mutate("player_animation_manifest.json", lambda data: data["animations"]["idle"].update(spritekit_anchor=[.5, .87890625]))
        self.rejects("source canvas or anchor differs")

    def test_attachment_normalized_and_source_coordinates_must_agree(self):
        self.mutate("boss_block.json", lambda data: data[16].update(paddle_center_normalized=[0, 0]))
        self.rejects("attachment normalization mismatch")

    def test_invalid_attachment_transform_fails(self):
        self.mutate("player_forehand_frames.json", lambda data: data[20].update(paddle_basis_x=[float("nan"), 1]))
        self.rejects("Invalid coordinate")

    def test_filename_cannot_escape_selected_atlas(self):
        self.mutate("player_animation_manifest.json", lambda data: data["animations"]["idle"]["files"].__setitem__(0, "../../other.png"))
        self.rejects("invalid filename/index")

    def test_source_frame_symlink_cannot_escape_approved_input(self):
        path = self.source / "Player/Runtime128/Player.atlas/player_idle_001.png"
        path.unlink()
        path.symlink_to(art.OUTPUT / "Player.atlas/player_idle_001.png")
        self.rejects("symlinks")

    def test_committed_original_fixture_hashes_match_inventory(self):
        for relative, expected in art.read_json(art.FIXTURES / "SHA256SUMS.json").items():
            self.assertEqual(art.digest(art.FIXTURES / relative), expected, relative)


class GeneratedResourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="pickleblast-import-output-test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.output = Path(cls.temporary.name) / "Art"
        cls.icons = Path(cls.temporary.name) / "Icon"
        cls.source = art.fixture_source(Path(cls.temporary.name) / "Source")
        cls.source_hashes = {str(path.relative_to(cls.source)): art.digest(path) for path in cls.source.rglob("*") if path.is_file()}
        cls.environment_hashes = {path: art.digest(path) for path in
            [art.BACKGROUND_APPROVED, art.BACKGROUND_CLEAN]
            + [item["source"] for item in art.environment_allowlist().values()]}
        cls.manifest, cls.audit = art.run(cls.source, cls.output, cls.icons)

    def test_source_pack_is_unchanged_and_character_frames_are_exact_copies(self):
        after = {str(path.relative_to(self.source)): art.digest(path) for path in self.source.rglob("*") if path.is_file()}
        self.assertEqual(after, self.source_hashes)
        images = [item for item in self.audit["resources"] if item["kind"] == "character"]
        self.assertEqual(len(images), 1626)
        self.assertTrue(all(item["sourceSHA256"] == item["sha256"] for item in images))
        self.assertEqual(sum(item["estimatedDecodedRGBABytes"] for item in images), 106_561_536)
        self.assertEqual(self.manifest["characters"], art.read_json(art.OUTPUT / "runtime_manifest.json")["characters"])

    def test_resources_exclude_unselected_resolutions_and_future_content(self):
        included = {item["source"] for item in self.audit["resources"]}
        self.assertNotIn("Targets/Objects/target_powerup.png", included)
        self.assertNotIn("Ball/ball_power.png", included)
        self.assertTrue(any(path.startswith("Bosses/Runtime128/BossDinker.atlas/") for path in included))
        self.assertTrue(any(path.startswith("Bosses/Runtime128/BossLobber.atlas/") for path in included))
        self.assertFalse(any("Master256" in path or "Body.atlas" in path for path in included))
        self.assertEqual(len(self.manifest["supporting"]), 50)
        self.assertIn("Targets/Objects/target_powerup.png", self.audit["omittedOptionalPNGs"])

    def test_approved_masters_are_unchanged_and_two_runtime_layers_are_bounded(self):
        self.assertEqual({path: art.digest(path) for path in self.environment_hashes}, self.environment_hashes)
        self.assertEqual(art.digest(art.BACKGROUND_APPROVED), art.BACKGROUND_APPROVED_SHA256)
        self.assertEqual(art.digest(art.BACKGROUND_CLEAN), art.BACKGROUND_CLEAN_SHA256)
        for key, atlas, name in (("backgroundArena", "Arena", "arena_b3"),
                                 ("courtSlateB3", "CourtMaterial", "court_slate_b3")):
            self.assertEqual(self.manifest["supporting"][key], {"atlas": atlas, "name": name,
                "pixelSize": [512, 512], "alphaBounds": [0, 0, 512, 512]})
            self.assertEqual(art.png_pixels(self.output / f"{atlas}.atlas/{name}.png")[:3], (512, 512, 3))
            self.assertEqual(self.audit["groups"][atlas + ".atlas"]["images"], 1)
            self.assertEqual(self.audit["groups"][atlas + ".atlas"]["estimatedDecodedRGBABytes"], 1_048_576)
        self.assertEqual(sum(self.audit["groups"][atlas]["estimatedDecodedRGBABytes"]
                             for atlas in ("Arena.atlas", "CourtMaterial.atlas")), 2_097_152)
        self.assertEqual(self.audit["backgroundSource"]["approvedFilename"], "PickleblastBackground.png")
        self.assertEqual(self.audit["environmentSources"], art.environment_sources())

    def test_environment_conversions_are_byte_deterministic(self):
        for specification in art.environment_allowlist().values():
            destination = Path(self.temporary.name) / (specification["name"] + "-again.png")
            art.convert_png(specification["source"], destination, art.BACKGROUND_RUNTIME_SIZE, opaque=True)
            self.assertEqual(destination.read_bytes(),
                             (self.output / f"{specification['atlas']}.atlas/{specification['name']}.png").read_bytes())

    def test_full_concepts_and_retired_background_are_not_runtime_resources(self):
        self.assertEqual({path.name for path in (self.output / "Arena.atlas").iterdir()},
                         {"arena_b3.png"})
        self.assertEqual({path.name for path in (self.output / "CourtMaterial.atlas").iterdir()},
                         {"court_slate_b3.png"})
        selected = [item for item in self.audit["resources"] if item["kind"] == "environment"]
        self.assertEqual({item["source"] for item in selected}, {
            "ArtSources/Backgrounds/B3/arena-b3-source.png",
            "ArtSources/Backgrounds/B3/court-slate-b3-source.png"})
        self.assertFalse(any("Concepts/" in item["source"] for item in self.audit["resources"]))
        self.assertTrue(art.RETIRED_MANAGED_ART_PATHS.isdisjoint(self.audit["managedArtPaths"]))

    def test_runtime_ball_preserves_padding_and_actual_alpha_bounds(self):
        entry = self.manifest["supporting"]["ball"]
        self.assertEqual(entry["pixelSize"], [128, 128])
        self.assertEqual(entry["alphaBounds"], art.pixel_info(self.output / "Pickleball.atlas/ball_normal.png")["alphaBounds"])
        self.assertLess(entry["alphaBounds"][2] - entry["alphaBounds"][0], 64)
        self.assertEqual([path.name for path in (self.output / "Pickleball.atlas").glob("*.png")], ["ball_normal.png"])
        self.assertEqual(self.audit["groups"]["Pickleball.atlas"]["estimatedDecodedRGBABytes"], 65_536)

    def test_catalog_declares_existing_opaque_images_at_correct_pixel_sizes(self):
        catalog = json.loads((self.icons / "Contents.json").read_text())
        self.assertEqual(len(catalog["images"]), 16)
        for entry in catalog["images"]:
            width, height, channels, _ = art.png_pixels(self.icons / entry["filename"])
            expected = round(float(entry["size"].split("x")[0]) * int(entry["scale"][0]))
            self.assertEqual((width, height), (expected, expected))
            self.assertEqual(channels, 3, "Catalog icon should have no alpha channel")

    def test_notification_icon_sizes_match_apple_watch_subtypes(self):
        catalog = json.loads((self.icons / "Contents.json").read_text())
        notification_slots = {entry["subtype"]: (entry["size"], entry["scale"], entry["filename"])
                              for entry in catalog["images"] if entry.get("role") == "notificationCenter"}
        self.assertEqual(notification_slots, {"38mm": ("24x24", "2x", "icon-48.png"),
                                               "42mm": ("27.5x27.5", "2x", "icon-55.png")})

    def test_check_detects_missing_required_generated_resource(self):
        stage = Path(self.temporary.name) / "CheckStage"
        stage.mkdir(exist_ok=True)
        (stage / "runtime_manifest.json").write_text("required")
        with self.assertRaisesRegex(art.ArtError, "differs or is missing"):
            art.install_tree(stage, self.output, ["runtime_manifest.json"], [], check=True)

    def test_technical_conversion_is_byte_deterministic(self):
        destination = Path(self.temporary.name) / "ball-again.png"
        art.convert_png(self.source / "Ball/ball_normal.png", destination, [128, 128])
        self.assertEqual(destination.read_bytes(), (self.output / "Pickleball.atlas/ball_normal.png").read_bytes())

    def test_outputs_cannot_mutate_source_pack(self):
        with self.assertRaisesRegex(art.ArtError, "outside immutable source pack"):
            art.run(self.source, self.source / "Imported", self.icons)

    def test_outputs_cannot_mutate_environment_source_directory(self):
        with self.assertRaisesRegex(art.ArtError, "immutable environment sources"):
            art.run(self.source, art.B3_SOURCE_ROOT / "Imported", self.icons)

    def test_runtime_check_needs_no_optional_master_pack(self):
        with patch.object(art, "SOURCE", Path(self.temporary.name) / "MissingPrivatePack"):
            manifest, _ = art.check_runtime(self.output, self.icons)
        self.assertEqual(manifest, self.manifest)

    def test_runtime_check_rejects_changed_timing(self):
        path = self.output / "runtime_manifest.json"
        original = path.read_bytes()
        data = json.loads(original)
        data["characters"]["player"]["clips"]["idle"]["duration"] = 2
        try:
            path.write_bytes(art.json_bytes(data))
            with self.assertRaisesRegex(art.ArtError, "character metadata or paddle alignment differs"):
                art.check_runtime(self.output, self.icons)
        finally:
            path.write_bytes(original)

    def test_runtime_check_rejects_unlisted_resource(self):
        path = self.output / "unlisted.json"
        try:
            path.write_text("{}")
            with self.assertRaisesRegex(art.ArtError, "membership differs"):
                art.check_runtime(self.output, self.icons)
        finally:
            path.unlink(missing_ok=True)

    def test_runtime_check_rejects_retired_background(self):
        for relative in sorted(art.RETIRED_MANAGED_ART_PATHS):
            path = self.output / relative
            try:
                shutil.copyfile(self.output / "Arena.atlas/arena_b3.png", path)
                with self.assertRaisesRegex(art.ArtError, "membership differs"):
                    art.check_runtime(self.output, self.icons)
            finally:
                path.unlink(missing_ok=True)

    def test_runtime_check_rejects_changed_environment_source_audit(self):
        path = self.output / "import_audit.json"
        original = path.read_bytes()
        data = json.loads(original)
        data["environmentSources"]["courtSlateB3"]["sourceSHA256"] = "0" * 64
        try:
            path.write_bytes(art.json_bytes(data))
            with self.assertRaisesRegex(art.ArtError, "environment source audit differs"):
                art.check_runtime(self.output, self.icons)
        finally:
            path.write_bytes(original)

    def test_runtime_check_rejects_swapped_environment_semantic(self):
        path = self.output / "import_audit.json"
        original = path.read_bytes()
        data = json.loads(original)
        next(item for item in data["resources"] if item.get("semanticKey") == "courtSlateB3")["semanticKey"] = "backgroundArena"
        try:
            path.write_bytes(art.json_bytes(data))
            with self.assertRaisesRegex(art.ArtError, "approved environment differs"):
                art.check_runtime(self.output, self.icons)
        finally:
            path.write_bytes(original)

    def test_runtime_check_rejects_changed_image_with_valid_png_layout(self):
        path = self.output / "UI.atlas/ui_close.png"
        original = path.read_bytes()
        width, height, channels, pixels = art.png_pixels(path)
        pixels[0] ^= 1
        try:
            art.write_png(path, width, height, channels, pixels)
            with self.assertRaisesRegex(art.ArtError, "resource hash or image metadata differs"):
                art.check_runtime(self.output, self.icons)
        finally:
            path.write_bytes(original)


class ImportSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pickleblast-import-safety-")
        self.addCleanup(self.temporary.cleanup)
        # macOS's system /var alias is unrelated to deliberately symlinked inputs.
        self.root = Path(self.temporary.name).resolve()
        self.staged = self.root / "staged"
        self.output = self.root / "output"
        self.staged.mkdir()
        self.output.mkdir()
        (self.staged / "runtime_manifest.json").write_text("new")
        self.outside = self.root / "outside.json"
        self.outside.write_text("untouched")

    def install(self, paths=None, previous=None):
        art.install_tree(self.staged, self.output, paths or ["runtime_manifest.json"], previous or [], False)

    def test_existing_destination_symlink_cannot_overwrite_external_file(self):
        (self.output / "runtime_manifest.json").symlink_to(self.outside)
        with self.assertRaisesRegex(art.ArtError, "symlink"):
            self.install()
        self.assertEqual(self.outside.read_text(), "untouched")

    def test_destination_directory_symlink_is_rejected_before_any_write(self):
        (self.output / "Player.atlas").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(art.ArtError, "symlink"):
            self.install()
        self.assertFalse((self.output / "runtime_manifest.json").exists())

    def test_staged_symlink_cannot_copy_external_content(self):
        (self.staged / "runtime_manifest.json").unlink()
        (self.staged / "runtime_manifest.json").symlink_to(self.outside)
        with self.assertRaisesRegex(art.ArtError, "symlink"):
            self.install()
        self.assertFalse((self.output / "runtime_manifest.json").exists())

    def test_previous_audit_cannot_delete_unrelated_output_file(self):
        path = self.output / "personal-notes.txt"
        path.write_text("untouched")
        with self.assertRaisesRegex(art.ArtError, "Unexpected previous managed"):
            self.install(previous=["personal-notes.txt"])
        self.assertEqual(path.read_text(), "untouched")
        self.assertFalse((self.output / "runtime_manifest.json").exists())

    def test_retired_background_is_removed_only_as_previous_managed_output(self):
        for relative in sorted(art.RETIRED_MANAGED_ART_PATHS):
            retired = self.output / relative
            retired.parent.mkdir(exist_ok=True)
            retired.write_text("old runtime")
            self.install(previous=[relative])
            self.assertFalse(retired.exists())
        self.assertEqual((self.output / "runtime_manifest.json").read_text(), "new")
        self.assertEqual(self.outside.read_text(), "untouched")

    def test_check_reports_retired_background_without_removing_it(self):
        for relative in sorted(art.RETIRED_MANAGED_ART_PATHS):
            retired = self.output / relative
            retired.parent.mkdir(exist_ok=True)
            retired.write_text("old runtime")
            shutil.copyfile(self.staged / "runtime_manifest.json", self.output / "runtime_manifest.json")
            with self.assertRaisesRegex(art.ArtError, "Obsolete generated resource remains"):
                art.install_tree(self.staged, self.output, ["runtime_manifest.json"], [relative], True)
            self.assertEqual(retired.read_text(), "old runtime")

    def test_retired_or_concept_image_cannot_be_new_managed_output(self):
        for relative in sorted(art.RETIRED_MANAGED_ART_PATHS | {"CourtMaterial.atlas/b3-concept.png"}):
            with self.subTest(path=relative), self.assertRaisesRegex(art.ArtError, "Unexpected managed"):
                self.install(paths=[relative])
        self.assertFalse((self.output / "runtime_manifest.json").exists())

    def test_shape_fill_material_allowlist_has_one_image_and_no_scenery(self):
        paths, _ = art.managed_path_sets()
        self.assertEqual({path for path in paths if path.startswith("CourtMaterial.atlas/")},
                         {"CourtMaterial.atlas/court_slate_b3.png"})
        self.assertEqual({path for path in paths if path.startswith("Arena.atlas/")},
                         {"Arena.atlas/arena_b3.png"})
        self.assertTrue(art.RETIRED_MANAGED_ART_PATHS.isdisjoint(paths))

    def test_traversal_or_absolute_managed_paths_fail_before_writes(self):
        for unsafe in ("../outside.json", str(self.outside), "./runtime_manifest.json", "Player.atlas/../outside.json", "Player.atlas\\outside.json"):
            with self.subTest(path=unsafe), self.assertRaisesRegex(art.ArtError, "Invalid managed"):
                self.install(previous=[unsafe])
        self.assertEqual(self.outside.read_text(), "untouched")
        self.assertFalse((self.output / "runtime_manifest.json").exists())

    def test_new_generated_path_cannot_escape_destination(self):
        with self.assertRaisesRegex(art.ArtError, "Invalid managed"):
            self.install(paths=["../outside.json"])
        self.assertEqual(self.outside.read_text(), "untouched")

    def test_hardlinked_destination_is_replaced_without_mutating_external_file(self):
        path = self.output / "runtime_manifest.json"
        path.hardlink_to(self.outside)
        self.install()
        self.assertEqual(path.read_text(), "new")
        self.assertEqual(self.outside.read_text(), "untouched")

    def test_output_ancestor_of_source_and_overlapping_outputs_are_rejected(self):
        source = self.root / "Source"
        source.mkdir()
        with self.assertRaisesRegex(art.ArtError, "cannot contain it"):
            art.run(source, self.root, self.output)
        with self.assertRaisesRegex(art.ArtError, "must not overlap"):
            art.run(source, self.output, self.output / "Icon")

    def test_nonlist_previous_paths_are_rejected(self):
        with self.assertRaisesRegex(art.ArtError, "must be lists"):
            art.install_tree(self.staged, self.output, ["runtime_manifest.json"], "runtime_manifest.json", False)

    def test_environment_source_hash_dimensions_and_opacity_are_required(self):
        path = self.root / "environment.png"
        art.write_png(path, 2, 2, 3, bytes([24, 61, 105]) * 4)
        approved = art.digest(path)
        art.validate_environment_source(path, approved, [2, 2])
        with self.assertRaisesRegex(art.ArtError, "dimensions or opacity differ"):
            art.validate_environment_source(path, approved, [512, 512])
        art.write_png(path, 2, 2, 4, bytes([24, 61, 105, 128]) * 4)
        with self.assertRaisesRegex(art.ArtError, "source differs"):
            art.validate_environment_source(path, approved, [2, 2])
        with self.assertRaisesRegex(art.ArtError, "dimensions or opacity differ"):
            art.validate_environment_source(path, art.digest(path), [2, 2])

    def test_environment_source_symlink_is_rejected_even_with_matching_hash(self):
        original = self.root / "master.png"
        art.write_png(original, 1, 1, 3, bytes([24, 61, 105]))
        path = self.root / "environment.png"
        path.symlink_to(original)
        with self.assertRaisesRegex(art.ArtError, "symlinks"):
            art.validate_environment_source(path, art.digest(original), [1, 1])

    def png(self, width, height, raw, end=True):
        def chunk(kind, payload):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
        path = self.root / "input.png"
        path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                         + chunk(b"IDAT", zlib.compress(raw)) + (chunk(b"IEND", b"") if end else b""))
        return path

    def test_oversized_dimensions_fail_before_decompression(self):
        path = self.png(art.MAX_IMAGE_SIDE + 1, 1, b"")
        with self.assertRaisesRegex(art.ArtError, "Unsupported PNG layout"):
            art.png_pixels(path)

    def test_pixel_stream_cannot_expand_beyond_declared_dimensions(self):
        path = self.png(1, 1, b"\0" * 100_000)
        with self.assertRaisesRegex(art.ArtError, "pixel length mismatch"):
            art.png_pixels(path)

    def test_encoded_png_size_is_bounded(self):
        path = self.png(1, 1, b"\0" * 5)
        with patch.object(art, "MAX_PNG_BYTES", 8), self.assertRaisesRegex(art.ArtError, "exceeds size limit"):
            art.png_pixels(path)

    def test_decoded_png_size_is_bounded(self):
        path = self.png(4, 4, b"\0" * 68)
        with patch.object(art, "MAX_DECODED_BYTES", 16), self.assertRaisesRegex(art.ArtError, "decoded size exceeds limit"):
            art.png_pixels(path)

    def test_missing_png_end_is_rejected(self):
        with self.assertRaisesRegex(art.ArtError, "missing header or end"):
            art.png_pixels(self.png(1, 1, b"\0" * 5, end=False))

    def test_metadata_size_and_nonfinite_literals_are_rejected(self):
        path = self.root / "metadata.json"
        path.write_text('{"value":12345}')
        with patch.object(art, "MAX_JSON_BYTES", 4), self.assertRaisesRegex(art.ArtError, "exceeds size limit"):
            art.read_json(path)
        path.write_text('{"value":NaN}')
        with self.assertRaisesRegex(art.ArtError, "nonfinite JSON"):
            art.read_json(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
