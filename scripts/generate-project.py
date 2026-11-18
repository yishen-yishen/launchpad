#!/usr/bin/env python3
"""Deterministic Xcode project using a local Swift package for the core module."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(name, text):
    key = ident(name); objects[key] = text; return key
files = []
for path in sorted((root/'Sources/LaunchDock').glob('*.swift')):
    ref = obj(str(path.name), f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Sources/LaunchDock/{path.name}; sourceTree = SOURCE_ROOT;}}')
    files.append(obj('build'+path.name, f'{{isa = PBXBuildFile; fileRef = {ref};}}'))
app = obj('app', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = LaunchDock.app; sourceTree = BUILT_PRODUCTS_DIR;}')
group = obj('group', '{isa = PBXGroup; children = ('+', '.join([ident(p.name) for p in sorted((root/'Sources/LaunchDock').glob('*.swift'))]+[app])+'); sourceTree = "<group>";}')
source = obj('source','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+', '.join(files)+'); runOnlyForDeploymentPostprocessing = 0;}')
package = obj('package', '{isa = XCLocalSwiftPackageReference; relativePath = .;}')
core = obj('core', f'{{isa = XCSwiftPackageProductDependency; package = {package}; productName = LaunchDockCore;}}')
corebuild = obj('corebuild', f'{{isa = PBXBuildFile; productRef = {core};}}')
frameworks = obj('frameworks', f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({corebuild}); runOnlyForDeploymentPostprocessing = 0;}}')
def configs(prefix, settings):
    ids = []
    for name in ['Debug','Release']:
        ids.append(obj(prefix+name, '{isa = XCBuildConfiguration; name = '+name+'; buildSettings = {'+settings+ ('ONLY_ACTIVE_ARCH = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if name=='Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')+'};}'))
    return obj(prefix+'list','{isa = XCConfigurationList; buildConfigurations = ('+', '.join(ids)+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
settings = 'ALWAYS_SEARCH_USER_PATHS = NO; SWIFT_VERSION = 6.0; MACOSX_DEPLOYMENT_TARGET = 26.0; SDKROOT = macosx;'
pc = configs('project',settings)
tc = configs('target',settings+'PRODUCT_BUNDLE_IDENTIFIER = app.launchdock.LaunchDock; PRODUCT_NAME = LaunchDock; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Config/LaunchDock-Info.plist; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"; INFOPLIST_KEY_CFBundleDisplayName = LaunchDock; MARKETING_VERSION = 0.0.1; CURRENT_PROJECT_VERSION = 1; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = NO; COMBINE_HIDPI_IMAGES = YES;')
target = obj('target',f'{{isa = PBXNativeTarget; name = LaunchDock; buildConfigurationList = {tc}; buildPhases = ({source}, {frameworks}); buildRules = (); dependencies = (); packageProductDependencies = ({core}); productName = LaunchDock; productReference = {app}; productType = "com.apple.product-type.application";}}')
testref = obj('testref', '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/LaunchDockCoreTests/CoreTests.swift; sourceTree = SOURCE_ROOT;}')
testfile = obj('testfile', f'{{isa = PBXBuildFile; fileRef = {testref};}}')
testsource = obj('testsource', f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({testfile}); runOnlyForDeploymentPostprocessing = 0;}}')
testproduct = obj('testproduct', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = LaunchDockTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
testcore = obj('testcore', f'{{isa = PBXBuildFile; productRef = {core};}}')
testframework = obj('testframework', f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({testcore}); runOnlyForDeploymentPostprocessing = 0;}}')
testconfig = configs('tests', settings+'PRODUCT_NAME = LaunchDockTests; PRODUCT_BUNDLE_IDENTIFIER = app.launchdock.Tests; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual;')
testtarget = obj('testtarget', f'{{isa = PBXNativeTarget; name = LaunchDockTests; buildConfigurationList = {testconfig}; buildPhases = ({testsource}, {testframework}); buildRules = (); dependencies = (); packageProductDependencies = ({core}); productName = LaunchDockTests; productReference = {testproduct}; productType = "com.apple.product-type.bundle.unit-test";}}')
objects[group] = objects[group].replace('children = (', f'children = ({testref}, {testproduct}, ')
project = obj('project',f'{{isa = PBXProject; attributes = {{LastUpgradeCheck = 2600;}}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; knownRegions = (en, zh_CN, Base); mainGroup = {group}; packageReferences = ({package}); projectDirPath = ""; projectRoot = ""; targets = ({target}, {testtarget});}}')
(root/'LaunchDock.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+';}\n')
(root/'LaunchDock.xcodeproj/xcshareddata/xcschemes/LaunchDock.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="LaunchDock.app" BlueprintName="LaunchDock" ReferencedContainer="container:LaunchDock.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testtarget}" BuildableName="LaunchDockTests.xctest" BlueprintName="LaunchDockTests" ReferencedContainer="container:LaunchDock.xcodeproj"/></TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="LaunchDock.app" BlueprintName="LaunchDock" ReferencedContainer="container:LaunchDock.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
