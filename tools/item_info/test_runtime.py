"""Run with python3 -m unittest discover -s tools/item_info -p 'test_*.py'."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest


class Screen:
    def __init__(self, namespace, name, param):
        self.shown = []
        self.panel = object()

    def Show(self, text):
        self.shown.append(text)


class System:
    def __init__(self, namespace, name):
        self.listened = []

    def ListenForEvent(self, namespace, system, event, target, callback):
        self.listened.append(event)


class Comp:
    def __init__(self, **methods):
        self.__dict__.update(methods)


class Factory:
    def __init__(self):
        self.facing = {'type': 'None'}
        self.blocks = {}
        self.hover = {}
        self.lang = {}
        self.entities = {}
        self.names = {}
        self.reads = 0

    def CreateCamera(self, level):
        return Comp(PickFacing=lambda: self.facing)

    def CreateBlockInfo(self, level):
        return Comp(GetBlock=lambda pos: self.blocks[pos])

    def CreateItem(self, level):
        def hover(identifier, aux):
            self.reads += 1
            return self.hover.get((identifier, aux), '')
        return Comp(GetItemHoverName=hover)

    def CreateGame(self, level):
        return Comp(GetChinese=lambda key: self.lang.get(key, key))

    def CreateEngineType(self, entity):
        return Comp(GetEngineTypeStr=lambda: self.entities[entity])

    def CreateName(self, entity):
        return Comp(GetName=lambda: self.names[entity])


def load():
    api = types.ModuleType('mod.client.extraClientApi')
    api.factory = Factory()
    api.registered = []
    api.existing = None
    api.created = []
    api.GetScreenNodeCls = lambda: Screen
    api.GetClientSystemCls = lambda: System
    api.GetEngineCompFactory = lambda: api.factory
    api.GetLevelId = lambda: '-1'
    api.GetEngineNamespace = lambda: 'Minecraft'
    api.GetEngineSystemName = lambda: 'Engine'
    api.RegisterUI = lambda *args: api.registered.append(args) or True
    api.GetUI = lambda namespace, key: api.existing

    def create(namespace, key, params):
        screen = Screen(namespace, key, params)
        api.created.append((key, params))
        return screen
    api.CreateUI = create
    for name in ('mod', 'mod.client'):
        sys.modules[name] = types.ModuleType(name)
    sys.modules['mod.client'].extraClientApi = api
    sys.modules['mod.client.extraClientApi'] = api
    spec = importlib.util.spec_from_file_location('item_info', Path(__file__).with_name('runtime.py'))
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    return runtime, api


class DescribeTest(unittest.TestCase):
    def setUp(self):
        self.runtime, _ = load()

    def test_translated_name_is_white(self):
        self.assertEqual(self.runtime.describe('花岗岩§r', 'tile.stone.name', 'minecraft:stone:1'),
                         '§f花岗岩\n§7minecraft:stone:1')

    def test_raw_key_is_red_and_names_the_key_to_add(self):
        key = 'tile.demo:glass_02.name'
        self.assertEqual(self.runtime.describe(key, key, 'demo:glass_02:0'),
                         '§c未配置中文 tile.demo:glass_02.name\n§7demo:glass_02:0')

    def test_raw_item_key_from_hover_name_is_red(self):
        text = self.runtime.describe('item.demo:glass.name§r', 'tile.demo:glass.name', 'demo:glass:0')
        self.assertTrue(text.startswith('§c未配置中文 item.demo:glass.name\n'))

    def test_empty_name_falls_back_to_the_expected_key(self):
        self.assertTrue(self.runtime.describe('', 'tile.demo:a.name', 'demo:a:0').startswith(
            '§c未配置中文 tile.demo:a.name\n'))

    def test_english_only_name_is_yellow(self):
        self.assertEqual(self.runtime.describe('Glass', 'tile.demo:a.name', 'demo:a:0'), '§eGlass\n§7demo:a:0')

    def test_vanilla_namespace_is_not_part_of_the_key(self):
        self.assertEqual(self.runtime.lang_key('entity', 'minecraft:zombie'), 'entity.zombie.name')
        self.assertEqual(self.runtime.lang_key('entity', 'demo:npc'), 'entity.demo:npc.name')


class SystemTest(unittest.TestCase):
    def setUp(self):
        self.runtime, self.api = load()
        self.factory = self.api.factory
        self.system = self.runtime.ItemInfoSystem('ns', 'name')
        self.system.OnUiReady({})
        self.screen = self.system.screen

    def sample(self):
        for _ in range(self.runtime.SAMPLE_TICKS):
            self.system.OnTick()

    def look_at_block(self, block):
        self.factory.facing = {'type': 'Block', 'x': 1, 'y': 2, 'z': 3}
        self.factory.blocks[(1, 2, 3)] = block

    def test_hud_screen_is_created_without_taking_input(self):
        self.assertEqual(self.api.created, [('itemInfo', {'isHud': 1})])
        self.assertEqual(self.api.registered[0][3], 'mcdevItemInfo.main')

    def test_block_variants_use_their_aux_name(self):
        self.factory.hover[('minecraft:stone', 1)] = '花岗岩'
        self.look_at_block(('minecraft:stone', 1))
        self.sample()
        self.assertEqual(self.screen.shown, ['§f花岗岩\n§7minecraft:stone:1'])

    def test_block_without_item_uses_tile_text(self):
        self.factory.lang['tile.portal.name'] = '下界传送门'
        self.look_at_block(('minecraft:portal', 0))
        self.sample()
        self.assertEqual(self.screen.shown, ['§f下界传送门\n§7minecraft:portal:0'])

    def test_unchanged_target_is_not_read_again(self):
        self.factory.hover[('minecraft:stone', 0)] = '石头'
        self.look_at_block(('minecraft:stone', 0))
        self.sample()
        self.sample()
        self.assertEqual(self.factory.reads, 1)
        self.assertEqual(len(self.screen.shown), 1)

    def test_block_change_at_same_position_refreshes(self):
        self.look_at_block(('minecraft:stone', 0))
        self.sample()
        self.factory.blocks[(1, 2, 3)] = ('demo:new', 0)
        self.sample()
        self.assertEqual(self.screen.shown[-1], '§c未配置中文 tile.demo:new.name\n§7demo:new:0')

    def test_entity_uses_entity_key(self):
        self.factory.entities['7'] = 'minecraft:zombie'
        self.factory.lang['entity.zombie.name'] = '僵尸'
        self.factory.facing = {'type': 'Entity', 'entityId': '7'}
        self.sample()
        self.assertEqual(self.screen.shown, ['§f僵尸\n§7minecraft:zombie'])

    def test_unnamed_custom_entity_is_red(self):
        self.factory.entities['7'] = 'demo:npc'
        self.factory.facing = {'type': 'Entity', 'entityId': '7'}
        self.sample()
        self.assertEqual(self.screen.shown, ['§c未配置中文 entity.demo:npc.name\n§7demo:npc'])

    def test_player_shows_its_name_rather_than_a_missing_key(self):
        self.factory.entities['7'] = 'minecraft:player'
        self.factory.names['7'] = 'Steve'
        self.factory.facing = {'type': 'Entity', 'entityId': '7'}
        self.sample()
        self.assertEqual(self.screen.shown, ['§fSteve\n§7minecraft:player'])

    def test_no_target_hides_the_panel_once(self):
        self.look_at_block(('minecraft:stone', 0))
        self.sample()
        self.factory.facing = {'type': 'None'}
        self.sample()
        self.sample()
        self.assertEqual(self.screen.shown[1:], [''])

    def test_screen_that_is_not_created_yet_is_left_alone(self):
        self.screen.panel = None
        self.look_at_block(('minecraft:stone', 0))
        self.sample()
        self.assertEqual(self.screen.shown, [])
        self.screen.panel = object()
        self.sample()
        self.assertEqual(len(self.screen.shown), 1)

    def test_ui_reinit_reuses_a_surviving_screen_and_repaints(self):
        self.look_at_block(('minecraft:stone', 0))
        self.sample()
        self.api.existing = self.screen
        self.system.OnUiReady({})
        self.sample()
        self.assertEqual(len(self.api.created), 1)
        self.assertEqual(len(self.api.registered), 1)
        self.assertEqual(len(self.screen.shown), 2)

    def test_failure_is_reported_once_and_keeps_sampling(self):
        self.factory.facing = None
        calls = []
        self.factory.CreateCamera = lambda level: calls.append(level) or Comp(
            PickFacing=lambda: (_ for _ in ()).throw(ValueError('not ready')))
        printed = []
        self.runtime.print = lambda text: printed.append(text)
        self.sample()
        self.sample()
        self.assertEqual(len(calls), 2)
        self.assertEqual(printed, ["MCDEV_ITEM_INFO failed: ValueError('not ready')"])


if __name__ == '__main__':
    unittest.main()
