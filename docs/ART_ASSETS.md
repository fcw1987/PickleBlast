# Artwork and runtime assets

The app bundles the player, The Wall, The Banger, The Poacher, The Dinker and The Lobber, plus the arena background, ball, targets, effects, interface graphics, wordmark and app icon. Court lines are drawn in code. All project artwork is covered by [ASSET_LICENSE.md](../ASSET_LICENSE.md); repository access does not permit reuse.

## Runtime contract

`WatchApp/Art/runtime_manifest.json` selects exactly 1,626 character frames: 271 per character across idle, left/right movement, forehand, backhand and block. The 128 × 128 PNGs preserve the original frame order and timing. Forehand/backhand contact uses frame 20 and block uses frame 16 (zero-based). Registration metadata uses a 512 × 512 source canvas and anchor `[0.5, 0.12109375]`.

Whole-frame translation aligns each character's embedded paddle to the authoritative ball contact. Bounds, wrist and paddle coordinates control presentation only. Never use them as a second collision model or add a second visible paddle. Each boss has its own attachment metadata. Dinker and Lobber registration is validated against their own approved pixels and shared clip timestamps.

There are 49 supporting textures across the Arena, Pickleball, Targets, Effects, UI and Brand atlases, and 16 icon PNGs in the asset catalog. Dynamic names and manifest membership are verified by the importer; absence of a literal filename in Swift does not prove a texture is unused. Only the current player's and selected opponent's character atlases need to stay cached.

The Xcode resource phase contains the twelve runtime atlases, runtime manifest, icon catalog and privacy manifest. `import_audit.json` stores hashes for source integrity verification and is deliberately excluded from the app bundle. Test fixtures, background masters, screenshots, tools and documentation are also excluded from the bundle.

## Verification and maintenance

```sh
python3 scripts/import_art.py --check-runtime
python3 scripts/test_import_art.py
```

These commands work from this repository alone. The small committed importer fixtures preserve the canonical motion metadata and supporting inputs required by tests. Two images in `ArtSources/Backgrounds` retain useful background maintenance inputs. Neither high-resolution animation exports nor unshipped boss artwork is required for builds or tests.

Full artwork regeneration is optional and requires the separately retained `PickleBlast_Final_Approved_Art` source handoff. Without that handoff, use the committed runtime resources and the verification commands above. Run optional imports into a temporary staging directory before reviewing any replacement. Preserve the source frames, timestamps, alpha bounds, contact registration and character-specific mappings. Do not hand-edit generated manifests or reduce animation quality to save space.

No bundled font, audio file or separately licensed third-party artwork was identified in the selected runtime inventory. Apple system text, frameworks and symbols remain subject to Apple's terms. A future replacement asset must have its own rights and maintenance record checked before inclusion.
