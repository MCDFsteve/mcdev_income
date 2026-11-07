# -*- coding: utf-8 -*-
import mod.server.extraServerApi as api

TARGETS = (
    ('block', 'minecraft:stone', 1),
    ('block', 'minecraft:oak_stairs', 2),
    ('block', 'minecraft:standing_banner', 0),
    ('block', 'mcdev_item_fixture:named', 0),
    ('block', 'mcdev_item_fixture:unnamed', 0),
    ('block', 'mcdev_item_fixture:english', 0),
    ('entity', 'minecraft:pig', 0),
    ('entity', 'mcdev_item_fixture:nameless', 0),
    ('none', '', 0),
)
STEP_TICKS = 150
SETTLE_TICKS = 300
HEIGHT = 200


class Stage(api.GetServerSystemCls()):
    """Puts each target two blocks in front of a player standing on a platform."""

    def __init__(self, namespace, name):
        super(Stage, self).__init__(namespace, name)
        self.ticks = 0
        self.index = -1
        self.base = None
        self.entity = None
        self.ListenForEvent(api.GetEngineNamespace(), api.GetEngineSystemName(), "OnScriptTickServer", self, self.OnTick)

    def OnTick(self, *args):
        self.ticks += 1
        players = api.GetPlayerList()
        if not players or self.ticks < SETTLE_TICKS or (self.ticks - SETTLE_TICKS) % STEP_TICKS:
            return
        factory = api.GetEngineCompFactory()
        if self.base is None:
            pos = factory.CreatePos(players[0]).GetFootPos()
            if not pos or pos[1] > 512:
                return
            self.base = int(pos[0]), HEIGHT, int(pos[2])
            print("ITEM_INFO_FIXTURE_READY")
        self.Next(factory, players[0])

    def Next(self, factory, player):
        self.index += 1
        if self.index > len(TARGETS):
            return
        if self.index == len(TARGETS):
            print("ITEM_INFO_FIXTURE_DONE")
            return
        x, y, z = self.base
        blocks = factory.CreateBlockInfo(api.GetLevelId())
        dimension = factory.CreateDimension(player).GetEntityDimensionId()
        blocks.SetBlockNew((x, y - 1, z), {'name': 'minecraft:stone', 'aux': 0}, 0, dimension)
        factory.CreatePos(player).SetFootPos((x + .5, y, z + .5))
        target = (x, y + 1, z + 2)
        blocks.SetBlockNew(target, {'name': 'minecraft:air', 'aux': 0}, 0, dimension)
        if self.entity:
            self.DestroyEntity(self.entity)
            self.entity = None
        kind, name, aux = TARGETS[self.index]
        if kind == 'block':
            blocks.SetBlockNew(target, {'name': name, 'aux': aux}, 0, dimension, True)
        elif kind == 'entity':
            self.entity = self.CreateEngineEntityByTypeStr(name, (x + .5, y + .8, z + 2.5), (0, 0), dimension, True)
        print("ITEM_INFO_TARGET %d %s:%d" % (self.index, name, aux))
