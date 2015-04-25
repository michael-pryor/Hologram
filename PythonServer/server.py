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
import uuid
from threading import Lock

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
    def __init__(self):
        super(UdpConnectionLinker, self).__init__()
        self.waiting_hashes = dict()

    def registerInterest(self, udpHash, waitingClient):
        obj = UdpConnectionLink(udpHash, waitingClient)
        if obj in self.waiting_hashes:
            logger.warn("Duplicate UDP hash detected [%s], not registering interest" % udpHash)
            return False

        self.waiting_hashes[obj] = obj
        logger.info("Interest registered in UDP hash [%s]" % udpHash)
        return True

    def generateHash(self):
        # Generate a truly unique hash.
        while True:
            newHash = str(uuid.uuid4())
            if newHash not in self.waiting_hashes:
                return newHash


    def registerInterestGenerated(self, waitingClient, newHash = None):
        while True:
            # it is possible for a race condition to occur where same hash generated at
            # similar time and attempted to be added. Allowing for failure here solves that problem.
            if newHash is None:
                newHash = self.generateHash()
            success = self.registerInterest(newHash, waitingClient)
            if success:
                return newHash

    def registerPrematureCompletion(self, udpHash, waitingClient):
        logger.info("UDP connection with hash [%s] was prematurely aborted" % udpHash)
        self.waiting_hashes.remove(UdpConnectionLink(udpHash, waitingClient))

    def registerCompletion(self, udpHash, clientUdp):
        try:
            hashObj = self.waiting_hashes[UdpConnectionLink(udpHash, None)]
            assert isinstance(hashObj, UdpConnectionLink)

            if hashObj.waiting_client.setUdp(clientUdp):
                del self.waiting_hashes[hashObj]

            logger.info("UDP connection with hash [%s] and connection details [%s] has been established" % (udpHash, unicode(clientUdp.remote_address)))
            return hashObj.waiting_client
        except KeyError:
            logger.warn("An invalid UDP hash was received from [%s], discarding" % unicode(clientUdp.remote_address))


# Representation of client from server's perspective.
class Client(object):
    class ConnectionStatus:
        WAITING_LOGON = 1
        WAITING_UDP = 2
        CONNECTED = 3

    class UdpOperationCodes:
        OP_REJECT_LOGON = 1
        OP_ACCEPT_LOGON = 2
        OP_ACCEPT_UDP = 3

    def __init__(self, tcp, onCloseFunc, udpConnectionLinker):
        super(Client, self).__init__()
        assert isinstance(tcp, ClientTcp)
        assert isinstance(udpConnectionLinker, UdpConnectionLinker)

        self.udp = None
        self.tcp = tcp
        self.tcp.parent = self
        self.connection_status = Client.ConnectionStatus.WAITING_LOGON
        self.on_close_func = onCloseFunc
        self.udp_connection_linker = udpConnectionLinker
        self.udp_hash = None
        self.udp_remote_address = None
        logger.info("New client connected, awaiting logon message")

        self.chunks = 0
        self.batch = 0

        self.client_lock = Lock()

    def setUdp(self, clientUdp):
        assert isinstance(clientUdp, ClientUdp)

        logger.info("UDP socket has connected: [%s]" % unicode(clientUdp.remote_address))
        self.udp = clientUdp;

        if self.udp is not None:
            self.connection_status = Client.ConnectionStatus.CONNECTED

            # don't need this anymore.
            self.udp_connection_linker = None

            logger.info("Client UDP stream activated, client is fully connected")
            return True
        else:
            return False

    def closeConnection(self):
        self.tcp.transport.loseConnection()
        self.on_close_func(self)

        if self.udp_hash is not None:
            self.udp_connection_linker.registerPrematureCompletion(self.udp_hash)

    def handleLogon(self, packet):
        assert isinstance(packet, ByteBuffer)
        versionNum = packet.getUnsignedInteger()
        loginName = packet.getString()

        # Reconnection attempt, UDP hash included in logon.
        if packet.used_size != packet.cursor_position:
            hashUdp = packet.getString()
            if hashUdp not in self.udp_connection_linker.clientsByUdpHash:
                return False, "Hash timed out, please reconnect fresh"

            # Update dict with new client object (old one is replaced).
            self.udp_connection_linker.clientsByUdpHash[hashUdp] = self

            # This indicates that a logon ACK should be sent via TCP.
            hashUdp = self.udp_connection_linker.registerInterestGenerated(self, hashUdp)
            logger.info("Reconnect accepted, hash: %s", hashUdp)
        else:
            hashUdp = self.udp_connection_linker.registerInterestGenerated(self)

        logger.info("Login processed with details, version number: [%d], login name: [%s], udp hash: [%s]", versionNum, loginName, hashUdp)
        return True, hashUdp

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)
        if self.connection_status == Client.ConnectionStatus.WAITING_LOGON:
            response = ByteBuffer()
            success, dataString = self.handleLogon(packet)
            if success:
                self.connection_status = Client.ConnectionStatus.WAITING_UDP
                logger.info("Logon accepted, waiting for UDP connection")

                response.addUnsignedInteger(Client.UdpOperationCodes.OP_ACCEPT_LOGON)
                response.addString(dataString) # the UDP hash code.
            else:
                logger.warn("Logon rejected, closing connection")
                response.addUnsignedInteger(Client.UdpOperationCodes.OP_REJECT_LOGON)
                response.addString("Reject reason: %s" % dataString)
                self.closeConnection()

            self.tcp.sendByteBuffer(response)

        elif self.connection_status == Client.ConnectionStatus.WAITING_UDP:
            logger.warn("TCP packet received while waiting for UDP connection to be established, dropping packet")
            pass
        elif self.connection_status == Client.ConnectionStatus.CONNECTED:
            self.onFriendlyPacketTcp(packet)
        else:
            logger.error("Client in unsupported connection state: %d" % self.parent.connection_status)
            self.closeConnection()

    def handleUdpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)
        if self.connection_status != Client.ConnectionStatus.CONNECTED:
            logger.warn("Client is not connected, discarding UDP packet")
            return

        self.onFriendlyPacketUdp(packet)

    def onFriendlyPacketTcp(self, packet):
        assert isinstance(packet, ByteBuffer)
        logger.info("Received a friendly TCP packet with length: %d" % packet.used_size)
        logger.info("Echoing back")
        self.tcp.sendByteBuffer(packet)

    def onFriendlyPacketUdp(self, packet):
        assert isinstance(packet, ByteBuffer)
        batchId = packet.getUnsignedInteger()
        chunkId = packet.getUnsignedInteger()

        if self.batch != batchId:
            logger.info("%d of %d received for batch %d, %.2f success" % (self.chunks, 96, self.batch, (float(self.chunks) / 96.0)))
            self.batch = batchId
            self.chunks = 0

        self.chunks += 1

        #logger.info("Received a friendly UDP packet, batch ID: %s, chunk ID: %s" % (batchId, chunkId))
        self.udp.sendByteBuffer(packet)

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

    def sendByteBuffer(self, byteBuffer):
        assert isinstance(byteBuffer, ByteBuffer)
        self.sendString(byteBuffer.convertToString())

    def __hash__(self):
        return hash(self.remote_address)

    def __eq__(self, other):
        assert isinstance(other, ClientTcp)
        return other.remote_address == self.remote_address

class ClientUdp(object):
    def __init__(self, remoteAddress, datagramSenderFunc):
        super(ClientUdp, self).__init__()
        self.remote_address = remoteAddress
        self.datagram_sender_func = datagramSenderFunc

    def sendByteBuffer(self, byteBuffer):
        assert isinstance(byteBuffer, ByteBuffer)
        strRepresentation = byteBuffer.convertToString()
        self.datagram_sender_func(strRepresentation, self.remote_address)

    def __hash__(self):
        return hash(self.remote_address)

    def __eq__(self, other):
        assert isinstance(other, ClientUdp)
        return other.remote_address == self.remote_address

# Represents server in memory state.
# There will only be one instance of this object.
#
# ClientFactory encapsulates the TCP listening socket.
class Server(ClientFactory, protocol.DatagramProtocol):
    def __init__(self):
        # All connected clients.
        self.clients = set()
        self.udp_connection_linker = UdpConnectionLinker()
        self.clientsByUdpAddress = dict()
        self.clientsByUdpHash = dict()
        self.udp_connection_linker.clientsByUdpHash = self.clientsByUdpHash

    def startedConnecting(self, connector):
        logger.info('Started to connect.')

    def clientDisconnected(self, client):
        self.clients.remove(client)
        del self.clientsByUdpAddress[client.udp]

    def buildProtocol(self, addr):
        logger.info('TCP connection initiated with new client [%s]' % addr)

        tcpCon = ClientTcp(addr)
        client = Client(tcpCon, self.clientDisconnected, self.udp_connection_linker)
        self.clients.add(client)
        return tcpCon

    def clientConnectionLost(self, connector, reason):
        logger.info('Lost connection.  Reason:')

    def clientConnectionFailed(self, connector, reason):
        logger.info('Connection failed. Reason:')

    def datagramReceived(self, data, remoteAddress):
        #logger.info('UDP packet received with size %d from host [%s], port [%s]' % (len(data), remoteAddress[0], remoteAddress[1]))
        knownClient = self.clientsByUdpAddress.get(remoteAddress)

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
                self.clientsByUdpAddress[remoteAddress] = registeredClient
                self.clientsByUdpHash[theHash] = registeredClient

                successPing = ByteBuffer()
                successPing.addUnsignedInteger(Client.UdpOperationCodes.OP_ACCEPT_UDP)

                logger.info("Sending fully connected ACK")
                registeredClient.tcp.sendByteBuffer(successPing)

                logger.info("Client successfully connected, sent success ack")
        else:
            # not a new client, possibly a client reconnecting.
            existingClient = self.clientsByUdpHash.get(theHash)
            if existingClient is not None:
                assert isinstance(existingClient, Client)
                assert isinstance(existingClient.udp, ClientUdp)

                existingClient.client_lock.acquire()
                try:
                    oldUdpRemoteAddress = existingClient.udp.remote_address
                    if oldUdpRemoteAddress != remoteAddress:
                        logger.info("Updating clients remote address from %s to %s" % (oldUdpRemoteAddress, remoteAddress))
                        del self.clientsByUdpAddress[oldUdpRemoteAddress]
                        self.clientsByUdpAddress[remoteAddress] = existingClient
                        existingClient.udp.remote_address = remoteAddress
                    else:
                        logger.info("Client reconnected with same address: %s" % remoteAddress)
                finally:
                    existingClient.client_lock.release()


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
