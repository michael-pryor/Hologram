__author__ = 'pryormic'
from client import Client
from byte_buffer import ByteBuffer
from utility import htons, inet_addr
from threading import RLock
import logging

logger = logging.getLogger(__name__)

# A house has lots of rooms in it, each room has two participants in it (the video call).
class House:
    def __init__(self):
        # Contains links e.g.
        # Participant A -> Participant B
        # Participant B -> Participant A
        self.room_participant = dict()

        # Participants who are not in a room yet, who are waiting.
        self.waiting_for_room = list()

        self.abort_nat_punchthrough_packet = ByteBuffer()
        self.abort_nat_punchthrough_packet.addUnsignedInteger(Client.TcpOperationCodes.OP_NAT_PUNCHTHROUGH_CLIENT_DISCONNECT)

        self.house_lock = RLock()

    def takeRoom(self, clientA, clientB):
        if clientA is clientB:
            return False

        self.house_lock.acquire()
        try:
            self.room_participant[clientA] = clientB
            self.room_participant[clientB] = clientA
        finally:
            self.house_lock.release()

        self.adviseNatPunchthrough(clientA, clientB)
        logger.info("New room set up between client [%s] and [%s]" % (clientA, clientB))
        return True

    def adviseNatPunchthrough(self, clientA, clientB):
        assert isinstance(clientA, Client)
        assert isinstance(clientB, Client)

        bufferClientA = ByteBuffer()
        bufferClientA.addUnsignedInteger(Client.TcpOperationCodes.OP_NAT_PUNCHTHROUGH_ADDRESS)
        bufferClientA.addUnsignedInteger(inet_addr(clientB.udp.remote_address[0]))
        bufferClientA.addUnsignedInteger(htons(clientB.udp.remote_address[1]))

        bufferClientB = ByteBuffer()
        bufferClientB.addUnsignedInteger(Client.TcpOperationCodes.OP_NAT_PUNCHTHROUGH_ADDRESS)
        bufferClientB.addUnsignedInteger(inet_addr(clientA.udp.remote_address[0]))
        bufferClientB.addUnsignedInteger(htons(clientA.udp.remote_address[1]))

        clientA.tcp.sendByteBuffer(bufferClientA)
        clientB.tcp.sendByteBuffer(bufferClientB)
        logger.info("NAT punchthrough introduction made between client [%s] and [%s]" % (clientA, clientB))

    def adviseAbortNatPunchthrough(self, client):
        assert isinstance(client, Client)
        client.tcp.sendByteBuffer(self.abort_nat_punchthrough_packet)

    # A client has disconnected (temporarily at this stage), so
    # tell the other client to stop sending data via NAT punchthrough.
    def pauseRoom(self, client):
        realClient = None

        self.house_lock.acquire()
        try:
            clientB = self.room_participant.get(client)
            if clientB is not None:
                # Possible that client reconnected before this socket disconnected, so do not clean up the new connection.
                realClient = self.room_participant.get(clientB)
        finally:
            self.house_lock.release()

        if realClient is not None and client is realClient:
            self.adviseAbortNatPunchthrough(clientB)
            logger.info("Session pause signaled to client [%s] because of client disconnect [%s]" % (clientB, client))

    # The session has been completely shutdown because a client has
    # permanently disconnected and we don't think they're coming back.
    def releaseRoom(self, client):
        self.house_lock.acquire()
        try:
            try:
                self.waiting_for_room.remove(client)
            except ValueError:
                pass

            clientB = self.room_participant.get(client)
            if clientB is not None:
                del self.room_participant[client]
                del self.room_participant[clientB]

                self.attemptTakeRoom(clientB)
                logger.info("Permanent closure of session between client [%s] and [%s] due to disconnect of client [%s]" % (client, clientB, client))
        finally:
            self.house_lock.release()

    def attemptTakeRoom(self, client):

        self.house_lock.acquire()
        try:
            failedRooms = list()
            while True:
                try:
                    clientMatch = self.waiting_for_room.pop(0)
                except IndexError:
                    # No more possible matches, this client needs to wait.
                    failedRooms.append(client)
                    clientMatch = None
                    break
                else:
                    # Try to take a room with the match, the match may be the same client though,
                    # in which case we skip.
                    if client is clientMatch:
                        continue

                    self.takeRoom(client, clientMatch)

            # Recreate the waiting list with failures.
            self.waiting_for_room = failedRooms + self.waiting_for_room

            # Return match if one found, or None if not.
            return clientMatch
        finally:
            self.house_lock.release()

    def handleUdpPacket(self, client, packet):
        self.house_lock.acquire()
        try:
            if client not in self.room_participant:
                clientMatch = self.attemptTakeRoom(client)
            else:
                clientMatch = self.room_participant[client]
                clientOld = self.room_participant[clientMatch]

                # A client has reconnected, and wants to use the old room.
                if clientOld is not client:
                    self.room_participant[client] = clientMatch
                    self.room_participant[clientMatch] = client

                    # NAT punchthrough won't be enabled on the new client and
                    # will probably be disabled on the old client.
                    self.adviseNatPunchthrough(client, clientMatch)
        finally:
            self.house_lock.release()

        if clientMatch is None:
            # Echo back.
            client.udp.sendRawBuffer(packet)
        else:
            # Send to client that we are matched with.
            clientMatch.udp.sendRawBuffer(packet)
