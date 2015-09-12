from twisted.internet.endpoints import TCP4ServerEndpoint
from twisted.internet import reactor, protocol
from twisted.internet.protocol import ClientFactory, ReconnectingClientFactory
from byte_buffer import ByteBuffer
from client import Client
from handshaking import UdpConnectionLinker
from protocol_client import ClientTcp, ClientUdp
from threading import RLock;
from twisted.internet.error import AlreadyCalled, AlreadyCancelled
from utility import getRemainingTimeOnAction
from house import House
import logging
import argparse
from database import Database

__author__ = 'pryormic'


logger = logging.getLogger(__name__)

# Represents server in memory state.
# There will only be one instance of this object.
#
# ClientFactory encapsulates the TCP listening socket.
class Governor(ClientFactory, protocol.DatagramProtocol):
    def __init__(self, reactor, database):
        # All connected clients.
        self.client_mappings_lock = RLock()

        # Storing
        self.clients_by_tcp_address = dict()
        self.clients_by_udp_hash = dict()
        self.clients_by_udp_address = dict()

        self.udp_connection_linker = UdpConnectionLinker(self.clients_by_udp_hash)

        self.clean_actions_by_udp_hash = dict()

        self.reactor = reactor
        self.house = House(database)

    def startedConnecting(self, connector):
        logger.info('Started to connect.')

    def _lockClm(self):
        self.client_mappings_lock.acquire()

    def _unlockClm(self):
        self.client_mappings_lock.release()

    def _cleanupUdp(self, client):
        assert isinstance(client, Client)

        udpClient = client.udp
        try:
            logger.info("Cleaning up UDP client: [%s]" % udpClient)
            del self.clients_by_udp_address[udpClient.remote_address]
        except KeyError:
            logger.debug("Attempt to cleanup UDP address [%s] failed, not yet connected via UDP" % udpClient)

        self.cleanupClientUdpHash(client)


    def cleanupClientUdpHash(self, client):
        self._lockClm()
        try:
            if client.udp_hash not in self.clients_by_udp_hash:
                return

            cleanAction = self.clean_actions_by_udp_hash.get(client.udp_hash)
            if cleanAction is None:
                logger.info("Scheduled new session expiry for client [%s] in [%s] seconds" % (client, UdpConnectionLinker.DELAY))
                cleanAction = self.reactor.callLater(UdpConnectionLinker.DELAY, self._doClientHashCleanup, client)
                self.clean_actions_by_udp_hash[client.udp_hash] = cleanAction
            else:
                logger.info("Reset expiry of [%s] seconds remaining for client [%s] to [%.2f] seconds" % (getRemainingTimeOnAction(cleanAction), client, UdpConnectionLinker.DELAY))
                try:
                    cleanAction.reset(self, UdpConnectionLinker.DELAY)
                except AlreadyCalled:
                    logger.info("Failed to reset, timer already fired for client [%s]" % client)
                except AlreadyCancelled:
                    logger.info("Failed to reset, action cancelled for client [%s], attempting fresh schedule" % client)
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

            logger.info("Cancelling new session expiry for client [%s] in [%.2f] seconds" % (client, getRemainingTimeOnAction(cleanAction)))
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
                    logger.warning("UDP hash [%s] for client [%s] not found in server" % (udpHash, client))
                else:
                    if existing is not client:
                        logger.info("Hash has been reused, not cleaning up UDP hash (old: [%s], new: [%s], hash [%s])" % (existing, client, udpHash))
                    else:
                        logger.info("Cleaning up UDP hash [%s] of client [%s]" % (udpHash, client))
                        del self.clients_by_udp_hash[udpHash]

                        # We need to make sure that client data is not left dangling without a UDP hash.
                        self.clientDisconnected(client)

                        # Completely release that room.
                        self.house.releaseRoom(client)
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

            # There is the possibility that client reconnected, creating new
            # Client object, but there was a delay in the original client
            # objects disconnection, so they appeared out of order.
            #
            # In this case, we don't want to remove the newly connected client.
            if origClient.udp is not None:
                if origClient is not client:
                    # Only need to cleanup UDP address if they are different.
                    if origClient.udp != client.udp:
                        logger.info("Client has reconnected via UDP on a different interface, cleaning up old UDP connection. Old [%s] vs new [%s]" % (origClient.udp, client.udp))
                        self._cleanupUdp(origClient)
                    else:
                        logger.info("Not cleaning up UDP address; as has been reused by reconnect [%s]" % client.udp)
                else:
                    # No reconnect concerns, cleanup the client normally.
                    self._cleanupUdp(origClient)

            logger.info("Cleaning up TCP: %s" % origClient.tcp)
            del self.clients_by_tcp_address[origClient.tcp.remote_address]
            logger.info("Client has disconnected: %s" % origClient)
        finally:
            self._unlockClm()

    def buildProtocol(self, addr):
        logger.info('TCP connection initiated with new client [%s]' % addr)

        tcpCon = ClientTcp(addr)
        client = Client(tcpCon, self.clientDisconnected, self.udp_connection_linker, self.house)

        self._lockClm()
        try:
            self.clients_by_tcp_address[tcpCon.remote_address] = client
        finally:
            self._unlockClm()

        return tcpCon

    def clientConnectionLost(self, connector, reason):
        logger.info('Lost connection.  Reason:')

    def clientConnectionFailed(self, connector, reason):
        logger.info('Connection failed. Reason:')

    def datagramReceived(self, data, remoteAddress):
        self._lockClm()
        try:
            #logger.info('UDP packet received with size %d from host [%s], port [%s]' % (len(data), remoteAddress[0], remoteAddress[1]))
            knownClient = self.clients_by_udp_address.get(remoteAddress)
        finally:
            self._unlockClm()

        if not knownClient:
            theBuffer = ByteBuffer.buildFromIterable(data)
            self.onUnknownData(theBuffer, remoteAddress)
        else:
            knownClient.handleUdpPacket(data)

    def onUnknownData(self, data, remoteAddress):
        assert isinstance(data, ByteBuffer)

        theHash = data.getString()
        if theHash is None or len(theHash) == 0:
            logger.warn("Malformed hash received in unknown UDP packet, discarding")
            return

        registeredClient = self.udp_connection_linker.registerCompletion(theHash, ClientUdp(remoteAddress, self.transport.write))

        if registeredClient:
            if registeredClient.connection_status == Client.ConnectionStatus.CONNECTED:
                self._lockClm()
                try:
                    existingClient = self.clients_by_udp_hash.get(theHash)
                    if existingClient is not None:
                        logger.info("Cleaning up existing client before processing reconnect: %s" % existingClient)
                        self.clientDisconnected(existingClient)

                    self.cancelCleanupClientUdpHash(registeredClient)
                    self.clients_by_udp_hash[theHash] = registeredClient
                    self.clients_by_udp_address[remoteAddress] = registeredClient
                finally:
                    self._unlockClm()

                successPing = ByteBuffer()
                successPing.addUnsignedInteger(Client.UdpOperationCodes.OP_ACCEPT_UDP)

                logger.info("Sending fully connected ACK")
                registeredClient.tcp.sendByteBuffer(successPing)

                logger.info("Client successfully connected, sent success ack")


class CommanderConnection(ReconnectingClientFactory):
    maxDelay = 10
    initialDelay = 1
    factor=1.25
    jitter=0.25

    class RouterCodes:
        SUCCESS = 1
        FAILURE = 2

    def __init__(self, commanderHost, commanderPort, ourGovernorTcpPort, ourGovernorUdpPort):
        self.governorPacket = ByteBuffer()
        self.governorPacket.addUnsignedInteger(ourGovernorTcpPort)
        self.governorPacket.addUnsignedInteger(ourGovernorUdpPort)

    def buildProtocol(self, addr):
        logger.info('TCP connection initiated with new client [%s]' % addr)
        self.tcp = ClientTcp(addr)
        self.tcp.parent = self

        return self.tcp

    def startedConnecting(self, connector):
        logger.info("Attempting to connect to commander...")

    def clientConnectionFailed(self, connector, reason):
        logger.warn("Failed to connect to commander, reason: [%s]" % reason.getErrorMessage())
        self.retry(connector)

    def onConnectionMade(self):
        logger.info("Connection to commander made, sending governor information")
        self.resetDelay()
        self.tcp.sendByteBuffer(self.governorPacket)

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)
        logger.warn("Received a packet from the commander, size: %d" % packet.used_size)

    def clientConnectionLost(self, connector, reason):
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

    logging.basicConfig(level = logging.DEBUG, format = '%(asctime)-30s %(name)-20s %(levelname)-8s %(message)s')
    parser = argparse.ArgumentParser(description='Chat Server', argument_default=argparse.SUPPRESS)
    parser.add_argument('--tcp_port', help='Port to bind to via TCP')
    parser.add_argument('--udp_port', help='Port to bind to via UDP')
    parser.add_argument('--commander_host', help='Commander host to connect to, defaults to this host', default="")
    parser.add_argument('--commander_port', help='Commander port to connect to, defaults to 12240', default="12240")
    parser.add_argument('--governor_name', help='Name of this instance, to uniquely identify it in the database', default="michael_governor")
    args = parser.parse_args()

    host = ""
    tcpPort = int(args.tcp_port)
    udpPort = int(args.udp_port)
    governorName = args.governor_name

    commanderHost = args.commander_host
    commanderPort = int(args.commander_port)

    commanderConnection = CommanderConnection(commanderHost, commanderPort, tcpPort, udpPort)
    logger.info("Connecting to commander via TCP with address: [%s:%d]" % (commanderHost, commanderPort))
    reactor.connectTCP(commanderHost, commanderPort, commanderConnection)

    database = Database(governorName, "localhost", 27017)

    server = Governor(reactor, database)

    # TCP server.
    endpoint = TCP4ServerEndpoint(reactor, tcpPort)
    endpoint.listen(server)

    # UDP server.
    reactor.listenUDP(udpPort, server)
    reactor.run()
