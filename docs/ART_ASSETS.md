# Artwork and runtime assets

The app bundles the player, The Wall, The Banger, The Poacher, The Dinker and The Lobber, plus the arena background, ball, targets, effects, interface graphics, wordmark and app icon. Court lines are drawn in code. All project artwork is covered by [ASSET_LICENSE.md](../ASSET_LICENSE.md); repository access does not permit reuse.

## Runtime contract

`WatchApp/Art/runtime_manifest.json` selects exactly 1,626 character frames: 271 per character across idle, left/right movement, forehand, backhand and block. The 128 × 128 PNGs preserve the original frame order and timing. Forehand/backhand contact uses frame 20 and block uses frame 16 (zero-based). Registration metadata uses a 512 × 512 source canvas and anchor `[0.5, 0.12109375]`.

Whole-frame translation aligns each character's embedded paddle to the authoritative ball contact. Bounds, wrist and paddle coordinates control presentation only. Never use them as a second collision model or add a second visible paddle. Each boss has its own attachment metadata. Dinker and Lobber registration is validated against their own approved pixels and shared clip timestamps.

There are 50 supporting textures across the Arena, CourtMaterial, Pickleball, Targets, Effects, UI and Brand atlases, and 16 icon PNGs in the asset catalog. Dynamic names and manifest membership are verified by the importer; absence of a literal filename in Swift does not prove a texture is unused. Only the current player's and selected opponent's character atlases need to stay cached.

The Xcode resource phase contains the thirteen runtime atlases, runtime manifest, icon catalog and privacy manifest. `import_audit.json` stores hashes for source integrity verification and is deliberately excluded from the app bundle. Test fixtures, background masters, screenshots, tools and documentation are also excluded from the bundle.

## Verification and maintenance

```sh
python3 scripts/import_art.py --check-runtime
python3 scripts/test_import_art.py
```

These commands work from this repository alone. The small committed importer fixtures preserve the canonical motion metadata and supporting inputs required by tests. `ArtSources/Backgrounds` retains the two historical background masters plus the separate B3 environment and court-material masters. Neither high-resolution animation exports nor unshipped boss artwork is required for builds or tests.

Full artwork regeneration is optional and requires the separately retained `PickleBlast_Final_Approved_Art` source handoff. Without that handoff, use the committed runtime resources and the verification commands above. Run optional imports into a temporary staging directory before reviewing any replacement. Preserve the source frames, timestamps, alpha bounds, contact registration and character-specific mappings. Do not hand-edit generated manifests or reduce animation quality to save space.

No bundled font, audio file or separately licensed third-party artwork was identified in the selected runtime inventory. Apple system text, frameworks and symbols remain subject to Apple's terms. A future replacement asset must have its own rights and maintenance record checked before inclusion.

## Selected B3 environment and court

The user selected the Cel Sports Comic surroundings and explicitly approved the B3 blue competition surface. The production assets are separate layers, generated from that project concept with the built-in ImageGen tool: `Arena.atlas/arena_b3.png` supplies the skyline and side architecture, while `CourtMaterial.atlas/court_slate_b3.png` supplies unmarked acrylic material. Court boundaries, kitchen regions, lines, net, ball and gameplay cues remain runtime geometry. No complete concept screenshot is bundled or drawn behind the gameplay.

The [B3 source record](../ArtSources/Backgrounds/B3/README.md) preserves the original source PNGs, exact generation prompts and maintenance contract. Both source masters are opaque 1254 × 1254 images, mechanically reduced by the existing importer to opaque 512 × 512 runtime PNGs. The old arena runtime texture is retired; its source masters remain unchanged. The six approved character frame sets, attachment metadata and animation timing are preserved. Their retained artwork is a visible difference from the more detailed concept characters.

The two runtime images have a combined estimated uncompressed RGBA pixel cost of 2 MiB, one MiB more than the former single arena texture. This estimate excludes atlas packing, upload copies, mipmaps and renderer overhead. Disk size, loaded memory and frame cadence must be measured separately; the selected blue surface also gives up the previous true-black court pixels. Asset storage tolerance does not establish GPU or OLED power cost.

The court material occupies its own single-image `CourtMaterial.atlas`. Native Watch simulator validation showed that `SKShapeNode.fillTexture` could sample neighboring packed arena content when both images shared an atlas. Keeping the material isolated prevents scenery from appearing inside the court; the original source and runtime PNG pixels are unchanged. Native compiled captures, rather than raw-file host fixtures alone, are required to verify this integration.

## Accepted icon and Arcade equipment

Build 10 uses original approved [paddle-outline icon artwork](../ArtSources/IconV1/README.md), with exact sRGB #000000 solid ink and naturally blended edges. All sixteen opaque Watch slots derive from its 1024×1024 production source. Original [Arcade equipment](../ArtSources/ArcadeV1/README.md) supplies paddles, a cone and baskets. No third-party rendering package or licensed artwork was added. Existing character/contact frames remain unchanged.
