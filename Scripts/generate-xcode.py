#!/usr/bin/env python3
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
proj=root/'StudyPilot.xcodeproj'; (proj/'xcshareddata/xcschemes').mkdir(parents=True,exist_ok=True)
def uid(name):return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects=[]
def obj(key,body):objects.append(f'\t\t{uid(key)} = {{ {body} }};')
files=sorted((root/'Sources/StudyPilot').rglob('*.swift'))
for p in files:
    rel=str(p.relative_to(root)); obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = "<group>";')
    obj('build:'+rel, f'isa = PBXBuildFile; fileRef = {uid(rel)};')
resources=['Resources/StudyPilot.icns','Resources/PrivacyInfo.xcprivacy']
for p in resources:
    obj(p, f'isa = PBXFileReference; lastKnownFileType = '+('image.icns' if p.endswith('icns') else 'text.xml')+f'; path = "{p}"; sourceTree = "<group>";')
    obj('build:'+p,f'isa = PBXBuildFile; fileRef = {uid(p)};')
obj('app','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = StudyPilot.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('root', 'isa = PBXGroup; children = ('+', '.join(uid(str(p.relative_to(root))) for p in files)+', '+', '.join(uid(p) for p in resources)+', '+uid('products')+'); sourceTree = "<group>";')
obj('products',f'isa = PBXGroup; children = ({uid("app")}); name = Products; sourceTree = "<group>";')
obj('sources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+', '.join(uid('build:'+str(p.relative_to(root))) for p in files)+'); runOnlyForDeploymentPostprocessing = 0;')
obj('resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+', '.join(uid('build:'+p) for p in resources)+'); runOnlyForDeploymentPostprocessing = 0;')
for name in ['StudyPilotCore','StudyPilotData','Sparkle']:
    obj(name,f'isa = XCSwiftPackageProductDependency; package = {uid("sparklePackage" if name == "Sparkle" else "package")}; productName = {name};')
    obj('link:'+name,f'isa = PBXBuildFile; productRef = {uid(name)};')
obj('sparklePackage', 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/sparkle-project/Sparkle"; requirement = { kind = upToNextMajorVersion; minimumVersion = 2.10.0; };')
obj('embedSparkle', f'isa = PBXBuildFile; productRef = {uid("Sparkle")}; settings = {{ ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy); }};')
obj('embedFrameworks', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 10; files = ({uid("embedSparkle")}); name = "Embed Frameworks"; runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({uid("link:StudyPilotCore")}, {uid("link:StudyPilotData")}, {uid("link:Sparkle")}); runOnlyForDeploymentPostprocessing = 0;')
obj('package','isa = XCLocalSwiftPackageReference; relativePath = .;')
obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")}, {uid("frameworks")}, {uid("resources")}, {uid("embedFrameworks")}); buildRules = (); dependencies = (); name = StudyPilot; packageProductDependencies = ({uid("StudyPilotCore")}, {uid("StudyPilotData")}, {uid("Sparkle")}); productName = StudyPilot; productReference = {uid("app")}; productType = "com.apple.product-type.application";')
for mode in ['Debug','Release']:
    obj('project'+mode,f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 6.0; SWIFT_STRICT_CONCURRENCY = complete; }}; name = {mode};')
    flags='SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES;' if mode=='Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule;'
    obj('target'+mode,f'''isa = XCBuildConfiguration; buildSettings = {{
        ARCHS = arm64; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual;
        COMBINE_HIDPI_IMAGES = YES; ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES;
        GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = Resources/Info.plist;
        LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");
        PRODUCT_BUNDLE_IDENTIFIER = com.studypilot.app; PRODUCT_NAME = StudyPilot;
        SWIFT_EMIT_LOC_STRINGS = YES; {flags}
    }}; name = {mode};''')
for group in ['target','project']:
    obj(group+'configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(group+"Debug")}, {uid(group+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {uid("root")}; packageReferences = ({uid("package")}, {uid("sparklePackage")}); productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
(proj/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+uid('project')+';\n}\n')
buildable=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="StudyPilot.app" BlueprintName="StudyPilot" ReferencedContainer="container:StudyPilot.xcodeproj"/>'
(proj/'xcshareddata/xcschemes/StudyPilot.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
