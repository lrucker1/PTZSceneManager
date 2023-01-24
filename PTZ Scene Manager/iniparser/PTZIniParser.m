//
//  PTZIniParser.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/15/23.
//

#import "PTZIniParser.h"

static char _last_error[1024];
static int _error_callback(const char *format, ...)
{
    int ret;
    va_list argptr;
    va_start(argptr, format);
    ret = vsprintf(_last_error, format, argptr);
    fprintf(stderr, "%s", _last_error); // Just dump to the log window.
    va_end(argptr);
    return ret;
}

@implementation PTZIniParser

+ (void)initialize {
    /* Specify our custom error_callback */
    iniparser_set_error_callback(_error_callback);
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _last_error[0] = '\0';
        _ini = iniparser_load([path UTF8String]);
        _path = path;
        if (_ini == NULL) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    iniparser_freedict(_ini);
    _ini = NULL;
}

- (BOOL)writeToFile:(NSString *)file {
    FILE * fd;
    if ((fd=fopen([file UTF8String], "w"))==NULL) {
        return NO;
    }

    iniparser_dump_ini(self.ini, fd);
    fclose(fd);
    return YES;
}

- (void)logDictionary {
    iniparser_dump(self.ini, stdout);
}

// Returns @"" if key is missing. @"" is also a valid result.
- (NSString *)stringForKey:(NSString *)aKey {
    const char *result = iniparser_getstring(self.ini, [aKey UTF8String], "");
    return [NSString stringWithUTF8String:result];
}

// Returns nil if key is missing.
- (NSString *)stringForKeyValidation:(NSString *)aKey {
    const char *result = iniparser_getstring(self.ini, [aKey UTF8String], NULL);
    if (result == NULL) {
        return nil;
    }
    return [NSString stringWithUTF8String:result];
}

- (BOOL)setString:(NSString *)string forKey:(NSString *)key {
    return iniparser_set(self.ini, [key UTF8String], [string UTF8String]) == 0;
}

@end
