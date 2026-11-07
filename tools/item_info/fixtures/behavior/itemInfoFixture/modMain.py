# -*- coding: utf-8 -*-
from mod.common.mod import Mod
import mod.client.extraClientApi as clientApi
import mod.server.extraServerApi as serverApi


@Mod.Binding(name="ItemInfoFixture", version="1.0.0")
class Fixture(object):
    @Mod.InitServer()
    def InitServer(self):
        serverApi.RegisterSystem("ItemInfoFixture", "Stage", "itemInfoFixture.stage.Stage")

    @Mod.InitClient()
    def InitClient(self):
        clientApi.RegisterSystem("ItemInfoFixture", "Report", "itemInfoFixture.report.Report")
