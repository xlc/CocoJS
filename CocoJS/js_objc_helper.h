//
//  js_objc_helper.h
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-22.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "jsapi.h"

NSString *jsval_to_NSString(JSContext *cx, jsval val);
NSString *jsval_to_source(JSContext *cx, jsval val);

const char *jsval_to_string(JSContext *cx, jsval val);

double jsval_to_number(jsval val);
int jsval_to_int_number(jsval val);
id jsval_to_objc(JSContext *cx, jsval val);

id jsobject_to_objc(JSContext *cx, JSObject *obj);
// create jsobject if not already associated
jsval jsval_from_objc(JSContext *cx, id object);
// get the associated jsobject
JSObject *jsobject_from_objc(id object);

void associate_object(JSContext *cx, JSObject *jsobj, id nsobj);
void remove_associated_object(JSObject *jsobj);

SEL find_selector(id obj, const char *selname, int argc);
SEL find_selector_class(Class cls, const char *selname, int argc, char **typedesc, char **rettype);

JSBool set_argument(JSContext *cx, NSInvocation *invocation, int idx, jsval val);

JSBool jsval_to_type(JSContext *cx, jsval val, const char *encode, void **outval, uint32_t *outsize);
JSBool jsval_from_type(JSContext *cx, const char *encode, void *value, jsval *outval);

IMP get_imp(char *rettype);

JSBool invoke_objc_method(JSContext *cx, NSInvocation *invocation, jsval *rval);