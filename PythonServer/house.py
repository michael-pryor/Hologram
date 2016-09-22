__author__ = 'pryormic'
from client import Client
from byte_buffer import ByteBuffer
from threading import RLock
import logging
from database.matching import Matching
from utility import getRemainingTimeOnAction, getEpoch
from geography import distanceBetweenPointsKm
import math
from database.karma_leveled import KarmaLeveled
from handshaking import UdpConnectionLinker
import pickle

logger = logging.getLogger(__name__)

# A house has lots of rooms in it, each room has two participants in it (the video call).
class House:
    def __init__(self, matchingDatabase, udpConnectionLinker, buildOfflineClientFunc):
        assert isinstance(matchingDatabase, Matching)
        assert isinstance(udpConnectionLinker, UdpConnectionLinker)

        # When clients are offline, and matched with somebody, we need to add
        # them to the clients by UDP hash map, which is contained within this object.
        self.udp_connection_linker = udpConnectionLinker

        # Function which (with no parameters) can build a client for matching.
        self.build_offline_client_func = buildOfflineClientFunc

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

        self.disconnected_temporary = ByteBuffer()
        self.disconnected_temporary.addUnsignedInteger(Client.TcpOperationCodes.OP_TEMP_DISCONNECT)

        self.disconnected_permanent = ByteBuffer()
        self.disconnected_permanent.addUnsignedInteger(Client.TcpOperationCodes.OP_PERM_DISCONNECT)

        self.disconnected_skip = ByteBuffer()
        self.disconnected_skip.addUnsignedInteger(Client.TcpOperationCodes.OP_SKIPPED_DISCONNECT)

        self.matchingDatabase = matchingDatabase

    def takeRoom(self, clientA, clientB):
        self.house_lock.acquire()
        try:
            self._removeFromWaitingList(clientA)
            self._removeFromWaitingList(clientB)

            self.room_participant[clientA] = clientB
            self.room_participant[clientB] = clientA

            clientA.onSuccessfulMatch(clientB)
            clientB.onSuccessfulMatch(clientA)
        finally:
            self.house_lock.release()

        self.adviseMatchDetails(clientA, clientB)

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("New room set up between client [%s] and [%s]" % (clientA, clientB))

    # Return false if we should skip this; the acceptance will never complete.
    def onAcceptConversation(self, sourceClient):
        self.house_lock.acquire()
        try:
            sourceClient.approved_match = True
            if sourceClient.state != Client.State.ACCEPTING_MATCH:
                # We shouldn't skip, even though this means we can't ever match with this particular client.
                # This happens close to the end of the timeout, when client accepts but has already timed out.
                # State does not need correcting in this case.
                return True
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client [%s] has accepted the conversation" % sourceClient)

            clientB = self.room_participant.get(sourceClient)
            if clientB is None:
                return False

            # Only advise when both clients have accepted.
            if clientB.state != Client.State.ACCEPTING_MATCH:
                return False

            if not clientB.approved_match:
                # ***** Here we would do the notify.
                clientB.trySendRemoteNotification(sourceClient)
                return True

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Both client [%s] and client [%s] have accepted the conversation, starting conversation" % (sourceClient, clientB))

            logger.info("Client %s and %s have started a conversation", sourceClient.login_details, clientB.login_details)

            sourceClient.transitionState(Client.State.ACCEPTING_MATCH, Client.State.MATCHED)
            clientB.transitionState(Client.State.ACCEPTING_MATCH, Client.State.MATCHED)

            self.adviseNatPunchthrough(sourceClient, clientB)
            return True
        finally:
            self.house_lock.release()

    def getDistance(self, clientA, clientB):
        assert isinstance(clientA, Client)
        assert isinstance(clientB, Client)

        trueDistance = distanceBetweenPointsKm(clientA.login_details.longitude,
                                               clientA.login_details.latitude,
                                               clientB.login_details.longitude,
                                               clientB.login_details.latitude)

        roundedDistance = math.ceil(trueDistance)
        return int(roundedDistance)

    def mutualAdvise(self, clientA, clientB, adviseFunc):
        adviseFunc(clientA, clientB)
        adviseFunc(clientB, clientA)

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("NAT punchthrough introduction made between client [%s] and [%s]" % (clientA, clientB))

    def adviseNatPunchthrough(self, clientA, clientB):
        self.mutualAdvise(clientA, clientB, Client.adviseNatPunchthrough)

    # reconnectingClient is true if one of the clients reconnected, and that's why it was resent match details.
    def adviseMatchDetails(self, clientA, clientB, reconnectingClient = False):
        distance = self.getDistance(clientA, clientB)
        self.mutualAdvise(clientA, clientB, lambda x,y: Client.adviseMatchDetails(x, y, distance, reconnectingClient))

        logger.info("Client %s and %s have swapped cards", clientA.login_details, clientB.login_details)
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Shared profiles between client [%s] and [%s], distance between them [%.2fkm]" % (clientB, clientA, distance))

    def readviseNatPunchthrough(self, client):
        self.house_lock.acquire()
        try:
            clientB = self.room_participant.get(client)
            if clientB is not None:
                self.adviseNatPunchthrough(client, clientB)
        finally:
            self.house_lock.release()

    def adviseAbortNatPunchthrough(self, client):
        assert isinstance(client, Client)
        if client.tcp is not None:
            client.tcp.sendByteBuffer(self.abort_nat_punchthrough_packet)
        else:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Not sending abort NAT punchthrough message to offline client: [%s]" % client)

    # A client has disconnected (temporarily at this stage), so
    # tell the other client to stop sending data via NAT punchthrough.
    def pauseRoom(self, client):
        realClient = None

        self.house_lock.acquire()
        try:
            # Don't want to match clients with disconnected clients, even if those clients are only temporarily disconnected.
            self._removeFromWaitingList(client, removeOfflineFromDatabase=False)

            clientB = self.room_participant.get(client)
            if clientB is not None:
                # Possible that client reconnected before this socket disconnected, so do not clean up the new connection.
                realClient = self.room_participant.get(clientB)
        finally:
            self.house_lock.release()

        if realClient is not None and client is realClient:
            self.adviseAbortNatPunchthrough(clientB)
            if clientB.tcp is not None:
                clientB.tcp.sendByteBuffer(self.disconnected_temporary)

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Session pause signaled to client [%s] because of client disconnect [%s]" % (clientB, client))

    def _removeFromWaitingList(self, client, removeOfflineFromDatabase=True):
        self.house_lock.acquire()
        try:
            if client in self.waiting_keys_by_client:
                del self.waiting_keys_by_client[client]
                del self.waiting_clients_by_key[client.login_details.unique_id]

                if not client.should_notify_on_match_accept or removeOfflineFromDatabase:
                    self.matchingDatabase.removeMatch(client)
            else:
                if removeOfflineFromDatabase:
                    self.matchingDatabase.removeMatch(client)
        finally:
            self.house_lock.release()

    # The session has been completely shutdown because a client has
    # permanently disconnected and we don't think they're coming back.
    def releaseRoom(self, client, notification = None):
        self.house_lock.acquire()
        try:
            self._removeFromWaitingList(client, removeOfflineFromDatabase=False)

            # ***** Here if notify enabled upsert on the DB record, indicating that should be notified.
            # Has to be a parameter indicating whether we shoudl do this. For example we shouldn't do on skip.

            clientB = self.room_participant.get(client)
            if clientB is None:
                return

            del self.room_participant[client]
            del self.room_participant[clientB]

            self.mutualAdvise(client, clientB, Client.onRoomClosure)

            self.adviseAbortNatPunchthrough(clientB)
            if client.isConnectedTcp():
                self.adviseAbortNatPunchthrough(client)

            if notification is not None:
                assert isinstance(notification, ByteBuffer)
                if clientB.tcp is not None:
                    clientB.tcp.sendByteBuffer(notification)

            clientB.setToWaitForRatingOfPreviousConversation(client)

            # If the client is an offline client and wants to be notified, then
            # we need to put it back into the waiting list.
            if clientB.connection_status != Client.ConnectionStatus.CONNECTED and clientB.should_notify_on_match_accept:
                clientB.transitionState(None, Client.State.MATCHING)
                self.matchingDatabase.pushWaiting(clientB)

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Permanent closure of session between client [%s] and [%s] due to client [%s] leaving the room" % (client, clientB, client))

            # Return the other client.
            return clientB
        finally:
            self.house_lock.release()

    def enableRemoteNotification(self, client):
        assert isinstance(client, Client)
        self.house_lock.acquire()
        try:
            if client.state != Client.State.MATCHING:
                return

            client.should_notify_on_match_accept = True
            self.matchingDatabase.pushWaiting(client)
        finally:
            self.house_lock.release()

    def attemptTakeRoom(self, client):
        def onFailure():
            if client not in self.waiting_keys_by_client:
                key = client.login_details.unique_id
                self.waiting_clients_by_key[key] = client
                self.waiting_keys_by_client[client] = key

                self.matchingDatabase.pushWaiting(client)

        # A client which is not connected should never be able to take a room.
        # This covers the edge case of a temporarily disconnected session where the connected party
        # skips, this triggers an attemptTakeRoom call on the disconnected party.
        if client.connection_status != Client.ConnectionStatus.CONNECTED:
            return

        client.state = Client.State.MATCHING

        self.house_lock.acquire()
        try:
            # Can't take more than one room at a time.
            if client in self.room_participant or client.waiting_for_rating_task is not None:
                return

            # Each client runs one query initially and then repeats
            # every two seconds.
            doQuery = client.house_match_timer is None or getEpoch() - client.house_match_timer > 2

            if doQuery:
                client.house_match_timer = getEpoch()

                try:
                    clientMatch = self.matchingDatabase.findMatch(client, lambda clientDatabaseResultMatch : self.buildAndVerifyClientFromDatabaseResult(client, clientDatabaseResultMatch))
                except ValueError as e:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Bad database query attempt [%s], forcefully disconnecting client: [%s]" % (e, client))
                    client.closeConnection()
                    return

                # If we can't immediately find a match then add it to the waiting list.
                if clientMatch is None:
                    onFailure()
                    return

                self.takeRoom(client, clientMatch)
        finally:
            self.house_lock.release()

    def getCurrentMatchOfClient(self, client, requiredState = None):
        self.house_lock.acquire()
        try:
            if requiredState is not None and client.state != requiredState:
                return None

            return self.room_participant.get(client)
        finally:
            self.house_lock.release()

    def aquireMatch(self, client):
        if client.connection_status != Client.ConnectionStatus.CONNECTED:
            if client.connection_status == Client.ConnectionStatus.NOT_CONNECTED:
                client.client_matcher.stop()

            return

        self.house_lock.acquire()
        try:
            if client not in self.room_participant:
                if client.state != Client.State.MATCHING and client.state != Client.State.MATCHED:
                    return

                clientMatch = self.attemptTakeRoom(client)
            else:
                clientMatch = self.room_participant[client]
                clientOld = self.room_participant[clientMatch]

                # A client has reconnected, and wants to use the old room.
                if clientOld is not client:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Old room reused, due to new client [%s], resuing old [%s]" % (client, clientOld))

                    # Key object is not replaced during an update of same key, so we need to do this, because
                    # keyed object may change, even if hash stays the same.
                    try:
                        del self.room_participant[client]
                    except KeyError:
                        pass

                    try:
                        del self.room_participant[clientMatch]
                    except KeyError:
                        pass

                    self.room_participant[client] = clientMatch
                    self.room_participant[clientMatch] = client

                    if client.state == Client.State.ACCEPTING_MATCH:
                        if logger.isEnabledFor(logging.DEBUG):
                            logger.debug("(REUSE) Readvised match details between client [%s] and [%s]" % (client, clientMatch))
                        self.adviseMatchDetails(client, clientMatch, reconnectingClient = True)
                    elif client.state == Client.State.MATCHED:
                        if logger.isEnabledFor(logging.DEBUG):
                            logger.debug("(REUSE) Readvised NAT punchthrough details between client [%s] and [%s]" % (client, clientMatch))
                        # NAT punchthrough won't be enabled on the new client and
                        # will probably be disabled on the old client.
                        self.adviseNatPunchthrough(client, clientMatch)
                    else:
                        if logger.isEnabledFor(logging.DEBUG):
                            logger.debug("(REUSE) Releasing room, reconnecting client state is unusual: %d and %d" % (client.state, clientMatch.state))
                        self.releaseRoom(client)
        finally:
            self.house_lock.release()

    def handleUdpPacket(self, client, packet = None):
        if client.connection_status == Client.ConnectionStatus.CONNECTED and client.state != Client.State.MATCHED:
            return

        self.house_lock.acquire()
        try:
            clientMatch = self.room_participant.get(client)
        finally:
            self.house_lock.release()

        if clientMatch is None:
            pass
        elif packet is not None:
            # Send to client that we are matched with.
            clientMatch.udp.sendRawBuffer(packet)

    def buildAndVerifyClientFromDatabaseResult(self, client, clientDatabaseResultMatch):
        clientMatch = self.buildClientFromDatabaseResult(clientDatabaseResultMatch)

        # Avoid recently skipped clients, and blocked clients.
        if clientMatch is not None and client is not clientMatch and client.shouldMatch(clientMatch):
            return clientMatch
        else:
            return None

    def buildClientFromDatabaseResult(self, databaseResultMatch):
        key = databaseResultMatch['unique_id']
        clientMatch = self.waiting_clients_by_key.get(key)

        if clientMatch is not None:
            return clientMatch

        # If the match is offline.
        # ***** Here if notify enabled on the record, we synthesize a client out of that record.

        shouldNotify = databaseResultMatch.get('should_notify')
        if not shouldNotify:
            # We don't tolerate an offline client here, because we're not going notify them.
            # So this must be because of a server restart, so clear that client out.
            self.matchingDatabase.removeMatchById(databaseResultMatch['_id'])
            logger.warn("Client in DB not found in waiting list, database inconsistency detected, removing key from database: " + key + ", and retrying")
            return None

        # We can tolerate an offline client, if we intend on notifying them.
        synthClient = self.matchingDatabase.synthesizeClient(databaseResultMatch, self.build_offline_client_func)
        assert isinstance(synthClient, Client)

        banMagnitude, banTime = synthClient.karma_database.getBanMagnitudeAndExpirationTime(synthClient)
        if banTime is not None:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Offline client [%s] is banned, removing" % synthClient)
            self._removeFromWaitingList(synthClient,True)
            return None

        synthClient.karma_rating = synthClient.karma_database.getKarma(synthClient)
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Offline client [%s] loaded karma of %d" % (synthClient, synthClient.karma_rating))

        # Allow client to reconnect and takeover this session.
        # If something there already, then maybe client recently connected and will soon
        # update this record.
        #
        # Basically prevents a race condition.
        synthClientDup = self.udp_connection_linker.clients_by_udp_hash.get(synthClient.udp_hash)
        if synthClientDup is not None:
            return synthClientDup
        else:
            return synthClient


    def pushBlock(self, blockerClient, blockedClient):
        self.matchingDatabase.pushBlock(blockerClient, blockedClient)

    def pushSkip(self, skipperClient, skippedClient):
        self.matchingDatabase.pushSkip(skipperClient, skippedClient)

    def didRecentlySkip(self, skipperClient, skippedClient):
        return self.matchingDatabase.didRecentlySkip(skipperClient, skippedClient)

    def didBlock(self, blockerClient, blockedClient, checkBothSides=True):
        return self.matchingDatabase.didBlock(blockerClient, blockedClient, checkBothSides=checkBothSides)