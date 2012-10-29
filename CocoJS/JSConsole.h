//
//  LuaConsole.h
//  CocosLua
//
//  Created by Xiliang Chen on 12-5-15.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@class HighlightingTextView;

@interface JSConsole : UIView

@property (nonatomic, retain, readonly) HighlightingTextView *textView;
@property (nonatomic) BOOL visible;
@property (nonatomic) BOOL fullScreen;

+ (JSConsole *)sharedInstance;

- (void)toggleVisible;
- (void)toggleFullScreen;

- (void)handleInputString:(NSString *)string;

- (void)appendMessage:(NSString *)msg;

@end
