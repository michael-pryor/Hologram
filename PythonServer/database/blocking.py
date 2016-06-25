import logging
import pymongo
import pymongo.errors

logger = logging.getLogger(__name__)

class Blocking(object):
    RANDOM_FACTOR = 20

    def __init__(self, mongoClient):
        self.mongo_client = mongoClient
        self.block_collection = self.mongo_client.db.blocked

    # find a match which is fit enough for the specified client.
    def canMatch(self, clientA, clientB, checkBothSides=True):
        #assert isinstance(clientA, Client)
        #assert isinstance(clientB, Client)

        clientFacebookIdA = clientA.login_details.facebook_id
        clientFacebookIdB = clientB.login_details.facebook_id

        queryA = { "blockerFacebookId" : clientFacebookIdA,
                   "blockedFacebookId" : clientFacebookIdB }

        queryB = {"blockerFacebookId": clientFacebookIdB,
                  "blockedFacebookId": clientFacebookIdA}

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

        blockerFacebookId = blockerClient.login_details.facebook_id
        blockedFacebookId = blockedClient.login_details.facebook_id

        self.block_collection.create_index([("blockerFacebookId", pymongo.ASCENDING),
                                            ("blockedFacebookId", pymongo.ASCENDING)])

        recordToInsert = {"blockerFacebookId" : blockerFacebookId,
                          "blockedFacebookId" : blockedFacebookId}

        logger.debug("Writing block record to DB for facebook ID: [%s] and [%s]" % (blockerFacebookId, blockedFacebookId))
        self.block_collection.insert_one(recordToInsert)

    def listItems(self):
        for item in self.block_collection.find():
            print item