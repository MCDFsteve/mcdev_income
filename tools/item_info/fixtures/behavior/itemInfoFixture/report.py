# -*- coding: utf-8 -*-
import json
import mod.client.extraClientApi as api


class Report(api.GetClientSystemCls()):
    """Logs what the HUD actually shows, as the launcher can only read the log."""

    def __init__(self, namespace, name):
        super(Report, self).__init__(namespace, name)
        self.ticks = 0
        self.shown = None
        self.ListenForEvent(api.GetEngineNamespace(), api.GetEngineSystemName(), "OnScriptTickClient", self, self.OnTick)

    def OnTick(self, *args):
        self.ticks += 1
        if self.ticks % 10:
            return
        api.GetEngineCompFactory().CreateRot(api.GetLocalPlayerId()).SetRot((0, 0))
        screen = api.GetUI('MCDevItemInfo', 'itemInfo')
        if screen is None or screen.panel is None:
            return
        shown = [screen.panel.GetVisible(), screen.label.GetText()]
        if shown != self.shown:
            self.shown = shown
            print("ITEM_INFO_SHOWN " + json.dumps(shown))
