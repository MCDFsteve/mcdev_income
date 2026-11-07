# -*- coding: utf-8 -*-
"""Small, audited survival recipe executor; it never grants free materials."""
import mod.server.extraServerApi as api

RECIPES = {
    'oak_planks': ('minecraft:oak_log', 1, 'minecraft:oak_planks', 4,
                   'minecraft:oak_planks'),
    'crafting_table': ('minecraft:oak_planks', 4,
                       'minecraft:crafting_table', 1,
                       'minecraft:WorkBench_recipeId_from_oak'),
}


def item_name(item):
    return item.get('newItemName', item.get('itemName')) if item else None


class CraftSystem(api.GetServerSystemCls()):
    def __init__(self, namespace, name):
        super(CraftSystem, self).__init__(namespace, name)
        self.seen = set()
        self.ListenForEvent('AiCraftDemo', 'Craft', 'CraftRequest', self, self.OnRequest)

    def OnRequest(self, args):
        identity = args.get('id')
        player = args.get('playerId')
        recipe = args.get('recipe')
        if not isinstance(identity, (str, type(u''))) or len(identity) > 64:
            return
        response = {'id': identity, 'recipe': recipe, 'ok': False,
                    'method': 'server_recipe_exchange'}
        try:
            if identity in self.seen or len(self.seen) >= 4096:
                raise ValueError('duplicate_or_budget_exceeded')
            self.seen.add(identity)
            if recipe not in RECIPES:
                raise ValueError('unsupported_recipe')
            players = api.GetPlayerList()
            if len(players) != 1 or player != players[0]:
                raise ValueError('single_player_only')
            game = api.GetEngineCompFactory().CreateGame(api.GetLevelId())
            if game.GetPlayerGameType(player) != 0:
                raise ValueError('survival_required')
            source, needed, product, amount, recipe_id = RECIPES[recipe]
            item = api.GetEngineCompFactory().CreateItem(player)
            items = item.GetPlayerAllItems(0, False)
            if not isinstance(items, list) or len(items) < 36:
                raise ValueError('inventory_unavailable')
            source_slot = next((i for i, value in enumerate(items[:36])
                                if item_name(value) == source and
                                value.get('count', 0) >= needed), None)
            target_slot = next((i for i, value in enumerate(items[:36])
                                if not value), None)
            if source_slot is None:
                raise ValueError('missing_material')
            if target_slot is None:
                raise ValueError('no_free_slot')
            previous = dict(items[source_slot])
            before = previous.get('count', 0)
            if item.SetInvItemNum(source_slot, before - needed) is False:
                raise ValueError('consume_failed')
            output = {'itemName': product, 'auxValue': 0, 'count': amount}
            try:
                if item.SpawnItemToPlayerInv(output, player, target_slot) is False:
                    raise ValueError('produce_failed')
                after = item.GetPlayerAllItems(0, False)
                if (not isinstance(after, list) or
                    item_name(after[target_slot]) != product or
                    after[target_slot].get('count', 0) < amount):
                    raise ValueError('postcondition_failed')
            except BaseException:
                restored = item.SetPlayerAllItems({(0, source_slot): previous})
                if restored.get((0, source_slot)) is not True:
                    raise ValueError('rollback_failed')
                raise
            response.update({'ok': True, 'recipe_id': recipe_id,
                             'source': source, 'consumed': needed,
                             'product': product, 'produced': amount,
                             'source_slot': source_slot,
                             'product_slot': target_slot})
            print('AI_CRAFT_DEMO %s consumed=%s:%d produced=%s:%d' %
                  (recipe_id, source, needed, product, amount))
        except BaseException as exc:
            response['reason'] = str(exc)[:128]
        if isinstance(player, (str, type(u''))):
            self.NotifyToClient(player, 'CraftResponse', response)

    def Destroy(self):
        self.UnListenForEvent('AiCraftDemo', 'Craft', 'CraftRequest', self, self.OnRequest)
