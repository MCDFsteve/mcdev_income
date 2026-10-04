# -*- coding: utf-8 -*-
"""Python 2.7/3 compatible implementation executed at the DLL's safe point.

Keep existing function/class identities so registered callbacks and system
instances see new code. Constructors and world initialization are not rerun.
"""
import base64
import json
import os
import sys
import time
import types


def _code(function):
    return getattr(function, '__code__', getattr(function, 'func_code', None))


def _defaults(function):
    return getattr(function, '__defaults__', getattr(function, 'func_defaults', None))


def _closure(function):
    return getattr(function, '__closure__', getattr(function, 'func_closure', None))


def _set_code(function, code):
    if hasattr(function, '__code__'):
        function.__code__ = code
    else:
        function.func_code = code


def _set_defaults(function, defaults):
    if hasattr(function, '__defaults__'):
        function.__defaults__ = defaults
    else:
        function.func_defaults = defaults


_CLASS_TYPES = (type,)
if hasattr(types, 'ClassType'):
    _CLASS_TYPES += (types.ClassType,)
_SKIP_CLASS = ('__dict__', '__weakref__', '__module__', '__slots__', '__classcell__', '__doc__')


def _function(descriptor, owner):
    if isinstance(descriptor, staticmethod):
        return descriptor.__get__(None, owner)
    if isinstance(descriptor, classmethod):
        bound = descriptor.__get__(None, owner)
        return getattr(bound, '__func__', getattr(bound, 'im_func', None))
    return descriptor


def _check(old, new, label, seen):
    if old is new:
        return
    key = (id(old), id(new))
    if key in seen:
        return
    seen.add(key)
    if isinstance(old, types.FunctionType) and isinstance(new, types.FunctionType):
        if _code(old).co_freevars != _code(new).co_freevars or _closure(old) or _closure(new):
            raise ValueError('Cannot replace a closure without restarting: ' + label)
    elif isinstance(old, _CLASS_TYPES) and isinstance(new, _CLASS_TYPES):
        old_bases = [(b.__module__, b.__name__) for b in old.__bases__]
        new_bases = [(b.__module__, b.__name__) for b in new.__bases__]
        if old_bases != new_bases or old.__dict__.get('__slots__') != new.__dict__.get('__slots__'):
            raise ValueError('Class bases or slots changed; restart required: ' + label)
        for name, value in old.__dict__.items():
            if name in _SKIP_CLASS:
                continue
            if name not in new.__dict__:
                raise ValueError('Class attribute removed; restart required: ' + label + '.' + name)
            other = new.__dict__[name]
            if type(value) != type(other):
                raise ValueError('Class attribute type changed; restart required: ' + label + '.' + name)
            if isinstance(value, property):
                for part in ('fget', 'fset', 'fdel'):
                    a, b = getattr(value, part), getattr(other, part)
                    if (a is None) != (b is None):
                        raise ValueError('Property structure changed: ' + label + '.' + name)
                    if a is not None:
                        _check(a, b, label + '.' + name, seen)
            else:
                _check(_function(value, old), _function(other, new), label + '.' + name, seen)


def _patch(old, new, globals_dict, replacements, seen):
    """Return a rebound value, updating original callable objects in place."""
    if old is new:
        return old
    known = replacements.get(id(new))
    if known is not None:
        return known
    if isinstance(new, types.FunctionType):
        if isinstance(old, types.FunctionType):
            result = old
            _set_code(result, _code(new))
            _set_defaults(result, _defaults(new))
        else:
            result = types.FunctionType(_code(new), globals_dict, new.__name__, _defaults(new), _closure(new))
        result.__dict__.update(new.__dict__)
        result.__doc__ = new.__doc__
        result.__module__ = new.__module__
        replacements[id(new)] = result
        return result
    if isinstance(new, _CLASS_TYPES):
        existing = isinstance(old, _CLASS_TYPES)
        result = old if existing else new
        replacements[id(new)] = result
        for name, value in list(new.__dict__.items()):
            if name in _SKIP_CLASS:
                continue
            previous = result.__dict__.get(name) if existing else None
            if isinstance(value, staticmethod):
                updated = staticmethod(_patch(_function(previous, result), _function(value, new), globals_dict, replacements, seen))
            elif isinstance(value, classmethod):
                updated = classmethod(_patch(_function(previous, result), _function(value, new), globals_dict, replacements, seen))
            elif isinstance(value, property):
                updated = property(*[_patch(getattr(previous, part, None), getattr(value, part), globals_dict, replacements, seen)
                                     if getattr(value, part) is not None else None
                                     for part in ('fget', 'fset', 'fdel')], doc=value.__doc__)
            else:
                updated = _patch(previous, value, globals_dict, replacements, seen)
            setattr(result, name, updated)
        return result
    return new


def reload_sources(files, apply=False):
    compiled = []
    for item in files:
        name = item['module']
        data = base64.b64decode(item['source'])
        code = compile(data, item['path'], 'exec')
        compiled.append((name, code))
    if not apply:
        return {'compiled': len(compiled)}
    prepared = []
    for name, code in compiled:
        module = sys.modules.get(name)
        if module is None:
            # New, not-yet-imported modules are available from the synced files.
            continue
        original = dict(module.__dict__)
        shadow = dict(original)
        exec(code, shadow)
        for key, value in shadow.items():
            if key in original and getattr(value, '__module__', None) == name:
                _check(original[key], value, name + '.' + key, set())
        prepared.append((name, module, original, shadow))
    replacements = {}
    # Bind definitions first. Imported aliases are repaired in the second pass.
    for name, module, original, shadow in prepared:
        for key, value in list(shadow.items()):
            if getattr(value, '__module__', None) == name:
                shadow[key] = _patch(original.get(key), value, module.__dict__, replacements, set())
    for name, module, original, shadow in prepared:
        for key, value in list(shadow.items()):
            shadow[key] = replacements.get(id(value), value)
        module.__dict__.update(shadow)
    return {'reloaded': len(prepared), 'deferred': len(compiled) - len(prepared)}


# Bridge state lives in this reserved module, never a developer's module.
_directory = os.environ.get('MCDEV_PYTHON_RELOAD_DIRECTORY', '')
_nonce = os.environ.get('MCDEV_PYTHON_RELOAD_NONCE', '')
_roots = tuple(json.loads(os.environ.get('MCDEV_PYTHON_RELOAD_ROOTS', '[]')))
_epoch = ''
_last_request = None
_result = None
_last_poll = 0
_sequence = 0
_poisoned = False


def _mcdev_native_reload_tick_310_v1():
    # Intentionally inert: the version-pinned DLL runs _mcdev_dispatch here.
    pass


def _mcdev_dispatch():
    global _last_poll, _last_request, _result, _sequence, _poisoned
    now = time.time()
    if not _directory or not _nonce or now - _last_poll < 0.25:
        return
    _last_poll = now
    request = None
    try:
        with open(os.path.join(_directory, 'request.json'), 'rb') as handle:
            raw = handle.read(48 * 1024 * 1024 + 1)
        if len(raw) <= 48 * 1024 * 1024:
            request = json.loads(raw)
    except (IOError, ValueError):
        pass
    if isinstance(request, dict) and request.get('nonce') == _nonce and request.get('epoch') == _epoch:
        identity = (request.get('id'), request.get('operation'))
        if identity != _last_request and identity[1] in ('validate', 'apply'):
            _last_request = identity
            applying = identity[1] == 'apply'
            _result = {'id': identity[0], 'operation': identity[1], 'ok': False, 'restartRequired': False}
            try:
                if _poisoned:
                    raise ValueError('A previous apply failed; restart the test game before reloading again.')
                files = request['files']
                if not isinstance(files, list) or len(files) > 4096:
                    raise ValueError('Invalid Python reload file list')
                for item in files:
                    if not any(item['module'] == root or item['module'].startswith(root + '.') for root in _roots):
                        raise ValueError('Module is outside the launched project: ' + item['module'])
                # Compile the entire batch before executing any user module.
                reload_sources(files, False)
                result = reload_sources(files, True) if applying else {'compiled': len(files)}
                _result.update(result)
                _result['ok'] = True
            except BaseException:
                import traceback
                _result['error'] = traceback.format_exc()[-16000:]
                # Syntax errors are detected before applying. User module-level
                # side effects cannot be rolled back after execution has begun.
                _poisoned = _poisoned or applying
                _result['restartRequired'] = _poisoned
    _sequence += 1
    report = {'nonce': _nonce, 'epoch': _epoch, 'sequence': _sequence, 'result': _result}
    try:
        with open(os.path.join(_directory, 'report.json'), 'wb') as handle:
            handle.write(json.dumps(report, ensure_ascii=True).encode('ascii'))
    except IOError:
        pass


def tick(epoch):
    global _epoch, _last_request, _result, _poisoned, _last_poll
    if epoch != _epoch:
        _last_request = None
        _result = None
        _poisoned = False
        _last_poll = 0
    _epoch = epoch
    _mcdev_native_reload_tick_310_v1()
