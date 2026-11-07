# -*- coding: utf-8 -*-
from mod.common.mod import Mod
import mod.server.extraServerApi as api


@Mod.Binding(name="AiMovementFixture", version="1.0.0")
class Fixture(object):
    @Mod.InitServer()
    def InitServer(self):
        api.RegisterSystem("AiMovementFixture", "Movement", "aiMovementFixture.modMain.Movement")


class Movement(api.GetServerSystemCls()):
    def __init__(self, namespace, name):
        super(Movement, self).__init__(namespace, name)
        self.origin = None
        self.counter = 0
        self.ListenForEvent(api.GetEngineNamespace(), api.GetEngineSystemName(), "OnScriptTickServer", self, self.OnTick)

    def OnTick(self, *args):
        self.counter += 1
        if self.counter % 15:
            return
        players = api.GetPlayerList()
        if not players:
            return
        pos = api.GetEngineCompFactory().CreatePos(players[0]).GetPos()
        if not pos or pos[1] > 512:
            return
        if self.origin is None:
            self.origin = pos
            print("AI_FIXTURE_READY")
        distance = abs(pos[0] - self.origin[0]) + abs(pos[2] - self.origin[2])
        if distance > .25:
            print("AI_FIXTURE_MOVED distance=%.3f" % distance)

    def Destroy(self):
        self.UnListenForEvent(api.GetEngineNamespace(), api.GetEngineSystemName(), "OnScriptTickServer", self, self.OnTick)
