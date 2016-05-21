from utility import getEpoch
from random import randint
from time import sleep
from threading import RLock

# Weighted average of tick rate.
class StatTracker(object):
    def __init__(self, timePeriodSeconds, averageSetSize = 10):
        super(StatTracker, self).__init__()
        self.time_period_seconds = timePeriodSeconds
        self.average_list = list()
        self.average_list_max_size = averageSetSize
        self.current_count = 0
        self.last_tick = getEpoch()
        self.average_tick_rate = 0
        self._lock = RLock()

    # If no data is coming in for example, we may want to force a recalculation such that 0 values are appended.
    def soft_tick(self):
        self.tick(0)

    def tick(self, amount):
        self._lock.acquire()
        try:
            self.current_count += amount
            currentTimeStatic = currentTime = getEpoch()
            while currentTime - self.last_tick >= self.time_period_seconds:
                currentTime -= self.time_period_seconds
                self.average_list.append(self.current_count)
                self.current_count = 0

                if len(self.average_list) > self.average_list_max_size and len(self.average_list) > 0:
                    del self.average_list[0];

                # Recalculate tick rate.
                self.average_tick_rate = reduce(lambda x, y: x + y, self.average_list) / len(self.average_list)

            self.last_tick = currentTimeStatic
            if len(self.average_list) == 0:
                self.average_tick_rate = self.current_count
        finally:
            self._lock.release()



if __name__ == '__main__':
    tracker = StatTracker(60)

    while True:
        sleep(1)
        amount = randint(1,10)
        print "Ticked by amount: %d" % amount
        tracker.tick(amount)
        print "Average is: %d" % tracker.average_tick_rate

