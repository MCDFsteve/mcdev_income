"""Run with python3 -m unittest discover -s tools/python_reload -p 'test_*.py'."""
import base64
import json
import os
import shutil
import sys
import tempfile
import types
import unittest

import runtime


class ReloadTests(unittest.TestCase):
    def setUp(self):
        self.names = []

    def tearDown(self):
        for name in self.names:
            sys.modules.pop(name, None)

    def module(self, name, source):
        module = types.ModuleType(name)
        exec(compile(source, name, 'exec'), module.__dict__)
        sys.modules[name] = module
        self.names.append(name)
        return module

    def file(self, name, source):
        return dict(module=name, path=name + '.py', source=base64.b64encode(source.encode('utf-8')).decode('ascii'))

    def test_bound_callback_import_alias_and_state_survive_two_reloads(self):
        def source(n):
            return '''VALUE = %d
def value(): return VALUE
class System(object):
    def __init__(self): self.counter = 0
    def tick(self):
        self.counter += 1
        return value(), self.counter
    @staticmethod
    def static(): return VALUE
    @classmethod
    def kind(cls): return cls
    @property
    def prop(self): return VALUE
''' % n
        module = self.module('probe', source(1))
        consumer = self.module('consumer', 'from probe import value, System')
        instance = module.System()
        callback = instance.tick
        static = instance.static
        getter = module.System.prop.fget
        kind = module.System.kind
        self.assertEqual(callback(), (1, 1))
        for revision in (2, 3):
            runtime.reload_sources([self.file('probe', source(revision))], True)
            self.assertEqual(callback(), (revision, revision))
            self.assertEqual(consumer.value(), revision)
            self.assertIs(consumer.System, module.System)
            self.assertIs(kind(), module.System)
            self.assertEqual(static(), revision)
            self.assertEqual(getter(instance), revision)

    def test_compile_whole_batch_before_changes(self):
        module = self.module('probe', 'VALUE = 1')
        for apply in (False, True):
            with self.assertRaises(SyntaxError):
                runtime.reload_sources([self.file('probe', 'VALUE = 2'), self.file('other', 'def broken(:')], apply)
            self.assertEqual(module.VALUE, 1)

    def test_validation_does_not_execute_module(self):
        runtime.reload_sources([self.file('probe', 'raise RuntimeError("must not execute")')], False)

    def test_new_functions_and_classes_use_live_module_globals(self):
        module = self.module('probe', 'VALUE = 1')
        runtime.reload_sources([self.file('probe', 'VALUE = 2\ndef read(): return VALUE\nclass Added(object):\n    def read(self): return VALUE\n')], True)
        module.VALUE = 7
        self.assertEqual(module.read(), 7)
        self.assertEqual(module.Added().read(), 7)

    def test_structural_edits_rejected_before_patching(self):
        module = self.module('probe', 'class System(object):\n    def tick(self): return 1\n')
        callback = module.System().tick
        for source in ('class System(object):\n    pass\n', 'class System(dict):\n    def tick(self): return 2\n', 'class System(object):\n    tick = 3\n'):
            with self.assertRaises(ValueError):
                runtime.reload_sources([self.file('probe', source)], True)
            self.assertEqual(callback(), 1)

    def test_closure_rejected(self):
        source = 'def factory():\n    v = 1\n    def inner(): return v\n    return inner\nread = factory()\n'
        module = self.module('probe', source)
        old = module.read
        with self.assertRaises(ValueError):
            runtime.reload_sources([self.file('probe', source.replace('v = 1', 'v = 2'))], True)
        self.assertIs(module.read, old)
        self.assertEqual(old(), 1)

    def test_dispatch_requires_nonce_epoch_and_allowed_module(self):
        directory = tempfile.mkdtemp()
        saved = {name: getattr(runtime, name) for name in ('_directory', '_nonce', '_epoch', '_roots', '_last_request', '_result', '_poisoned', '_last_poll')}
        try:
            runtime._directory, runtime._nonce, runtime._epoch, runtime._roots = directory, 'nonce', 'world', ('probe',)
            runtime._last_request, runtime._result, runtime._poisoned = None, None, False
            module = self.module('probe', 'VALUE = 1')
            request = dict(nonce='wrong', epoch='world', id='1', operation='apply', files=[self.file('probe', 'VALUE = 2')])
            def dispatch():
                with open(os.path.join(directory, 'request.json'), 'w') as handle:
                    json.dump(request, handle)
                runtime._last_poll = 0
                runtime._mcdev_dispatch()
            dispatch()
            self.assertEqual(module.VALUE, 1)
            request.update(nonce='nonce', epoch='stale')
            dispatch()
            self.assertEqual(module.VALUE, 1)
            request.update(epoch='world')
            dispatch()
            self.assertEqual(module.VALUE, 2)
            module.VALUE = 3
            dispatch()  # replay must not execute twice
            self.assertEqual(module.VALUE, 3)
            request.update(id='2', files=[self.file('os', 'raise AssertionError')])
            dispatch()
            self.assertIn('outside the launched project', runtime._result['error'])
            self.assertTrue(runtime._result['restartRequired'])
            request.update(id='3', operation='validate', files=[self.file('probe', 'VALUE = 4')])
            dispatch()
            self.assertFalse(runtime._result['ok'])
            self.assertTrue(runtime._result['restartRequired'])
            self.assertEqual(module.VALUE, 3)
            runtime.tick('new-world')
            self.assertFalse(runtime._poisoned)
            self.assertIsNone(runtime._result)
        finally:
            for name, value in saved.items():
                setattr(runtime, name, value)
            shutil.rmtree(directory)


if __name__ == '__main__':
    unittest.main()
