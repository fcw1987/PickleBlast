#!/usr/bin/env python3
"""Static portable project/resource checks; not a substitute for xcodebuild."""
from pathlib import Path
import json
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise SystemExit('Project check failed: ' + message)


plist = plistlib.loads((root / 'WatchApp/Info.plist').read_bytes())
require(plist.get('WKWatchOnly') is True and plist.get('WKApplication') is True,
        'Application must remain standalone Watch-only.')
require('WKCompanionAppBundleIdentifier' not in plist, 'Unexpected phone companion reference.')
require(plist.get('CFBundleVersion') == '$(CURRENT_PROJECT_VERSION)' and
        plist.get('CFBundleShortVersionString') == '$(MARKETING_VERSION)',
        'Version metadata must use project settings.')
privacy = plistlib.loads((root / 'WatchApp/PrivacyInfo.xcprivacy').read_bytes())
require(privacy.get('NSPrivacyTracking') is False and
        privacy.get('NSPrivacyTrackingDomains') == [] and
        privacy.get('NSPrivacyCollectedDataTypes') == [], 'Unexpected privacy declarations.')
require(privacy.get('NSPrivacyAccessedAPITypes') == [{
    'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults',
    'NSPrivacyAccessedAPITypeReasons': ['CA92.1']}], 'Unexpected required-reason declarations.')

project_path = root / 'PickleBlast.xcodeproj/project.pbxproj'
p = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project_path)]))
objects = p['objects']
project = objects[p['rootObject']]
targets = {objects[t]['name']: objects[t] for t in project['targets']}
require(set(targets) == {'PickleBlast', 'PickleBlastWatchUITests'}, 'Unexpected native targets.')
app = targets['PickleBlast']
test = targets['PickleBlastWatchUITests']
require(app['productType'] == 'com.apple.product-type.application', 'Incorrect app product type.')
require(test['productType'] == 'com.apple.product-type.bundle.ui-testing', 'Incorrect UI-test product type.')

# Resolve group references from the checkout, never a developer's absolute path.
resolved = {}


def visit(oid, parent):
    obj = objects[oid]
    if obj.get('sourceTree') == 'BUILT_PRODUCTS_DIR':
        return
    require(obj.get('sourceTree') in {'<group>', 'SOURCE_ROOT'}, 'Unsupported source reference.')
    path = Path(obj.get('path', ''))
    require(not path.is_absolute() and '..' not in path.parts, 'Nonportable source reference.')
    base = root if obj['sourceTree'] == 'SOURCE_ROOT' else parent
    location = base / path
    require(location.resolve().is_relative_to(root), 'Source reference escapes checkout.')
    if obj['isa'] == 'PBXGroup':
        for child in obj['children']:
            visit(child, location)
    else:
        require(location.exists(), 'Missing source reference: ' + str(location.relative_to(root)))
        resolved[oid] = location.relative_to(root).as_posix()


visit(project['mainGroup'], root)
packages = [objects[oid] for oid in project['packageReferences']]
require(len(packages) == 1 and packages[0].get('relativePath') == '.', 'Nonportable package reference.')
products = {objects[oid]['productName'] for oid in app['packageProductDependencies']}
require(products == {'PickleBlastCore', 'PickleBlastRendering'}, 'Unexpected package dependencies.')
for product in products:
    require((root / 'Sources' / product).is_dir(), 'Missing package source: ' + product)


def phase_paths(target, phase_type):
    phases = [objects[oid] for oid in target['buildPhases'] if objects[oid]['isa'] == phase_type]
    require(len(phases) == 1, 'Expected one ' + phase_type)
    return [resolved[objects[oid]['fileRef']] for oid in phases[0]['files']]


app_sources = phase_paths(app, 'PBXSourcesBuildPhase')
require(len(app_sources) == len(set(app_sources)) and
        set(app_sources) == {path.relative_to(root).as_posix() for path in (root / 'WatchApp').glob('*.swift')},
        'Watch Swift source membership differs from checkout.')
require(phase_paths(test, 'PBXSourcesBuildPhase') == ['WatchUITests/PickleBlastWatchUITests.swift'],
        'Unexpected UI-test source membership.')
resources = phase_paths(app, 'PBXResourcesBuildPhase')
expected_resources = {'WatchApp/Assets.xcassets', 'WatchApp/PrivacyInfo.xcprivacy',
                      'WatchApp/Art/runtime_manifest.json'} | {
    path.relative_to(root).as_posix() for path in (root / 'WatchApp/Art').glob('*.atlas')}
require(len(resources) == len(set(resources)) and set(resources) == expected_resources,
        'App resource membership differs from runtime inputs.')

signing_id = next((oid for oid, path in resolved.items() if path == 'Configuration/Signing.xcconfig'), None)
require(signing_id is not None, 'Missing portable signing configuration.')
signing = (root / 'Configuration/Signing.xcconfig').read_text()
require(re.findall(r'^DEVELOPMENT_TEAM[ \t]*=[ \t]*(.*)$', signing, re.MULTILINE) == [''] and
        '#include? "Signing.local.xcconfig"' in signing, 'Signing defaults must remain account-free.')
versions = set()
for target in [app, test]:
    configurations = [objects[oid] for oid in objects[target['buildConfigurationList']]['buildConfigurations']]
    require({config['name'] for config in configurations} == {'Debug', 'Release'}, 'Missing native build configuration.')
    for config in configurations:
        settings = config['buildSettings']
        require(config.get('baseConfigurationReference') == signing_id and 'DEVELOPMENT_TEAM' not in settings,
                'Native signing must come from portable/local configuration.')
        require(settings.get('CODE_SIGN_STYLE') == 'Automatic' and
                settings.get('TARGETED_DEVICE_FAMILY') == '4' and
                settings.get('SUPPORTED_PLATFORMS') == 'watchos watchsimulator', 'Incorrect Watch target settings.')
        expected_bundle = 'com.pickleblast.watchapp' + ('.uitests' if target is test else '')
        require(settings.get('PRODUCT_BUNDLE_IDENTIFIER') == expected_bundle, 'Changed application identity.')
        versions.add((settings.get('MARKETING_VERSION'), settings.get('CURRENT_PROJECT_VERSION')))
require(len(versions) == 1 and all(next(iter(versions))), 'App and test versions must match.')
for oid in objects[project['buildConfigurationList']]['buildConfigurations']:
    config = objects[oid]
    settings = config['buildSettings']
    require(settings.get('WATCHOS_DEPLOYMENT_TARGET') == '10.0', 'Changed minimum supported watchOS.')
    require(settings.get('SWIFT_OPTIMIZATION_LEVEL') == ('-Onone' if config['name'] == 'Debug' else '-O'),
            'Incorrect Debug/Release optimization.')
    if config['name'] == 'Release':
        require(settings.get('SWIFT_COMPILATION_MODE') == 'wholemodule' and
                'DEBUG' not in settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', ''),
                'Release must remain optimized without DEBUG conditions.')
require(all('DEVELOPMENT_TEAM' not in obj.get('buildSettings', {}) for obj in objects.values()),
        'Inline development team found in public project.')

for icon_set in (root / 'WatchApp/Assets.xcassets').glob('*.appiconset'):
    manifest = json.loads((icon_set / 'Contents.json').read_text())
    for item in manifest['images']:
        filename = Path(item['filename'])
        require(not filename.is_absolute() and '..' not in filename.parts and (icon_set / filename).is_file(),
                'Missing or invalid icon file.')
scheme = ET.parse(root / 'PickleBlast.xcodeproj/xcshareddata/xcschemes/PickleBlast.xcscheme').getroot()
require(scheme.find('ArchiveAction').get('buildConfiguration') == 'Release', 'Archive must use Release.')
require(scheme.find('TestAction').get('buildConfiguration') == 'Debug', 'UI tests must use Debug by default.')
target_ids = set(project['targets'])
for reference in scheme.findall('.//BuildableReference'):
    require(reference.get('BlueprintIdentifier') in target_ids and
            reference.get('ReferencedContainer') == 'container:PickleBlast.xcodeproj', 'Invalid shared scheme target.')
require(all(objects[oid]['buildSettings'].get('SKIP_INSTALL') == 'NO'
            for oid in objects[app['buildConfigurationList']]['buildConfigurations']), 'App must be archivable.')
print('PASS: portable native targets, source/resource references, signing defaults, versions, optimization, privacy, icons and shared scheme.')
