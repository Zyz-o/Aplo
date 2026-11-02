"""Replace a complete app bundle; retain the prior bundle until activation succeeds."""
from pathlib import Path
import shutil
import tempfile


class RollbackFailure(RuntimeError):
    """The previous bundle remains in staging and needs manual recovery."""


def replace_bundle(source, destination, verify, activate, deactivate=lambda path: None):
    source, destination = Path(source), Path(destination)
    if source.is_symlink() or destination.is_symlink():
        raise ValueError('Refusing a symlink application bundle')
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.Aplo-install-', dir=destination.parent))
    staged, previous = staging / 'Aplo.app', staging / 'previous.app'
    promoted = False
    keep_recovery = False
    try:
        # A fresh directory prevents files removed from a new version surviving an upgrade.
        shutil.copytree(source, staged, symlinks=True)
        verify(staged)
        if destination.exists():
            destination.rename(previous)
        staged.rename(destination)
        promoted = True
        verify(destination)
        activate(destination)
    except BaseException as original:
        try:
            if promoted:
                deactivate(destination)
                destination.rename(staging / 'failed.app')
            if previous.exists():
                previous.rename(destination)
        except BaseException as recovery_error:
            keep_recovery = True
            raise RollbackFailure('Automatic rollback failed; recovery bundle retained at ' + str(previous)) from recovery_error
        raise original
    finally:
        if not keep_recovery:
            shutil.rmtree(staging, ignore_errors=True)


def acquire_install_lock(directory):
    """Private, UID-owned lock; reject symlink directories/files and hard links."""
    import os, stat, fcntl
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    dirfd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        metadata = os.fstat(dirfd)
        if metadata.st_uid != os.getuid():
            raise ValueError('Install lock directory belongs to another user')
        os.fchmod(dirfd, 0o700)
        fd = os.open('install.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600, dir_fd=dirfd)
    finally:
        os.close(dirfd)
    try:
        metadata = os.fstat(fd)
        if metadata.st_uid != os.getuid() or not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise ValueError('Unsafe install lock')
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return os.fdopen(fd, 'r+')
    except BaseException:
        os.close(fd)
        raise


def owned_process_ids(rows, executables, uid):
    result = []
    for row in rows.splitlines():
        parts = row.strip().split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            if int(parts[1]) == uid and parts[2] in executables:
                result.append(int(parts[0]))
    return result


def install_destination(shared, personal, uid):
    import os
    shared, personal = Path(shared), Path(personal)
    if personal.exists():
        return personal
    if os.access(shared.parent, os.W_OK) and (not shared.exists() or shared.stat().st_uid == uid):
        return shared
    return personal
