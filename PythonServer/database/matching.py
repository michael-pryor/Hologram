import logging
import pymongo
import time
from client import Client
from protocol_client import ClientTcp, ClientUdp
import uuid
import random
import pymongo.errors
import random
from byte_buffer import ByteBuffer
import pickle
from bson.binary import Binary
import struct
from blocking import Blocking
from datetime import datetime

logger = logging.getLogger(__name__)

class Matching(object):
    # We will search through 1000 people that match search criteria such as gender, both online and offline
    # until we give up on finding an online match (since e.g. we've been blocked or skipped by everybody).
    #
    # Then we will we will use the first offline person we found earlier, or will continue searching, but take
    # the first online or offline person we find.
    PRIORITISE_ONLINE_UP_TO = 1000

    # Expire matches after 1 week.
    # Technically this impacts online clients too, but unlikely a client will be online for an entire week.
    # This is aimed at getting rid of offline clients which are unfavourable i.e. noone accepts.
    EXPIRATION_TIME_SECONDS = 7 * 24 * 60 * 60

    def __init__(self, serverName, mongoClient, blockingDatabase, matchHistoryDatabase):
        assert isinstance(blockingDatabase, Blocking)
        assert isinstance(matchHistoryDatabase, Blocking)

        self.mongo_client = mongoClient
        self.match_collection = self.mongo_client.db.matcher_v2
        self.server_name = serverName

        self.blocking_database = blockingDatabase
        self.match_history_database = matchHistoryDatabase

        logger.info("Expiring waiting matches after %d seconds" % Matching.EXPIRATION_TIME_SECONDS)

    def pushBlock(self, blockerClient, blockedClient):
        self.blocking_database.pushBlock(blockerClient, blockedClient)

    def pushSkip(self, skipperClient, skippedClient):
        self.match_history_database.pushBlock(skipperClient, skippedClient)

    def didRecentlySkip(self, skipperClient, skippedClient):
        return not self.match_history_database.canMatch(skipperClient, skippedClient)

    def didBlock(self, blockerClient, blockedClient, checkBothSides=True):
        return not self.blocking_database.canMatch(blockerClient, blockedClient, checkBothSides=checkBothSides)

    def removeMatch(self, client):
        assert isinstance(client, Client)
        self.match_collection.remove({'_id': self.buildId(client.login_details)})

    def removeMatchById(self, theId):
        self.match_collection.remove({'_id': theId})

    # find a match which is fit enough for the specified client.
    def findMatch(self, sourceClient, buildClientFromDatabaseResultFunc):
        assert isinstance(sourceClient, Client)
        loginDetails = sourceClient.login_details

        # Note that age can be 0 here if user does not want to disclose via social. We should handle this case.

        # Gender can be 0 here if user does not want to disclose via social. We handle this by saying that users
        # not specifying gender can match people looking for either male, female or who do not care. We do not
        # specify a specific gender.
        matchWithGenderWanted = [3]
        if loginDetails.gender == 0:
            matchWithGenderWanted += [1, 2]
        else:
            matchWithGenderWanted.append(loginDetails.gender)

        # If a user has not specified what gender htey are interested in, then they can match anything.
        if loginDetails.interested_in == 0:
            loginDetails.interested_in = 3
        genderWanted = loginDetails.interested_in

        # If they don't care what gender they want, then don't include gender as part of the query.
        if genderWanted == 3:
            query = {}
        else:
            query = {'gender' : genderWanted}

        query.update({'server': self.server_name,
                      'gender_wanted' : {'$in' : matchWithGenderWanted},
                      # Age over complicates things for now, because we need age selection on GUI.
                      # If we get loads of users we can put this in.
                      #'age' : {'$gt': 0,
                      #         '$lt': loginDetails.age+40},
                      'location' :
                           {'$nearSphere' :
                                  {'$geometry' :
                                       {'type' : 'Point',
                                        'coordinates' : [loginDetails.longitude, loginDetails.latitude]
                                       }
                                  }
                           },
                      '_id': {'$ne': self.buildId(loginDetails)}
                    })

        try:
            cursor = self.match_collection.find(query)
        except Exception as e:
            raise ValueError(e)

        bestOfflineClient = None
        try:
            while True:
                for iteration in xrange(Matching.PRIORITISE_ONLINE_UP_TO):
                    dbResult = cursor.next()
                    client = buildClientFromDatabaseResultFunc(dbResult)
                    if client is None:
                        continue

                    isOffline = client.isSynthesizedOfflineClient()
                    if isOffline:
                        if bestOfflineClient is None:
                            bestOfflineClient = client
                    else:
                        return client

                # When we reach this point, we are prepared to tolerate an offline client.
                if bestOfflineClient is not None:
                    return bestOfflineClient
        except StopIteration:
            # When we reach this point, we have iterated over all clients in the DB,
            # and didn't find anyone online, and hadn't reached our toleration limit, such
            # that we wouldn't accept an offline client yet. Since we've reached the end,
            # return the best offline client that we found.
            if bestOfflineClient is not None:
                return bestOfflineClient

        return None

    def synthesizeClient(self, dataRecord, buildClientFunc):
        assert isinstance(dataRecord, dict)

        client = buildClientFunc()

        profilePicture = ByteBuffer()
        profilePictureString = dataRecord['profile_picture']
        assert isinstance(profilePictureString, basestring)
        profilePicture.buffer = bytearray(profilePictureString, encoding='latin1')
        profilePicture.used_size = len(profilePicture.buffer)
        profilePicture.memory_size = profilePicture.used_size

        client.login_details = Client.LoginDetails(str(dataRecord['unique_id']), str(dataRecord['persisted_unique_id']),
                                                   str(dataRecord['name']), str(dataRecord['short_name']), dataRecord['age'],
                                                   dataRecord['gender'], dataRecord['gender_wanted'], dataRecord['location'][0],
                                                   dataRecord['location'][1], str(dataRecord['card_text']), profilePicture, dataRecord['profile_picture_orientation'])

        client.remote_notification_payload = str(dataRecord['remote_notification_payload'])

        client.should_notify_on_match_accept = True
        client.udp_hash = client.login_details.unique_id

        return client



    # push a client into the waiting list, ready to be found by findMatch.
    def pushWaiting(self, client):
        assert isinstance(client, Client)

        loginDetails = client.login_details

        attempts = 0
        while attempts < 2:
            try:
                attempts += 1
                self.match_collection.create_index([("date", pymongo.ASCENDING)],
                                                   expireAfterSeconds=Matching.EXPIRATION_TIME_SECONDS)
                break
            except pymongo.errors.OperationFailure as e:
                logger.warn("Pymongo error: %s, dropping date index on matching collection" % e)
                self.match_collection.drop_index([("date", pymongo.ASCENDING)])

        self.match_collection.create_index([("server", pymongo.ASCENDING),
                                            ("gender", pymongo.ASCENDING),
                                            ("gender_wanted", pymongo.ASCENDING),
                                            ("age", pymongo.ASCENDING),
                                            ("location", pymongo.GEOSPHERE)])

        self.match_collection.create_index([("server", pymongo.ASCENDING),
                                            ("gender_wanted", pymongo.ASCENDING),
                                            ("age", pymongo.ASCENDING),
                                            ("location", pymongo.GEOSPHERE)])

        utcNow = datetime.utcnow()
        shouldNotify = client.should_notify_on_match_accept
        uniqueId = self.buildId(loginDetails)
        recordToInsert = {"_id" : uniqueId,
                          "server" : self.server_name,
                          "age" : loginDetails.age,
                          "gender": loginDetails.gender,
                          "location": [loginDetails.longitude, loginDetails.latitude],
                          "gender_wanted": loginDetails.interested_in,
                          "unique_id": loginDetails.unique_id,
                          "should_notify": shouldNotify,
                          "date": utcNow}

        if shouldNotify:
            buf = loginDetails.profile_picture
            assert isinstance(buf, ByteBuffer)
            encodedProfilePicture = buf.buffer[:buf.used_size].decode('latin-1')

            recordToInsert.update({'name' : loginDetails.name,
                                   'short_name' : loginDetails.short_name,
                                   'card_text' : loginDetails.card_text,
                                   'profile_picture_used_size' : loginDetails.profile_picture.used_size,
                                   'profile_picture' : encodedProfilePicture,
                                   'profile_picture_orientation' : loginDetails.profile_picture_orientation,
                                   'persisted_unique_id' : loginDetails.persisted_unique_id,
                                   'remote_notification_payload' : client.remote_notification_payload})

        self.match_collection.replace_one({"_id" : uniqueId}, recordToInsert, upsert=True)

    def buildId(self, loginDetails):
        assert isinstance(loginDetails, Client.LoginDetails)
        return loginDetails.persisted_unique_id

    def listItems(self):
        for item in self.match_collection.find():
            print item

if __name__ == '__main__':
    db = Matching("michael_governor", pymongo.MongoClient("localhost", 27017))
    db.match_collection.drop()
    exit(0)

    amountToPush = 1000
    amountToTest = 1000

    def getRandomClient():
        dummyClient = Client(ClientTcp(("localhost",0)), None, None, None)
        dummyClient.login_details = Client.LoginDetails(str(uuid.uuid4()), "Mike P", "Mike", random.randint(18,30), random.randint(1,2), random.randint(1,3), random.randint(0,180), random.randint(0,90))
        return dummyClient

    try:
        for n in range(0,amountToPush):
            db.pushWaiting(getRandomClient())
    finally:
        db.listItems()

    count = 0
    total = 0
    for n in range(0,amountToTest):
        testClient = getRandomClient()
        result = db.findMatch(testClient)
        total += result['executionStats']['totalKeysExamined']
        if result['executionStats']['nReturned'] == 0:
            print 'oh dear'

        print result
        count+=1

    av = float(total) / float(count)
    pkeys = av / float(amountToPush) * 100
    print "Average number of lookups: %.2f" % av
    print "Average %% of records looked at: %.2f" % pkeys

