from twisted.internet.endpoints import TCP4ServerEndpoint
from twisted.internet import reactor, protocol, ssl
from twisted.internet.protocol import ClientFactory, ReconnectingClientFactory
from byte_buffer import ByteBuffer
from client import Client
from handshaking import UdpConnectionLinker
from protocol_client import ClientTcp, ClientUdp
from threading import RLock;
from twisted.internet.error import AlreadyCalled, AlreadyCancelled
from utility import getRemainingTimeOnAction, Throttle, parseLogLevel
from house import House
import logging
import argparse
import os
from stat_tracker import StatTracker
from analytics import Analytics
import pymongo
from database.matching import Matching
from database.blocking import Blocking
from database.karma_leveled import KarmaLeveled
from database.persisted_ids import PersistedIds
from payments import PaymentsEx

__author__ = 'pryormic'


logger = logging.getLogger(__name__)

# Represents server in memory state.
# There will only be one instance of this object.
#
# ClientFactory encapsulates the TCP listening socket.
class Governor(ClientFactory, protocol.DatagramProtocol):
    def __init__(self, reactor, matchingDatabase, blockingDatabase, matchDecisionDatabase, karmaDatabase, persistedIdsDatabase, governorName):
        # All connected clients.
        self.client_mappings_lock = RLock()

        # Storing
        self.clients_by_tcp_address = dict()
        self.clients_by_udp_hash = dict()
        self.clients_by_udp_address = dict()

        self.udp_connection_linker = UdpConnectionLinker(self.clients_by_udp_hash)

        self.clean_actions_by_udp_hash = dict()

        self.reactor = reactor
        self.house = House(matchingDatabase)

        # Track kilobytes per second averaged over last 30 seconds.
        self.kilobyte_per_second_tracker = StatTracker(1,30)

        self.governor_name = governorName
        self.blocking_database = blockingDatabase
        self.match_decision_database = matchDecisionDatabase
        self.karma_database = karmaDatabase
        self.payments_verifier = PaymentsEx(100)
        self.persisted_ids_verifier = persistedIdsDatabase

    # Higher = under more stress, handling more traffic, lower = handling less.
    def getLoad(self):
        self.kilobyte_per_second_tracker.soft_tick()
        return self.kilobyte_per_second_tracker.average_tick_rate

    def startedConnecting(self, connector):
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug('Started to connect.')

    def _lockClm(self):
        self.client_mappings_lock.acquire()

    def _unlockClm(self):
        self.client_mappings_lock.release()

    def _cleanupUdp(self, client):
        assert isinstance(client, Client)

        udpClient = client.udp
        try:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Cleaning up UDP client: [%s]" % udpClient)
            del self.clients_by_udp_address[udpClient.remote_address]
        except KeyError:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Attempt to cleanup UDP address [%s] failed, not yet connected via UDP" % udpClient)

        self.cleanupClientUdpHash(client)


    def cleanupClientUdpHash(self, client):
        self._lockClm()
        try:
            if client.udp_hash not in self.clients_by_udp_hash:
                return

            cleanAction = self.clean_actions_by_udp_hash.get(client.udp_hash)
            if cleanAction is None:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Scheduled new session expiry for client [%s] in [%s] seconds" % (client, UdpConnectionLinker.DELAY))
                cleanAction = self.reactor.callLater(UdpConnectionLinker.DELAY, self._doClientHashCleanup, client)

                self.clean_actions_by_udp_hash[client.udp_hash] = cleanAction
            else:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Reset expiry of [%s] seconds remaining for client [%s] to [%.2f] seconds" % (getRemainingTimeOnAction(cleanAction), client, UdpConnectionLinker.DELAY))
                try:
                    cleanAction.reset(self, UdpConnectionLinker.DELAY)
                except AlreadyCalled:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Failed to reset, timer already fired for client [%s]" % client)
                except AlreadyCancelled:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Failed to reset, action cancelled for client [%s], attempting fresh schedule" % client)
                    del self.clean_actions_by_udp_hash[client.udp_hash]
                    self.cleanupClientUdpHash(client)
        finally:
            self._unlockClm()

    def cancelCleanupClientUdpHash(self, client):
        self._lockClm()
        try:
            if client.udp_hash not in self.clients_by_udp_hash:
                return

            cleanAction = self.clean_actions_by_udp_hash.get(client.udp_hash)

            # Already cancelled
            if cleanAction is None:
                return

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Cancelling new session expiry for client [%s] in [%.2f] seconds" % (client, getRemainingTimeOnAction(cleanAction)))
            try:
                cleanAction.cancel()
            except (AlreadyCancelled, AlreadyCalled) as e:
                pass

            del self.clean_actions_by_udp_hash[client.udp_hash]
        finally:
            self._unlockClm()


    def _doClientHashCleanup(self, client):
        self._lockClm()
        try:
            udpHash = client.udp_hash
            if udpHash is not None:
                del self.clean_actions_by_udp_hash[client.udp_hash]

                existing = self.clients_by_udp_hash.get(udpHash)
                if existing is None:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("UDP hash [%s] for client [%s] not found in server" % (udpHash, client))
                else:
                    if existing is not client:
                        if logger.isEnabledFor(logging.DEBUG):
                            logger.debug("Hash has been reused, not cleaning up UDP hash (old: [%s], new: [%s], hash [%s])" % (existing, client, udpHash))
                    else:
                        if logger.isEnabledFor(logging.DEBUG):
                            logger.debug("Cleaning up UDP hash [%s] of client [%s]" % (udpHash, client))
                        del self.clients_by_udp_hash[udpHash]

                        # We need to make sure that client data is not left dangling without a UDP hash.
                        self.clientDisconnected(client)

                        # Completely release that room.
                        self.house.releaseRoom(client, self.house.disconnected_permanent)
        finally:
            self._unlockClm()

    def clientDisconnected(self, client):
        client.closeConnection()

        self._lockClm()
        try:
            origClient = self.clients_by_tcp_address.get(client.tcp.remote_address)
            if origClient is None:
                # Already disconnected.
                return

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Cleaning up TCP: %s" % origClient.tcp)

            del self.clients_by_tcp_address[origClient.tcp.remote_address]

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client has disconnected: %s" % origClient)

            # There is the possibility that client reconnected, creating new
            # Client object, but there was a delay in the original client
            # objects disconnection, so they appeared out of order.
            #
            # In this case, we don't want to remove the newly connected client.
            if origClient.udp is not None:
                if origClient is not client:
                    # Only need to cleanup UDP address if they are different.
                    if origClient.udp != client.udp:
                        if logger.isEnabledFor(logging.DEBUG):
                            logger.debug("Client has reconnected via UDP on a different interface, cleaning up old UDP connection. Old [%s] vs new [%s]" % (origClient.udp, client.udp))
                        self._cleanupUdp(origClient)
                    else:
                        if logger.isEnabledFor(logging.DEBUG):
                            logger.debug("Not cleaning up UDP address; as has been reused by reconnect [%s]" % client.udp)
                else:
                    # No reconnect concerns, cleanup the client normally.
                    self._cleanupUdp(origClient)
        finally:
            self._unlockClm()

    def buildProtocol(self, addr):
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug('TCP connection initiated with new client [%s]' % addr)

        tcpCon = ClientTcp(addr)
        client = Client(reactor, tcpCon, self.clientDisconnected, self.udp_connection_linker, self.house, self.blocking_database, self.match_decision_database, self.karma_database, self.payments_verifier, self.persisted_ids_verifier)

        self._lockClm()
        try:
            self.clients_by_tcp_address[tcpCon.remote_address] = client
        finally:
            self._unlockClm()

        return tcpCon

    def clientConnectionLost(self, connector, reason):
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug('Lost connection.  Reason:')

    def clientConnectionFailed(self, connector, reason):
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug('Connection failed. Reason:')

    def datagramReceived(self, data, remoteAddress):
        self.kilobyte_per_second_tracker.tick(float(len(data)) / 1024.0)

        self._lockClm()
        try:
            knownClient = self.clients_by_udp_address.get(remoteAddress)
        finally:
            self._unlockClm()

        if not knownClient:
            theBuffer = ByteBuffer.buildFromIterable(data)
            self.onUnknownData(theBuffer, remoteAddress)
        else:
            knownClient.handleUdpPacket(data)

    @Throttle(1)
    def _onMalformed(self, fromAddress):
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Malformed UDP data received from unknown client [%s], discarding" % unicode(fromAddress))

    def onUnknownData(self, data, remoteAddress):
        assert isinstance(data, ByteBuffer)

        op = data.getUnsignedInteger8()
        if op != Client.UdpOperationCodes.OP_UDP_HASH:
            self._onMalformed(remoteAddress)
            return

        theHash = data.getString()
        if theHash is None or len(theHash) == 0:
            # This can happen because of UDP ordering or client sending video frames before fully connected.
            self._onMalformed(remoteAddress)
            return

        registeredClient = self.udp_connection_linker.registerCompletion(theHash, ClientUdp(remoteAddress, self.transport.write))

        if registeredClient:
            self._lockClm()
            try:
                existingClient = self.clients_by_udp_hash.get(theHash)
                if existingClient is not None:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Cleaning up existing client before processing reconnect: %s" % existingClient)
                    registeredClient.consumeMetaState(existingClient)
                    self.clientDisconnected(existingClient)

                self.cancelCleanupClientUdpHash(registeredClient)
                self.clients_by_udp_hash[theHash] = registeredClient
                self.clients_by_udp_address[remoteAddress] = registeredClient
            finally:
                self._unlockClm()

            successPing = ByteBuffer()
            successPing.addUnsignedInteger8(Client.TcpOperationCodes.OP_ACCEPT_UDP)

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Sending fully connected ACK")
            registeredClient.tcp.sendByteBuffer(successPing)

            # Must be done AFTER success ack, to avoid race conditions on client side.
            registeredClient.connection_status = Client.ConnectionStatus.CONNECTED

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client successfully connected, sent success ack and registered with house")
        else:
            # This case is most commonly seen if user switches from 3G to wifi, UDP route changes to go via wifi but
            # TCP route stays unchanged, so we need to update on the fly.
            client = self.clients_by_udp_hash.get(theHash)
            if client is not None and client.connection_status == Client.ConnectionStatus.CONNECTED and client.udp is not None:
                self._lockClm()
                try:
                    newUdp = ClientUdp(remoteAddress, self.transport.write)
                    oldUdp = client.udp
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Client UDP routing has changed from [%s] to [%s]" % (oldUdp, newUdp))

                    try:
                        del self.clients_by_udp_address[oldUdp.remote_address]
                    except KeyError:
                        pass

                    self.clients_by_udp_address[remoteAddress] = client
                    client.udp = newUdp

                    self.house.readviseNatPunchthrough(client)
                finally:
                    self._unlockClm()


class CommanderConnection(ReconnectingClientFactory):
    maxDelay = 10
    initialDelay = 1
    factor=1.25
    jitter=0.25

    ping_frequency=5

    class RouterCodes:
        SUCCESS = 1
        FAILURE = 2

    def __init__(self, commanderHost, commanderPort, ourGovernorTcpPort, ourGovernorUdpPort, governor, analytics):
        assert isinstance(governor, Governor)

        self.governorPacket = ByteBuffer()
        passwordEnvVariable = os.environ['HOLOGRAM_PASSWORD']
        if len(passwordEnvVariable) == 0:
           raise RuntimeError('HOLOGRAM_PASSWORD env variable must be set')
        self.governorPacket.addString(passwordEnvVariable)
        self.governorPacket.addUnsignedInteger(ourGovernorTcpPort)
        self.governorPacket.addUnsignedInteger(ourGovernorUdpPort)

        self.governor = governor
        self.analytics = analytics
        self.isConnected = False
        self.scheduled_ping = None

    def buildProtocol(self, addr):
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug('TCP connection initiated with new client [%s]' % addr)
        self.tcp = ClientTcp(addr)
        self.tcp.parent = self

        return self.tcp

    def startedConnecting(self, connector):
        logger.info("Attempting to connect to commander...")

    def clientConnectionFailed(self, connector, reason):
        self.isConnected = False
        logger.warn("Failed to connect to commander, reason: [%s]" % reason.getErrorMessage())
        self.retry(connector)

    def doPing(self):
        if not self.isConnected:
            return

        load = self.governor.getLoad()

        # Tell commander how much load we are handling so that it can load balance.
        pingPacket = ByteBuffer()
        pingPacket.addUnsignedInteger(load)
        self.tcp.sendByteBuffer(pingPacket)
        self.schedulePing()

        # Tell Google analytics how much load we are handling
        if analytics is not None:
            analytics.pushEvent(load, "governor_load", "bandwidth", self.governor.governor_name)

    # Always have one, and only one, ping scheduled.
    def schedulePing(self):
        try:
            if self.scheduled_ping is not None:
                self.scheduled_ping.cancel()
        except (AlreadyCalled, AlreadyCancelled):
            pass

        self.scheduled_ping = self.governor.reactor.callLater(CommanderConnection.ping_frequency, self.doPing)

    def onConnectionMade(self):
        self.isConnected = True
        logger.info("Connection to commander made, sending governor information")
        self.resetDelay()
        self.tcp.sendByteBuffer(self.governorPacket)
        self.schedulePing()

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)
        logger.warn("Received a packet from the commander, size: %d" % packet.used_size)

    def clientConnectionLost(self, connector, reason):
        self.isConnected = False
        logger.warn("Connection with commander lost, reason [%s]" % reason.getErrorMessage())
        self.retry(connector)

if __name__ == "__main__":
    # This is what we actually need to code:
    # sub server connects to a central server to register its existence, it waits to be told what port it should bind to.
    # once told, it sets up the server (thats what this particular main method currently does).
    #
    # central server accepts TCP connection from client (iphone app), client sends logon information with details of what it is looking to get i.e. age/gender/location.
    # central server then looks in central server database table for a match, on the record will be the sub server which contains the match. Central server removes record from central server database to prevent duplicates.
    #
    # central server sends message back to client with details of sub server.
    # app connects to sub server via TCP and UDP and does all the house stuff we see in this python server code already. Except this house stuff will use the database.
    # Sub server removes record from sub server database table and begins session with two clients, keeping a record of that session in memory only.
    #
    # If central server couldn't find a match, central server will round robin (or some other criteria, but round robin is nice and simple) to a sub server.
    # Sub server sees in its sub server database table that it has no match, so adds the record to central server and sub server database tables,
    # waiting for a match to come along as described above.

    parser = argparse.ArgumentParser(description='Chat Server', argument_default=argparse.SUPPRESS)
    parser.add_argument('--tcp_port', help='Port to bind to via TCP')
    parser.add_argument('--udp_port', help='Port to bind to via UDP')
    parser.add_argument('--commander_host', help='Commander host to connect to, defaults to this host', default="")
    parser.add_argument('--commander_port', help='Commander port to connect to, defaults to 12240', default="12240")
    parser.add_argument('--governor_name', help='Name of this instance, to uniquely identify it in the database')
    parser.add_argument('--log_level', help="ERROR, WARN, INFO or DEBUG", default="INFO")
    args = parser.parse_args()

    logLevel = parseLogLevel(args.log_level)
    logging.basicConfig(level = logLevel, format = '%(asctime)-30s %(name)-20s %(levelname)-8s %(message)s')

    host = ""
    tcpPort = int(args.tcp_port)
    udpPort = int(args.udp_port)
    governorName = args.governor_name

    logger.info("GOVERNOR [%s] STARTED" % governorName)

    commanderHost = args.commander_host
    commanderPort = int(args.commander_port)

    mongoClient = pymongo.MongoClient("localhost", 27017)
    matchingDatabase = Matching(governorName, mongoClient)
    blockingDatabase = Blocking(mongoClient.db.blocked)
    matchDecisionDatabase = Blocking(mongoClient.db.match_decision, expiryTimeSeconds=60 * 60)
    karmaDatabase = KarmaLeveled(mongoClient)
    persistedIdsDatabase = PersistedIds(mongoClient)
    server = Governor(reactor, matchingDatabase, blockingDatabase, matchDecisionDatabase, karmaDatabase, persistedIdsDatabase, governorName)

    analytics =  None#Analytics(100, governorName)

    commanderConnection = CommanderConnection(commanderHost, commanderPort, tcpPort, udpPort, server, analytics)
    logger.info("Connecting to commander via TCP with address: [%s:%d]" % (commanderHost, commanderPort))
    reactor.connectSSL(commanderHost, commanderPort, commanderConnection, ssl.ClientContextFactory())

    # TCP server.
    endpoint = TCP4ServerEndpoint(reactor, tcpPort)
    endpoint.listen(server)

    # UDP server.
    reactor.listenUDP(udpPort, server)
    reactor.run()
