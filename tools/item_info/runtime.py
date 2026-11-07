# -*- coding: utf-8 -*-
"""Names the crosshair target on the HUD, so missing Chinese text shows in tests.

Python 2.7 compatible. Mounted only when the test option is enabled, and it
only reads client state.
"""
import re
import mod.client.extraClientApi as clientApi

NAMESPACE = 'MCDevItemInfo'
UI_KEY = 'itemInfo'
UI_DEF = 'mcdevItemInfo.main'
SCREEN_CLASS = 'mcdevItemInfoScripts.itemInfo.ItemInfoScreen'
SAMPLE_TICKS = 3
FORMAT_CODE = re.compile('§.')
RAW_KEY = re.compile(r'^(tile|item|entity)\..*\.name$')


def utf8(value):
    # GetChinese returns unicode, while SetText takes UTF-8 str on Python 2.
    value = value or ''
    if str is bytes and not isinstance(value, bytes):
        return value.encode('utf-8')
    return value


def has_chinese(text):
    if isinstance(text, bytes):
        text = text.decode('utf-8', 'ignore')
    return any(0x4e00 <= ord(char) <= 0x9fff for char in text)


def lang_key(prefix, identifier):
    if identifier.startswith('minecraft:'):
        identifier = identifier[len('minecraft:'):]
    return '%s.%s.name' % (prefix, identifier)


def describe(name, key, identifier):
    shown = FORMAT_CODE.sub('', utf8(name)).strip()
    if not shown or RAW_KEY.match(shown):
        return '§c未配置中文 %s\n§7%s' % (shown or key, identifier)
    # Text that was registered but never translated, such as English in zh_CN.lang.
    return '%s%s\n§7%s' % ('§f' if has_chinese(shown) else '§e', shown, identifier)


class ItemInfoScreen(clientApi.GetScreenNodeCls()):
    def __init__(self, namespace, name, param):
        super(ItemInfoScreen, self).__init__(namespace, name, param)
        self.panel = None
        self.label = None

    def Create(self):
        self.panel = self.GetBaseUIControl('/info')
        self.label = self.GetBaseUIControl('/info/text').asLabel()

    def Show(self, text):
        if text:
            self.label.SetText(text, True)
        self.panel.SetVisible(bool(text))


class ItemInfoSystem(clientApi.GetClientSystemCls()):
    def __init__(self, namespace, name):
        super(ItemInfoSystem, self).__init__(namespace, name)
        self.factory = clientApi.GetEngineCompFactory()
        self.level = clientApi.GetLevelId()
        self.registered = False
        self.screen = None
        self.target = None
        self.ticks = 0
        self.failure = None
        engine = clientApi.GetEngineNamespace(), clientApi.GetEngineSystemName()
        self.ListenForEvent(engine[0], engine[1], 'UiInitFinished', self, self.OnUiReady)
        self.ListenForEvent(engine[0], engine[1], 'OnScriptTickClient', self, self.OnTick)

    def OnUiReady(self, args):
        if not self.registered:
            self.registered = clientApi.RegisterUI(NAMESPACE, UI_KEY, SCREEN_CLASS, UI_DEF)
        # Reuse a screen that survived the re-init, because CreateUI rejects
        # a key that is still in use.
        self.screen = clientApi.GetUI(NAMESPACE, UI_KEY) or clientApi.CreateUI(NAMESPACE, UI_KEY, {'isHud': 1})
        self.target = None

    def OnTick(self, *args):
        self.ticks += 1
        if self.ticks % SAMPLE_TICKS or self.screen is None or self.screen.panel is None:
            return
        try:
            self.Refresh()
        except Exception as exc:
            # A broken lookup would repeat at every sample.
            if repr(exc) != self.failure:
                self.failure = repr(exc)
                print('MCDEV_ITEM_INFO failed: %s' % self.failure)

    def Refresh(self):
        facing = self.factory.CreateCamera(self.level).PickFacing() or {}
        kind = facing.get('type')
        if kind == 'Block':
            block = self.factory.CreateBlockInfo(self.level).GetBlock((facing['x'], facing['y'], facing['z']))
            target = tuple(block)
            read = lambda: self.BlockText(*block)
        elif kind == 'Entity':
            target = facing['entityId']
            read = lambda: self.EntityText(target)
        else:
            target = None
            read = lambda: ''
        if target != self.target:
            self.screen.Show(read())
            self.target = target

    def Chinese(self, key):
        return self.factory.CreateGame(self.level).GetChinese(key)

    def BlockText(self, identifier, aux):
        identifier = utf8(identifier)
        key = lang_key('tile', identifier)
        # The item name distinguishes aux variants; blocks without an item,
        # such as portals, only have their tile key.
        name = self.factory.CreateItem(self.level).GetItemHoverName(identifier, aux) or self.Chinese(key)
        return describe(name, key, '%s:%d' % (identifier, aux))

    def EntityText(self, entity):
        identifier = utf8(self.factory.CreateEngineType(entity).GetEngineTypeStr())
        if identifier == 'minecraft:player':
            return '§f%s\n§7%s' % (utf8(self.factory.CreateName(entity).GetName()), identifier)
        key = lang_key('entity', identifier)
        return describe(self.Chinese(key), key, identifier)
