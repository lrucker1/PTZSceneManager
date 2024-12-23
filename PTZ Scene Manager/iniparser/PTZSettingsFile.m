//
//  PTZSettingsFile.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/22/22.
//

#import "PTZSettingsFile.h"
#import "ObjCUtils.h"

static NSCharacterSet *PTZSettings_iniKeyCharacterSet;

@interface PTZSettingsFile ()


@end


@implementation PTZSettingsFile

+ (void)initialize {
    [super initialize];
    // Keys should only include alphanumeric characters plus '.' (period), '_' (underscore), and '-' (hyphen)
    // USB device names can have spaces. Maybe even non-ASCII, I don't know who names them.
    PTZSettings_iniKeyCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.-_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
    
    // Section names should only include alphanumeric characters plus '.' (period), '_' (underscore), and '-' (hyphen)
    // Not adding sections, so we're good.
}

+ (BOOL)validateFileWithPath:(NSString *)path error:(NSError * _Nullable *)error {
    PTZSettingsFile *testFile = [[PTZSettingsFile alloc] initWithPath:path];
    if (testFile == nil) {
        if (error != nil) {
            *error = OCUtilErrorWithDescription(NSLocalizedString(@"The settings file could not be opened", @"failed to open file"), NSLocalizedString(@"Make sure the directory contains a valid PTZOptics settings.ini file", @"File not found alert message"), @"PTZSettingsFile", 100);
        }
        return NO;
    }
    return [testFile validateDictionary:error];
}

- (BOOL)validateDictionary:(NSError * _Nullable *)error {
    // Check for missing required keys - nil result from stringForKeyValidation:
    NSString *sizeObj = [self stringForKeyValidation:@"cameraslist:size"];
    NSString *checkVersion = NSLocalizedString(@"The PTZOptics settings.ini file may be damaged, or the format might not be compatible with this version of PTZ Backup", @"Bad file or incompatible versions");
    if (sizeObj == nil) {
        if (error != nil) {
            *error = OCUtilErrorWithDescription(NSLocalizedString(@"cameraslist:size missing from dictionary", @"cameraslist:size missing"), checkVersion, @"PTZSettingsFile", 102);
        }
        return NO;
    }
    
    int size = [sizeObj intValue];
    if (size <= 0) {
        if (error != nil) {
            NSString *formatStr = NSLocalizedString(@"cameraslist:size contains unexpected value %@", @"cameraslist:size has a bad value");
             *error = OCUtilErrorWithDescription([NSString localizedStringWithFormat:formatStr, sizeObj], checkVersion, @"PTZSettingsFile", 103);
        }
        return NO;
    }

    size = MIN(size, 8); // 8 is the current value but could change. 8 is enough for detecting a bad file.
    for (int i = 1; i <= size; i++) {
        // Empty values should be fine. nil values imply PTZ has changed formats again.
        NSString *devicename = [self stringForKeyValidation:[NSString stringWithFormat:@"cameraslist:%d\\devicename", i]];
        NSString *cameraname = [self stringForKeyValidation:[NSString stringWithFormat:@"cameraslist:%d\\cameraname", i]];
        if (devicename == nil || cameraname == nil) {
            if (error != nil) {
                *error = OCUtilErrorWithDescription(NSLocalizedString(@"cameraslist devicename or cameraname information missing from dictionary", @"cameraslist camera info missing"), checkVersion, @"PTZSettingsFile", 104);
            }
            return NO;
        }
    }
    return YES;
}

// Note that this applies to key subcomponents, which is why we do it here; super deals with full keys including the ':' for lists.
- (NSString *)fixKey:(NSString *)key {
    return [key stringByAddingPercentEncodingWithAllowedCharacters:PTZSettings_iniKeyCharacterSet];
}


- (NSString *)stringFromList:(NSString *)list key:(NSString *)key {
    NSString *iniKey = [NSString stringWithFormat:@"%@:%@", list, key];
    return [self stringForKey:iniKey];
}

- (void)setName:(NSString *)name forScene:(NSInteger)scene camera:(NSString *)devname {
    // list General "mem" + index + ip
    NSString *key = [NSString stringWithFormat:@"%@:mem%d%@", @"General", (int)scene, [self fixKey:devname]];
    if ([self setString:name forKey:key]) {
        [self writeToFile:self.path];
    }
}

- (NSString *)nameForScene:(NSInteger)scene camera:(NSString *)devname {
    // list General "mem" + index + ip
    
    NSString *key = [NSString stringWithFormat:@"mem%d%@", (int)scene, [self fixKey:devname]];
    return [self stringFromList:@"General" key:key];
}

- (NSArray<NSDictionary *> *)cameraInfo {
    static NSString *noCamera = @"0.0.0.0";

    NSMutableArray *cameras = [NSMutableArray new];
    int size = [[self stringForKey:@"cameraslist:size"] intValue];
    for (int i = 1; i <= size; i++) {
        NSInteger cameratype = [self integerForKey:[NSString stringWithFormat:@"cameraslist:%d\\cameratype", i]];
        NSString *devicename = [self stringForKey:[NSString stringWithFormat:@"cameraslist:%d\\devicename", i]];
        if ([devicename length] > 0 && ![devicename isEqualToString:noCamera]) {
            NSString *cameraname = [self stringForKey:[NSString stringWithFormat:@"cameraslist:%d\\cameraname", i]];
            [cameras addObject:@{@"cameraname":cameraname, @"devicename":devicename, @"original":devicename, @"cameratype":@(cameratype), @"menuIndex":@(i)}];
        }
    }
    return cameras;
}

@end
