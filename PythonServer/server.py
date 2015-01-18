__author__ = 'pryormic'

import logging
import time
import threading

logger = logging.getLogger(__name__)

from twisted.internet.protocol import Protocol, ClientFactory
import twisted
from twisted.internet.endpoints import TCP4ServerEndpoint
from twisted.internet import reactor, task, protocol, defer

from twisted.protocols.basic import IntNStringReceiver

import struct
from utility import DataConstants

from byte_buffer import ByteBuffer

class UdpConnectionLink(object):
    def __init__(self, udpHash, waitingClient):
        super(UdpConnectionLink, self).__init__()
        assert isinstance(waitingClient, Client)
        self.udp_hash = udpHash
        self.waiting_client = waitingClient

    def __hash__(self):
        return hash(self.udp_hash)

    def __eq__(self, other):
        if not isinstance(other, UdpConnectionLink):
            return False

        return self.udp_hash == other.udp_hash


class UdpConnectionLinker(object):
    def __init__(self):
        super(UdpConnectionLinker, self).__init__()
        self.waiting_hashes = set()

    def registerInterest(self, udpHash, waitingClient):
        obj = UdpConnectionLink(udpHash, waitingClient)
        if obj in self.waiting_hashes:
            logger.warn("Duplicate UDP hash detected [%s], not registering interest" % udpHash)
            return False

        self.waiting_hashes.add(obj)
        logger.info("Interest registered in UDP hash [%s]" % udpHash)
        return True

    def registerPrematureCompletion(self, udpHash, waitingClient):
        logger.info("UDP connection with hash [%s] was prematurely aborted" % udpHash)
        self.waiting_hashes.remove(UdpConnectionLink(udpHash, waitingClient))

    def registerCompletion(self, udpHash, udpClient):
        logger.info("UDP connection with hash [%s] has been established" % udpHash)
        hashObj = self.waiting_hashes.remove(UdpConnectionLink(udpHash, None))
        assert isinstance(hashObj, UdpConnectionLink)

        hashObj.waiting_client.setUdp(udpClient)

# Representation of client from server's perspective.
class Client(object):
    class ConnectionStatus:
        WAITING_LOGON = 1
        WAITING_UDP = 2
        CONNECTED = 3

    def __init__(self, tcp, onCloseFunc, udpConnectionLinker):
        super(Client, self).__init__()
        assert isinstance(tcp, ClientTcp)
        assert isinstance(udpConnectionLinker, UdpConnectionLinker)

        self.tcp = tcp
        self.tcp.parent = self
        self.connection_status = ConnectionStatus.WAITING_LOGON
        self.on_close_func = onCloseFunc
        self.udp_connection_linker = udpConnectionLinker
        self.udp_hash = None
        logger.info("New client connected, awaiting logon message")

    def setUdp(self, udp):
        assert isinstance(udp, ClientUdp)
        self.udp = udp
        self.udp.parent = self
        self.connection_status = ConnectionStatus.CONNECTED

        # don't need this anymore.
        self.udp_connection_linker = None

        logger.info("Client UDP stream detected, client is fully connected")

    def closeConnection(self):
        self.tcp.transport.loseConnection()
        self.on_close_func(self)

        if self.udp_hash is not None:
            self.udp_connection_linker.registerPrematureCompletion(self.udp_hash)

    def handleLogon(self, packet):
        assert isinstance(packet, ByteBuffer)
        versionNum = byteBuffer.getUnsignedInteger()
        loginName = byteBuffer.getString()
        self.udp_hash = byteBuffer.getString()
        if not self.udp_connection_linker.registerInterest(self.udp_hash, self):
            # there is a very small chance of this, but we should handle it anyways.
            logger.warn("Duplicate udp hash detected, rejecting login")
            self.udp_hash = None
            return False

        logger.info("Login processed with details, version number: [%d], login name: [%s], udp hash: [%s]", verisonNum, loginName, self.udp_hash)
        return True

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)
        if self.connection_status == ConnectionStatus.WAITING_LOGON:
            if self.handleLogon(packet):
                self.connection_status = ConnectionStatus.WAITING_UDP
                logger.info("Logon accepted, waiting for UDP connection")
            else:
                logger.warn("Logon rejected, closing connection")
                self.closeConnection()
        elif self.connection_status == ConnectionStatus.WAITING_UDP:
            logger.warn("TCP packet received while waiting for UDP connection to be established, dropping")
            pass
        elif self.connection_status == ConnectionStatus.CONNECTED:
            self.sendString(data);
        else:
            logger.error("Client in unsupported connection state: %d" % self.parent.connection_status)
            self.closeConnection()


# UDP connection of client.
def ClientUdp(object):
    def __init__(self, connectionDetails):
        super(ClientUdp, self).__init__()

# TCP connection of client.
# Expects incoming packets to be prefixed with size of subsequent data.
# Prefixes data sent with size of subsequent data.
class ClientTcp(IntNStringReceiver):
    # Little endian unsigned long.
    structFormat = DataConstants.ULONG_FORMAT

    MAX_LENGTH = 100000000
    prefixLength = struct.calcsize(structFormat)

    def __init__(self, remoteAddress):
        #super(ClientTcp, self).__init__()
        assert remoteAddress is not None
        self.remote_address = remoteAddress;
        self.parent = None

    def connectionMade(self):
        logger.info("Connection made to client")

    def stringReceived(self, data):
        logger.info("Client received TCP packet, length: %d" % (len(data)))
        byteBuffer = ByteBuffer.buildFromIterable(data)
        self.parent.handleTcpPacket(byteBuffer)

    def __hash__(self):
        return hash(self.remote_address)

    def __eq__(self, other):
        assert isinstance(other, ClientTcp)
        return other.remote_address == self.remote_address

# Represents server in memory state.
# There will only be one instance of this object.
#
# ClientFactory encapsulates the TCP listening socket.
class Server(ClientFactory):
    def __init__(self):
        # All connected clients.
        self.clients = set()

    def startedConnecting(self, connector):
        logger.info('Started to connect.')

    def clientDisconnected(self, client):
        self.clients.remove(client)

    def buildProtocol(self, addr):

        logger.info('Connected.')

        tcpCon = ClientTcp(addr)
        client = Client(tcpCon, self.clientDisconnected)
        self.clients.add(client)
        return tcpCon

    def clientConnectionLost(self, connector, reason):
        logger.info('Lost connection.  Reason:')

    def clientConnectionFailed(self, connector, reason):
        logger.info('Connection failed. Reason:')


if __name__ == "__main__":
    logging.basicConfig(level = logging.DEBUG)

    host = ""
    port = 12340

    endpoint = TCP4ServerEndpoint(reactor, 12340)
    endpoint.listen(Server())
    reactor.run()