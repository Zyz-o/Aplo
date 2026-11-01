#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
python3 - "$project_dir" <<'PY'
from pathlib import Path
import subprocess, sys, plistlib, shutil, os, signal, time, uuid, fcntl
root = Path(sys.argv[1])
sys.dont_write_bytecode = True
sys.path.insert(0, str(root / 'Scripts'))
from install_support import replace_bundle, RollbackFailure
# Serialize installers even when invoked from different source checkouts.
lock = open('/Applications/.Aplo-install.lock', 'a')
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
built = root / 'build/Aplo.app'
identity = 'local.jianqi.SimpleLauncher'
def info(path): return plistlib.loads((path / 'Contents/Info.plist').read_bytes())
package = info(built)
assert package['CFBundleIdentifier'] == identity and package['CFBundleDisplayName'] == 'Aplo'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(built)], check=True)
backup = root / 'build/InstallBackups' / uuid.uuid4().hex[:12]
backup.mkdir(parents=True)
installed = [p for p in [Path('/Applications/Aplo.app'), Path('/Applications/SimpleLauncher.app')] if p.exists()]
for path in installed:
    assert info(path).get('CFBundleIdentifier') == identity, 'Refusing to replace an unrelated app: ' + str(path)
    shutil.copytree(path, backup / (path.name + '.backup'))
layout = Path.home() / 'Library/Application Support/简启/layout.json'
archive = layout.parent / 'Backups'
if layout.exists():
    shutil.copy2(layout, backup / 'layout.json')
    archive = layout.parent / 'Backups'
    archive.mkdir(exist_ok=True)
    shutil.copy2(layout, archive / ('Aplo-before-upgrade-' + backup.name + '.json'))
prefs = subprocess.run(['defaults', 'export', identity, '-'], capture_output=True)
if prefs.returncode == 0: (backup / 'preferences.plist').write_bytes(prefs.stdout)
executables = {str(p / 'Contents/MacOS' / info(p)['CFBundleExecutable']) for p in installed}
executables.add(str(built / 'Contents/MacOS/Aplo'))
for row in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
    parts = row.strip().split(None, 1)
    if len(parts) == 2 and parts[1] in executables: os.kill(int(parts[0]), signal.SIGTERM)
for _ in range(50):
    rows = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines()
    if not any(len(r.strip().split(None, 1)) == 2 and r.strip().split(None, 1)[1] in executables for r in rows): break
    time.sleep(0.1)
else: raise RuntimeError('Existing Aplo did not exit; no files were replaced')
# Capture final state after the app flushes debounced preferences and window position.
if layout.exists():
    archive.mkdir(exist_ok=True)
    shutil.copy2(layout, backup / 'layout.json')
    shutil.copy2(layout, archive / ('Aplo-before-upgrade-' + backup.name + '.json'))
prefs = subprocess.run(['defaults', 'export', identity, '-'], capture_output=True)
if prefs.returncode == 0: (backup / 'preferences.plist').write_bytes(prefs.stdout)
destination = Path('/Applications/Aplo.app')
register = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
def verify(path):
    assert info(path)['CFBundleIdentifier'] == identity
    assert info(path)['CFBundleShortVersionString'] == package['CFBundleShortVersionString']
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True)
def activate(path):
    subprocess.run([register, '-f', str(path)], check=True)
    for attempt in range(3):
        opened = subprocess.run(['open', str(path), '--args', '--show'], capture_output=True, text=True)
        if opened.returncode == 0:
            for _ in range(30):
                if any(row.strip().split(None, 1)[-1] == str(path / 'Contents/MacOS/Aplo') for row in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines()): break
                time.sleep(0.1)
            else: raise RuntimeError('Aplo did not start during installation')
            # open succeeding alone does not establish that the executable stayed alive.
            for _ in range(20):
                time.sleep(0.1)
                if not any(row.strip().split(None, 1)[-1] == str(path / 'Contents/MacOS/Aplo') for row in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines()):
                    raise RuntimeError('Aplo exited during the installation launch check')
            return
        time.sleep(0.25 * (attempt + 1))
    raise RuntimeError('LaunchServices could not open Aplo: ' + opened.stderr)
def deactivate(path):
    executable = str(path / 'Contents/MacOS/Aplo')
    for row in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
        parts = row.strip().split(None, 1)
        if len(parts) == 2 and parts[1] == executable:
            os.kill(int(parts[0]), signal.SIGTERM)
    for _ in range(50):
        if not any(row.strip().split(None, 1)[-1] == executable for row in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines()): return
        time.sleep(0.1)
    raise RuntimeError('New app did not exit during rollback')
try:
    replace_bundle(built, destination, verify, activate, deactivate)
except BaseException as error:
    if isinstance(error, RollbackFailure):
        print(str(error) + '; user-state backup: ' + str(backup), file=sys.stderr)
        raise
    # Restore the final pre-upgrade user state before restarting the old app.
    if (backup / 'layout.json').exists():
        shutil.copy2(backup / 'layout.json', layout)
    if (backup / 'preferences.plist').exists():
        subprocess.run(['defaults', 'import', identity, str(backup / 'preferences.plist')], check=True)
    if destination.exists():
        subprocess.run([register, '-f', str(destination)], check=False)
        subprocess.run(['open', str(destination)], check=False)
    print('Installation failed; prior bundle restored when possible. Backup: ' + str(backup), file=sys.stderr)
    raise
old = Path('/Applications/SimpleLauncher.app')
if old.exists(): shutil.move(str(old), backup / 'old-installed-name.app.backup')
print('Installed Aplo ' + package['CFBundleShortVersionString'])
print('Recovery backup: ' + str(backup))
PY
