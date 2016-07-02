//
// Created by Michael Pryor on 02/07/2016.
//

#import <Foundation/Foundation.h>


@interface NameParsing : NSObject
+ (NSString *)getShortNameAndBuildLongName:(NSMutableString *)outLongName firstName:(NSString *)firstName middleName:(NSString *)middleName lastName:(NSString *)lastName;
@end