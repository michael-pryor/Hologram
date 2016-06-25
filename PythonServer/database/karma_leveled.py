import logging
logger = logging.getLogger(__name__)
from database.karma import Karma

class KarmaLeveled(object):
    # 1 hour.
    #
    # Each Karma deduction will take this amount of time to expire.
    # The first ban will last this long, thereafter bans exponentially increase.
    KARMA_BASE_EXPIRY_TIME_SECONDS = 60 * 60

    # We will start at x, and so assuming no expiration takes place:
    # Ban 1: banned for x seconds.
    # Ban 2: x^2
    # Ban 3: x^3
    # Ban 4: x^4
    MAX_EXPONENTIAL_INCREASES = 3

    # Karma ratings are from between 0 to 5.
    KARMA_MAXIMUM = 5

    def __init__(self, mongoClient):
        self.karma = Karma(mongoClient.db.karma, KarmaLeveled.KARMA_BASE_EXPIRY_TIME_SECONDS)

        # Most severe ban is first in the list (element 0).
        self.bans = []
        for n in range(KarmaLeveled.MAX_EXPONENTIAL_INCREASES, 0, -1):
            expirationTime = KarmaLeveled.KARMA_BASE_EXPIRY_TIME_SECONDS * n
            collectionName = "ban_%d" % n
            logger.info("MongoDB collection [%s] has expiration of %d seconds" % (collectionName, expirationTime))
            self.bans.append(Karma(getattr(mongoClient.db,collectionName), expiryTimeSeconds=expirationTime))

    def listItems(self):
        print "Karma: "
        self.karma.listItems()

        print
        print "Bans:"
        for item, n in zip(self.bans, range(0,len(self.bans))):
            print "BAN_%d" % n
            item.listItems()
            print

    def dropCollections(self):
        self.karma.karma_collection.drop()

        for ban in self.bans:
            ban.karma_collection.drop()

    def getKarma(self, client):
        #assert isinstance(client, Client)

        karmaDeduction = self.karma.getKarmaDeduction(client)
        maxKarma = KarmaLeveled.KARMA_MAXIMUM
        karma = maxKarma - karmaDeduction

        if karma > KarmaLeveled.KARMA_MAXIMUM:
            karma = KarmaLeveled.KARMA_MAXIMUM
        elif karma < 0:
            karma = 0

        return karma

    # Return true if client has been banned.
    def deductKarma(self, client, karmaOverride=None):
        if client is None:
            return False

        if karmaOverride is None:
            currentKarma = self.getKarma(client)
        else:
            currentKarma = karmaOverride

        if currentKarma <= 0:
            return False

        self.karma.pushKarmaDeduction(client)
        if currentKarma - 1 > 0:
            return False

        for ban in self.bans:
            assert isinstance(ban, Karma)
            ban.pushKarmaDeduction(client)

        return True

    def getBanTime(self, client):
        for banTimeMultiplier, karmaTracker in zip(range(KarmaLeveled.MAX_EXPONENTIAL_INCREASES, 0, -1), self.bans):
            assert isinstance(karmaTracker, Karma)

            banEntries, expirationTime = karmaTracker.getKarmaDeductionAndExpirationTime(client)
            if banEntries >= banTimeMultiplier:
                return expirationTime

        return None

    def incrementKarma(self, client):
        if client is None:
            return

        self.karma.incrementKarma(client)