# -*- coding: utf-8 -*-
import mod.client.extraClientApi as api


class CraftSystem(api.GetClientSystemCls()):
    def __init__(self, namespace, name):
        super(CraftSystem, self).__init__(namespace, name)
        self.responses = {}
        self.ListenForEvent("AiCraftDemo", "Craft", "CraftResponse", self, self.OnResponse)

    def request(self, identity, recipe):
        player = api.GetLocalPlayerId()
        if not player or player == '-1':
            return False
        self.NotifyToServer("CraftRequest", {'id': identity, 'recipe': recipe, 'playerId': player})
        return True

    def OnResponse(self, args):
        identity = args.get('id')
        if isinstance(identity, (str, type(u''))) and len(identity) <= 64:
            self.responses[identity] = dict(args)
            if len(self.responses) > 16:
                self.responses.clear()

    def take(self, identity):
        return self.responses.pop(identity, None)

    def Destroy(self):
        self.UnListenForEvent("AiCraftDemo", "Craft", "CraftResponse", self, self.OnResponse)
