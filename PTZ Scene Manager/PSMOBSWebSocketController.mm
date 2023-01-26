//
//  PSMOBSWebSocketController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/26/23.
//
// Credit: https://github.com/dhbaird/easywsclient
// Credit: https://stackoverflow.com/questions/69051106/c-or-c-websocket-client-working-example

#import "PSMOBSWebSocketController.h"
#import "PTZPrefCamera.h"
#include "easywsclient.hpp"
#include <iostream>
#include <string>
#include <memory>
#include <mutex>
#include <deque>
#include <thread>
#include <chrono>
#include <atomic>

NSString *PSMOBSSceneInputDidChange = @"PSMOBSSceneInputDidChange";
NSString *PSMOBSSessionDidEnd = @"PSMOBSSessionDidEnd";
static NSString *PSMOBSBundleID = @"com.obsproject.obs-studio";

// a simple, thread-safe queue with (mostly) non-blocking reads and writes
// Yes, this could probably be replaced by dispatch_queue code.
namespace non_blocking {
template <class T>
class Queue {
    mutable std::mutex m;
    std::deque<T> data;
public:
    void push(T const &input) {
        std::lock_guard<std::mutex> L(m);
        data.push_back(input);
    }

    bool pop(T &output) {
        std::lock_guard<std::mutex> L(m);
        if (data.empty())
            return false;
        output = data.front();
        data.pop_front();
        return true;
    }
};
}

/*
 Hello (OpCode 0)
 Identify (OpCode 1)
 Identified (OpCode 2)
 Reidentify (OpCode 3)
 Event (OpCode 5)
 Request (OpCode 6)
 RequestResponse (OpCode 7)
 RequestBatch (OpCode 8)
 RequestBatchResponse (OpCode 9)
 */
typedef enum  {
    Op_Hello = 0,
    Op_Identify = 1,
    Op_Identified = 2,
    Op_Reidentify = 3,
    Op_Event = 5,
    Op_Request = 6,
    Op_RequestResponse = 7,
    Op_RequestBatch = 8,
    Op_RequestBatchResponse = 9
} OpCode;

/*
 
 EventSubscription::None
 EventSubscription::General
 EventSubscription::Config
 EventSubscription::Scenes
 EventSubscription::Inputs
 EventSubscription::Transitions
 EventSubscription::Filters
 EventSubscription::Outputs
 EventSubscription::SceneItems
 EventSubscription::MediaInputs
 EventSubscription::Vendors
 EventSubscription::Ui
 EventSubscription::All
 EventSubscription::InputVolumeMeters
 EventSubscription::InputActiveStateChanged
 EventSubscription::InputShowStateChanged
 EventSubscription::SceneItemTransformChanged
 */
typedef enum {
    ES_None = 0,
    ES_General = (1 << 0),
    ES_Config = (1 << 1),
    ES_Scenes = (1 << 2),
    ES_Inputs = (1 << 3),
    ES_Transition = (1 << 4),
    ES_Filters = (1 << 5),
    ES_Outputs = (1 << 6),
    ES_SceneItems = (1 << 7),
    ES_MediaInputs = (1 << 8),
    ES_Vendors = (1 << 9),
 // All non-high-volume events. (General | Config | Scenes | Inputs | Transitions | Filters | Outputs | SceneItems | MediaInputs | Vendors | Ui)
    
} EventSubscription;

@interface PSMOBSWebSocketController () {
    non_blocking::Queue<std::string> outgoing;
    non_blocking::Queue<std::string> incoming;
    dispatch_queue_t socketQueue;
}
@property (readwrite) BOOL connected;
@property NSString *command;
@property BOOL running;
@property BOOL isObservingAppLaunch;
@property NSMutableDictionary *obsInputs;
@property NSString *requestId;
@property NSString *obsURL;

@end

@implementation PSMOBSWebSocketController

+ (instancetype)defaultController {
    static dispatch_once_t once;
    static id defaultController;
    dispatch_once(&once, ^{
        defaultController = [[self alloc] init];
    });
    return defaultController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // A unique ID for requests when we don't care about matching request with reply.
        _requestId = [[NSUUID new] UUIDString];
        socketQueue = dispatch_queue_create("socketQueue", NULL);
    }
    return self;
}

- (BOOL)obsIsRunning {
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:PSMOBSBundleID]) {
            return YES;
        }
    }
    return NO;
}

- (void)startObservingRunningApps {
    if (!self.isObservingAppLaunch) {
        [[[NSWorkspace sharedWorkspace] notificationCenter]
         addObserver:self
         selector:@selector(onSomeApplicationDidLaunch:)
         name:NSWorkspaceDidLaunchApplicationNotification
         object:nil];
        self.isObservingAppLaunch = YES;
    }
}

- (void)stopObservingRunningApps {
    if (self.isObservingAppLaunch) {
        [[[NSWorkspace sharedWorkspace] notificationCenter]
         removeObserver:self
         name:NSWorkspaceDidLaunchApplicationNotification
         object:nil];
        self.isObservingAppLaunch = NO;
    }
}

// Called by AppDelegate at launch.
- (void)connectToServer:(NSString *)urlString {
    self.obsURL = urlString;
    if (self.connected) {
        return;
    }
    if ([self obsIsRunning]) {
        [self runSocketFromURL:self.obsURL];
    } else {
        [self startObservingRunningApps];
    }
}

- (NSString *)convertToJSON:(id)dictionaryOrArrayToOutput {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionaryOrArrayToOutput
                                                       options:NSJSONWritingPrettyPrinted // Pass 0 if you don't care about the readability of the generated string
                                                         error:&error];

    if (! jsonData) {
        return nil;
    } else {
        return[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
}

- (NSString *)jsonHelloReply {
    // This is a simple app; it only listens to scene changes.
    NSDictionary *dict = @{@"op":@(1),
                           @"d":@{@"rpcVersion":@(1),
                                  @"eventSubscriptions":@(ES_General | ES_Scenes)}};
    return [self convertToJSON:dict];
}

- (NSString *)jsonGetSourceActive:(NSString *)sourceName {
    NSDictionary *dict = @{@"op":@(6),
                           @"d": @{@"requestType": @"GetSourceActive",
                                   @"requestId": sourceName,
                                   @"requestData": @{@"sourceName": sourceName}}};
    return [self convertToJSON:dict];
}

- (NSString *)jsonGetInputList {
    NSDictionary *dict = @{@"op":@(6),
                           @"d": @{@"requestType": @"GetInputList",
                                   @"requestId": self.requestId,
                                   @"requestData": @{}}};
    return [self convertToJSON:dict];
}

- (void)requestNotificationsForCamera:(PTZPrefCamera *)camera {
    if (self.obsInputs == nil) {
        self.obsInputs = [NSMutableDictionary dictionary];
    }
    [self.obsInputs setObject:camera forKey:camera.cameraname];
    [self getSourceActive];
}

- (void)handleInputList:(NSDictionary *)dict {
    [self getSourceActive];
}

- (void)handleSourceActive:(NSDictionary *)dict {
    NSString *sourceName = dict[@"requestId"];
    PTZCamera *camera = self.obsInputs[sourceName];
    [[NSNotificationCenter defaultCenter] postNotificationName:PSMOBSSceneInputDidChange
                                    object:camera
                                  userInfo:dict];
}

- (void)handleRequestResponse:(NSDictionary *)dict {
    NSDictionary *data = dict[@"d"];
    NSString *type = data[@"requestType"];
    if ([type isEqualToString:@"GetInputList"]) {
        [self handleInputList:data[@"responseData"]];
    } else if ([type isEqualToString:@"GetSourceActive"]) {
        [self handleSourceActive:data];
    }
}

- (void)getSourceActive {
    if (self.connected) {
        for (NSString *input in self.obsInputs) {
            NSString *json = [self jsonGetSourceActive:input];
            [self sendString:json];
        }
    }
}

- (void)handleEventResponse:(NSDictionary *)dict {
    NSDictionary *data = dict[@"d"];
    NSNumber *intentObj = data[@"eventIntent"];
    if (intentObj == nil) {
        return;
    }
    NSInteger intent = [intentObj integerValue];
    if (intent == ES_Scenes) {
        // Ignore SceneCreated, SceneRemoved, and SceneListChanged
        NSString *eventType = data[@"eventType"];
        if ([eventType isEqualToString:@"CurrentProgramSceneChanged"] ||
            [eventType isEqualToString:@"CurrentPreviewSceneChanged"]) {
            [self getSourceActive];
        }
    } else if (intent == ES_General) {
        // Ignore Vendor and Custom events.
        NSString *eventType = data[@"eventType"];
        if ([eventType isEqualToString:@"ExitStarted"]) {
            self.running = NO;
        }
    }
}

- (void)handleJSON:(id)jsonObj {
    if (![jsonObj isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *dict = (NSDictionary *)jsonObj;
    NSNumber *opObj = dict[@"op"];
    if (opObj == nil) {
        return;
    }
    switch ([opObj integerValue]) {
        case Op_Hello:
            self.connected = YES;
            [self sendString:self.jsonHelloReply];
            break;
        case Op_Identified:
            if ([self.obsInputs count] > 0) {
                [self getSourceActive];
            }
            break;
        case Op_Event:
            [self handleEventResponse:dict];
            break;
        case Op_RequestResponse:
            [self handleRequestResponse:dict];
            break;
        default:
            break;
    }
}

#pragma mark WebSocket thread

- (void)onSomeApplicationDidLaunch:(NSNotification *)note {
    //  The userInfo dictionary contains the NSWorkspaceApplicationKey key with a corresponding instance of NSRunningApplication that represents the affected app.
    if (self.connected) {
        return;
    }
    NSDictionary *dict = note.userInfo;
    NSRunningApplication *app = dict[NSWorkspaceApplicationKey];
    if ([app.bundleIdentifier isEqualToString:PSMOBSBundleID]) {
        [self runSocketFromURL:self.obsURL];
    }
}

- (void)sendString:(NSString *)str {
    outgoing.push([str UTF8String]);
}

- (void)recvString {
    dispatch_async(dispatch_get_main_queue(), ^{
        std::string s;
        if (self->incoming.pop(s)) {
            const char *msg = s.c_str();
            NSData *data = [NSData dataWithBytes:msg length:strlen(msg)];
            NSError *error;
            id msgObj = [NSJSONSerialization JSONObjectWithData:data
                             options:0
                               error:&error];
            [self handleJSON:msgObj];
        }
    });
}

- (void)connectionDidEnd {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connected = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:PSMOBSSessionDidEnd
                                        object:nil
                                      userInfo:nil];
        // OBS may be quitting, so don't check if it's currently running.
        [self startObservingRunningApps];
    });
}

- (void)runSocketFromURL:(NSString *)url {
    
    dispatch_async(socketQueue, ^() {
        using easywsclient::WebSocket;
        std::unique_ptr<WebSocket> ws(WebSocket::from_url([url UTF8String]));
        if (ws == NULL) {
            NSLog(@"Unable to connect to %@", url);
            if (![self obsIsRunning]) {
                [self startObservingRunningApps];
            }
            return;
        }
        self.running = YES;
        [self stopObservingRunningApps];
        while (self.running) {
            if (ws->getReadyState() == WebSocket::CLOSED)
                break;
            std::string data;
            if (self->outgoing.pop(data))
                ws->send(data);
            ws->poll();
            ws->dispatch([&](const std::string & message) {
                self->incoming.push(message);
                [self recvString];
            });
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        ws->close();
        ws->poll();
        [self connectionDidEnd];
    });
}

@end
