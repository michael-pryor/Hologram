from utility import getEpoch

__author__ = 'pryormic'
import logging

# I want to see exactly what we are sending.
#requests_log = logging.getLogger("requests.packages.urllib3")
#requests_log.setLevel(logging.DEBUG)
#requests_log.propagate = True
#import httplib
#httplib.HTTPConnection.debuglevel = 2

import time
from twisted.internet import threads
import requests

from hyper.contrib import HTTP20Adapter

logger = logging.getLogger(__name__)

class RemoteNotification(object):
    def __init__(self, maxLiveCount, serverName, production):
        super(RemoteNotification, self).__init__()
        # Requests which are waiting but not actioned yet.
        self.live_count = 0
        self.max_live_count = maxLiveCount
        self.server_name = serverName

        self.httpSession = requests.Session()

        # Support HTTP v2.0 (Requests doesn't by itself).
        if production:
            environment = "https://api.push.apple.com:443"
        else:
            environment = "https://api.development.push.apple.com:443" # this is dev.
        self.httpSession.mount(environment, HTTP20Adapter())

        self.httpSession.cert = '../security/hologram_private.cer'
        self.httpSession.headers.update({'apns-topic' : 'mike.Spawn'})

        self.url_push = environment + "/3/device/%s"

    def _doPushEvent(self, client, payload):
        theUrl = self.url_push % client.remote_notification_payload
        if client.remote_notification_payload is None:
            logger.error("No remote notification payload associated with client [%s], failed to notify" % client)
            return

        # I noticed occasional failures here, retrying to see if that helps.
        lastException = None
        for n in xrange(0,5):
            try:
                return self.httpSession.post(theUrl, json={'aps' : payload, 'server_name' : self.server_name})
            except Exception as e:
                lastException = e
                backoff = 0.1
                logger.warn("Failed to post remote notificaiton, retrying in %.1f seconds: %s", backoff, e)
                time.sleep(backoff)

        raise lastException

    def onTransactionSuccess(self, client):
        pass

    def onTransactionFailure(self, client, statusCode, rejectReason):
        logger.error("Remote notification could not be sent to client [%s], status code: %d, reject reason: %s." % (client, statusCode, rejectReason))

    def _onEventCompletion(self, result, client):
        self.live_count-=1

        if result.status_code == 200:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Successfully sent remote notification request: [%s] (live count = %d)" % (result.reason, self.live_count))
            self.onTransactionSuccess(client)
        else:
            logger.error("Failed to send remote notification request status code [%d]: [%s] (live count = %d)" % (result.status_code, result.reason, self.live_count))
            self.onTransactionFailure(client, result.status_code, result.text)


    def pushEvent(self, client, payload):
        if self.live_count >= self.max_live_count:
            logger.error("Failed to push remote notification event, too many in progress requests (%d of max %d)" % (self.live_count, self.max_live_count))
            self.onTransactionFailure(client, -1, "Too many requests in progress")
            return

        self.live_count+=1
        item = threads.deferToThread(lambda: self._doPushEvent(client, payload))
        item.addCallback(lambda code: self._onEventCompletion(code, client))
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Remote notification event pushed, live count is %d" % self.live_count)



