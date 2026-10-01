# Approved art importer fixtures

These are unchanged copies of selected inputs from the locally supplied `PickleBlast_Final_Approved_Art` handoff: the Player v4.1 and boss v4.2 metadata, 48 original support textures, the original 1024-pixel icon, and two unused examples that verify exclusion from shipping resources. `SHA256SUMS.json` records the original file hashes. Visual approval and matching hashes establish identity, not redistribution rights. Code, artwork, and branding licenses remain owner decisions.

The 1,084 selected character frames already exist byte-for-byte in `WatchApp/Art`. Importer tests copy those runtime frames into a temporary source layout rather than commit a second copy. The accepted background sources remain in `ArtSources/Backgrounds`. Tests regenerate temporary resources and icons with the original metadata and macOS `sips`; they never overwrite the approved artwork or shipping assets.

`python3 scripts/import_art.py --check-runtime` verifies committed frame/image hashes, PNG layout and limits, resource membership, metadata mappings, timing, anchors, each boss's own paddle registration, support selection, icon catalog, and group totals without requiring the private full source pack.

`python3 scripts/import_art.py --check` additionally compares a complete reimport with the canonical approved source pack. The full pack contains optional resolutions, editable source material, unused bosses, and previews; it is privately preserved and is not required to build or test the committed application.
