//
//  CocoJSTerminal.m
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-29.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "CocoJSTerminal.h"

#import <readline/readline.h>

#import "ThoMoClientStub.h"

@interface CocoJSTerminal () <ThoMoClientDelegateProtocol>

@property BOOL firstline;
@property (retain) NSConditionLock *lock;

- (void)prompt:(BOOL)firstline;
- (void)threadMain;

@end

@implementation CocoJSTerminal {
    ThoMoClientStub *_client;
}

+ (void)run {
    CocoJSTerminal *app = [[self alloc] init];
    
    [app run];
    
    [app release];
}

#pragma mark -

- (id)init
{
    self = [super init];
    if (self) {
        _client = [[ThoMoClientStub alloc] initWithProtocolIdentifier:@"CocoJSDebug"];
        _client.delegate = self;
        _lock = [[NSConditionLock alloc] initWithCondition:0];
    }
    return self;
}

- (void)dealloc
{
    [_client stop];
    [_client release];
    
    [_lock release];
    
    [super dealloc];
}

#pragma mark -

- (void)run {
    [_client start];
    [self performSelectorInBackground:@selector(threadMain) withObject:nil];
    [[NSRunLoop mainRunLoop] run];
}

- (void)prompt:(BOOL)firstline {
    [self.lock lockWhenCondition:0];
    self.firstline = firstline;
    [self.lock unlockWithCondition:1];
}

- (void)threadMain {
    @autoreleasepool {
        for (;;) {
            [self.lock lockWhenCondition:1];
            BOOL firstline = self.firstline;
            const char *str = firstline ? "> " : ">> ";
            char *line;
            do {
                line = readline(str);
            } while (line && line[0] == '\0');
            if (line) {
                add_history(line);
                
                NSString *script = @(line);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_client sendToAllServers:script];
                });
            } else {
                exit(EXIT_SUCCESS);
            }
            [self.lock unlockWithCondition:0];
        }
    }
}

#pragma mark - ThoMoClientDelegateProtocol

- (void)client:(ThoMoClientStub *)theClient didConnectToServer:(NSString *)aServerIdString {
    printf("connect to server '%s'\n", [aServerIdString UTF8String]);
    [self prompt:YES];
}

- (void)client:(ThoMoClientStub *)theClient didDisconnectFromServer:(NSString *)aServerIdString errorMessage:(NSString *)errorMessage {
    printf("disconnect from server '%s'. %s\n", [aServerIdString UTF8String], [errorMessage UTF8String]);
}

- (void)client:(ThoMoClientStub *)theClient didReceiveData:(id)theData fromServer:(NSString *)aServerIdString {
    if ([theData isKindOfClass:[NSString class]]) {
        printf("%s\n", [theData UTF8String]);
    } else {
        [self prompt:[theData boolValue]];
    }
}

@end
