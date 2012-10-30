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

- (void)prompt:(BOOL)firstline;
- (void)threadMain;

@end

@implementation CocoJSTerminal {
    ThoMoClientStub *_client;
    NSCondition *_condition;
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
        _condition = [[NSCondition alloc] init];
        
    }
    return self;
}

- (void)dealloc
{
    [_client stop];
    [_client release];
    
    [_condition release];
    
    [super dealloc];
}

#pragma mark -

- (void)run {
    [_client start];
    [self performSelectorInBackground:@selector(threadMain) withObject:nil];
    [[NSRunLoop mainRunLoop] run];
}

- (void)prompt:(BOOL)firstline {
    [_condition lock];
    [_condition broadcast];
    self.firstline = firstline;
    [_condition unlock];
}

- (void)threadMain {
    @autoreleasepool {
        char *line = NULL;
        
        // disable tab completion
        rl_bind_key ('\t', rl_insert);

        for (;;) {
            [_condition lock];
            [_condition wait];
            [_condition unlock];
            BOOL firstline = self.firstline;
            const char *str = firstline ? "\r> " : "\r>> ";
            do {
                if (line) {
                    free(line);
                }
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
        printf("\r%s\n%s", [theData UTF8String], rl_prompt);
        fflush(stdout);
    } else {
        [self prompt:[theData boolValue]];
    }
}

@end
