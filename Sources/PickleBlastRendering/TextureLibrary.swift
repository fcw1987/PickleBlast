import Foundation
import ImageIO
import SpriteKit

/// Validated approved assets. Missing required resources are an integration error.
public final class TextureLibrary {
    public let manifest: RuntimeArtManifest
    private let resourceDirectory: URL?
    private var atlases: [String: SKTextureAtlas] = [:]
    private var atlasNames: [String: Set<String>] = [:]
    private var cached: [String: SKTexture] = [:]
    private var optionalCharacterAvailable: [String: Bool] = [:]
    #if DEBUG
    // Test-only observability for repeated-render and lifecycle checks. These
    // counters do not exist in the shipping Release renderer.
    var debugTextureRequests = 0
    var debugTextureMisses = 0
    var debugCachedTextureCount: Int { cached.count }
    var debugCachedTextureKeys: Set<String> { Set(cached.keys) }
    var debugLoadedAtlasCount: Int { atlases.count }
    var debugLoadedCharacterAtlases: [String] {
        let characters = Set(manifest.characters.values.map(\.atlas))
        return atlases.keys.filter { characters.contains($0) }.sorted()
    }
    #endif
    public lazy var ball: SKTexture = supporting("ball")

    public init(bundle: Bundle = .main) {
        let url: URL
        if let bundled = bundle.url(forResource: "runtime_manifest", withExtension: "json") {
            url = bundled
            resourceDirectory = nil
        } else {
            #if os(watchOS)
            preconditionFailure("Missing required runtime_manifest.json. Run scripts/import_art.py and regenerate the project.")
            #else
            // Explicit host development resource path; never compiled into the Watch application.
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let art = root.appendingPathComponent("WatchApp/Art")
            url = art.appendingPathComponent("runtime_manifest.json")
            resourceDirectory = art
            #endif
        }
        do { manifest = try JSONDecoder().decode(RuntimeArtManifest.self, from: Data(contentsOf: url)) }
        catch { preconditionFailure("Invalid required approved-art manifest: \(error)") }
        precondition(manifest.schemaVersion == 1, "Unsupported art manifest")
    }
    #if DEBUG
    init(testManifest: RuntimeArtManifest, resourceDirectory: URL) {
        manifest = testManifest
        self.resourceDirectory = resourceDirectory
    }
    #endif
    func character(_ name: String) -> CharacterArt { manifest.characters[name]! }
    /// The new opponents are optional presentation resources. If an opponent's
    /// metadata or atlas is incomplete, its approved Wall animation can still
    /// present the authoritative match. Player and Wall remain required assets.
    func resolvedCharacterName(_ requested: String) -> String {
        guard requested == "banger" || requested == "poacher" else { return requested }
        if let available = optionalCharacterAvailable[requested] { return available ? requested : "wall" }
        guard let art = manifest.characters[requested] else {
            optionalCharacterAvailable[requested] = false
            return "wall"
        }
        let names = art.clips.values.flatMap { $0.frames.map(\.name) }
        guard names.count == 271 else {
            optionalCharacterAvailable[requested] = false
            return "wall"
        }
        let available: Bool
        if let resourceDirectory {
            let directory = resourceDirectory.appendingPathComponent(art.atlas + ".atlas")
            available = names.allSatisfy {
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0 + ".png").path)
            }
        } else {
            available = Set(names).isSubset(of: namesInAtlas(art.atlas))
        }
        optionalCharacterAvailable[requested] = available
        return available ? requested : "wall"
    }
    func texture(character: String, clip: String, elapsed: Double) -> SKTexture {
        let art = self.character(character)
        let animation = art.clips[clip]!
        return texture(atlas: art.atlas, name: animation.frames[animation.frameIndex(at: elapsed)].name)
    }
    /// Selection uses the canonical idle pose without retaining full opponent atlases.
    public func opponentThumbnail(_ identity: String) -> CGImage {
        guard let art = manifest.characters[identity], let idle = art.clips["idle"],
              let frame = idle.frames.first else {
            preconditionFailure("Missing required opponent thumbnail: \(identity)")
        }
        let image = texture(atlas: art.atlas, name: frame.name).cgImage()
        releaseCharacter(identity)
        return image
    }
    public func supporting(_ key: String) -> SKTexture {
        guard let asset = manifest.supporting[key] else { preconditionFailure("Missing required supporting asset: \(key)") }
        return texture(atlas: asset.atlas, name: asset.name)
    }
    func texture(atlas: String, name: String) -> SKTexture {
        #if DEBUG
        debugTextureRequests += 1
        #endif
        let key = atlas + "/" + name
        if let value = cached[key] { return value }
        #if DEBUG
        debugTextureMisses += 1
        #endif
        let texture: SKTexture
        if let resourceDirectory {
            let url = resourceDirectory.appendingPathComponent(atlas + ".atlas/" + name + ".png")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                preconditionFailure("Missing required approved texture: \(key)")
            }
            texture = SKTexture(cgImage: image)
        } else {
            let source = atlases[atlas] ?? SKTextureAtlas(named: atlas)
            atlases[atlas] = source
            precondition(namesInAtlas(atlas).contains(name), "Missing required atlas texture: \(key)")
            texture = source.textureNamed(name)
        }
        texture.filteringMode = .linear
        cached[key] = texture
        return texture
    }
    private func namesInAtlas(_ atlas: String) -> Set<String> {
        if let names = atlasNames[atlas] { return names }
        let source = atlases[atlas] ?? SKTextureAtlas(named: atlas)
        atlases[atlas] = source
        let names = Set(source.textureNames.map { ($0 as NSString).deletingPathExtension })
        atlasNames[atlas] = names
        return names
    }
    func releaseCharacter(_ name: String) {
        guard let atlas = manifest.characters[name]?.atlas else { return }
        cached = cached.filter { !$0.key.hasPrefix(atlas + "/") }
        atlases.removeValue(forKey: atlas)
        atlasNames.removeValue(forKey: atlas)
    }
}

enum Neon {
    static let black = SKColor(white: 0, alpha: 1)
    static let cyan = SKColor(red: 0, green: 229 / 255, blue: 1, alpha: 1)
    static let lime = SKColor(red: 215 / 255, green: 1, blue: 0, alpha: 1)
    static let magenta = SKColor(red: 1, green: 46 / 255, blue: 209 / 255, alpha: 1)
    static let orange = SKColor(red: 1, green: 138 / 255, blue: 0, alpha: 1)
    static let white = SKColor.white
}
