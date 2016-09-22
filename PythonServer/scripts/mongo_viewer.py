import pymongo
from pymongo.database import Database

__author__ = 'pryormic'


if __name__ == '__main__':
    mongoClient = pymongo.MongoClient("localhost", 27017)

    for item in mongoClient.db.matcher.find():
        try:
            del item['profile_picture']
        except KeyError:
            pass
        print item
        print