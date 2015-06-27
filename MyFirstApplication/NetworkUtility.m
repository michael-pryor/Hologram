//
//  NetworkUtility.m
//  MyFirstApplication
//
//  Created by Michael Pryor on 27/06/2015.
//
//

#import "NetworkUtility.h"

@implementation NetworkUtility
+ (Boolean)isEqualAddress:(struct sockaddr_in*)addr1 address:(struct sockaddr_in*)addr2 {
    if(addr1->sin_port != addr2->sin_port) {
        return false;
    }
    
    return addr1->sin_addr.s_addr == addr2->sin_addr.s_addr;
}
@end
