import logging

from datetime import datetime
import pymongo
import pymongo.errors

logger = logging.getLogger(__name__)

class Blocking(object):
    def __init__(self, mongoCollection, expiryTimeSeconds=None):
        self.block_collection = mongoCollection
        self.expiry_time_seconds = expiryTimeSeconds

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


        if self.expiry_time_seconds is not None:
            attempts = 0
            while attempts < 2:
                try:
                    attempts += 1
                    self.block_collection.create_index([("date", pymongo.ASCENDING)],
                                                       expireAfterSeconds=self.expiry_time_seconds)
                    break
                except pymongo.errors.OperationFailure as e:
                    logger.warn("Pymongo error: %s, dropping date index on blocking collection" % e)
                    self.block_collection.drop_index([("date", pymongo.ASCENDING)])

            utcNow = datetime.utcnow()
            recordToInsert.update({"date": utcNow})

        logger.debug("Writing block record with expiration time of [%s] to DB for social ID: [%s] and [%s]" % (self.expiry_time_seconds, blockerSocialId, blockedSocialId))
        self.block_collection.insert_one(recordToInsert)

    def listItems(self):
        for item in self.block_collection.find():
            print item