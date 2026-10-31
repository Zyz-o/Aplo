#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
python3 - "$project_dir" <<'PY'
from pathlib import Path
import subprocess, sys, plistlib, shutil, os, signal, time, uuid
root = Path(sys.argv[1])
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
subprocess.run(['ditto', str(built), '/Applications/Aplo.app'], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '/Applications/Aplo.app'], check=True)
old = Path('/Applications/SimpleLauncher.app')
if old.exists(): shutil.move(str(old), backup / 'old-installed-name.app.backup')
register = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
subprocess.run([register, '-f', '/Applications/Aplo.app'], check=True)
# LaunchServices may briefly retain the just-terminated app's process registration.
for attempt in range(3):
    opened = subprocess.run(['open', '/Applications/Aplo.app', '--args', '--show'], capture_output=True, text=True)
    if opened.returncode == 0: break
    time.sleep(0.25 * (attempt + 1))
else:
    raise RuntimeError('Installed safely; LaunchServices could not open Aplo. Backup: ' + str(backup) + '\n' + opened.stderr)
print('Installed Aplo ' + package['CFBundleShortVersionString'])
print('Recovery backup: ' + str(backup))
PY
