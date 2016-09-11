import uuid
import logging
from client import Client

__author__ = 'pryormic'

logger = logging.getLogger(__name__)

class UdpConnectionLink(object):
    def __init__(self, udpHash, waitingClient):
        super(UdpConnectionLink, self).__init__()
        if waitingClient is not None:
            assert isinstance(waitingClient, Client)
        self.udp_hash = udpHash
        self.waiting_client = waitingClient
        self.registered_addresses = set()

    def __hash__(self):
        return hash(self.udp_hash)

    def __eq__(self, other):
        if isinstance(other, UdpConnectionLink):
            return self.udp_hash == other.udp_hash
        elif isinstance(other, basestring):
            return self.udp_hash == other
        else:
            return False


class UdpConnectionLinker(object):
    DELAY = 20

    def __init__(self, clientsByUdpHash):
        super(UdpConnectionLinker, self).__init__()
        self.waiting_hashes = dict()
        self.clients_by_udp_hash = clientsByUdpHash


    def registerInterest(self, udpHash, waitingClient):
        obj = UdpConnectionLink(udpHash, waitingClient)
        if obj in self.waiting_hashes:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Duplicate UDP hash detected [%s], not registering interest" % udpHash)
            return False

        self.waiting_hashes[obj] = obj
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Interest registered in UDP hash [%s]" % udpHash)
        return True

    def generateHash(self):
        # Generate a truly unique hash.
        while True:
            newHash = str(uuid.uuid4())
            if newHash not in self.waiting_hashes:
                return newHash

            # Incase we end up with lots of spinning.
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Hash clash found with hash [%s], generating new hash" % newHash)


    def registerInterestGenerated(self, waitingClient, newHash = None):
        provided = newHash is not None

        while True:
            # it is possible for a race condition to occur where same hash generated at
            # similar time and attempted to be added. Allowing for failure here solves that problem.
            if newHash is None:
                newHash = self.generateHash()
            success = self.registerInterest(newHash, waitingClient)
            if success or provided:
                return newHash
            else:
                newHash = None

    def registerPrematureCompletion(self, udpHash, waitingClient):
        try:
            del self.waiting_hashes[UdpConnectionLink(udpHash, waitingClient)]
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("UDP connection with hash [%s] was prematurely aborted" % udpHash)
        except KeyError:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("UDP hash not found in waiting hashes, no need to remove [%s]" % udpHash)


    def registerCompletion(self, udpHash, clientUdp):
        try:
            hashObj = self.waiting_hashes[UdpConnectionLink(udpHash, None)]
            assert isinstance(hashObj, UdpConnectionLink)

            hashObj.waiting_client.setUdp(clientUdp)
            del self.waiting_hashes[hashObj]

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("UDP connection with hash [%s] and details [%s] has been established" % (udpHash, unicode(clientUdp)))
            return hashObj.waiting_client
        except KeyError:
            pass
            # This happens when if a client thinks it is connected but is not and spams us with data.
