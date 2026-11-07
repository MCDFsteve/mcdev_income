# -*- coding: utf-8 -*-
"""3.10 client adapter. Only called by the existing DLL on the client tick.

Python 2.7 compatible; no generated code, blocking IO, or worker game calls.
Wire format: bounded UTF-8 NDJSON. A complete line is one transaction.
"""
import errno
import json
import math
import os
import socket
import time
import mod.client.extraClientApi as api

# Python 2 on Windows exposes the high-resolution elapsed timer as clock().
monotonic = getattr(time, 'monotonic', None) or time.clock

MAX_FRAME = 16384
ACTIONS = ('move', 'look', 'jump', 'wait', 'select_slot', 'use', 'dig', 'place', 'attack', 'craft')


def encode(value):
    return (json.dumps(value, ensure_ascii=True, separators=(',', ':'), allow_nan=False) + '\n').encode('ascii')


def finite(value, low, high):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and low <= value <= high


def validate(action):
    if not isinstance(action, dict) or action.get('op') not in ACTIONS:
        raise ValueError('unsupported_action')
    op = action['op']
    fields = {'move': ('left', 'forward', 'duration_ms'), 'look': ('pitch', 'yaw'),
              'jump': (), 'wait': ('duration_ms',), 'select_slot': ('slot',),
              'use': ('duration_ms',), 'dig': ('x', 'y', 'z', 'face', 'duration_ms'),
              'place': ('x', 'y', 'z', 'face'), 'attack': ('entity_id',),
              'craft': ('recipe',)}[op]
    if set(action) != set(('op',) + fields):
        raise ValueError('invalid_fields')
    for name in fields:
        if name == 'recipe':
            if action[name] not in ('oak_planks', 'crafting_table'):
                raise ValueError('unsupported_recipe')
            continue
        if name == 'entity_id':
            value = action[name]
            if not isinstance(value, (str, type(u''))) or len(value) > 24 or not value.lstrip('-').isdigit():
                raise ValueError('invalid_entity_id')
            continue
        bounds = {'left': (-1, 1), 'forward': (-1, 1),
                  'duration_ms': (1, 5000 if op == 'dig' else 1500),
                  'pitch': (-90, 90), 'yaw': (-180, 180), 'slot': (0, 8),
                  'x': (-30000000, 30000000), 'z': (-30000000, 30000000),
                  'y': (-512, 4096), 'face': (0, 5)}[name]
        if not finite(action[name], *bounds):
            raise ValueError('invalid_' + name)
        if name in ('slot', 'x', 'y', 'z', 'face') and not isinstance(action[name], int):
            raise ValueError('integer_required_' + name)


class Bridge(object):
    def __init__(self):
        self.sock = None
        self.input = b''
        self.output = b''
        self.epoch = None
        self.generation = 0
        self.lease = 0
        self.retry = 0
        self.sample_at = 0
        self.sequence = 0
        self.pending = []
        self.active = None
        self.seen = set()
        self.player = None
        self.motion = None
        self.tick_count = 0
        self.screens = []
        self.errors = {}
        self.rate = 5
        self.slow_windows = 0
        self.costs = []
        self.metrics_at = 0
        self.metrics = {}
        self.inventory = []
        self.inventory_at = 0
        self.event_seq = 0
        self.loaded = False
        self.suspended = False
        self.requested_rate = 5
        self.good_windows = 0
        self.sample_costs = []
        self.last_interaction = None
        self.native = None
        try:
            import _player
            self.native = _player
        except BaseException as exc:
            self.errors['native_actions'] = str(exc)[:160]
        self.last_send = 0
        self.byte_tokens = 96 * 1024.0
        self.budget_at = monotonic()
        self.io_at = 0
        self.event_at = 0
        self.event_tokens = 16 * 1024.0
        self.event_budget_at = monotonic()
        self.factory = api.GetEngineCompFactory()
        self.level = api.GetLevelId()
        print('MCDEV_AI_RUNTIME initialized')

    def queue(self, value):
        raw = encode(value)
        if len(raw) > MAX_FRAME or len(self.output) + len(raw) > 65536:
            raise ValueError('output_overflow')
        if not self.output:
            self.last_send = monotonic()
        self.output += raw

    def release(self, reason='cancelled'):
        if self.motion is not None:
            self.motion.UnlockInputVector()
        self.release_native()
        work = ([self.active] if self.active else []) + self.pending
        self.active = None
        self.pending = []
        for request in work:
            self.receipt(request, reason)

    def release_native(self):
        if self.native is not None and self.active:
            op = self.active['action']['op']
            if op == 'dig':
                a = self.active['action']
                self.native.local_player_stop_destroy_block(a['x'], a['y'], a['z'])
            elif op == 'use':
                self.native.local_player_release_using_item()

    def target_matches(self, action):
        target = self.factory.CreateCamera(self.level).PickFacing()
        origin = self.factory.CreatePos(self.player).GetPos()
        if action['op'] == 'attack':
            if target.get('type') != 'Entity' or target.get('entityId') != action['entity_id']:
                return False
            position = self.factory.CreatePos(action['entity_id']).GetPos()
        else:
            if target.get('type') != 'Block' or not all(target.get(k) == action[k] for k in ('x', 'y', 'z', 'face')):
                return False
            position = (action['x'] + .5, action['y'] + .5, action['z'] + .5)
        return bool(origin and position and sum((a - b) ** 2 for a, b in zip(origin, position)) <= 36)

    def close(self):
        try:
            self.release('disconnected')
        except BaseException:
            # Motion is released before receipts are queued. Overflow must not
            # prevent closing a broken transport.
            pass
        finally:
            if self.sock:
                self.sock.close()
            self.sock = None
            self.input = b''
            self.output = b''
            self.lease = 0
            self.last_send = 0

    def receipt(self, request, status, detail=None):
        action = request.get('action', {})
        if status == 'completed' and action.get('op') in ('dig', 'place'):
            pos = (action['x'], action['y'], action['z'])
            self.last_interaction = {'position': pos, 'tick': self.tick_count,
                                     'block': self.factory.CreateBlockInfo(self.level).GetBlock(pos)}
        self.queue({'type': 'receipt', 'epoch': self.epoch,
                    'generation': request.get('generation'), 'id': request.get('id'),
                    'status': status, 'detail': detail, 'tick': self.tick_count})

    def connect(self, now):
        if self.sock or now < self.retry:
            return
        self.retry = now + 2
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setblocking(False)
        self.sock.connect_ex(('127.0.0.1', int(os.environ['MCDEV_AI_PORT'])))
        self.queue({'type': 'hello', 'role': 'game', 'token': os.environ['MCDEV_AI_GAME_TOKEN'],
                    'epoch': self.epoch, 'actions': list(ACTIONS), 'protocol': 1})

    def io(self, now):
        try:
            if self.output:
                if self.last_send and now - self.last_send > 2:
                    self.close()
                    return
                self.byte_tokens = min(128 * 1024, self.byte_tokens + (now - self.budget_at) * 96 * 1024)
                self.budget_at = now
                size = min(MAX_FRAME, int(self.byte_tokens))
                if size > 0:
                    count = self.sock.send(self.output[:size])
                    self.byte_tokens -= count
                    self.output = self.output[count:]
                    if count:
                        self.last_send = now if self.output else 0
            try:
                data = self.sock.recv(MAX_FRAME)
            except socket.error as exc:
                if exc.errno not in (errno.EAGAIN, errno.EWOULDBLOCK, 10035):
                    raise
                data = None
            if data is None:
                data = b''
            elif not data:
                self.close()
                return
            self.input += data
            # Four bounded commands per tick, controls included.
            for unused in range(4):
                if b'\n' not in self.input:
                    break
                line, self.input = self.input.split(b'\n', 1)
                if len(line) > MAX_FRAME:
                    raise ValueError('frame_overflow')
                self.command(json.loads(line), now)
            if len(self.input) > MAX_FRAME * 2:
                raise ValueError('input_overflow')
        except socket.error as exc:
            if exc.errno not in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EINPROGRESS,
                                 errno.EALREADY, 10035, 10036, 10037, 10057):
                self.close()

    def command(self, request, now):
        if request.get('epoch') != self.epoch:
            return
        kind = request.get('type')
        generation = request.get('generation', -1)
        if kind == 'shutdown':
            self.release('cancelled')
            self.lease = 0
            self.suspended = True
            self.queue({'type': 'shutdown_ack', 'epoch': self.epoch})
            return
        if self.suspended:
            return
        if kind == 'control' and generation >= self.generation:
            if generation > self.generation or not request.get('enabled'):
                self.release()
                self.seen.clear()
            self.generation = generation
            remaining = min(2, request.get('valid_until_ms', 0) / 1000.0 - time.time())
            self.lease = now + max(0, remaining) if request.get('enabled') else 0
            self.requested_rate = request.get('hz', 5) if request.get('hz') in (2, 5, 10) else 5
            self.rate = min(self.rate, self.requested_rate)
            return
        if kind != 'action':
            return
        if generation != self.generation or now >= self.lease:
            self.receipt(request, 'rejected', 'stale_generation_or_lease')
            return
        if not self.loaded:
            self.receipt(request, 'rejected', 'world_loading')
            return
        identity = request.get('id')
        if identity in self.seen:
            return
        if not isinstance(identity, str) and not isinstance(identity, type(u'')):
            return
        if len(self.pending) >= 8 or len(self.seen) >= 4096:
            self.receipt(request, 'rejected', 'queue_full_or_rotate_generation')
            return
        try:
            validate(request['action'])
        except (ValueError, KeyError, TypeError) as exc:
            self.receipt(request, 'rejected', str(exc))
            return
        self.seen.add(identity)
        request['expires'] = now + min(2, request.get('not_after_ms', 0) / 1000.0 - time.time())
        self.pending.append(request)
        self.receipt(request, 'accepted')

    def execute(self, now):
        if now >= self.lease:
            if self.active or self.pending:
                self.release('lease_expired')
            return
        if self.active:
            if self.active['action']['op'] == 'craft':
                system = getattr(api, 'GetSystem', lambda *args: None)('AiCraftDemo', 'Craft')
                answer = system.take(self.active['id']) if system is not None else None
                if answer is not None:
                    self.receipt(self.active, 'completed' if answer.get('ok') else 'failed', answer)
                    self.active = None
                elif now >= self.active['ends']:
                    self.receipt(self.active, 'failed', 'craft_response_timeout_verify_inventory')
                    self.active = None
                return
            if now < self.active['ends']:
                if self.active['action']['op'] == 'dig':
                    a = self.active['action']
                    if self.target_matches(a):
                        self.native.local_player_continue_destroy_block(a['x'], a['y'], a['z'], a['face'])
                    else:
                        self.release_native()
                        self.receipt(self.active, 'completed', 'target_changed_verify_postcondition')
                        self.active = None
                return
            self.motion.UnlockInputVector()
            self.release_native()
            self.receipt(self.active, 'completed')
            self.active = None
        if not self.pending:
            return
        request = self.pending.pop(0)
        if now >= request['expires']:
            self.receipt(request, 'expired')
            return
        action = request['action']
        try:
            op = action['op']
            if op == 'move':
                result = self.motion.LockInputVector((action['left'], action['forward']))
            elif op == 'look':
                result = self.factory.CreateRot(self.player).SetRot((action['pitch'], action['yaw']))
            elif op == 'jump':
                result = api.SimulateJump()
            elif op == 'select_slot':
                result = self.native.local_player_select_slot(action['slot'])
            elif op == 'use':
                result = self.native.local_player_use_item()
            elif op == 'craft':
                system = getattr(api, 'GetSystem', lambda *args: None)('AiCraftDemo', 'Craft')
                if system is None:
                    raise ValueError('craft_demo_pack_not_loaded')
                result = system.request(request['id'], action['recipe'])
            elif op in ('dig', 'place', 'attack'):
                if not self.target_matches(action):
                    raise ValueError('crosshair_precondition_failed')
                if op == 'attack':
                    result = self.native.local_player_attack_entity(int(action['entity_id']))
                elif op == 'dig':
                    result = self.native.local_player_start_destroy_block(action['x'], action['y'], action['z'], action['face'])
                else:
                    result = self.native.local_player_build_block(action['x'], action['y'], action['z'], action['face'])
            else:
                result = True
            if result is False:
                raise ValueError('game_rejected')
            if op in ('move', 'wait', 'dig', 'use', 'craft'):
                self.active = request
                request['ends'] = now + (5 if op == 'craft' else action['duration_ms'] / 1000.0)
                self.receipt(request, 'started')
            else:
                self.receipt(request, 'completed')
        except BaseException as exc:
            self.motion.UnlockInputVector()
            self.receipt(request, 'failed', str(exc)[:256])

    def read(self, label, callback):
        try:
            value = callback()
            self.errors.pop(label, None)
            return value
        except BaseException as exc:
            self.errors[label] = str(exc)[:160]
            return None

    def observe(self, now):
        f = self.factory
        pos = self.read('position', lambda: f.CreatePos(self.player).GetPos())
        rot = self.read('rotation', lambda: f.CreateRot(self.player).GetRot())
        camera = f.CreateCamera(self.level)
        facing = self.read('crosshair', lambda: camera.PickFacing())
        camera_pos = self.read('camera_position', lambda: camera.GetPosition())
        camera_rot = self.read('camera_rotation', lambda: camera.GetCameraRotation())
        forward = self.read('camera_forward', lambda: camera.GetForward())
        camera_ready = bool(camera_pos and forward and sum(x * x for x in forward) > .5)
        if not camera_ready:
            facing = None
        fov = self.read('camera_fov', lambda: camera.GetFov())
        perspective = self.read('perspective', lambda: f.CreatePlayerView(self.player).GetPerspective())
        if facing and facing.get('type') == 'Block':
            facing['block'] = self.read('crosshair_block', lambda: f.CreateBlockInfo(self.level).GetBlock(
                (facing['x'], facing['y'], facing['z'])))
        if now >= self.inventory_at:
            items = self.read('inventory', lambda: f.CreateItem(self.player).GetPlayerAllItems(0, False))
            if items is not None:
                self.inventory = [{'slot': i, 'name': x.get('newItemName', x.get('itemName')),
                                   'count': x.get('count'), 'aux': x.get('newAuxValue', x.get('auxValue'))}
                                  for i, x in enumerate(items[:36]) if x]
            self.inventory_at = now + 1
        if self.last_interaction is not None:
            block = self.read('last_interaction', lambda: f.CreateBlockInfo(self.level).GetBlock(
                tuple(self.last_interaction['position'])))
            self.last_interaction.update({'block': block, 'sample_tick': self.tick_count,
                                          'source': 'client_loaded_block'})
        rays = []
        if camera_ready and self.loaded:
            # Eight explicit view samples. This is a sparse
            # geometric estimate, not pixel visibility or a complete scene.
            pitch = math.degrees(math.asin(max(-1, min(1, -forward[1]))))
            yaw = math.degrees(math.atan2(-forward[0], forward[2]))
            for dp, dy in ((0, 0), (-15, -30), (-15, 0), (-15, 30), (0, -30), (0, 30), (15, -30), (15, 0)):
                direction = api.GetDirFromRot((max(-90, min(90, pitch + dp)), yaw + dy))
                hit = self.read('rays', lambda: api.getEntitiesOrBlockFromRay(
                    tuple(camera_pos), direction, 16, True, 3))
                # Ignore the camera's own player, but never expose anything
                # behind the first other collision (including block occlusion).
                visible = [x for x in (hit or []) if x.get('entityId') != self.player][:1]
                rays.append({'offset': [dp, dy], 'hits': visible})
        self.sequence += 1
        return {'type': 'observation', 'epoch': self.epoch, 'seq': self.sequence, 'tick': self.tick_count,
                'world_ready': self.loaded and camera_ready,
                'time_ms': int(time.time() * 1000), 'generation': self.generation,
                'camera': {'position': camera_pos, 'rotation': camera_rot, 'forward': forward, 'fov': fov, 'perspective': perspective},
                'player': {'id': self.player, 'position': pos, 'rotation': rot,
                           'health': self.read('health', lambda: f.CreateAttr(self.player).GetAttrValue(0)),
                           'inventory': self.inventory},
                'last_interaction': self.last_interaction,
                'scene': {'crosshair': facing, 'rays': rays, 'range': 16,
                          'visibility': 'sparse_geometry_estimate', 'origin': 'camera_position'},
                'ui': {'top': self.read('ui_top', lambda: api.GetTopUI()),
                       'screen_events': list(self.screens), 'coverage': 'top_name_and_push_pop'},
                'coverage': {'audio': 'play_requests_not_audibility', 'pixels': False,
                             'ui_controls': False, 'complete_scene': False,
                             'unverified_actions': ['jump', 'use', 'place', 'attack']},
                'capabilities': list(ACTIONS if self.native is not None else ACTIONS[:4])
                if getattr(api, 'GetSystem', lambda *args: None)('AiCraftDemo', 'Craft') is not None
                else list(ACTIONS[:-1] if self.native is not None else ACTIONS[:4]),
                'errors': dict(self.errors),
                'metrics': self.metrics, 'hz': self.rate}

    def tick(self, system, epoch, events):
        start = monotonic()
        if getattr(system, 'ai_destroyed', False):
            # The entity/world may already be destroyed: no SDK reads or writes.
            self.active = None
            self.pending = []
            self.motion = None
            self.close()
            self.suspended = True
            return
        if self.suspended:
            # Explicit process shutdown is permanent, including dimension
            # events dispatched while the engine is destroying its world.
            if self.sock and start >= self.io_at:
                self.io(start)
                self.io_at = start + .05
            return
        if self.epoch != epoch:
            self.close()
            self.epoch = epoch
            self.generation = 0
            self.suspended = False
            self.seen.clear()
            self.screens = []
            self.player = None
            self.motion = None
            self.last_interaction = None
            self.inventory = []
            self.inventory_at = 0
            del events[:]
        self.tick_count += 1
        self.loaded = bool(getattr(system, 'ai_loaded', False))
        player = api.GetLocalPlayerId()
        if not player or player == '-1':
            # A cached component can outlive the native entity it wraps.
            self.player = None
            self.motion = None
            self.active = None
            self.pending = []
            self.loaded = False
            self.close()
            return
        if player != self.player:
            self.player = player
            self.motion = self.factory.CreateActorMotion(self.player)
        self.connect(start)
        if not self.sock:
            return
        if start >= self.io_at:
            self.io(start)
            self.io_at = start + .05
        if not self.sock:
            return
        if self.suspended:
            return
        self.execute(start)
        if events and start >= self.event_at:
            self.event_at = start + .05
            selected = events[:8]
            del events[:8]
            for event in selected:
                self.event_seq += 1
                event['event_seq'] = self.event_seq
                event['tick'] = self.tick_count
                if event['kind'] == 'screen_push':
                    self.screens = (self.screens + [event['data']])[-8:]
                elif event['kind'] == 'screen_pop' and self.screens:
                    self.screens.pop()
            packet = {'type': 'events', 'epoch': self.epoch, 'events': selected}
            packet_size = len(encode(packet))
            self.event_tokens = min(16 * 1024, self.event_tokens + (start - self.event_budget_at) * 16 * 1024)
            self.event_budget_at = start
            if packet_size <= min(4096, self.event_tokens):
                self.queue(packet)
                self.event_tokens -= packet_size
            else:
                self.queue({'type': 'events', 'epoch': self.epoch, 'events': [
                    {'kind': 'event_gap', 'event_seq': self.event_seq, 'tick': self.tick_count,
                     'data': {'reason': 'event_batch_exceeds_4KiB', 'count': len(selected)}}]})
        if start >= self.sample_at and len(self.output) < MAX_FRAME:
            sample_start = monotonic()
            observation = self.observe(start)
            if len(encode(observation)) > MAX_FRAME:
                observation['scene']['rays'] = []
                observation['errors']['size'] = 'rays_omitted_frame_budget'
            self.queue(observation)
            self.sample_costs.append((monotonic() - sample_start) * 1000)
            self.sample_at = start + 1.0 / self.rate
        self.costs.append((monotonic() - start) * 1000)
        if start >= self.metrics_at:
            ordered = sorted(self.costs)
            self.metrics = {'bridge_ms_p95': round(ordered[int((len(ordered) - 1) * .95)], 3),
                            'samples': len(ordered), 'pending': len(self.pending),
                            'output_bytes': len(self.output),
                            'sample_ms_max': round(max(self.sample_costs or [0]), 3)}
            self.slow_windows = self.slow_windows + 1 if self.metrics['bridge_ms_p95'] > .5 else 0
            self.good_windows = self.good_windows + 1 if self.metrics['bridge_ms_p95'] <= .5 else 0
            if self.slow_windows >= 2:
                self.rate = 2 if self.rate <= 5 else 5
                self.slow_windows = 0
            elif self.good_windows >= 5:
                self.rate = min(self.requested_rate, 5 if self.rate < 5 else 10)
                self.good_windows = 0
            self.costs = []
            self.sample_costs = []
            self.metrics_at = start + 2
