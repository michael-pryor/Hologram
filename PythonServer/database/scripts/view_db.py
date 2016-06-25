import pymongo
from database.karma_leveled import KarmaLeveled

if __name__ == '__main__':
    mongoClient = pymongo.MongoClient("localhost", 27017)
    db = KarmaLeveled(mongoClient)
    db.listItems()