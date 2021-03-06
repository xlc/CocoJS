//
//  LuaConsole.m
//  CocosLua
//
//  Created by Xiliang Chen on 12-5-15.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "JSConsole.h"

#import "JSCore.h"
#import "HighlightingTextView.h"
#import "JavascriptSyntaxHighlighter.h"
#import "ThoMoServerStub.h"

static JSConsole *sharedConsole;

@interface JSConsole () <UITextViewDelegate, ThoMoServerDelegateProtocol>

@property (nonatomic, retain) HighlightingTextView *textView;
@property (nonatomic, retain) UILabel *titleView;

- (void)appendValue:(jsval)vale;

- (void)appendPromptWithFirstLine:(BOOL)firstline;

- (void)keyboardWillShow:(NSNotification *)notification;
- (void)keyboardWillHide:(NSNotification *)notification;

- (void)handleString:(NSString *)string;

- (void)moveView:(UIPanGestureRecognizer *)recognizer;
- (void)resizeView:(UIPanGestureRecognizer *)recognizer;

- (void)clear;

@end

@implementation JSConsole {
    NSMutableString *_text;
    NSUInteger _lastPosition;
    BOOL _changeContainNewLine;
    NSMutableString *_buffer;
    CGRect _orignalFrame;
    UIView *_resizerView;
    UITapGestureRecognizer *_tapRecognizer;
    
    ThoMoServerStub *_server;
}

@synthesize textView = _textView;
@synthesize titleView = _titleView;
@synthesize visible = _visible;
@synthesize fullScreen = _fullScreen;

#pragma mark -

+ (JSConsole *)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedConsole = [[JSConsole alloc] init];
    });
    return sharedConsole;
}

+ (JSConsole *)tryGetInstance {
    return sharedConsole;
}

- (id)init
{
    return [self initWithFrame:CGRectMake(0, 0, 600, 300)];
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _orignalFrame = frame;
        
        _titleView = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleView.text = @"JSConsole";
        _titleView.textAlignment = NSTextAlignmentCenter;
        _titleView.backgroundColor = [UIColor lightGrayColor];
        _titleView.userInteractionEnabled = YES;
        UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleFullScreen)];
        tapRecognizer.numberOfTapsRequired = 2;
        [_titleView addGestureRecognizer:tapRecognizer];
        [tapRecognizer release];
        UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveView:)];
        [_titleView addGestureRecognizer:panRecognizer];
        [panRecognizer release];
        [self addSubview:_titleView];
        
        UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [clearButton setTitle:@"Clear" forState:UIControlStateNormal];
        [clearButton addTarget:self action:@selector(clear) forControlEvents:UIControlEventTouchUpInside];
        
        _textView = [[HighlightingTextView alloc] initWithFrame:CGRectZero];
        _textView.editable = YES;
        _textView.delegate = self;
        _textView.autoresizingMask = UITextAutocorrectionTypeNo;
        _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
        JavascriptSyntaxHighlighter *highlighter = [[[JavascriptSyntaxHighlighter alloc] init] autorelease];
        highlighter.commandLineMode = YES;
        _textView.syntaxHighlighter = highlighter;
        _textView.font = [UIFont fontWithName:@"CourierNewPSMT" size:16];  // TODO only works with this font size
        [self addSubview:_textView];
        
        _resizerView = [[UIView alloc] initWithFrame:CGRectZero];
        _resizerView.backgroundColor = [UIColor grayColor];
        panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeView:)];
        [_resizerView addGestureRecognizer:panRecognizer];
        [panRecognizer release];
        [self addSubview:_resizerView];
        
        _text = [[NSMutableString alloc] init];
        [self appendPromptWithFirstLine:YES];
        
        _buffer = [[NSMutableString alloc] initWithCapacity:200];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillShow:)
                                                     name:UIKeyboardWillShowNotification object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillHide:)
                                                     name:UIKeyboardWillHideNotification object:nil];
        
    }
    return self;
}

- (void)dealloc
{
    [_tapRecognizer.view removeGestureRecognizer:_tapRecognizer];
    [_tapRecognizer release];
    
    self.textView = nil;
    self.titleView = nil;
    
    [_text release];
    [_buffer release];
    
    [_server stop];
    [_server release];
    
    [super dealloc];
}

#pragma mark -

- (void)setVisible:(BOOL)visible {
    if (_visible != visible) {
        _visible = visible;
        if (_visible) { // show
            self.hidden = NO;
            UIView *superview = [[[[UIApplication sharedApplication].windows objectAtIndex:0] rootViewController] view];
            if (!self.superview) {
                [superview addSubview:self];
            }
            [superview bringSubviewToFront:self];
            //            [_textView becomeFirstResponder];
        } else { // hide
            [_textView resignFirstResponder];
            self.hidden = YES;
        }
    }
}

- (void)toggleVisible {
    self.visible = !_visible;
}

- (void)setEnableGesture:(BOOL)enableGesture {
    if (_enableGesture != enableGesture) {
        _enableGesture = enableGesture;
        if (_enableGesture) {
            _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleVisible)];
            _tapRecognizer.numberOfTapsRequired = 3;
            _tapRecognizer.numberOfTouchesRequired = 2;
            UIWindow *window = [[[UIApplication sharedApplication] windows] objectAtIndex:0];
            [window addGestureRecognizer:_tapRecognizer];
        } else {
            [_tapRecognizer.view removeGestureRecognizer:_tapRecognizer];
            [_tapRecognizer release];
            _tapRecognizer = nil;
        }
    }
}

- (void)setFullScreen:(BOOL)fullScreen {
    _fullScreen = fullScreen;
    if (_fullScreen) {
        _orignalFrame = self.frame;
        self.frame = [[[[[UIApplication sharedApplication].windows objectAtIndex:0] rootViewController] view] bounds];
        _resizerView.hidden = YES;
    } else {
        self.frame = _orignalFrame;
        _resizerView.hidden = NO;
    }
}

- (void)toggleFullScreen {
    self.fullScreen = !_fullScreen;
}

- (void)layoutSubviews {
    const int titleViewHeight = 30;
    const int resizerSize = 20;
    
    CGRect frame = self.bounds;
    frame.size.height = titleViewHeight;
    _titleView.frame = frame;
    frame.origin.y = titleViewHeight;
    frame.size.height = self.bounds.size.height - titleViewHeight;
    _textView.frame = frame;
    
    frame.origin.x = self.bounds.size.width - resizerSize;
    frame.origin.y = self.bounds.size.height - resizerSize;
    frame.size.height = resizerSize;
    frame.size.width = resizerSize;
    _resizerView.frame = frame;
}

- (void)moveView:(UIPanGestureRecognizer *)recognizer {
    CGRect frame = self.frame;
    if (_fullScreen) {
        frame = _orignalFrame;
        frame.origin.y = 0;
        self.fullScreen = NO;
    }
    CGPoint delta = [recognizer translationInView:self];
    [recognizer setTranslation:CGPointZero inView:self];
    frame.origin.x += delta.x;
    frame.origin.y += delta.y;
    if (frame.origin.y <= 0) {
        self.fullScreen = YES;
    } else {
        self.frame = frame;
    }
}

- (void)resizeView:(UIPanGestureRecognizer *)recognizer {
    CGPoint delta = [recognizer translationInView:self];
    [recognizer setTranslation:CGPointZero inView:self];
    CGRect frame = self.frame;
    frame.size.width += delta.x;
    frame.size.height += delta.y;
    _orignalFrame = frame;
    self.frame = frame;
}

#pragma mark -

- (void)appendMessage:(NSString *)msg { // TODO what happen when user is typeing?
    if (!msg) return;
    
    NSRange range = [_text rangeOfString:@"> " options:NSBackwardsSearch];
    if (range.length + range.location == [_text length]) {
        [_text deleteCharactersInRange:range];
    }
    if ([_text characterAtIndex:[_text length]-1] != '\n')
        [_text appendString:@"\n"];
    [_text appendString:msg];
    
    [_server sendToAllClients:msg];
    
    [self appendPromptWithFirstLine:YES];
}

- (void)appendPromptWithFirstLine:(BOOL)firstline {
    NSRange range = [_text rangeOfString:@"> " options:NSBackwardsSearch];
    if (range.length + range.location == [_text length]) {
        [_text deleteCharactersInRange:range];
    }
    if (_text.length > 0 && [_text characterAtIndex:[_text length]-1] != '\n') {
        [_text appendString:@"\n"];
    }
    if (firstline)
        [_text appendString:@"> "];
    else
        [_text appendString:@">> "];
    _lastPosition = [_text length];
    _textView.text = _text;
    
    [_server sendToAllClients:@(firstline)];
}

- (void)appendValue:(jsval)value {
    if (!JSVAL_IS_VOID(value)) {
        [self appendMessage:[[JSCore sharedInstance] stringFromValue:value]];
    }
    [self appendPromptWithFirstLine:YES];
}

- (void)clear {
    NSRange range = [_text rangeOfString:@"\n" options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        return;
    }
    NSString *str = [_text substringFromIndex:range.location+1];
    [_text setString:str];
    _textView.text = _text;
}

- (void)handleInputString:(NSString *)string {
    
    [_text appendString:string];
    
    [self handleString:string];
}

- (void)handleString:(NSString *)string {
    if ([string length] == 0)
        return;
    [_buffer appendString:string];
    [_buffer appendString:@"\n"];   // add new line
    jsval rval;
    BOOL completed = [[JSCore sharedInstance] isStringCompleted:_buffer];
    if (completed) {
        BOOL ok = [[JSCore sharedInstance] evaluateString:_buffer outVal:&rval];
        if (ok) {
            [self appendValue:rval];
        } else {
            [self appendMessage:[[JSCore sharedInstance] errorString]];
        }
        [_buffer setString:@""];    // clear buffer
    } else {
        [self appendPromptWithFirstLine:completed];
    }
}

#pragma mark - Keyboard Notification

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary* userInfo = [notification userInfo];
    NSTimeInterval duration = [[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    
    CGRect keyboardFrame = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboardFrame = [self.superview convertRect:keyboardFrame fromView:nil];
    
    CGRect frame = self.frame;
    CGFloat buttom = CGRectGetMaxY(frame);;
    CGFloat keyboardTop = CGRectGetMinY(keyboardFrame);
    if (buttom > keyboardTop) {
        frame.origin.y += keyboardTop - buttom;
        if (frame.origin.y < 0) {
            frame.size.height += frame.origin.y;
            frame.origin.y = 0;
        }
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | curve animations:^{
            self.frame = frame;
        } completion:nil];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.fullScreen = _fullScreen;  // reset the frame size
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    _changeContainNewLine = NO;
    if (range.location < _lastPosition) { // not able to modify fixed text
        if ([text isEqualToString:@"\n"]) {
            [_textView setSelectedRange:NSMakeRange(_text.length, 0)];
        } else {
            [_text appendString:text];
            _textView.text = _text;
        }
        return NO;
    }
    if ([text isEqualToString:@"\n"] && range.location != [_text length]) {
        _textView.text = _text;
        _changeContainNewLine = YES;
        return NO;
    }
    [_text deleteCharactersInRange:range];
    [_text insertString:text atIndex:range.location];
    NSRange newlinepos = [text rangeOfString:@"\n"];
    if (newlinepos.location != NSNotFound)
        _changeContainNewLine = YES;
    return YES;
}

- (void)textViewDidChange:(UITextView *)textView {
    if (_changeContainNewLine) {
        NSString *scriptString = [_text substringFromIndex:_lastPosition];
        [self handleString:scriptString];
    }
}

#pragma mark -

- (void)startServer {
    if (!_server) {
        _server = [[ThoMoServerStub alloc] initWithProtocolIdentifier:@"CocoJSDebug"];
        _server.delegate = self;
    }
    [_server start];
}

- (void)stopServer {
    [_server stop];
    [_server release];
    _server = nil;
}

#pragma mark - ThoMoServerDelegateProtocol

- (void) server:(ThoMoServerStub *)theServer acceptedConnectionFromClient:(NSString *)aClientIdString {
    MILOG(@"New Client: %@", aClientIdString);
}

- (void) server:(ThoMoServerStub *)theServer didReceiveData:(id)theData fromClient:(NSString *)aClientIdString {    
    if ([theData isKindOfClass:[NSString class]]) {
        [self handleInputString:theData];
    } else if ([theData isKindOfClass:[NSDictionary class]]) {
        NSString *documentDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        
        NSDictionary *dict = theData;
        NSString *filename = dict[@"filename"];
        NSString *content = dict[@"content"];
        NSString *filepath = [documentDir stringByAppendingPathComponent:[@"scripts" stringByAppendingPathComponent:filename]];
        
        [[NSFileManager defaultManager] createDirectoryAtPath:[filepath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        MASSERT([content writeToFile:filepath atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"cannot write file to path: %@", filepath);
        
        [JSCore sharedInstance].searchDocumentDirectory = YES;
    }

}

@end
