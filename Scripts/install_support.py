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
