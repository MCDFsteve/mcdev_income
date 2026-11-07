import unittest
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
from client import matches, model_update, run_test


class AssertionsTest(unittest.TestCase):
    def test_event_from_another_world_cannot_certify_a_mod_test(self):
        class FakeClient:
            event_loss = 0
            events = []
            observation = {'epoch': 'world_a', 'tick': 1}
            def observe(self):
                return self.observation
            def action(self, action):
                self.events = [{'epoch': 'world_b', 'event_seq': 1, 'kind': 'mod_log',
                                'data': {'text': 'success'}}]
                return {'tick': 2}
            def wait(self, predicate, timeout):
                result = predicate()
                if result is None:
                    raise TimeoutError('No same-world evidence')
                return result
            def send(self, value):
                pass
        report = run_test(FakeClient(), {'steps': [
            {'action': {'op': 'wait', 'duration_ms': 10},
             'event': {'path': 'data.text', 'contains': 'success'}}]})
        self.assertFalse(report['passed'])
        self.assertIn('same-world', report['failure'])

    def test_stdio_eof_drains_completed_actions_and_emits_receipts(self):
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(5)
        errors = []
        def serve():
            try:
                connection, _ = listener.accept()
                with connection:
                    connection.settimeout(5)
                    stream = connection.makefile('r')
                    def send(value):
                        connection.sendall((json.dumps(value) + '\n').encode())
                    hello = json.loads(stream.readline())
                    self.assertEqual(hello['token'], 'fixture')
                    send({'type': 'welcome', 'epoch': 'e', 'generation': 1})
                    send({'type': 'observation', 'epoch': 'e', 'generation': 1, 'seq': 1,
                          'tick': 1, 'world_ready': True, 'player': {'rotation': [0, 0]}})
                    for line in stream:
                        request = json.loads(line)
                        if request['type'] == 'claim':
                            send({'type': 'stopped', 'epoch': 'e', 'generation': 2})
                            send({'type': 'claimed', 'epoch': 'e', 'generation': 2})
                        elif request['type'] == 'action':
                            self.assertEqual(request['generation'], 2)
                            send({'type': 'receipt', 'epoch': 'e', 'generation': 2,
                                  'id': request['id'], 'status': 'completed', 'tick': 2})
                        elif request['type'] == 'stop':
                            break
            except Exception as exc:
                errors.append(exc)
        worker = threading.Thread(target=serve, daemon=True)
        worker.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                descriptor = Path(directory) / 'ai-game.json'
                descriptor.write_text(json.dumps({'host': '127.0.0.1', 'port': listener.getsockname()[1],
                                                  'protocol': 1, 'token': 'fixture'}))
                result = subprocess.run([sys.executable, str(Path(__file__).with_name('client.py')),
                                         '--descriptor', str(descriptor), '--stream'],
                                        input='{"id":"one","action":{"op":"look","pitch":0,"yaw":90}}\n',
                                        text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                messages = [json.loads(line) for line in result.stdout.splitlines()]
                self.assertTrue(any(m.get('id') == 'one' and m.get('status') == 'completed' for m in messages))
        finally:
            listener.close()
            worker.join(timeout=2)
        self.assertFalse(errors, str(errors))

    def test_missing_value_is_not_success(self):
        self.assertFalse(matches({'player': {}}, {'path': 'player.health', 'min': 1}))
        self.assertFalse(matches({'player': {'health': None}}, {'path': 'player.health', 'min': 1}))
    def test_numeric_tolerance_and_array_path(self):
        self.assertTrue(matches({'player': {'rotation': [20.1, 90]}},
                                {'path': 'player.rotation.0', 'near': 20, 'tolerance': .2}))
    def test_unknown_assertion_cannot_pass(self):
        with self.assertRaises(ValueError):
            matches({'x': 1}, {'path': 'x', 'unknown': 1})
    def test_model_update_is_bounded_utf8_and_reports_omissions(self):
        observation = {'epoch': 'world', 'seq': 1, 'coverage': {'pixels': False},
                       'player': {'inventory': [{'name': '很长的模组名称' * 40}] * 36},
                       'scene': {'rays': [{'identifier': 'grass'}] * 64}}
        update = model_update(observation, [{'data': '音效' * 3000}] * 20)
        self.assertLessEqual(len(json.dumps(update, ensure_ascii=False, separators=(',', ':')).encode()), 4096)
        self.assertTrue(update['truncated'])
        self.assertEqual(update['observation']['epoch'], 'world')
        self.assertGreater(update['omitted_events'], 0)


if __name__ == '__main__':
    unittest.main()
