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

// Client disconnected from master server, but may reconnect later under same
// session.
//
// For now we should stop sending to the client via NAT punch through,
// as the address may be invalid (e.g. interface change) when the client reconnects.
#define NAT_PUNCHTHROUGH_DISCONNECT 3

// No longer interested in talking to current person, give me someone new.
#define SKIP_PERSON 4

// Reset video speed
#define RESET_VIDEO_SPEED 5

#define COMMANDER_SUCCESS 1
#define COMMANDER_FAILURE 2

#endif
