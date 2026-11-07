"""Optional native-session test: disposable app copies only, never the installed app."""
import os, plistlib, shutil, signal, subprocess, tempfile, time
from pathlib import Path
root=Path(tempfile.mkdtemp(prefix='Neylu-helper-fixture-',dir='/private/tmp'))
pids=[]
workers=[]
def wait_for(path, process=None):
    deadline=time.monotonic()+25
    while time.monotonic()<deadline:
        if path.exists(): return
        if process is not None and process.poll() is not None: raise RuntimeError('Helper exited before readiness')
        time.sleep(.1)
    raise RuntimeError('Timed out waiting for '+path.name)
try:
    source=root/'fixture.swift'
    source.write_text('''import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let folder = Bundle.main.bundleURL.deletingLastPathComponent()
let phase = try String(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/phase"), encoding: .utf8)
try String(ProcessInfo.processInfo.processIdentifier).write(to: folder.appendingPathComponent(phase + ".pid"), atomically: true, encoding: .utf8)
if phase == "crash" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) } }
app.run()
''')
    binary=root/'Fixture'
    subprocess.run(['xcrun','swiftc',str(source),'-framework','AppKit','-o',str(binary)],check=True)
    target=root/'Neylu.app'; stage=root/'.Neylu-update-fixture';stage.mkdir(mode=0o700)
    def helper_resources():
        for language in ['en','zh-Hans']:
            shutil.copytree(Path('build/Neylu.app/Contents/Resources')/(language+'.lproj'),stage/'Resources'/(language+'.lproj'))
    def fixture(path,phase,version):
        (path/'Contents/MacOS').mkdir(parents=True);(path/'Contents/Resources').mkdir()
        shutil.copy2(binary,path/'Contents/MacOS/Neylu')
        (path/'Contents/Resources/phase').write_text(phase)
        (path/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'Neylu','CFBundleIdentifier':'io.github.chenmobuys.Neylu','CFBundleName':'Neylu Test Fixture','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'0.1.0','NeyluReleaseVersion':version,'LSMinimumSystemVersion':'13.0','LSUIElement':True}))
        subprocess.run(['codesign','--force','--sign','-',str(path)],check=True,capture_output=True)
    fixture(target,'old','0.1.0-alpha.2');fixture(stage/'Neylu.app','new','0.1.0-alpha.3')
    helper=stage/'NeyluUpdater';shutil.copy2('build/Neylu.app/Contents/Helpers/NeyluUpdater',helper)
    helper_resources()
    subprocess.run(['open','-n',str(target)],check=True)
    wait_for(root/'old.pid');oldpid=int((root/'old.pid').read_text());pids.append(oldpid)
    worker=subprocess.Popen([str(helper),str(target),str(oldpid),'0.1.0-alpha.3',os.uname().machine,str(root/'download'),'en'])
    workers.append(worker)
    wait_for(stage/'ready',worker)
    os.kill(oldpid,signal.SIGTERM)
    wait_for(root/'new.pid')
    pids.append(int((root/'new.pid').read_text()))
    result=worker.wait(timeout=35)
    assert result==0, result
    assert (target/'Contents/Resources/phase').read_text()=='new'
    assert not stage.exists()
    print('PASS real native helper readiness, parent shutdown, application replacement, LaunchServices relaunch and staging cleanup')
    # A validly signed candidate that exits immediately must restore and relaunch
    # the previous app. Stop our helper before its error alert is presented.
    previous_pid = pids[-1]
    stage.mkdir(mode=0o700)
    fixture(stage/'Neylu.app','crash','0.1.0-alpha.4')
    helper_resources()
    shutil.copy2('build/Neylu.app/Contents/Helpers/NeyluUpdater',helper)
    worker=subprocess.Popen([str(helper),str(target),str(previous_pid),'0.1.0-alpha.4',os.uname().machine,str(root/'download'),'en'])
    workers.append(worker)
    wait_for(stage/'ready',worker)
    (root/'new.pid').unlink()
    os.kill(previous_pid,signal.SIGTERM)
    wait_for(root/'new.pid')
    restored_pid=int((root/'new.pid').read_text());pids.append(restored_pid)
    assert restored_pid != previous_pid
    assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['NeyluReleaseVersion']=='0.1.0-alpha.3'
    worker.terminate();worker.wait(timeout=5)
    assert not stage.exists()
    print('PASS immediate startup exit restores and relaunches the previous application')
finally:
    for worker in workers:
        if worker.poll() is None:
            worker.terminate();worker.wait(timeout=5)
    for pid in pids:
        try: os.kill(pid,signal.SIGTERM)
        except ProcessLookupError: pass
    shutil.rmtree(root,ignore_errors=True)
