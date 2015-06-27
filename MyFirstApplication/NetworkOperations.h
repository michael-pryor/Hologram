//
//  NetworkOperations.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#ifndef MyFirstApplication_NetworkOperations_h
#define MyFirstApplication_NetworkOperations_h

// ****** UDP ******
#define AUDIO_ID 1
#define VIDEO_ID 2

// Try to punchthrough NAT
#define NAT_PUNCHTHROUGH_DISCOVERY 3

// ****** TCP ******
// End point cannot keep up with rate of network flow,
// slow down the video frame rate that we are sending to help them cope.
#define SLOW_DOWN_VIDEO 1

// The master server has sent a packet containing an address to connect to,
// we will periodically fire discovery messages to try and connect.
#define NAT_PUNCHTHROUGH_ADDRESS 2


#endif
