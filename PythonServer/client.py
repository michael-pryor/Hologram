import logging
from multiprocessing import Lock
from byte_buffer import ByteBuffer
from protocol_client import ClientTcp, ClientUdp

__author__ = 'pryormic'

logger = logging.getLogger(__name__)

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