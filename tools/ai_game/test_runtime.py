import importlib.util
from pathlib import Path
import sys
import types
import unittest

for name in ('mod', 'mod.client', 'mod.client.extraClientApi'):
    sys.modules[name] = types.ModuleType(name)
sys.modules['mod.client.extraClientApi'].GetEngineCompFactory = lambda: None
sys.modules['mod.client.extraClientApi'].GetLevelId = lambda: '-1'
spec = importlib.util.spec_from_file_location('ai_runtime', Path(__file__).with_name('runtime.py'))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class Motion:
    def __init__(self):
        self.locked = False
        self.unlocks = 0
    def LockInputVector(self, vector):
        self.locked = True
        return True
    def UnlockInputVector(self):
        self.locked = False
        self.unlocks += 1


class RuntimeTest(unittest.TestCase):
    def setUp(self):
        self.bridge = runtime.Bridge()
        self.bridge.motion = Motion()
        self.bridge.epoch = 'e1'
        self.bridge.generation = 2
        self.bridge.lease = 102
        self.bridge.loaded = True
        self.messages = []
        self.bridge.queue = self.messages.append
    def request(self, identity='a', **changes):
        request = dict(type='action', epoch='e1', generation=2, id=identity,
                       not_after_ms=int(runtime.time.time() * 1000) + 1000,
                       action=dict(op='move', left=0, forward=1, duration_ms=1000))
        request.update(changes)
        return request
    def test_lease_releases_motion_and_pending(self):
        b = self.bridge
        b.command(self.request(), 100)
        b.execute(100)
        self.assertTrue(b.motion.locked)
        b.command(self.request('b'), 100)
        b.execute(103)
        self.assertFalse(b.motion.locked)
        self.assertIsNone(b.active)
        self.assertFalse(b.pending)
        self.assertEqual([m['status'] for m in self.messages][-2:], ['lease_expired'] * 2)
    def test_stale_world_generation_and_duplicate_cannot_execute(self):
        b = self.bridge
        b.command(self.request(epoch='old'), 100)
        b.command(self.request(generation=1), 100)
        self.assertFalse(b.pending)
        b.command(self.request(), 100)
        b.command(self.request(), 100)
        self.assertEqual(len(b.pending), 1)
    def test_expired_in_transit_does_not_start(self):
        b = self.bridge
        b.command(self.request(not_after_ms=1), 100)
        b.execute(100)
        self.assertFalse(b.motion.locked)
        self.assertEqual(self.messages[-1]['status'], 'expired')
    def test_world_loading_is_not_ready(self):
        self.bridge.loaded = False
        self.bridge.command(self.request(), 100)
        self.assertEqual(self.messages[-1]['detail'], 'world_loading')
    def test_old_heartbeat_cannot_extend_lease_after_stall(self):
        b = self.bridge
        b.command(dict(type='control', epoch='e1', generation=2,
                       enabled=True, valid_until_ms=1), 100)
        self.assertEqual(b.lease, 100)
    def test_new_generation_cancels_queue_and_releases(self):
        b = self.bridge
        b.command(self.request(), 100)
        b.execute(100)
        b.command(dict(type='control', epoch='e1', generation=3, enabled=False), 100)
        self.assertFalse(b.motion.locked)
        self.assertEqual(b.generation, 3)
    def test_shutdown_quiesces_sdk_before_world_teardown(self):
        b = self.bridge
        b.command(self.request(), 100)
        b.execute(100)
        b.command(dict(type='shutdown', epoch='e1', generation=3), 100)
        self.assertFalse(b.motion.locked)
        self.assertTrue(b.suspended)
        self.assertEqual(self.messages[-1]['type'], 'shutdown_ack')
        # A suspended adapter must not touch the SDK, even with no factory.
        b.factory = None
        b.tick(object(), 'e1', [])
        b.tick(object(), 'teardown-dimension', [])
        self.assertEqual(b.tick_count, 0)


if __name__ == '__main__':
    unittest.main()
