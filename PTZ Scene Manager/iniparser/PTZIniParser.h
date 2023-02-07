//
//  PTZIniParser.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/15/23.
//

#import <Foundation/Foundation.h>
#import "dictionary.h"
#import "iniparser.h"

NS_ASSUME_NONNULL_BEGIN

@interface PTZIniParser : NSObject

@property dictionary *ini;
@property NSString *path;

- (instancetype)initWithPath:(NSString *)path;
- (void)logDictionary;
- (NSString *)stringForKey:(NSString *)aKey;
- (NSString *)stringForKeyValidation:(NSString *)aKey;
- (BOOL)setString:(NSString *)string forKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)aKey;
- (BOOL)setInteger:(NSInteger)value forKey:(NSString *)aKey;

- (BOOL)writeToFile:(NSString *)file;

@end

NS_ASSUME_NONNULL_END
