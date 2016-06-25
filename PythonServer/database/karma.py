import logging
import pymongo
import pymongo.errors
from datetime import datetime
logger = logging.getLogger(__name__)

class Karma(object):
    def __init__(self, mongoCollection, expiryTimeSeconds):
        self.karma_collection = mongoCollection
        self.expiry_time_seconds = expiryTimeSeconds

    # find a match which is fit enough for the specified client.
    def getKarmaDeduction(self, client):
        #assert isinstance(client, Client)

        clientFacebookId = client.login_details.facebook_id
        query = { "facebookId" : clientFacebookId }
        try:
            item = self.karma_collection.find(query)
            if item is None:
                return 0

            return item.count()
        except Exception as e:
            raise ValueError(e)

    def pushKarmaDeduction(self, client):
        if client is None:
            return

        #assert isinstance(client, Client)

        clientFacebookId = client.login_details.facebook_id

        self.karma_collection.create_index([("facebookId", pymongo.ASCENDING),("date", pymongo.ASCENDING)])
        self.karma_collection.create_index([("date", pymongo.ASCENDING)], expireAfterSeconds=self.expiry_time_seconds)

        recordToInsert = {"facebookId" : clientFacebookId,
                          "date": datetime.utcnow() } # For TTL removing.

        logger.debug("Writing karma deduction to database for Facebook ID: [%s]" % (clientFacebookId))
        self.karma_collection.insert_one(recordToInsert)

    def incrementKarma(self, client):
        if client is None:
            return

        #assert isinstance(client, Client)
        clientFacebookId = client.login_details.facebook_id

        logger.debug("Incrementing karma for Facebook ID: %s" % clientFacebookId)
        record = self.karma_collection.find_one_and_delete({"facebookId": clientFacebookId}, sort=[("date", pymongo.ASCENDING)])
        if record is None:
            logger.debug("Failed to increment karma, could not find any records for Facebook ID: %s" % clientFacebookId)

    def listItems(self):
        for item in self.karma_collection.find():
            print item