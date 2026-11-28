"""Reproducible UI smoke on the named, disposable API36 ARM64 AVD only.
Requires fresh install of build-enabled-ui.py artifact, English system locale.
Never grants VPN consent or reads credentials.
"""
import re, subprocess, time, xml.etree.ElementTree as E
from pathlib import Path
ADB=Path.home()/'Library/Android/sdk/platform-tools/adb'
SERIAL='emulator-5580'
PACKAGE='ru.arvectum.proxylauncher.acceptanceui'
LAUNCHER=PACKAGE+'/ru.arvectum.proxylauncher.LauncherActivity'
def cmd(*args):
    return subprocess.check_output([str(ADB),'-s',SERIAL,*args],text=True,timeout=15)
def dump():
    cmd('shell','uiautomator','dump','/sdcard/apl-window.xml')
    return list(E.fromstring(cmd('shell','cat','/sdcard/apl-window.xml')).iter('node'))
def node(text):
    result=[n for n in dump() if n.get('text')==text or n.get('content-desc')==text]
    assert len(result)==1,text
    return result[0]
def tap(text):
    xy=list(map(int,re.findall(r'\d+',node(text).get('bounds'))))
    cmd('shell','input','tap',str((xy[0]+xy[2])//2),str((xy[1]+xy[3])//2));time.sleep(.3)
def visible(text): return any(n.get('text')==text for n in dump())
def field(hint,value):
    tap(hint);cmd('shell','input','text',value);cmd('shell','input','keyevent','4');time.sleep(.2)
def saved():
    tap('CONFIRM');assert visible('Changes saved.');tap('OK')
def report(name): print(name+'=PASS',flush=True)
def subscription(action):
    tap('HTTPS subscription');tap('1. example.com');tap(action)
def main():
    assert cmd('emu','avd','name').splitlines()[0].strip()=='apl_enabled_ui'
    assert cmd('shell','getprop','ro.kernel.qemu').strip()=='1'
    assert cmd('shell','getprop','ro.build.version.sdk').strip()=='36'
    info=cmd('shell','dumpsys','package',PACKAGE)
    assert 'android.permission.INTERNET: granted=true' not in info
    assert cmd('shell','pm','path',PACKAGE).startswith('package:')
    cmd('shell','am','start','-W','-n',LAUNCHER);assert visible('Add a proxy') or visible('Select a proxy')
    report('ui_launch')
    tap('Profiles');tap('+ New');field('E.g. Primary','A%sanchor');field('proxy.example.com','anchor.invalid');field('8000','8080')
    tap('Auto protocol');tap('HTTP/HTTPS (CONNECT)');tap('Priority for Auto mode');tap('Save')
    tap('HTTPS subscription');tap('SAVE URL');field('https://','https://example.com/apl-fixture');tap('SAVE URL');tap('1. example.com');tap('Download')
    texts=[n.get('text') or '' for n in dump()]
    assert any('Add · HTTP · managed.invalid:8081' in t for t in texts)
    assert not any('first-fixture' in t or 'second-fixture' in t for t in texts)
    saved();report('ui_import')
    subscription('Download')
    assert any('Update · HTTP · managed.invalid:8081' in (n.get('text') or '') for n in dump())
    report('ui_update_preview')
    assert node('CONFIRM').get('enabled')=='false'
    tap('I understand that the previous undo will no longer be available.')
    assert node('CONFIRM').get('enabled')=='true'
    saved();report('ui_explicit_replacement_consent')
    subscription('Undo update');saved();report('ui_rollback')
    subscription('Remove subscription')
    cmd('shell','input','keyevent','3');time.sleep(.5);cmd('shell','am','start','-W','-n',LAUNCHER);time.sleep(.5)
    assert not visible('CONFIRM');report('ui_background_cancel')
    subscription('Remove subscription');assert visible('Profiles remain on this device. Profiles to detach: 1.')
    saved();tap('HTTPS subscription');assert visible('No saved subscriptions');tap('CANCEL');tap('⌄')
    assert any('managed.invalid:8081' in (n.get('text') or '') for n in dump())
    report('ui_detach_preserves_profile')
    cmd('shell','input','keyevent','4');tap('Home');tap('Connect');assert visible('Connection request');tap('Cancel')
    assert visible('Connect');assert 'ProxyVpnService' not in cmd('shell','dumpsys','activity','services',PACKAGE)
    report('ui_vpn_permission_denied')
    print('result=PASS',flush=True)
if __name__=='__main__':main()
