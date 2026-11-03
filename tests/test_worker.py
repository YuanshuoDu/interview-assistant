"""Offline checks for the worker's session and capture boundaries."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import worker


class WorkerBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='interview-worker-test-')
        self.root = Path(self.temp.name)
        (self.root / 'captures').mkdir()
        self.paths = patch.multiple(worker, ROOT=self.root,
                                    CONTROL=self.root / 'control.json',
                                    REQUEST=self.root / 'request.json',
                                    RESULT=self.root / 'result.json',
                                    STATUS=self.root / 'status.json')
        self.paths.start()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.paths.stop)
        self.session = 'synthetic-session'
        self.generation = 'a' * 32
        worker.write(worker.CONTROL, {'enabled': True, 'request_id': self.session})
        worker.write(worker.REQUEST, {'session_id': self.session, 'generation_id': self.generation})

    def test_rejects_image_outside_capture_directory(self):
        image = self.root / (self.generation + '.png')
        image.write_bytes(b'synthetic image data')
        with patch.object(worker, 'run_cancellable') as call:
            message = worker.generate(self.session, {'generation_id': self.generation,
                                                      'image_path': str(image)}, 'codex')
        self.assertIn('Invalid screenshot', message)
        call.assert_not_called()
        self.assertFalse(worker.RESULT.exists())

    def test_session_change_discards_successful_result(self):
        image = self.root / 'captures' / (self.generation + '.png')
        image.write_bytes(b'synthetic image data')

        def fake_inference(cmd, *args, **kwargs):
            output = Path(cmd[cmd.index('-o') + 1])
            output.write_text(json.dumps({'question': 'Synthetic question?',
                                          'answer': 'A synthetic answer.', 'keywords': []}),
                              encoding='utf-8')
            worker.write(worker.CONTROL, {'enabled': True, 'request_id': 'new-session'})
            return 0, ''

        with patch.object(worker, 'run_cancellable', side_effect=fake_inference):
            message = worker.generate(self.session, {'generation_id': self.generation,
                                                      'image_path': str(image)}, 'codex')
        self.assertEqual(message, 'Generation cancelled.')
        self.assertFalse(worker.RESULT.exists())

    def test_sign_in_alone_does_not_report_connected(self):
        with patch.object(worker, 'run_cancellable', side_effect=[(0, 'Logged in using ChatGPT'), (1, '')]):
            connected, message = worker.connect(self.session, 'codex')
        self.assertFalse(connected)
        self.assertIn('failed', message.lower())

    def test_stopped_session_does_not_start_a_child_process(self):
        worker.write(worker.CONTROL, {'enabled': False, 'request_id': self.session})
        with patch.object(worker.subprocess, 'Popen') as popen:
            code, _ = worker.run_cancellable(['codex', 'login', 'status'], self.session)
        self.assertIsNone(code)
        popen.assert_not_called()


if __name__ == '__main__':
    unittest.main()
