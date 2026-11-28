"""Disposable enabled MainActivity build, synthetic subscription payloads, no INTERNET permission.
Does not change tracked activation or access the project signing directory.
Usage: build-enabled-ui.py OUT CI_PRIVATE_APK SHA256 ZXING_JAR
"""
import hashlib, os, shutil, subprocess, sys, zipfile
from pathlib import Path
import xml.etree.ElementTree as ET
here=Path(__file__).resolve().parent
assert len(sys.argv)==5
out=Path(sys.argv[1]).resolve();out.mkdir(parents=True,exist_ok=True)
assert not any(out.iterdir())
artifact=Path(sys.argv[2]);assert hashlib.sha256(artifact.read_bytes()).hexdigest()==sys.argv[3]
sdk=Path.home()/'Library/Android/sdk';jdk=Path('/opt/homebrew/opt/openjdk@17')
bt=sdk/'build-tools/36.0.0';platform=sdk/'platforms/android-35/android.jar'
cache=Path.home()/'.gradle/caches/modules-2/files-2.1'
def jar(g,n,v):return next((cache/g/n/v).glob('*/*.jar'))
k='org.jetbrains.kotlin';std=jar(k,'kotlin-stdlib','2.0.21')
compiler=[jar(k,'kotlin-compiler-embeddable','2.0.21'),std,jar(k,'kotlin-script-runtime','2.0.21'),jar(k,'kotlin-daemon-embeddable','2.0.21'),jar('org.jetbrains.intellij.deps','trove4j','1.0.20200330'),jar('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.6.4'),next((cache/'org.jetbrains'/'annotations').glob('*/*/*.jar'))]
def run(*args):subprocess.run(list(map(str,args)),check=True,env=dict(os.environ,JAVA_HOME=str(jdk)))
src=here.parents[1]/'app/src'
for name in ('main','private'):shutil.copytree(src/name,out/name)
main=out/'main'
package='ru.arvectum.proxylauncher.acceptanceui'
base=main/'java/ru/arvectum/proxylauncher'
controller=base/'ui/ManagedSubscriptionController.kt'
s=controller.read_text();assert s.count('const val ENABLED = false')==1
controller.write_text(s.replace('const val ENABLED = false','const val ENABLED = true'))
activity=base/'MainActivity.kt'
s=activity.read_text();assert s.count('val items = fetch.load()')==1
# Only replace the result producer in the disposable copy; keep real request/ticket,
# parser, dialog, lifecycle, storage and review paths. No outbound network.
activity.write_text(s.replace('val items = fetch.load()', '''val items = try {
                fetch.cancel()
                if (managedRequest?.url == "https://example.com/apl-fixture") {
                    val count = FixturePayload.next.incrementAndGet()
                    val password = if(count == 1) "first-fixture" else "second-fixture"
                    ru.arvectum.proxylauncher.model.ProxySubscriptionImport.decode(
                        "http://fixture:$password@managed.invalid:8081".toByteArray())
                } else null
            } catch (_:Exception) { null }'''))
(base/'FixturePayload.kt').write_text('package ru.arvectum.proxylauncher\ninternal object FixturePayload { val next=java.util.concurrent.atomic.AtomicInteger() }\n')
manifest=main/'AndroidManifest.xml';ns='{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android',ns[1:-1]);tree=ET.parse(manifest);root=tree.getroot();root.set('package','ru.arvectum.proxylauncher')
ET.SubElement(root,'uses-sdk',{ns+'minSdkVersion':'26',ns+'targetSdkVersion':'35'})
for node in list(root.findall('uses-permission')):
    if node.get(ns+'name')=='android.permission.INTERNET':root.remove(node)
for node in root.findall('application/provider'):node.set(ns+'authorities',package+'.qrshare')
tree.write(manifest,encoding='utf-8',xml_declaration=True)
draw=main/'res/drawable-nodpi';draw.mkdir(exist_ok=True)
with zipfile.ZipFile(artifact) as z:
    for name in ('arvectum_mark.png','arvectum_launcher_foreground.png'):
        (draw/name).write_bytes(z.read('res/drawable-nodpi-v4/'+name))
core=next((cache/'androidx.core/core/1.15.0').glob('*/*.aar'))
with zipfile.ZipFile(core) as z:
    (out/'androidx-core.jar').write_bytes(z.read('classes.jar'))
deps=[Path(sys.argv[4]),jar('com.squareup.okhttp3','okhttp','4.12.0'),jar('com.squareup.okio','okio-jvm','3.6.0'),out/'androidx-core.jar',jar('androidx.annotation','annotation-jvm','1.8.2')]
for file,digest in zip(deps[:3],['71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13','b1050081b14bb7a3a7e55a4d3ef01b5dcfabc453b4573a4fc019767191d5f4e0','67543f0736fc422ae927ed0e504b98bc5e269fda0d3500579337cb713da28412']):
    assert hashlib.sha256(file.read_bytes()).hexdigest()==digest, file.name
generated=out/'generated';generated.mkdir();classes=out/'classes';classes.mkdir()
run(bt/'aapt2','compile','--dir',main/'res','-o',out/'res.zip')
run(bt/'aapt2','link','-I',platform,'--manifest',manifest,'--rename-manifest-package',package,'--custom-package','ru.arvectum.proxylauncher','--java',generated,'-o',out/'unsigned.apk',out/'res.zip')
run(jdk/'bin/javac','-source','8','-target','8','-classpath',platform,'-d',classes,*sorted(generated.rglob('*.java')),*sorted(main.rglob('*.java')))
run(jdk/'bin/java','-cp',os.pathsep.join(map(str,compiler)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','1.8','-classpath',os.pathsep.join(map(str,[std,platform,classes,*deps])),'-d',out/'app.jar',*sorted(main.rglob('*.kt')),*sorted((out/'private').rglob('*.kt')))
run(bt/'d8','--min-api','26','--lib',platform,'--output',out,out/'app.jar',std,*deps,*sorted(classes.rglob('*.class')))
with zipfile.ZipFile(out/'unsigned.apk','a') as z:
    for file in sorted(out.glob('classes*.dex')):z.write(file,file.name)
run(bt/'zipalign','-f','4',out/'unsigned.apk',out/'aligned.apk')
ks=out/'fixture.p12';pw='fixture-only'
run(jdk/'bin/keytool','-genkeypair','-keystore',ks,'-storepass',pw,'-keypass',pw,'-alias','fixture','-keyalg','RSA','-keysize','2048','-validity','1','-dname','CN=Disposable UI Acceptance')
run(bt/'apksigner','sign','--ks',ks,'--ks-pass','pass:'+pw,'--key-pass','pass:'+pw,'--out',out/'acceptance-ui.apk',out/'aligned.apk')
run(bt/'apksigner','verify',out/'acceptance-ui.apk')
print(out/'acceptance-ui.apk')
