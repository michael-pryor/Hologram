from twisted.internet.endpoints import TCP4ServerEndpoint
from twisted.internet import reactor, protocol
from twisted.internet.protocol import ClientFactory
from byte_buffer import ByteBuffer
from client import Client
from handshaking import UdpConnectionLinker
from protocol_client import ClientTcp, ClientUdp
from threading import RLock;

__author__ = 'pryormic'

import logging

logger = logging.getLogger(__name__)

# Represents server in memory state.
# There will only be one instance of this object.
#
# ClientFactory encapsulates the TCP listening socket.
class Server(ClientFactory, protocol.DatagramProtocol):
    def __init__(self):
        # All connected clients.
        self.client_mappings_lock = RLock()

        # Storing
        self.clientsByTcpAddress = dict()
        self.udp_connection_linker = UdpConnectionLinker()
        self.clientsByUdpAddress = dict()
        self.clientsByUdpHash = dict()
        self.udp_connection_linker.clientsByUdpHash = self.clientsByUdpHash

    def startedConnecting(self, connector):
        logger.info('Started to connect.')

    def _lockClm(self):
        self.client_mappings_lock.acquire()

    def _unlockClm(self):
        self.client_mappings_lock.release()

    def _cleanupUdp(self, udpClient):
        try:
            del self.clientsByUdpAddress[udpClient]
            logger.info("Cleaning up UDP address of client: %s" % udpClient)
        except KeyError:
            logger.debug("Attempt to cleanup UDP address failed, not yet connected via UDP")
            pass

    def clientDisconnected(self, client):
        self._lockClm()
        try:
            origClient = self.clientsByTcpAddress.get(client.tcp)

            # There is the possibility that client reconnected, creating new
            # Client object, but there was a delay in the original client
            # objects disconnection, so they appeared out of order.
            #
            # In this case, we don't want to remove the newly connected client.
            if origClient is not client:
                # Only need to cleanup UDP address if they are different.
                if origClient.udp != client.udp:
                    self._cleanupUdp(origClient.udp)
                else:
                    logger.debug("Not cleaning up UDP address; as has been reused by reconnect: %s" % client.udp)
            else:
                # No reconnect concerns, cleanup the client normally.
                logger.info("Client has disconnected normally")
                del self.clientsByTcpAddress[origClient]
                self._cleanupUdp(origClient.udp)

            logger.info("Client has disconnected")
        finally:
            self._unlockClm()

    def buildProtocol(self, addr):
        logger.info('TCP connection initiated with new client [%s]' % addr)

        tcpCon = ClientTcp(addr)
        client = Client(tcpCon, self.clientDisconnected, self.udp_connection_linker)

        self._lockClm()
        try:
            self.clientsByTcpAddress[tcpCon] = client
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
            knownClient = self.clientsByUdpAddress.get(remoteAddress)
        finally:
            self._unlockClm()

        if not knownClient:
            theBuffer = ByteBuffer.buildFromIterable(data)
            self.onUnknownData(theBuffer, remoteAddress)
        else:
            # FAST ECHO
            self.transport.write(data,knownClient.udp.remote_address)
            # END OF FAST ECHO
            #assert isinstance(knownClient, Client)
            #knownClient.handleUdpPacket(theBuffer)

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
                    self.clientsByUdpAddress[remoteAddress] = registeredClient
                    self.clientsByUdpHash[theHash] = registeredClient
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


    server = Server()

    # TCP server.
    endpoint = TCP4ServerEndpoint(reactor, 12340)
    endpoint.listen(server)

    reactor.listenUDP(udpPort, server)
    reactor.run()
