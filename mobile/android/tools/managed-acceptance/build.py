"""Offline disposable acceptance APK; never uses app signing or app data.
Usage: python3 build.py /absolute/empty/output-dir
Requires installed Android SDK 35 + build-tools 36, JDK 17 and cached Kotlin 2.0.21.
"""
from pathlib import Path
import os, subprocess, sys, zipfile
here=Path(__file__).resolve().parent
out=Path(sys.argv[1]).resolve(); out.mkdir(parents=True,exist_ok=True)
assert not any(out.iterdir()), 'Use an empty disposable output directory'
sdk=Path(os.environ.get('ANDROID_HOME',Path.home()/'Library/Android/sdk'))
jdk=Path(os.environ.get('JAVA_HOME','/opt/homebrew/opt/openjdk@17'))
cache=Path.home()/'.gradle/caches/modules-2/files-2.1'
def jar(g,n,v): return str(next((cache/g/n/v).glob('*/*.jar')))
k='org.jetbrains.kotlin';std=jar(k,'kotlin-stdlib','2.0.21')
compiler=[jar(k,'kotlin-compiler-embeddable','2.0.21'),std,jar(k,'kotlin-script-runtime','2.0.21'),jar(k,'kotlin-daemon-embeddable','2.0.21'),jar('org.jetbrains.intellij.deps','trove4j','1.0.20200330'),jar('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.6.4'),str(next((cache/'org.jetbrains'/'annotations').glob('*/*/*.jar')))]
platform=sdk/'platforms/android-35/android.jar'; bt=sdk/'build-tools/36.0.0'; env=dict(os.environ,JAVA_HOME=str(jdk))
def run(*args): subprocess.run(list(map(str,args)),check=True,env=env)
storage=here.parents[1]/'app/src/main/java/ru/arvectum/proxylauncher/storage'
classes=out/'probe.jar'
run(jdk/'bin/java','-cp',os.pathsep.join(compiler),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','1.8','-classpath',os.pathsep.join([std,str(platform)]),'-d',classes,here/'Probe.kt',*[storage/(name+'.kt') for name in ('ManagedCrashGate','ManagedProfileGateLocation','ManagedVpnProcessLease','ManagedPreferenceDiskVerifier','ManagedRecoveryEvidence','ManagedRecoveryReview')])
run(bt/'d8','--min-api','26','--lib',platform,'--output',out,classes,std)
unsigned=out/'unsigned.apk';aligned=out/'aligned.apk';signed=out/'acceptance.apk'
run(bt/'aapt2','link','-I',platform,'--manifest',here/'AndroidManifest.xml','-o',unsigned)
with zipfile.ZipFile(unsigned,'a') as apk:
    for dex in sorted(out.glob('classes*.dex')): apk.write(dex,dex.name)
run(bt/'zipalign','-f','4',unsigned,aligned)
# Temporary local debug fixture only, with no relation to the production signing chain.
ks=out/'disposable.p12'; password='acceptance-only'
run(jdk/'bin/keytool','-genkeypair','-keystore',ks,'-storepass',password,'-keypass',password,'-alias','fixture','-keyalg','RSA','-keysize','2048','-validity','1','-dname','CN=Disposable Android Acceptance')
run(bt/'apksigner','sign','--ks',ks,'--ks-pass','pass:'+password,'--key-pass','pass:'+password,'--out',signed,aligned)
run(bt/'apksigner','verify',signed)
print(signed)
