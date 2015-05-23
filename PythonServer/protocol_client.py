import struct
import logging
from twisted.protocols.basic import IntNStringReceiver
from byte_buffer import ByteBuffer
from utility import DataConstants

__author__ = 'pryormic'

logger = logging.getLogger(__name__)

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
        self.remote_address = remoteAddress
        self.parent = None

    def connectionMade(self):
        logger.info("Connection made to client")

    def connectionLost(self, reason):
        logger.info("TCP connection lost with: [%s]", self);

    def stringReceived(self, data):
        logger.info("Client received TCP packet, length: %d, from: [%s]" % (len(data), self))
        byteBuffer = ByteBuffer.buildFromIterable(data)
        self.parent.handleTcpPacket(byteBuffer)

    def sendByteBuffer(self, byteBuffer):
        assert isinstance(byteBuffer, ByteBuffer)
        self.sendString(byteBuffer.convertToString())

    def formatAddress(self, addressTuple):
        return "%s:%s" % (addressTuple.host, addressTuple.port)

    def __hash__(self):
        return hash(self.remote_address)

    def __eq__(self, other):
        assert isinstance(other, ClientTcp)
        return other.remote_address == self.remote_address

    def __str__(self):
        return "{ClientTCP: [%s]}" % self.formatAddress(self.remote_address)

# UDP interactions with client.
class ClientUdp(object):
    def __init__(self, remoteAddress, datagramSenderFunc):
        super(ClientUdp, self).__init__()
        self.remote_address = remoteAddress
        self.datagram_sender_func = datagramSenderFunc

    def sendByteBuffer(self, byteBuffer):
        assert isinstance(byteBuffer, ByteBuffer)
        strRepresentation = byteBuffer.convertToString()
        self.datagram_sender_func(strRepresentation, self.remote_address)

    def formatAddress(self, address):
        return "%s:%s" % address

    def __hash__(self):
        return hash(self.remote_address)

    def __eq__(self, other):
        assert isinstance(other, ClientUdp)
        return other.remote_address == self.remote_address

    def __str__(self):
        return "{ClientUDP: [%s]}" % self.formatAddress(self.remote_address)