import logging
import pymongo
import pymongo.errors

logger = logging.getLogger(__name__)

class PersistedIds(object):
    def __init__(self, mongoClient):
        self.mongo_client = mongoClient
        self.collection = self.mongo_client.db.persisted_ids

    # return true if ID is new, or false if its already in use.
    def validateId(self, persistedId):
        if persistedId is None:
            return

        # ID is always indexed.

        recordToInsert = {"_id" : persistedId}
        mongoResult = self.collection.update(recordToInsert, recordToInsert, upsert=True)
        result = not mongoResult['updatedExisting']
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Validated ID [%s], is new: [%s]" % (recordToInsert, result))
        return result


    def listItems(self):
        for item in self.collection.find():
            print item


