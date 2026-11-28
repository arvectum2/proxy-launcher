"""Offline disposable acceptance APK; never uses app signing or app data.
Usage: python3 build.py /absolute/empty/output-dir
Requires installed Android SDK 35 + build-tools 36, JDK 17 and cached Kotlin 2.0.21.
"""
from pathlib import Path
import hashlib, os, subprocess, sys, zipfile
import xml.etree.ElementTree as ET
here=Path(__file__).resolve().parent
out=Path(sys.argv[1]).resolve(); out.mkdir(parents=True,exist_ok=True)
assert not any(out.iterdir()), 'Use an empty disposable output directory'
# Optional native fixture only: explicitly provided, digest-verified CI artifact.
assert len(sys.argv) in (2,4), 'build.py OUT [CI_PRIVATE_APK SHA256]'
native=None
if len(sys.argv)==4:
    source=Path(sys.argv[2]);assert hashlib.sha256(source.read_bytes()).hexdigest()==sys.argv[3]
    with zipfile.ZipFile(source) as archive:
        native=archive.read('lib/arm64-v8a/libtun2proxy.so')
    assert native[:4]==b'\x7fELF' and native[18:20]==bytes((183,0))
sdk=Path(os.environ.get('ANDROID_HOME',Path.home()/'Library/Android/sdk'))
jdk=Path(os.environ.get('JAVA_HOME','/opt/homebrew/opt/openjdk@17'))
cache=Path.home()/'.gradle/caches/modules-2/files-2.1'
def jar(g,n,v): return str(next((cache/g/n/v).glob('*/*.jar')))
k='org.jetbrains.kotlin';std=jar(k,'kotlin-stdlib','2.0.21')
compiler=[jar(k,'kotlin-compiler-embeddable','2.0.21'),std,jar(k,'kotlin-script-runtime','2.0.21'),jar(k,'kotlin-daemon-embeddable','2.0.21'),jar('org.jetbrains.intellij.deps','trove4j','1.0.20200330'),jar('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.6.4'),str(next((cache/'org.jetbrains'/'annotations').glob('*/*/*.jar')))]
platform=sdk/'platforms/android-35/android.jar'; bt=sdk/'build-tools/36.0.0'; env=dict(os.environ,JAVA_HOME=str(jdk))
def run(*args): subprocess.run(list(map(str,args)),check=True,env=env)
storage=here.parents[1]/'app/src/main/java/ru/arvectum/proxylauncher/storage'
model=storage.parent/'model'
routing=storage.parent/'routing'
classes=out/'probe.jar'
java_classes=out/'java';java_classes.mkdir()
unsigned=out/'unsigned.apk';aligned=out/'aligned.apk';signed=out/'acceptance.apk'
res=here.parents[1]/'app/src/main/res'
flats=out/'flats';flats.mkdir();generated=out/'generated';generated.mkdir()
for locale in ('values','values-en'):
    run(bt/'aapt2','compile','-o',flats,res/locale/'managed_review_strings.xml')
manifest=here/'AndroidManifest.xml'
if native is not None:
    ns='{http://schemas.android.com/apk/res/android}'
    ET.register_namespace('android',ns[1:-1]);tree=ET.parse(manifest);root=tree.getroot()
    ET.SubElement(root,'uses-permission',{ns+'name':'android.permission.INTERNET'})
    ET.SubElement(root,'permission',{ns+'name':'ru.arvectum.apl.acceptance.FIXTURE',ns+'protectionLevel':'signature'})
    ET.SubElement(root,'uses-permission',{ns+'name':'ru.arvectum.apl.acceptance.FIXTURE'})
    queries=ET.SubElement(root,'queries')
    ET.SubElement(queries,'package',{ns+'name':'ru.arvectum.apl.acceptance.client'})
    service=ET.SubElement(root.find('application'),'service',{ns+'name':'.NativeFixtureService',ns+'exported':'false',ns+'permission':'android.permission.BIND_VPN_SERVICE',ns+'foregroundServiceType':'specialUse'})
    intent=ET.SubElement(service,'intent-filter');ET.SubElement(intent,'action',{ns+'name':'android.net.VpnService'})
    ET.SubElement(service,'meta-data',{ns+'name':'android.net.VpnService.SUPPORTS_ALWAYS_ON',ns+'value':'false'})
    ET.SubElement(root,'instrumentation',{ns+'name':'.NativeProbe',ns+'targetPackage':'ru.arvectum.apl.acceptance',ns+'functionalTest':'true'})
    manifest=out/'NativeManifest.xml';tree.write(manifest,encoding='utf-8',xml_declaration=True)
run(bt/'aapt2','link','-I',platform,'--manifest',manifest,'--java',generated,'--custom-package','ru.arvectum.proxylauncher','-o',unsigned,*sorted(flats.glob('*.flat')))
run(jdk/'bin/javac','-source','8','-target','8','-d',java_classes,*sorted(generated.rglob('*.java')))
run(jdk/'bin/javac','-source','8','-target','8','-d',java_classes,storage.parent.parent.parent.parent/'com/github/shadowsocks/bg/Tun2proxy.java')
run(jdk/'bin/java','-cp',os.pathsep.join(compiler),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','1.8','-classpath',os.pathsep.join([std,str(platform),str(java_classes)]),'-d',classes,here/'Probe.kt',here/'StoreProbe.kt',here/'VpnProbe.kt',here/'FixtureActivity.kt',here/'DialogProbe.kt',here/'ControllerProbe.kt',*([here/'NativeProbe.kt'] if native is not None else []),storage.parent/'ui/ManagedSubscriptionController.kt',storage.parent/'ui/ManagedReviewMessages.kt',storage.parent/'ui/ManagedReviewDialogs.kt',*[storage/(name+'.kt') for name in ('ManagedCrashGate','ManagedProfileGateLocation','ManagedVpnProcessLease','ManagedPreferenceDiskVerifier','ManagedRecoveryEvidence','ManagedRecoveryReview','SecureProfileStore','SecureSubscriptionStore','ManagedPreferenceTransaction','ManagedCrashTransaction','ManagedChangeReview','ManagedOwnershipReview','ManagedReviewSession')],*[model/(name+'.kt') for name in ('ProxyProfile','ProxyImport','ProxyBatchImport','ProxySubscriptionImport','ProxyStructuredImport','StructuredJsonReader','SavedSubscriptionCatalog','ManagedSubscriptionRefresh','ManagedRollbackJournal','ProxyPoolState')],routing/'ApplicationExclusionPolicy.kt',routing/'SiteExclusionPolicy.kt',storage/'PoolUiStateStore.kt',*sorted((storage.parent/'tunnel').glob('*.kt')))
run(bt/'d8','--min-api','26','--lib',platform,'--output',out,classes,std,*sorted(java_classes.rglob('*.class')))
with zipfile.ZipFile(unsigned,'a') as apk:
    for dex in sorted(out.glob('classes*.dex')): apk.write(dex,dex.name)
    if native is not None: apk.writestr('lib/arm64-v8a/libtun2proxy.so',native)
run(bt/'zipalign','-f','4',unsigned,aligned)
# Temporary local debug fixture only, with no relation to the production signing chain.
ks=out/'disposable.p12'; password='acceptance-only'
run(jdk/'bin/keytool','-genkeypair','-keystore',ks,'-storepass',password,'-keypass',password,'-alias','fixture','-keyalg','RSA','-keysize','2048','-validity','1','-dname','CN=Disposable Android Acceptance')
run(bt/'apksigner','sign','--ks',ks,'--ks-pass','pass:'+password,'--key-pass','pass:'+password,'--out',signed,aligned)
run(bt/'apksigner','verify',signed)
print(signed)

if native is not None:
    client=out/'client';client.mkdir()
    client_classes=client/'java';client_classes.mkdir()
    run(jdk/'bin/javac','-source','8','-target','8','-classpath',platform,'-d',client_classes,here/'NativeClient.java')
    run(bt/'d8','--min-api','26','--lib',platform,'--output',client,*sorted(client_classes.rglob('*.class')))
    client_unsigned=client/'unsigned.apk';client_aligned=client/'aligned.apk'
    run(bt/'aapt2','link','-I',platform,'--manifest',here/'NativeClientManifest.xml','-o',client_unsigned)
    with zipfile.ZipFile(client_unsigned,'a') as apk: apk.write(client/'classes.dex','classes.dex')
    run(bt/'zipalign','-f','4',client_unsigned,client_aligned)
    run(bt/'apksigner','sign','--ks',ks,'--ks-pass','pass:'+password,'--key-pass','pass:'+password,'--out',out/'client.apk',client_aligned)
    run(bt/'apksigner','verify',out/'client.apk')
