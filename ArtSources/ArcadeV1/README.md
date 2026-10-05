# Original Arcade equipment, build 9

ImageGen created the six sports-comic equipment illustrations in `generated-master.png` for PickleBlast, then removed the backdrop with transparency requested. Alpha inspection confirms transparent inter-object space. No third-party artwork or package was imported.

`swift Tools/ArtProcessing/normalize_arcade.swift` isolates the six regular atlas cells using their alpha bounds and normalizes them onto 256px transparent canvases. `normalization.json` records exact crops and placement. Paddle heads retain a 112px authored width, which becomes the existing 56px runtime head width; head center remains approximately (128,100) before 128px downsampling. The existing head-based collider registration and gameplay radii are preserved. The baskets and cone use the existing alpha-diameter registration.

`selection.json` records the seven bounded authored sources, dimensions and SHA-256 hashes (six equipment sprites plus the separate app icon). The art importer selects these without changing the historical approved source pack. Runtime targets remain 128px, with the same atlas membership and character contact frames. Source sheets and normalization tools are development assets, excluded from the Watch bundle.

Arcade presentation adds a 0.30-second bounded sprite recoil to hits and expansion/dissolve to the existing pooled impacts. It creates no extra nodes, actions, shaders or particles. Paused scene time freezes feedback; Reduced Motion retains static damage and flash cues.
