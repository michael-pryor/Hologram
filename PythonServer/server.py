from twisted.internet.endpoints import TCP4ServerEndpoint
from twisted.internet import reactor, protocol
from twisted.internet.protocol import ClientFactory
from byte_buffer import ByteBuffer
from client import Client
from handshaking import UdpConnectionLinker
from protocol_client import ClientTcp, ClientUdp
from threading import RLock;
from twisted.internet.error import AlreadyCalled, AlreadyCancelled
from utility import getRemainingTimeOnAction

__author__ = 'pryormic'

import logging
from house import House

logger = logging.getLogger(__name__)

# Represents server in memory state.
# There will only be one instance of this object.
#
# ClientFactory encapsulates the TCP listening socket.
class Server(ClientFactory, protocol.DatagramProtocol):
    def __init__(self, reactor):
        # All connected clients.
        self.client_mappings_lock = RLock()

        # Storing
        self.clients_by_tcp_address = dict()
        self.clients_by_udp_hash = dict()
        self.clients_by_udp_address = dict()

        self.udp_connection_linker = UdpConnectionLinker(self.clients_by_udp_hash)

        self.clean_actions_by_udp_hash = dict()

        self.reactor = reactor
        self.house = House()

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


if __name__ == "__main__":
    logging.basicConfig(level = logging.DEBUG)

    host = ""
    port = 12340
    udpPort = 12341


    server = Server(reactor)

    # TCP server.
    endpoint = TCP4ServerEndpoint(reactor, 12340)
    endpoint.listen(server)

    reactor.listenUDP(udpPort, server)
    reactor.run()
