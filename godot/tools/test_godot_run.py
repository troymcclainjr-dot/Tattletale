"""No engine needed: exercise the wrapper against owned, unbuffered Python children."""
import io
from pathlib import Path
import subprocess
import sys
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from godot_run import run_child


class GodotRunTests(unittest.TestCase):
    def run_fake(self, source, timeout=4):
        output = io.StringIO()
        start = time.monotonic()
        code = run_child([sys.executable, "-u", "-c", source],
                         cwd=Path(__file__).resolve().parent, timeout=timeout,
                         output_stream=output)
        return code, output.getvalue(), time.monotonic()-start

    def test_normal_output_noise_and_nonzero_exit(self):
        code, output, _ = self.run_fake(
            "import sys; print('Godot Engine v fake'); print('Vulkan fake'); "
            "print('OpenGL API fake'); print('normal stdout'); "
            "print('normal stderr',file=sys.stderr); sys.exit(7)")
        self.assertEqual(code,7)
        self.assertIn('normal stdout',output)
        self.assertIn('normal stderr',output)
        self.assertNotIn('Godot Engine v',output)
        self.assertNotIn('Vulkan fake',output)
        self.assertNotIn('OpenGL API fake',output)

    def test_normal_success_and_error_words_are_not_error_lines(self):
        code, output, _ = self.run_fake("print('fixture checks ERROR: rejection'); print('PASS')")
        self.assertEqual(code,0)
        self.assertIn('PASS',output)

    def test_errors_override_child_exit_zero(self):
        for prefix in ('SCRIPT ERROR:', 'SHADER ERROR:', 'ERROR:'):
            with self.subTest(prefix=prefix):
                code, output, _ = self.run_fake(
                    "import sys; sys.stderr.write("+repr('  '+prefix+' broken\n    at fixture:4\n')+"); sys.stderr.flush()")
                self.assertNotEqual(code,0)
                self.assertIn(prefix+' broken',output)
                self.assertIn('at fixture:4',output)

    def test_error_hang_fails_fast_and_keeps_queued_backtrace(self):
        code, output, elapsed = self.run_fake(
            "import sys,time; sys.stdout.write("+repr('SCRIPT ERROR: broken\n    frame one\n    frame two\n')+"); "
            "sys.stdout.flush(); time.sleep(60)",timeout=20)
        self.assertNotEqual(code,0)
        self.assertNotEqual(code,124)
        self.assertLess(elapsed,4)
        self.assertIn('frame one',output)
        self.assertIn('frame two',output)

    def test_timeout_reaps_owned_child_and_preserves_output(self):
        code, output, elapsed = self.run_fake(
            "import time; print('before timeout',flush=True); time.sleep(60)",timeout=.25)
        self.assertEqual(code,124)
        self.assertIn('before timeout',output)
        self.assertIn('exceeded',output)
        self.assertLess(elapsed,4)

    def test_closed_stdout_does_not_evade_timeout(self):
        code, _, elapsed = self.run_fake(
            "import os,time; os.close(1); os.close(2); time.sleep(60)",timeout=.25)
        self.assertEqual(code,124)
        self.assertLess(elapsed,4)

    def test_unrelated_child_survives_failure(self):
        other = subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'],
                                 stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            code, _, _ = self.run_fake("import time; print('ERROR: broken',flush=True); time.sleep(60)")
            self.assertNotEqual(code,0)
            self.assertIsNone(other.poll())
        finally:
            other.terminate()
            other.wait(timeout=4)


if __name__ == '__main__':
    unittest.main()
