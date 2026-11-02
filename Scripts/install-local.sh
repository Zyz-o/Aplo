#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
python3 - "$project_dir" <<'PY'
from pathlib import Path
import subprocess, sys, plistlib, shutil, os, signal, time, uuid, fcntl
root = Path(sys.argv[1])
sys.dont_write_bytecode = True
sys.path.insert(0, str(root / 'Scripts'))
from install_support import replace_bundle, RollbackFailure, acquire_install_lock, owned_process_ids, install_destination
# Serialize installers even when invoked from different source checkouts.
lock = acquire_install_lock(Path.home() / 'Library/Caches/local.jianqi.SimpleLauncher/Installer')
destination = install_destination('/Applications/Aplo.app', Path.home() / 'Applications/Aplo.app', os.getuid())
def processes(paths):
    rows = subprocess.check_output(['ps', '-axo', 'pid=,uid=,comm='], text=True)
    return owned_process_ids(rows, paths, os.getuid())
built = root / 'build/Aplo.app'
identity = 'local.jianqi.SimpleLauncher'
def info(path): return plistlib.loads((path / 'Contents/Info.plist').read_bytes())
package = info(built)
assert package['CFBundleIdentifier'] == identity and package['CFBundleDisplayName'] == 'Aplo'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(built)], check=True)
backup = root / 'build/InstallBackups' / uuid.uuid4().hex[:12]
backup.mkdir(parents=True)
installed = [p for p in [destination, destination.parent / 'SimpleLauncher.app'] if p.exists()]
for path in installed:
    if path.is_symlink(): raise ValueError('Refusing a symlink installed bundle: ' + str(path))
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
# A personal-directory fallback may supersede a shared copy without modifying it.
# Stop only this UID's running copies of the same identity before LaunchServices activation.
for candidate in [Path('/Applications/Aplo.app'), Path('/Applications/SimpleLauncher.app'), Path.home() / 'Applications/Aplo.app']:
    try:
        candidate_info = info(candidate)
        if candidate_info.get('CFBundleIdentifier') == identity:
            executables.add(str(candidate / 'Contents/MacOS' / candidate_info['CFBundleExecutable']))
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException):
        pass
for pid in processes(executables): os.kill(pid, signal.SIGTERM)
for _ in range(50):
    if not processes(executables): break
    time.sleep(0.1)
else: raise RuntimeError('Existing Aplo did not exit; no files were replaced')
# Capture final state after the app flushes debounced preferences and window position.
if layout.exists():
    archive.mkdir(exist_ok=True)
    shutil.copy2(layout, backup / 'layout.json')
    shutil.copy2(layout, archive / ('Aplo-before-upgrade-' + backup.name + '.json'))
prefs = subprocess.run(['defaults', 'export', identity, '-'], capture_output=True)
if prefs.returncode == 0: (backup / 'preferences.plist').write_bytes(prefs.stdout)
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
                if processes({str(path / 'Contents/MacOS/Aplo')}): break
                time.sleep(0.1)
            else: raise RuntimeError('Aplo did not start during installation')
            # open succeeding alone does not establish that the executable stayed alive.
            for _ in range(20):
                time.sleep(0.1)
                if not processes({str(path / 'Contents/MacOS/Aplo')}):
                    raise RuntimeError('Aplo exited during the installation launch check')
            return
        time.sleep(0.25 * (attempt + 1))
    raise RuntimeError('LaunchServices could not open Aplo: ' + opened.stderr)
def deactivate(path):
    executable = str(path / 'Contents/MacOS/Aplo')
    for pid in processes({executable}): os.kill(pid, signal.SIGTERM)
    for _ in range(50):
        if not processes({executable}): return
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
old = destination.parent / 'SimpleLauncher.app'
if old.exists(): shutil.move(str(old), backup / 'old-installed-name.app.backup')
print('Installed Aplo ' + package['CFBundleShortVersionString'] + ' at ' + str(destination))
print('Recovery backup: ' + str(backup))
PY
