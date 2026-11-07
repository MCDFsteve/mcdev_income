#!/usr/bin/env python3
"""Agent stdin/stdout adapter and deterministic, evidence-based mod test runner.

No third-party dependencies. Credentials are read from the launch descriptor.
Model adapters can write one complete action per line while reading observations.
"""
import argparse
import collections
import copy
import json
import math
import socket
import sys
import threading
import time
import uuid
from pathlib import Path

TERMINAL = {'completed', 'failed', 'rejected', 'expired', 'cancelled', 'lease_expired', 'disconnected'}


class Client:
    def __init__(self, descriptor):
        config = json.loads(Path(descriptor).read_text())
        if config['host'] != '127.0.0.1' or config['protocol'] != 1:
            raise ValueError('Unsupported descriptor')
        self.socket = socket.create_connection((config['host'], config['port']), timeout=3)
        self.socket.settimeout(1)
        self.send_lock = threading.Lock()
        self.condition = threading.Condition()
        self.closed = False
        self.failure = None
        self.observation = None
        self.observed_at = 0
        self.generation = None
        self.epoch = None
        self.claimed = False
        self.messages = collections.deque(maxlen=256)
        self.receipts = {}
        self.events = collections.deque(maxlen=256)
        self.event_loss = 0
        self.counter = 0
        self.session_id = uuid.uuid4().hex[:12]
        self.submitted = set()
        self.send({'type': 'hello', 'role': 'agent', 'protocol': 1, 'token': config['token']})
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.heartbeat = threading.Thread(target=self._heartbeat, daemon=True)
        self.heartbeat.start()

    def send(self, data):
        raw = (json.dumps(data, separators=(',', ':'), allow_nan=False) + '\n').encode()
        if len(raw) > 16384:
            raise ValueError('Frame too large')
        with self.send_lock:
            self.socket.sendall(raw)

    def _read(self):
        buffer = b''
        try:
            while not self.closed:
                try:
                    data = self.socket.recv(16384)
                except socket.timeout:
                    continue
                if not data:
                    raise EOFError('Game bridge disconnected')
                buffer += data
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    if len(line) > 16384:
                        raise ValueError('Frame too large')
                    message = json.loads(line)
                    with self.condition:
                        kind = message['type']
                        if kind == 'observation':
                            if self.epoch != message['epoch']:
                                self.claimed = False
                            self.epoch = message['epoch']
                            self.observation = message
                            self.observed_at = time.monotonic()
                        elif kind == 'claimed':
                            self.epoch, self.generation = message['epoch'], message['generation']
                            self.claimed = True
                        elif kind in ('receipt', 'error') and message.get('id'):
                            self.receipts[message['id']] = message
                            if len(self.receipts) > 4096:
                                raise RuntimeError('Rotate the control generation after 4096 actions')
                        elif kind == 'events':
                            self.event_loss += max(0, len(self.events) + len(message['events']) - self.events.maxlen)
                            self.events.extend(dict(event, epoch=message['epoch']) for event in message['events'])
                        elif kind == 'stopped' or kind == 'status' and not message.get('ready'):
                            self.claimed = False
                        if kind != 'observation':
                            self.messages.append(message)
                        self.condition.notify_all()
                if len(buffer) > 16384:
                    raise ValueError('Unterminated frame too large')
        except Exception as exc:
            with self.condition:
                if not self.closed:
                    self.failure = str(exc)
                self.condition.notify_all()

    def _heartbeat(self):
        while not self.closed:
            time.sleep(.5)
            if self.claimed:
                try:
                    self.send({'type': 'heartbeat', 'epoch': self.epoch, 'generation': self.generation})
                except OSError:
                    return

    def wait(self, predicate, timeout=10):
        deadline = time.monotonic() + timeout
        with self.condition:
            while True:
                if self.failure:
                    raise RuntimeError(self.failure)
                result = predicate()
                if result:
                    return result
                left = deadline - time.monotonic()
                if left <= 0:
                    raise TimeoutError('No matching game evidence before deadline')
                self.condition.wait(min(left, .25))

    def observe(self):
        return self.wait(lambda: self.observation if self.observation and
                         self.observation.get('world_ready') and
                         time.monotonic() - self.observed_at < 2 else None, 30)

    def claim(self, hz=5):
        self.observe()
        self.claimed = False
        self.receipts.clear()
        self.submitted.clear()
        self.send({'type': 'claim', 'epoch': self.epoch, 'hz': hz})
        self.wait(lambda: self.claimed)

    def action(self, action, identity=None, wait=True):
        if not self.claimed:
            raise RuntimeError('No active control lease')
        self.counter += 1
        identity = identity or 'action_%s_%d' % (self.session_id, self.counter)
        self.submitted.add(identity)
        self.send({'type': 'action', 'epoch': self.epoch, 'generation': self.generation,
                   'id': identity, 'ttl_ms': 2000, 'action': action})
        if not wait:
            return identity
        result = self.wait(lambda: self.receipts.get(identity) if
                           self.receipts.get(identity, {}).get('status') in TERMINAL or
                           self.receipts.get(identity, {}).get('type') == 'error' else None, 8)
        if result.get('status') != 'completed':
            raise RuntimeError(json.dumps(result))
        return result

    def close(self):
        if not self.closed:
            try:
                self.send({'type': 'stop'})
            except OSError:
                pass
            self.closed = True
            self.claimed = False
            self.socket.close()


def resolve(value, path):
    for part in path.split('.'):
        value = value[int(part)] if isinstance(value, list) else value[part]
    return value


def matches(value, assertion):
    try:
        actual = resolve(value, assertion['path'])
        if 'equals' in assertion:
            return actual == assertion['equals']
        if 'near' in assertion:
            return isinstance(actual, (float, int)) and abs(actual - assertion['near']) <= assertion.get('tolerance', .1)
        if 'min' in assertion:
            return isinstance(actual, (float, int)) and actual >= assertion['min']
        if 'contains' in assertion:
            return assertion['contains'] in actual
    except (KeyError, IndexError, TypeError, ValueError):
        return False
    raise ValueError('Assertion needs equals/near/min/contains')


def run_test(client, recipe):
    report = {'name': recipe.get('name', 'mod-test'), 'passed': False, 'steps': [],
              'coverage': 'state_events_only; visual_and_audible_quality_unverified'}
    baseline = client.observe()
    report['epoch'] = baseline['epoch']
    try:
        if not any(any(k in step for k in ('assert', 'event', 'displacement_min')) for step in recipe['steps']):
            raise ValueError('A test needs at least one state/event assertion')
        for step in recipe['steps']:
            start_observation = client.observe()
            start_tick = start_observation['tick']
            if start_observation['epoch'] != report['epoch']:
                raise RuntimeError('World epoch changed during test')
            event_cursor = max((x['event_seq'] for x in client.events), default=0)
            event_loss = client.event_loss
            result = {'step': step, 'start_tick': start_tick}
            if 'action' in step:
                result['receipt'] = client.action(step['action'])
                start_tick = max(start_tick, result['receipt']['tick'] - 1)
            # Always require fresh evidence after the action, never an old success.
            if 'assert' in step:
                assertion = step['assert']
                evidence = client.wait(lambda: client.observation if client.observation and
                    client.observation['epoch'] == report['epoch'] and
                    client.observation['tick'] > start_tick and
                    time.monotonic() - client.observed_at < 2 and
                    matches(client.observation, assertion) else None, step.get('timeout_s', 5))
                result['evidence'] = {'tick': evidence['tick'], 'path': assertion['path'],
                                      'value': resolve(evidence, assertion['path'])}
            if 'event' in step:
                event = client.wait(lambda: next((x for x in client.events if x['event_seq'] > event_cursor
                    and x.get('epoch') == report['epoch']
                    and matches(x, step['event'])), None), step.get('timeout_s', 5))
                if client.event_loss != event_loss or any(x['event_seq'] > event_cursor and x['kind'] == 'event_gap' for x in client.events):
                    raise RuntimeError('Event coverage gap: cannot certify this assertion')
                result['event_evidence'] = event
            if 'displacement_min' in step:
                origin = baseline['player']['position']
                evidence = client.wait(lambda: client.observation if client.observation and
                    client.observation['epoch'] == report['epoch'] and client.observation['tick'] > start_tick and
                    time.monotonic() - client.observed_at < 2 and
                    math.dist(origin, client.observation['player']['position']) >= step['displacement_min']
                    else None, step.get('timeout_s', 5))
                result['evidence'] = {'tick': evidence['tick'], 'position': evidence['player']['position']}
            result['passed'] = True
            report['steps'].append(result)
        report['passed'] = True
    except Exception as exc:
        report['failure'] = str(exc)
        report['last_observation'] = client.observation
    finally:
        try:
            client.send({'type': 'stop'})
        except OSError:
            report['passed'] = False
            report.setdefault('failure', 'Bridge disconnected before stop acknowledgement')
    return report


def model_update(observation, events, limit=4096):
    """Bound the model-facing view independently of the game sampling rate."""
    def rounded(value):
        if isinstance(value, float):
            return round(value, 2)
        if isinstance(value, list):
            return [rounded(x) for x in value]
        if isinstance(value, dict):
            return {k: rounded(v) for k, v in value.items()}
        return value
    value = {'type': 'model_update', 'observation': rounded(copy.deepcopy(observation)),
             'events': rounded(list(events)[-8:]), 'omitted_events': max(0, len(events) - 8),
             'truncated': False}
    def size():
        return len(json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf8'))
    while size() > limit and value['events']:
        value['events'].pop(0)
        value['omitted_events'] += 1
        value['truncated'] = True
    obs = value['observation'] or {}
    for container, key in ((obs.get('scene', {}), 'rays'), (obs.get('player', {}), 'inventory'),
                           (obs.get('ui', {}), 'screen_events')):
        while size() > limit and container.get(key):
            container[key].pop()
            value['truncated'] = True
    if size() > limit:
        # Exact details remain available through --observe. Never truncate JSON.
        value['observation'] = {k: obs[k] for k in ('epoch', 'seq', 'tick', 'world_ready', 'generation', 'coverage') if k in obs}
        value['truncated'] = True
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--descriptor', required=True)
    parser.add_argument('--hz', type=int, choices=(2, 5, 10), default=5)
    parser.add_argument('--model-interval', type=float, default=2,
                        help='seconds between model observations, default 2 (game sampling is independent)')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--observe', action='store_true')
    group.add_argument('--stream', action='store_true', help='stdin NDJSON actions; stdout observations/events/receipts')
    group.add_argument('--test', type=Path, help='JSON test recipe')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if not .5 <= args.model_interval <= 10:
        parser.error('--model-interval must be between 0.5 and 10 seconds')
    client = Client(args.descriptor)
    try:
        if args.observe:
            print(json.dumps(client.observe(), ensure_ascii=False))
            return 0
        client.claim(args.hz)
        if args.test:
            report = run_test(client, json.loads(args.test.read_text()))
            output = json.dumps(report, ensure_ascii=False, indent=2)
            if args.report:
                args.report.write_text(output + '\n')
            print(output)
            return 0 if report['passed'] else 1
        stream_done = threading.Event()
        def output():
            next_update = 0
            events = collections.deque(maxlen=256)
            while not client.closed and not stream_done.is_set():
                with client.condition:
                    messages = list(client.messages)
                    client.messages.clear()
                for message in messages:
                    if message['type'] == 'events':
                        events.extend(message['events'])
                    else:
                        print(json.dumps(message, ensure_ascii=False, separators=(',', ':')), flush=True)
                if client.observation and time.monotonic() >= next_update:
                    print(json.dumps(model_update(client.observation, events), ensure_ascii=False,
                                     separators=(',', ':')), flush=True)
                    events.clear()
                    next_update = time.monotonic() + args.model_interval
                time.sleep(.05)
        writer = threading.Thread(target=output, daemon=True)
        writer.start()
        # readline(size) bounds incomplete model output; no partial JSON executes.
        while True:
            line = sys.stdin.buffer.readline(1025)
            if not line:
                break
            if len(line) > 1024 or not line.endswith(b'\n'):
                raise ValueError('Action must be a complete NDJSON line <= 1 KiB')
            value = json.loads(line)
            if value.get('type') == 'stop':
                client.send({'type': 'stop'})
                break
            client.action(value.get('action', value), value.get('id'), wait=False)
        # Let accepted bounded actions finish when a producer closes stdin.
        # A stop line remains an immediate cancellation.
        if client.claimed and client.submitted:
            client.wait(lambda: all(identity in client.receipts and (
                client.receipts[identity].get('status') in TERMINAL or
                client.receipts[identity].get('type') == 'error') for identity in client.submitted), 8)
        stream_done.set()
        writer.join(timeout=1)
        with client.condition:
            remaining = list(client.messages)
            client.messages.clear()
        for message in remaining:
            if message['type'] != 'events':
                print(json.dumps(message, ensure_ascii=False, separators=(',', ':')), flush=True)
        return 0
    finally:
        client.close()


if __name__ == '__main__':
    raise SystemExit(main())
