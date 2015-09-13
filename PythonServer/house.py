__author__ = 'pryormic'
from client import Client
from byte_buffer import ByteBuffer
from utility import htons, inet_addr
from threading import RLock
import logging
from database import Database

logger = logging.getLogger(__name__)

# A house has lots of rooms in it, each room has two participants in it (the video call).
class House:
    def __init__(self, database):
        assert isinstance(database, Database)

        # Contains links e.g.
        # Participant A -> Participant B
        # Participant B -> Participant A
        self.room_participant = dict()

        # Map from:
        # Unique key (stored in DB) -> Client
        self.waiting_clients_by_key = dict()

        # Client -> Unique key (stored in DB)
        self.waiting_keys_by_client = dict()

        self.abort_nat_punchthrough_packet = ByteBuffer()
        self.abort_nat_punchthrough_packet.addUnsignedInteger(Client.TcpOperationCodes.OP_NAT_PUNCHTHROUGH_CLIENT_DISCONNECT)

        self.house_lock = RLock()

        self.reset_send_speed_packet = ByteBuffer()
        self.reset_send_speed_packet.addUnsignedInteger(Client.TcpOperationCodes.OP_RESET_SEND_RATE)

        self.disconnected_temporary = ByteBuffer()
        self.disconnected_temporary.addUnsignedInteger(Client.TcpOperationCodes.OP_TEMP_DISCONNECT)

        self.disconnected_permanent = ByteBuffer()
        self.disconnected_permanent.addUnsignedInteger(Client.TcpOperationCodes.OP_PERM_DISCONNECT)

        self.disconnected_skip = ByteBuffer()
        self.disconnected_skip.addUnsignedInteger(Client.TcpOperationCodes.OP_SKIPPED_DISCONNECT)

        self.database = database

    def takeRoom(self, clientA, clientB):
        if clientA is clientB:
            return False

        self.house_lock.acquire()
        try:
            self._removeFromWaitingList(clientA)
            self._removeFromWaitingList(clientB)

            self.room_participant[clientA] = clientB
            self.room_participant[clientB] = clientA
        finally:
            self.house_lock.release()

        self.adviseNatPunchthrough(clientA, clientB)
        self.resetSendFrequency(clientA)
        self.resetSendFrequency(clientB)

        logger.info("New room set up between client [%s] and [%s]" % (clientA, clientB))
        return True

    def resetSendFrequency(self, client):
        assert isinstance(client, Client)
        client.tcp.sendByteBuffer(self.reset_send_speed_packet)


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
            # Don't want to match clients with disconnected clients, even if those clients are only temporarily disconnected.
            self._removeFromWaitingList(client)

            clientB = self.room_participant.get(client)
            if clientB is not None:
                # Possible that client reconnected before this socket disconnected, so do not clean up the new connection.
                realClient = self.room_participant.get(clientB)
        finally:
            self.house_lock.release()

        if realClient is not None and client is realClient:
            self.adviseAbortNatPunchthrough(clientB)
            clientB.tcp.sendByteBuffer(self.disconnected_temporary)
            logger.info("Session pause signaled to client [%s] because of client disconnect [%s]" % (clientB, client))

    def _removeFromWaitingList(self, client):
        self.house_lock.acquire()
        try:
            if client in self.waiting_keys_by_client:
                del self.waiting_keys_by_client[client]
                del self.waiting_clients_by_key[client.login_details.unique_id]

                self.database.removeMatch(client)
        finally:
            self.house_lock.release()


    # The session has been completely shutdown because a client has
    # permanently disconnected and we don't think they're coming back.
    def releaseRoom(self, client, notification = None):
        self.house_lock.acquire()
        try:
            self._removeFromWaitingList(client)

            clientB = self.room_participant.get(client)
            if clientB is not None:
                del self.room_participant[client]
                del self.room_participant[clientB]

                if notification is not None:
                    assert isinstance(notification, ByteBuffer)
                    clientB.tcp.sendByteBuffer(notification)

                self.attemptTakeRoom(clientB)
                logger.info("Permanent closure of session between client [%s] and [%s] due to disconnect of client [%s]" % (client, clientB, client))
        finally:
            self.house_lock.release()

    def attemptTakeRoom(self, client):
        def onFailure():
            if client not in self.waiting_keys_by_client:
                key = client.login_details.unique_id
                self.waiting_clients_by_key[key] = client
                self.waiting_keys_by_client[client] = key

                self.database.pushWaiting(client)

        self.house_lock.acquire()
        try:
            databaseResultMatch = self.database.findMatch(client)
            if databaseResultMatch is None:
                onFailure()
                return

            key = databaseResultMatch['_id']
            clientMatch = self.waiting_clients_by_key.get(key)
            if clientMatch is None:
                self.database.removeMatchById(key)
                logger.warn("Client in DB not found in waiting list, database inconsistency detected")
                onFailure()
                return

            self.takeRoom(client, clientMatch)

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
            pass
        else:
            # Send to client that we are matched with.
            clientMatch.udp.sendRawBuffer(packet)
