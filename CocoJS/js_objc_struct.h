//
//  js_objc_struct.h
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-28.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "jsapi.h"

// supported structs: CGPoint, CGSize, CGRect, CGAffineTransform, NSRange, UIEdgeInsets

JSBool jsval_from_struct(JSContext *cx, const char *encode, void *value, jsval *outval);
JSBool jsval_to_struct(JSContext *cx, jsval val, const char *encode, void **outval, uint32_t *outsize);
