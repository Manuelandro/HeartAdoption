#!/usr/bin/env python3
"""Generate a deterministic Xcode project using only Python's standard library."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / 'HeartAdoption.xcodeproj'
PROJECT.mkdir(exist_ok=True)
objects = {}

def ident(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

def obj(key, text):
    value = ident(key)
    objects[value] = text
    return value

def array(values):
    return '(' + ', '.join(values) + (',)' if values else ')')

def file(path, kind):
    return obj('file:' + path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{path}"; sourceTree = SOURCE_ROOT;')

def buildfile(ref):
    return obj('build:' + ref, f'isa = PBXBuildFile; fileRef = {ref};')

def phase(key, kind, files):
    return obj(key, f'isa = {kind}; buildActionMask = 2147483647; files = {array([buildfile(f) for f in files])}; runOnlyForDeploymentPostprocessing = 0;')

def configlist(key, settings, base=None):
    configurations = []
    for name in ['Debug', 'Release']:
        extra = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES;' if name == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; VALIDATE_PRODUCT = YES;'
        configurations.append(obj(key + name, f'isa = XCBuildConfiguration; {f"baseConfigurationReference = {base};" if base else ""} buildSettings = {{ {settings} {extra} }}; name = {name};'))
    return obj(key + ':configs', f'isa = XCConfigurationList; buildConfigurations = {array(configurations)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

app_id = ident('target:HeartAdoption')
source_refs = []
target_ids, products = [], []
base_config = file('Config/Base.xcconfig', 'text.xcconfig')
for name, folder, product_type in [('HeartAdoption', 'HeartAdoption', 'application'), ('HeartAdoptionTests', 'HeartAdoptionTests', 'bundle.unit-test'), ('HeartAdoptionUITests', 'HeartAdoptionUITests', 'bundle.ui-testing')]:
    refs = [file(str(p.relative_to(ROOT)), 'sourcecode.swift') for p in sorted((ROOT / folder).glob('*.swift'))]
    source_refs += refs
    resources = []
    if name == 'HeartAdoption':
        resources = [file('HeartAdoption/Assets.xcassets', 'folder.assetcatalog'), file('Resources/countries.json', 'text.json'), file('HeartAdoption/PrivacyInfo.xcprivacy', 'text.xml')]
        source_refs += resources
    phases = [phase(name + ':sources', 'PBXSourcesBuildPhase', refs), phase(name + ':frameworks', 'PBXFrameworksBuildPhase', []), phase(name + ':resources', 'PBXResourcesBuildPhase', resources)]
    ext = '.app' if name == 'HeartAdoption' else '.xctest'
    product = obj(name + ':product', f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if ext == ".app" else "wrapper.cfbundle"}; includeInIndex = 0; path = {name}{ext}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    settings = f'PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.manuelandro.{name}; CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES;'
    if name == 'HeartAdoption':
        settings += ' GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = Config/Info.plist; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 1;'
    elif name == 'HeartAdoptionTests':
        settings += ' TEST_HOST = "$(BUILT_PRODUCTS_DIR)/HeartAdoption.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/HeartAdoption"; BUNDLE_LOADER = "$(TEST_HOST)";'
    else:
        settings += ' TEST_TARGET_NAME = HeartAdoption;'
    dependencies = []
    if name != 'HeartAdoption':
        proxy = obj(name + ':proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = HeartAdoption;')
        dependencies = [obj(name + ':dependency', f'isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy};')]
    configs = configlist(name, settings, base_config if name == 'HeartAdoption' else None)
    target_ids.append(obj('target:' + name, f'isa = PBXNativeTarget; buildConfigurationList = {configs}; buildPhases = {array(phases)}; buildRules = (); dependencies = {array(dependencies) if dependencies else "()"}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{product_type}";'))

product_group = obj('products', f'isa = PBXGroup; children = {array(products)}; name = Products; sourceTree = "<group>";')
main_group = obj('main', f'isa = PBXGroup; children = {array(source_refs + [base_config, product_group])}; sourceTree = "<group>";')
project_config = configlist('project', 'CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; TARGETED_DEVICE_FAMILY = "1,2"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SWIFT_STRICT_CONCURRENCY = minimal;')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2620; BuildIndependentTargetsInParallel = YES; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {array(target_ids)};')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text += '\n'.join(f'{key} = {{ {value} }};' for key, value in sorted(objects.items()))
text += f'\n}}; rootObject = {ident("project")}; }}\n'
(PROJECT / 'project.pbxproj').write_text(text)

def reference(name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target:" + name)}" BuildableName="{name}{".app" if name == "HeartAdoption" else ".xctest"}" BlueprintName="{name}" ReferencedContainer="container:HeartAdoption.xcodeproj"/>'

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2620" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference('HeartAdoption')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference('HeartAdoptionTests')}</TestableReference><TestableReference skipped="NO">{reference('HeartAdoptionUITests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('HeartAdoption')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('HeartAdoption')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
schemes = PROJECT / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'HeartAdoption.xcscheme').write_text(scheme)
print('Generated HeartAdoption.xcodeproj')
