import logging
import pymongo
import pymongo.errors

logger = logging.getLogger(__name__)

class Blocking(object):
    def __init__(self, mongoClient):
        self.mongo_client = mongoClient
        self.block_collection = self.mongo_client.db.blocked

    # find a match which is fit enough for the specified client.
    def canMatch(self, clientA, clientB, checkBothSides=True):
        #assert isinstance(clientA, Client)
        #assert isinstance(clientB, Client)

        clientSocialIdA = clientA.login_details.persisted_unique_id
        clientSocialIdB = clientB.login_details.persisted_unique_id

        queryA = { "blockerSocialId" : clientSocialIdA,
                   "blockedSocialId" : clientSocialIdB }

        queryB = {"blockerSocialId": clientSocialIdB,
                  "blockedSocialId": clientSocialIdA}

        try:
            item = self.block_collection.find_one(queryA)
            if item is not None:
                return False

            if checkBothSides:
                item = self.block_collection.find_one(queryB)
                if item is not None:
                    return False
        except Exception as e:
            raise ValueError(e)

        return True

    def pushBlock(self, blockerClient, blockedClient):
        if blockerClient is None or blockedClient is None:
            return

        #assert isinstance(blockerClient, Client)
        #assert isinstance(blockedClient, Client)

        blockerSocialId = blockerClient.login_details.persisted_unique_id
        blockedSocialId = blockedClient.login_details.persisted_unique_id

        self.block_collection.create_index([("blockerSocialId", pymongo.ASCENDING),
                                            ("blockedSocialId", pymongo.ASCENDING)])

        recordToInsert = {"blockerSocialId" : blockerSocialId,
                          "blockedSocialId" : blockedSocialId}

        logger.debug("Writing block record to DB for social ID: [%s] and [%s]" % (blockerSocialId, blockedSocialId))
        self.block_collection.insert_one(recordToInsert)

    def listItems(self):
        for item in self.block_collection.find():
            print item