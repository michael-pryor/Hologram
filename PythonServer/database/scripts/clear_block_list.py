import pymongo
from database.blocking import Blocking

if __name__ == '__main__':
    mongoClient = pymongo.MongoClient("localhost", 27017)
    db = Blocking(mongoClient.db.blocked)
    db.block_collection.drop()

    matchDecisionDb = Blocking(mongoClient.db.match_decision)
    matchDecisionDb.block_collection.drop()