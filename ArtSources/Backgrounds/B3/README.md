# B3 production environment sources

The user selected direction B's cel-sports-comic surroundings and B3's blue competition court for the next playable proof. These are original project assets generated with the built-in ImageGen tool using the [selected B3 concept](../../Concepts/b-court-directions/b3-slate-competition-concept.png) as the edit reference. No external artwork or dependency was imported. The project's [asset license](../../../ASSET_LICENSE.md) applies where rights are recognized.

| Source master | Role | Runtime texture | Runtime dimensions |
| --- | --- | --- | --- |
| [arena-b3-source.png](arena-b3-source.png) | Clean skyline, palms, side architecture and quiet apron; no characters, court markings, net, ball or UI | `Arena.atlas/arena_b3.png` | 512 × 512 |
| [court-slate-b3-source.png](court-slate-b3-source.png) | Flat unmarked blue acrylic material; no perspective, lighting objects, lines or kitchen divisions | `CourtMaterial.atlas/court_slate_b3.png` | 512 × 512 |

Both masters are opaque RGB PNGs at 1254 × 1254. [generation-record.json](generation-record.json) contains the exact generation prompts and reference path. Rerunning a prompt does not guarantee identical output. The importer pins both source hashes and performs only deterministic technical reduction and PNG encoding; source PNG bytes remain unchanged.

The original masters and their 512-pixel technical previews were visually inspected. The environment has clean separation for native gameplay, and the material has restrained grain without embedded symbols. Actual shared-SpriteKit host captures were also inspected at small and large Watch layouts: skyline, moon, palms and side architecture remain recognizable after square aspect-fill; only the extreme outer floodlight edges crop. This inspection is not native Watch validation or sustained device performance evidence.

Court boundaries, regulation kitchen/service lines, net geometry, cues and character contact remain authoritative in the renderer. No full concept screenshot is a runtime resource. The initial proof retains the existing 271 frames per character and approved animation timing; it does not reproduce the concept's new character anatomy or painted paddles.

At 512 × 512 each, the two runtime textures imply 2,097,152 bytes of uncompressed RGBA pixels combined, excluding atlas packing and graphics-driver overhead. The existing arena used one 512 × 512 texture, so the additional pixel-data estimate is 1 MiB. Pixel brightness, decoded memory, GPU frame pacing and OLED battery impact need separate measurement. B3's non-black court surface is an explicitly selected visual tradeoff, not a claim of free performance.

The two imported runtime PNGs total 871,663 bytes (arena 391,676; material 479,987), versus 426,024 bytes for the retired arena PNG. These are source-resource disk bytes, not the compiled app or loaded-memory measurement. Final runtime hashes and dimensions are recorded in the generation record and guarded by the importer audit.

The court material is isolated in the single-image `CourtMaterial.atlas`. An initial native compiled test found neighboring arena content leaking into the court when both textures shared `Arena.atlas`; raw-file host fixtures had not exposed the packing issue. The atlas separation changes resource organization only, not source or runtime pixels. Native revalidation is required after packing changes.
