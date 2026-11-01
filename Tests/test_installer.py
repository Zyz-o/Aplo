import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'Scripts'))
from install_support import replace_bundle, RollbackFailure


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.new = self.root / 'built.app'
        self.old = self.root / 'Applications/Aplo.app'
        self.new.mkdir(); self.old.mkdir(parents=True)
        (self.new / 'version').write_text('new')
        (self.old / 'version').write_text('old')
        (self.old / 'obsolete-file').write_text('must not survive')

    def check_clean(self):
        self.assertEqual(list(self.old.parent.glob('.Aplo-install-*')), [])

    def test_replacement_removes_stale_files(self):
        replace_bundle(self.new, self.old, lambda p: None, lambda p: None)
        self.assertEqual((self.old / 'version').read_text(), 'new')
        self.assertFalse((self.old / 'obsolete-file').exists())
        self.check_clean()

    def test_stage_verification_failure_preserves_old_bundle(self):
        def fail(path): raise RuntimeError('invalid signature')
        with self.assertRaisesRegex(RuntimeError, 'invalid signature'):
            replace_bundle(self.new, self.old, fail, lambda p: None)
        self.assertEqual((self.old / 'version').read_text(), 'old')
        self.assertTrue((self.old / 'obsolete-file').exists())
        self.check_clean()

    def test_installed_verification_failure_rolls_back(self):
        def verify(path):
            if path == self.old: raise RuntimeError('post-install failure')
        with self.assertRaisesRegex(RuntimeError, 'post-install failure'):
            replace_bundle(self.new, self.old, verify, lambda p: None)
        self.assertEqual((self.old / 'version').read_text(), 'old')
        self.check_clean()

    def test_launch_failure_stops_new_bundle_and_rolls_back(self):
        stopped = []
        def fail(path): raise RuntimeError('launch failed')
        with self.assertRaisesRegex(RuntimeError, 'launch failed'):
            replace_bundle(self.new, self.old, lambda p: None, fail, stopped.append)
        self.assertEqual(stopped, [self.old])
        self.assertEqual((self.old / 'version').read_text(), 'old')
        self.check_clean()

    def test_failed_first_install_leaves_no_partial_app(self):
        import shutil
        shutil.rmtree(self.old)
        def fail(path): raise RuntimeError('launch failed')
        with self.assertRaises(RuntimeError):
            replace_bundle(self.new, self.old, lambda p: None, fail)
        self.assertFalse(self.old.exists())
        self.check_clean()

    def test_rollback_failure_retains_recoverable_old_bundle(self):
        def fail(path): raise RuntimeError('simulated failure')
        with self.assertRaisesRegex(RollbackFailure, 'recovery bundle retained'):
            replace_bundle(self.new, self.old, lambda p: None, fail, fail)
        previous = list(self.old.parent.glob('.Aplo-install-*/previous.app'))
        self.assertEqual(len(previous), 1)
        self.assertEqual((previous[0] / 'version').read_text(), 'old')


if __name__ == '__main__': unittest.main()
