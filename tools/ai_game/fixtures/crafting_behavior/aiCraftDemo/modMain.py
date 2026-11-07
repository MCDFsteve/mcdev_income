# -*- coding: utf-8 -*-
from mod.common.mod import Mod


@Mod.Binding(name="AiCraftDemo", version="1.0.0")
class CraftMod(object):
    @Mod.InitClient()
    def InitClient(self):
        import mod.client.extraClientApi as client_api
        client_api.RegisterSystem("AiCraftDemo", "Craft", "aiCraftDemo.clientSystem.CraftSystem")

    @Mod.InitServer()
    def InitServer(self):
        import mod.server.extraServerApi as server_api
        server_api.RegisterSystem("AiCraftDemo", "Craft", "aiCraftDemo.serverSystem.CraftSystem")
