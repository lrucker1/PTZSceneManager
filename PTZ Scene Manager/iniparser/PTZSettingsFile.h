//
//  PTZSettingsFile.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/22/22.
//

#import <Foundation/Foundation.h>
#import "PTZIniParser.h"

NS_ASSUME_NONNULL_BEGIN

@interface PTZSettingsFile : PTZIniParser

+ (BOOL)validateFileWithPath:(NSString *)path error:(NSError * _Nullable *)error;

- (NSArray *)cameraInfo;
- (NSString *)nameForScene:(NSInteger)scene camera:(NSString *)ipAddr;
- (void)setName:(NSString *)name forScene:(NSInteger)scene camera:(NSString *)ipAddr;

@end

NS_ASSUME_NONNULL_END
