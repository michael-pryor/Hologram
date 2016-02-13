__author__ = 'pryormic'

import math

def distanceBetweenPoints(longitudeA, latitudeA, longitudeB, latitudeB):
    # Convert latitude and longitude to
    # spherical coordinates in radians.
    degrees_to_radians = math.pi/180.0

    # phi = 90 - latitude
    phi1 = (90.0 - latitudeA)*degrees_to_radians
    phi2 = (90.0 - latitudeB)*degrees_to_radians

    # theta = longitude
    theta1 = longitudeA*degrees_to_radians
    theta2 = longitudeB*degrees_to_radians

    # Compute spherical distance from spherical coordinates.

    # For two locations in spherical coordinates
    # (1, theta, phi) and (1, theta', phi')
    # cosine( arc length ) =
    #    sin phi sin phi' cos(theta-theta') + cos phi cos phi'
    # distance = rho * arc length

    cos = (math.sin(phi1)*math.sin(phi2)*math.cos(theta1 - theta2) +
           math.cos(phi1)*math.cos(phi2))
    arc = math.acos( cos )

    return arc

def distanceBetweenPointsKm(longitudeA, latitudeA, longitudeB, latitudeB):
    return distanceBetweenPoints(longitudeA, latitudeA, longitudeB, latitudeB) * 6373

if __name__ == '__main__':
    print distanceBetweenPointsKm(-0.110755, 51.507761, -0.389731, 51.651498)
    print distanceBetweenPointsKm(-0.02312598, 51.49324584,+37.61763300, +55.75578600)
    print distanceBetweenPointsKm(51.49324584, -0.02312598, +55.75578600, +37.61763300)