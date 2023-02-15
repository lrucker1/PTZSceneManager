//
//  PTZPrefObject.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/14/23.
//

#import "PTZPrefObject.h"

@implementation PTZPrefObject

// Macros go through the KeyWithSelector variants because we know they have prefixes, and "remove" is not a special word like "set" is.

- (NSString *)prefKeyForKey:(NSString *)key {
    NSAssert(0, @"Subclass must override %@", NSStringFromSelector(_cmd));
    return key;
}

- (id)prefValueForKey:(NSString *)key {
    NSString *objKey = [self prefKeyForKey:key];
    return [[NSUserDefaults standardUserDefaults] objectForKey:objKey] ?: [[NSUserDefaults standardUserDefaults] objectForKey:key];
}

// Convert prefixFoo/prefixFoo: to foo. foo: is returned unchanged.
- (NSString *)removePrefix:(NSString *)basePrefix fromKey:(NSString *)key {
    NSInteger len = [basePrefix length];
    BOOL hasPrefix = [key hasPrefix:basePrefix];
    if (!hasPrefix) {
        return key;
    }
    BOOL hasColon = [key hasSuffix:@":"];
    NSInteger testLength = len + 1 + (hasColon ? 1 : 0);
    // Take off the "setF" and ":", convert the F to f.
    NSString *prefix = [key substringToIndex:len+1];
    NSString *firstChar = [prefix substringFromIndex:len];
    NSString *suffix = [key substringWithRange:NSMakeRange(len+1, [key length] - testLength)];
    key = [NSString stringWithFormat:@"%@%@", [firstChar lowercaseString], suffix];
    return key;
}

- (void)setPrefValue:(id)obj forKeyWithSelector:(NSString *)key {
    // Convert setFoo: to foo
    key = [self removePrefix:@"set" fromKey:key];
    [self setPrefValue:obj forKey:key];
}

- (void)setPrefValue:(id)obj forKey:(NSString *)key {
     NSString *objKey = [self prefKeyForKey:key];
    [self willChangeValueForKey:key];
    [[NSUserDefaults standardUserDefaults] setObject:obj forKey:objKey];
    [self didChangeValueForKey:key];
}

- (void)removePrefValueForKeyWithSelector:(NSString *)key {
    // Convert removeFoo to foo
    key = [self removePrefix:@"remove" fromKey:key];
    [self removePrefValueForKey:key];
}

- (void)removePrefValueForKey:(NSString *)key {
    NSString *objKey = [self prefKeyForKey:key];
    // objKey has the obj-specific prefix. key is what KVO is watching.
    [self willChangeValueForKey:key];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:objKey];
    [self didChangeValueForKey:key];
}

@end
