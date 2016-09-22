__author__ = 'pryormic'

from twisted.internet import threads, defer
import requests
import logging

logger = logging.getLogger(__name__)
class Analytics(object):
    def __init__(self, maxLiveCount, name):
        super(Analytics, self).__init__()
        # Requests which are waiting but not actioned yet.
        self.live_count = 0
        self.max_live_count = maxLiveCount

        self.httpSession = requests.Session()
        self.server_name = name

    # Do the actual HTTP request to Google analytics.
    def _doPushEvent(self, value, category, name, label):
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Pushing event with category [%s], name [%s], label [%s], value [%s]" % (category, name, label, value))

        postToMake = {
            'v': 1, # Protocol version (required)
            'tid': 'UA-78124726-1', # Identify our instance in google analytics (required)
            'cid': self.server_name, # ID of user (required)
            't': 'event', # Type of event, must be one of 'pageview', 'screenview', 'event', 'transaction', 'item', 'social', 'exception', 'timing'.
            'ec': category, # Event category
            'ea': name, # Event action
            'ev' : value, # Event value, must be >=0.
        }
        if label is not None:
            postToMake['el'] = label

        return self.httpSession.post("https://www.google-analytics.com/collect",postToMake)

    def _onEventCompletion(self, result):
        self.live_count-=1

        if result.status_code == 200:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Successfully pushed analytics result: [%s] (live count = %d)" % (result.reason, self.live_count))
        else:
            logger.error("Failed to push analytics result with status code [%d]: [%s] (live count = %d)" % (result.status_code, result.reason, self.live_count))


    def pushEvent(self, value, category, name, label):
        if self.live_count >= self.max_live_count:
            logger.error("Failed to push analytics event, too many in progress requests (%d of max %d)" % (self.live_count, self.max_live_count))
            return

        self.live_count+=1
        item = threads.deferToThread(lambda: self._doPushEvent(value, category, name, label))
        item.addCallback(self._onEventCompletion)
        logger.debug("Event pushed, live count is %d" % self.live_count)



