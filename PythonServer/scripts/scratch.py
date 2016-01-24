__author__ = 'pryormic'

# size of packet we are trying to batch.
# desiredBatchSize = ideal batch size we strive for (but we want all packets to be same size, so can't always get this).
# minumum batch size we will tolerate, before giving up and defaulting to desiredBatchSize.
# maximum batch size we will tolerate, before giving up and defaulting to desiredBatchSize.
def computeBatchSize(fullPacketSize, desiredBatchSize, minimumBatchSizeThreshold, maximumBatchSizeThreshold):
    if fullPacketSize <= desiredBatchSize:
        return fullPacketSize

    if fullPacketSize % desiredBatchSize == 0:
        return desiredBatchSize

    up = desiredBatchSize + 1
    down = desiredBatchSize - 1

    lowestWastedValue = [None, None]

    while True:
        upHitThreshold = up == maximumBatchSizeThreshold
        downHitThreshold = down == minimumBatchSizeThreshold

        if upHitThreshold and downHitThreshold:
            return lowestWastedValue[1]

        if not upHitThreshold:
            remainder = fullPacketSize % up
            if remainder == 0:
                return up

            wasted = up - remainder
            if lowestWastedValue[0] is None or wasted < lowestWastedValue[0]:
                lowestWastedValue[0] = wasted
                lowestWastedValue[1] = up

            up+=1

        if not downHitThreshold:
            remainder = fullPacketSize % down
            if remainder == 0:
                return down

            wasted = down - remainder
            if lowestWastedValue[0] is None or wasted < lowestWastedValue[0]:
                lowestWastedValue[0] = wasted
                lowestWastedValue[1] = down

            down-=1

if __name__ == '__main__':
    desiredBatchSize = 128

    minimumAcceptableBatchSize = 90
    maximumAcceptableBatchSize = 256

    maximumPacketSize = 1000

    mapping_to_batch_size = list()

    for n in range(0, maximumPacketSize):
        result = computeBatchSize(n, desiredBatchSize, minimumAcceptableBatchSize, maximumAcceptableBatchSize)
        mapping_to_batch_size.append(result)
        #print 'batch size for %d -> %d' % (n, result)
        if n > desiredBatchSize and n % result != 0:
            print "PROPPER FAILURE!: %d (batch size=%d), remainder: %d" % (n, result, n % result)

    for n in range(0, maximumPacketSize):
        a = mapping_to_batch_size[n]
        if n < desiredBatchSize:
            if a != n:
                print "PROBLEM %d" % a
            continue

        if n % a != 0:
            print "FAILURE: %d (batch size=%d), remainder: %d" % (n, a, (n % a))


