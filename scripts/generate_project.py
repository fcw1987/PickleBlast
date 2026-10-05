#!/usr/bin/env python3
"""Regenerate the dependency-free native watchOS project (stdlib only)."""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true', help='Fail if tracked project files differ from reproducible generation; write nothing.')
args = parser.parse_args()
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(s): return json.dumps(s)
# Personal signing is supplied by Configuration/Signing.local.xcconfig.
# Generated public files never depend on that file, the environment, or old output.
objects = []
def obj(name, value):
    objects.append(f'\t\t{uid(name)} = {{ {value} }};')
    return uid(name)

files = sorted(p.name for p in (ROOT/'WatchApp').glob('*.swift'))
atlases = sorted((ROOT/'WatchApp/Art').glob('*.atlas'))
for atlas in atlases:
    relative = 'Art/' + atlas.name
    obj('atlas:'+atlas.name, f'isa = PBXFileReference; lastKnownFileType = folder.skatlas; path = {q(relative)}; sourceTree = \"<group>\";')
    obj('atlasBuild:'+atlas.name, f'isa = PBXBuildFile; fileRef = {uid("atlas:"+atlas.name)};')
for file in files:
    obj('file:'+file, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(file)}; sourceTree = "<group>";')
    obj('build:'+file, f'isa = PBXBuildFile; fileRef = {uid("file:"+file)};')
obj('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
obj('assetsBuild', f'isa = PBXBuildFile; fileRef = {uid("assets")};')
obj('manifest', 'isa = PBXFileReference; lastKnownFileType = text.json; path = Art/runtime_manifest.json; sourceTree = \"<group>\";')
obj('manifestBuild', f'isa = PBXBuildFile; fileRef = {uid("manifest")};')
obj('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = \"<group>\";')
obj('privacyBuild', f'isa = PBXBuildFile; fileRef = {uid("privacy")};')
obj('policyText', 'isa = PBXFileReference; lastKnownFileType = text; path = Policy/Privacy.txt; sourceTree = "<group>";')
obj('policyTextBuild', f'isa = PBXBuildFile; fileRef = {uid("policyText")};')
obj('plist', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PickleBlast.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('watchGroup', f'isa = PBXGroup; path = WatchApp; sourceTree = "<group>"; children = ({", ".join(uid("file:"+f) for f in files)}, {uid("assets")}, {uid("plist")}, {uid("privacy")}, {uid("policyText")}, {uid("manifest")}{"".join(", " + uid("atlas:"+a.name) for a in atlases)});')
obj('testFile', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchUITests/PickleBlastWatchUITests.swift; sourceTree = SOURCE_ROOT;')
obj('testBuild', f'isa = PBXBuildFile; fileRef = {uid("testFile")};')
obj('testProduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PickleBlastWatchUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj('testSources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("testBuild")}); runOnlyForDeploymentPostprocessing = 0;')
obj('testFrameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('testResources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('testProxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target")}; remoteInfo = PickleBlast;')
obj('testDependency', f'isa = PBXTargetDependency; target = {uid("target")}; targetProxy = {uid("testProxy")};')
obj('products', f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({uid("product")}, {uid("testProduct")});')
obj('signing', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Signing.xcconfig; sourceTree = "<group>";')
obj('signingExample', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Signing.example.xcconfig; sourceTree = "<group>";')
obj('configurationGroup', f'isa = PBXGroup; path = Configuration; sourceTree = "<group>"; children = ({uid("signing")}, {uid("signingExample")});')
obj('rootGroup', f'isa = PBXGroup; sourceTree = "<group>"; children = ({uid("watchGroup")}, {uid("configurationGroup")}, {uid("testFile")}, {uid("products")});')
obj('localPackage', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
for product in ['PickleBlastCore', 'PickleBlastRendering']:
    obj(product, f'isa = XCSwiftPackageProductDependency; productName = {product};')
    obj(product+'Build', f'isa = PBXBuildFile; productRef = {uid(product)};')
obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(uid("build:"+f) for f in files)}); runOnlyForDeploymentPostprocessing = 0;')
obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("assetsBuild")}, {uid("privacyBuild")}, {uid("policyTextBuild")}, {uid("manifestBuild")}{"".join(", " + uid("atlasBuild:"+a.name) for a in atlases)}); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({uid("PickleBlastCoreBuild")}, {uid("PickleBlastRenderingBuild")}); runOnlyForDeploymentPostprocessing = 0;')
for mode in ['Debug', 'Release']:
    common = 'CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SDKROOT = watchos; SWIFT_VERSION = 5.0; WATCHOS_DEPLOYMENT_TARGET = 10.0;'
    project = common + (' DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"; ONLY_ACTIVE_ARCH = YES;' if mode == 'Debug' else ' DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O"; VALIDATE_PRODUCT = YES;')
    app = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 10; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = WatchApp/Info.plist; MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.pickleblast.watchapp; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "watchos watchsimulator"; TARGETED_DEVICE_FAMILY = 4; SKIP_INSTALL = NO; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"; SWIFT_EMIT_LOC_STRINGS = YES;'
    obj('project'+mode, f'isa = XCBuildConfiguration; buildSettings = {{ {project} }}; name = {mode};')
    obj('app'+mode, f'isa = XCBuildConfiguration; baseConfigurationReference = {uid("signing")}; buildSettings = {{ {app} }}; name = {mode};')
    test = 'CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.pickleblast.watchapp.uitests; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "watchos watchsimulator"; TARGETED_DEVICE_FAMILY = 4; TEST_TARGET_NAME = PickleBlast; SWIFT_EMIT_LOC_STRINGS = NO; STRING_CATALOG_GENERATE_SYMBOLS = NO; CURRENT_PROJECT_VERSION = 10; MARKETING_VERSION = 1.0;'
    obj('test'+mode, f'isa = XCBuildConfiguration; baseConfigurationReference = {uid("signing")}; buildSettings = {{ {test} }}; name = {mode};')
for prefix in ['project', 'app', 'test']:
    obj(prefix+'Configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(prefix+"Debug")}, {uid(prefix+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("appConfigs")}; buildPhases = ({uid("sources")}, {uid("frameworks")}, {uid("resources")}); buildRules = (); dependencies = (); name = PickleBlast; packageProductDependencies = ({uid("PickleBlastCore")}, {uid("PickleBlastRendering")}); productName = PickleBlast; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
obj('testTarget', f'isa = PBXNativeTarget; buildConfigurationList = {uid("testConfigs")}; buildPhases = ({uid("testSources")}, {uid("testFrameworks")}, {uid("testResources")}); buildRules = (); dependencies = ({uid("testDependency")}); name = PickleBlastWatchUITests; productName = PickleBlastWatchUITests; productReference = {uid("testProduct")}; productType = \"com.apple.product-type.bundle.ui-testing\";')
obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{ {uid("target")} = {{ CreatedOnToolsVersion = 27.0; }}; {uid("testTarget")} = {{ CreatedOnToolsVersion = 27.0; TestTargetID = {uid("target")}; }}; }}; }}; buildConfigurationList = {uid("projectConfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {uid("rootGroup")}; productRefGroup = {uid("products")}; packageReferences = ({uid("localPackage")}); projectDirPath = ""; projectRoot = ""; targets = ({uid("target")}, {uid("testTarget")});')
project_dir = ROOT / 'PickleBlast.xcodeproj'
project_text = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+uid('project')+';\n}\n'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="PickleBlast.app" BlueprintName="PickleBlast" ReferencedContainer="container:PickleBlast.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('testTarget')}" BuildableName="PickleBlastWatchUITests.xctest" BlueprintName="PickleBlastWatchUITests" ReferencedContainer="container:PickleBlast.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="PickleBlast.app" BlueprintName="PickleBlast" ReferencedContainer="container:PickleBlast.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="PickleBlast.app" BlueprintName="PickleBlast" ReferencedContainer="container:PickleBlast.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = project_dir/'xcshareddata/xcschemes'
outputs = {project_dir/'project.pbxproj': project_text, scheme_dir/'PickleBlast.xcscheme': scheme}
for path in outputs:
    if not path.resolve().is_relative_to(ROOT):
        raise SystemExit('Project generation failed: output path escapes checkout: ' + str(path.relative_to(ROOT)))
if args.check:
    different = [str(path.relative_to(ROOT)) for path, content in outputs.items()
                 if not path.is_file() or path.read_bytes() != content.encode('utf-8')]
    if different:
        raise SystemExit('Project generation check failed: ' + ', '.join(different) + '. Run python3 scripts/generate_project.py.')
    print('PASS: native project and shared scheme match reproducible generation.')
else:
    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')
    print('Generated native standalone watchOS project; local signing configuration remains separate.')
