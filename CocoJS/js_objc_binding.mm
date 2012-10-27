//
//  js_objc_binding.mm
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-23.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "js_objc_binding.h"

#import <objc/runtime.h>

#import "js_objc_helper.h"

static int internalOperation = 0;

static JSFunction *createSelectorFunc;
static JSFunction *callSuperFunc;
static JSFunction *extendFunc;

static JSBool objc_property_op(JSContext *cx, JSHandleObject obj, JSHandleId jid, jsval *vp) {
    if (internalOperation) return JS_TRUE;
    MDLOG(@"property change blocked: %s", JS_EncodeString(cx, JSID_TO_STRING(jid)));
    *vp = JSVAL_VOID;
    return JS_FALSE;
}

static JSBool objc_property_setter(JSContext *cx, JSHandleObject obj, JSHandleId jid, JSBool strict, jsval *vp) {
    return objc_property_op(cx, obj, jid, vp);
}

static JSBool resolve_objc_selector(JSContext *cx, JSHandleObject obj, JSHandleId jid) {
    if (internalOperation) return JS_TRUE;
    
    JSString *jsname = JSID_TO_STRING(jid);
    const char *selname = JS_EncodeString(cx, jsname);
    
    JSObject *proto;
    proto = JS_GetPrototype(obj);
    JSBool found;
    MASSERT_SOFT(JS_HasPropertyById(cx, proto, jid, &found));
    if (found) {
        return JS_TRUE;
    }
    
    jsval rval;
    jsval arg = STRING_TO_JSVAL(jsname);
    JS_CallFunction(cx, obj, createSelectorFunc, 1, &arg, &rval);
    
    internalOperation++;
    JS_SetProperty(cx, obj, selname, &rval);
    internalOperation--;
    
    return JS_TRUE;
}

static JSClass js_objc_prototype_class = { "ObjCInstancePrototype", 0, objc_property_op, objc_property_op, JS_PropertyStub, objc_property_setter, JS_EnumerateStub, resolve_objc_selector, JS_ConvertStub, NULL, JSCLASS_NO_OPTIONAL_MEMBERS };

static JSBool js_objc_lookup_static_method(JSContext *cx, uint32_t argc, jsval *vp) {
    
    jsval *argvp = JS_ARGV(cx, vp);
    
    JSObject *thisobj = JS_THIS_OBJECT(cx, vp);
    jsval nameval;
    MASSERT_SOFT(JS_GetProperty(cx, thisobj, "name", &nameval));
    Class cls = NSClassFromString(@(jsval_to_string(cx, nameval)));
    
    if (!JSVAL_IS_STRING(argvp[0])) return JS_FALSE;
    const char *selname = jsval_to_string(cx, argvp[0]);
    
    unsigned len;
    JSObject *argv = JSVAL_TO_OBJECT(argvp[1]);
    MASSERT_SOFT(JS_GetArrayLength(cx, argv, &len));
    
    SEL sel = find_selector(cls, selname, len);
    if (!sel) {
        MILOG(@"cannot find selector '%s' for class %@", selname, cls);
        return JS_FALSE;
    }
    
    JSBool ok = JS_TRUE;
    NSMethodSignature *signature = [cls methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:cls];
    [invocation setSelector:sel];
    for (int i = 0; i < len; i++) {
        jsval arg;
        MASSERT_SOFT(JS_GetElement(cx, argv, i, &arg));
        ok &= set_argument(cx, invocation, i, arg);
    }
    if (!ok) return JS_FALSE;
    [invocation invoke];
    
    jsval rval;
    void *retval = malloc([signature methodReturnLength]);
    [invocation getReturnValue:retval];
    
    ok &= jsval_from_type(cx, [signature methodReturnType], retval, &rval);
    free(retval);
    
    JS_SET_RVAL(cx, vp, rval);
    return JS_TRUE;
}

static jsval create_objc_instance_class(JSContext *cx, const char *clsname) {
    jsval val;
    const char *script = [[NSString stringWithFormat:@"(function(){function %s () {objc._alloc(this)};%s.toString = function(){return '%s'}; return %s;})()", clsname, clsname, clsname, clsname] UTF8String];
    MASSERT_SOFT(JS_EvaluateScript(cx, JS_GetGlobalObject(cx), script, strlen(script), NULL, 0, &val));
    
    JSObject *obj = JSVAL_TO_OBJECT(val);
    
    JSObject *proto = JS_NewObject(cx, &js_objc_prototype_class, NULL, NULL);
    jsval protoval = OBJECT_TO_JSVAL(proto);
    
    internalOperation++;
    jsval objcval;
    JS_GetProperty(cx, JS_GetGlobalObject(cx), "objc", &objcval);
    JS_SetProperty(cx, JSVAL_TO_OBJECT(objcval), clsname, &val);
    
    
    JS_SetProperty(cx, obj, "prototype", &protoval);   // class.prototype = proto
    JS_SetProperty(cx, proto, "constructor", &val);     // class.prototype.constructor = class
    internalOperation--;
    
    int op = internalOperation;
    internalOperation = 0;
    jsval descval;
    JS_GetProperty(cx, proto, "description", &descval);
    internalOperation = op;
    
    internalOperation++;
    JS_SetProperty(cx, proto, "toString", &descval);  // proto.toString = proto.description
    jsval callsuperval = OBJECT_TO_JSVAL(JS_GetFunctionObject(callSuperFunc));
    JS_SetProperty(cx, proto, "_super", &callsuperval);
    associate_object(cx, proto, objc_getClass(clsname));
    
    JSObject *map = JS_NewObject(cx, NULL, NULL, NULL);
    jsval mapval = OBJECT_TO_JSVAL(map);
    JS_SetProperty(cx, proto, "_selectorMap", &mapval);
    
    jsval zero = JSVAL_ZERO;
    JS_SetProperty(cx, proto, "_superCount", &zero);
    internalOperation--;
    
    jsval extendval = OBJECT_TO_JSVAL(JS_GetFunctionObject(extendFunc));
    JS_SetProperty(cx, obj, "extend", &extendval);
    JS_DefineFunction(cx, obj, "__noSuchMethod__", js_objc_lookup_static_method, 2, JSPROP_READONLY | JSPROP_PERMANENT );       // for static method lookup
    
    return val;
}

static JSBool resolve_objc_class(JSContext *cx, JSHandleObject obj, JSHandleId jid) {
    internalOperation++;
    
    JSString *jsname = JSID_TO_STRING(jid);
    const char *clsname =JS_EncodeString(cx, jsname);
    Class cls = objc_getClass(clsname);
    if (cls) {
        create_objc_instance_class(cx, clsname);
    }
    
    internalOperation--;
    return JS_TRUE;
}

static JSClass js_objc_class = { "ObjC", 0, objc_property_op, objc_property_op, JS_PropertyStub, objc_property_setter, JS_EnumerateStub, resolve_objc_class, JS_ConvertStub, NULL, JSCLASS_NO_OPTIONAL_MEMBERS };

static JSBool js_objc_perform_selector(JSContext *cx, uint32_t argc, jsval *vp) {
    if (argc < 2) return JS_FALSE;
    
    jsval *argvp = JS_ARGV(cx, vp);
    if (JSVAL_IS_PRIMITIVE(argvp[0])) return JS_FALSE;
    
    id nsobj = jsobject_to_objc(cx, JSVAL_TO_OBJECT(argvp[0]));
    if (!nsobj) return JS_FALSE;
    
    if (!JSVAL_IS_STRING(argvp[1])) return JS_FALSE;
    const char *selname = jsval_to_string(cx, argvp[1]);
    
    jsval selmap;
    JS_GetProperty(cx, JSVAL_TO_OBJECT(argvp[0]), "_selectorMap", &selmap);
    JSObject *selmapobj = JSVAL_TO_OBJECT(selmap);
    
    argc -= 2;
    argvp += 2;
    
    SEL sel;
    
    jsval selval;
    JS_GetProperty(cx, selmapobj, selname, &selval);
    if (JSVAL_IS_STRING(selval)) {
        const char *trueselname = jsval_to_string(cx, selval);
        sel = sel_getUid(trueselname);
    } else {
        sel = find_selector(nsobj, selname, argc);
        if (sel) {
            selval = STRING_TO_JSVAL(JS_NewStringCopyZ(cx, sel_getName(sel)));
            JS_SetProperty(cx, selmapobj, selname, &selval);
            selval = STRING_TO_JSVAL(JS_NewStringCopyZ(cx, selname));
            JS_SetProperty(cx, selmapobj, sel_getName(sel), &selval);
        }
    }
    
    if (!sel) {
        MILOG(@"cannot find selector '%s' for object %@", selname, nsobj);
        return JS_FALSE;
    }
    
    JSBool ok = JS_TRUE;
    NSMethodSignature *signature = [nsobj methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:nsobj];
    [invocation setSelector:sel];
    for (int i = 0; i < argc; i++) {
        ok &= set_argument(cx, invocation, i, argvp[i]);
    }
    if (!ok) return JS_FALSE;
    [invocation invoke];
    
    jsval rval;
    int retlen = [signature methodReturnLength];
    if (retlen != 0) {
        void *retval = malloc([signature methodReturnLength]);
        [invocation getReturnValue:retval];
        
        ok &= jsval_from_type(cx, [signature methodReturnType], retval, &rval);
        free(retval);
        
        JS_SET_RVAL(cx, vp, rval);
    } else {
        JS_SET_RVAL(cx, vp, JSVAL_VOID);
    }
    
    
    return ok;
}

static JSBool js_objc_alloc(JSContext *cx, uint32_t argc, jsval *vp) {
    if (argc < 1) return JS_FALSE;
    jsval *argvp = JS_ARGV(cx, vp);
    JSObject *obj = JSVAL_TO_OBJECT(argvp[0]);
    jsval cstrval, nameval;
    MASSERT_SOFT(JS_GetProperty(cx, obj, "constructor", &cstrval));
    MASSERT_SOFT(JS_GetProperty(cx, JSVAL_TO_OBJECT(cstrval), "name", &nameval));
    Class cls = NSClassFromString(@(jsval_to_string(cx, nameval)));
    id nsobj = [[cls alloc] autorelease];
    
    internalOperation++;
    
    associate_object(cx, obj, nsobj);   // this will retain the object
    
    internalOperation--;
    
    JS_SET_RVAL(cx, vp, JSVAL_VOID);
    return JS_TRUE;
}

static JSBool js_objc_create_class(JSContext *cx, uint32_t argc, jsval *vp) {
    jsval *argvp = JS_ARGV(cx, vp);
    
    const char *superclsname = jsval_to_string(cx, argvp[0]);
    const char *newclsname = jsval_to_string(cx, argvp[1]);

    Class supercls = objc_getClass(superclsname);
    Class newcls = objc_allocateClassPair(supercls, newclsname, 0);
    objc_registerClassPair(newcls);
    
    if (!newcls) {
        MWLOG(@"cannot create new class. super class: %s, new class: %s", superclsname, newclsname);
        return JS_FALSE;
    }
    
    if (argc >= 3) {
        jsval pval = argvp[2];
        if (JSVAL_IS_STRING(pval)) {
            const char *pname = jsval_to_string(cx, pval);
            Protocol *p = objc_getProtocol(pname);
            if (!class_addProtocol(newcls, p))
                MILOG(@"fail to add protocol (%s) to class (%s)", pname, newclsname);
        } else if (!JSVAL_IS_PRIMITIVE(pval)) {
            JSObject *protocols = JSVAL_TO_OBJECT(argvp[2]);
            if (protocols) {
                unsigned len;
                MASSERT_SOFT(JS_GetArrayLength(cx, protocols, &len));
                for (unsigned i = 0; i < len; i++) {
                    jsval protocol;
                    JS_GetElement(cx, protocols, i, &protocol);
                    const char *pname = jsval_to_string(cx, protocol);
                    Protocol *p = objc_getProtocol(pname);
                    if (!class_addProtocol(newcls, p))
                        MILOG(@"fail to add protocol (%s) to class (%s)", pname, newclsname);
                }
            }
        }
        
    }
    
    jsval rval = create_objc_instance_class(cx, newclsname);
    
    JS_SET_RVAL(cx, vp, rval);
    return JS_TRUE;
}

static JSBool js_objc_add_method(JSContext *cx, uint32_t argc, jsval *vp) {
    jsval *argvp = JS_ARGV(cx, vp);
    
    const char *clsname = jsval_to_string(cx, argvp[0]);
    const char *selname = jsval_to_string(cx, argvp[1]);
    jsval protoval = argvp[2];
    jsval methodval = argvp[3];
    
    internalOperation++;
    JS_SetProperty(cx, JSVAL_TO_OBJECT(protoval), selname, &methodval);
    internalOperation--;
    
    if (JSVAL_IS_PRIMITIVE(methodval)) {
        JS_SET_RVAL(cx, vp, JSVAL_FALSE);
        return JS_TRUE;
    }
    
    JSObject *methodobj = JSVAL_TO_OBJECT(methodval);
    
    if (!JS_ObjectIsFunction(cx, methodobj)) {
        JS_SET_RVAL(cx, vp, JSVAL_FALSE);
        return JS_TRUE;
    }
    
    JS_SetProperty(cx, methodobj, "_name", &argvp[1]);
    
    jsval lenval;
    JS_GetProperty(cx, methodobj, "length", &lenval);
    
    int len = JSVAL_TO_INT(lenval);
    Class cls = objc_getClass(clsname);
    
    char *typedesc;
    char *rettype;
    SEL sel = find_selector_class(cls, selname, len, &typedesc, &rettype);
    if (!sel) {
        
        JS_SET_RVAL(cx, vp, JSVAL_FALSE);
        return JS_TRUE;
    }
    
    IMP imp = get_imp(rettype);
    MASSERT_SOFT(class_addMethod(cls, sel, imp, typedesc));
    
    free(rettype);
    
    JS_SET_RVAL(cx, vp, JSVAL_TRUE);
    return JS_TRUE;
}

static JSBool js_objc_native_super(JSContext *cx, uint32_t argc, jsval *vp) {
    jsval *argvp = JS_ARGV(cx, vp);
    id nsobj = jsobject_to_objc(cx, JSVAL_TO_OBJECT(argvp[0]));
    const char *selname = jsval_to_string(cx, argvp[1]);
    
    jsval selmap;
    JS_GetProperty(cx, JSVAL_TO_OBJECT(argvp[0]), "_selectorMap", &selmap);
    JSObject *selmapobj = JSVAL_TO_OBJECT(selmap);
    
    JSObject *argobj = JSVAL_TO_OBJECT(argvp[2]);
    unsigned len;
    JS_GetArrayLength(cx, argobj, &len);
    
    SEL sel;
    
    jsval selval;
    JS_GetProperty(cx, selmapobj, selname, &selval);
    if (JSVAL_IS_STRING(selval)) {
        const char *trueselname = jsval_to_string(cx, selval);
        sel = sel_getUid(trueselname);
    } else {
        sel = find_selector(nsobj, selname, len);
        if (sel) {
            selval = STRING_TO_JSVAL(JS_NewStringCopyZ(cx, sel_getName(sel)));
            JS_SetProperty(cx, selmapobj, selname, &selval);
            selval = STRING_TO_JSVAL(JS_NewStringCopyZ(cx, selname));
            JS_SetProperty(cx, selmapobj, sel_getName(sel), &selval);
        }
    }
    
    MASSERT(sel, @"selector not found: %s-%d", selname, len);
    
    Class selfcls = [nsobj class];
    Class supercls = [selfcls superclass];
    Method selfmethod = class_getInstanceMethod(selfcls, sel);
    Method supermethod = class_getInstanceMethod(supercls, sel);
    IMP selfimp = method_getImplementation(selfmethod);
    IMP superimp = method_getImplementation(supermethod);
    
    while (selfimp == superimp) {   // in case super is also implemented in JS
        supercls = [supercls superclass];
        supermethod = class_getInstanceMethod(supercls, sel);
        superimp = method_getImplementation(supermethod);
    }
    
    method_setImplementation(selfmethod, superimp); // change IMP to call super
    
    JSBool ok = JS_TRUE;
    NSMethodSignature *signature = [nsobj methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:nsobj];
    [invocation setSelector:sel];
    for (int i = 0; i < len; i++) {
        jsval arg;
        JS_GetElement(cx, argobj, i, &arg);
        ok &= set_argument(cx, invocation, i, arg);
    }
    if (!ok) return JS_FALSE;
    [invocation invoke];
    
    jsval rval;
    void *retval = malloc([signature methodReturnLength]);
    [invocation getReturnValue:retval];
    
    ok &= jsval_from_type(cx, [signature methodReturnType], retval, &rval);
    free(retval);
    
    method_setImplementation(selfmethod, selfimp);
    
    JS_SET_RVAL(cx, vp, rval);
    
    return ok;
}

static JSBool js_objc_gc(JSContext *cx, uint32_t argc, jsval *vp) {
    JS_GC(JS_GetRuntime(cx));
    JS_SET_RVAL(cx, vp, JSVAL_VOID);
    return JS_TRUE;
}

static JSBool js_log(JSContext *cx, uint32_t argc, jsval *vp) {
    jsval *argvp = JS_ARGV(cx, vp);
    
    if (argc == 0) {
        printf("\n");
    } else {
        NSMutableString *str = [NSMutableString string];
        for (int i = 0; i < argc; i++) {
            NSString *value = jsval_to_NSString(cx, argvp[i]);
            [str appendString:value];
            if (i != argc-1) {
                [str appendString:@", "];
            }
        }
        NSLog(@"%@", str);
    }
    
    JS_SET_RVAL(cx, vp, JSVAL_VOID);
    return JS_TRUE;
}

void js_objc_init(JSContext *cx, JSObject *global) {
    JSObject *obj = JS_NewObject(cx, &js_objc_class, NULL, NULL);
    jsval objval = OBJECT_TO_JSVAL(obj);
    JS_SetProperty(cx, global, "objc", &objval);
    
    internalOperation++;
    
    JS_DefineFunction(cx, global, "log", js_log, 1, JSPROP_READONLY | JSPROP_PERMANENT | JSPROP_ENUMERATE );
    
    JS_DefineFunction(cx, obj, "_perform", js_objc_perform_selector, 2, JSPROP_READONLY | JSPROP_PERMANENT );
    JS_DefineFunction(cx, obj, "_alloc", js_objc_alloc, 1, JSPROP_READONLY | JSPROP_PERMANENT );
    JS_DefineFunction(cx, obj, "_createClass", js_objc_create_class, 3, JSPROP_READONLY | JSPROP_PERMANENT );
    JS_DefineFunction(cx, obj, "_addMethod", js_objc_add_method, 4, JSPROP_READONLY | JSPROP_PERMANENT );
    JS_DefineFunction(cx, obj, "_nativeSuper", js_objc_native_super, 3, JSPROP_READONLY | JSPROP_PERMANENT );
    
    JS_DefineFunction(cx, obj, "gc", js_objc_gc, 0, JSPROP_READONLY | JSPROP_PERMANENT | JSPROP_ENUMERATE );
    
    const char *selargname = "sel";
    const char *selfuncbody =
    "var f = function() {" "\n"
    "   [].splice.call(arguments, 0, 0, this, sel);" "\n"
    "   return objc._perform.apply(null, arguments);" "\n"
    "};" "\n"
    "f._name = sel;" "\n"
    "f._native = true;" "\n"
    "return f;";
    createSelectorFunc = JS_CompileFunction(cx, obj, "_selector", 1, &selargname, selfuncbody, strlen(selfuncbody), "_selector", 1);
    
    const char *superfuncbody =
    "var caller = arguments.callee.caller;" "\n"
    "var name = caller._name || caller.name;" "\n"
    "this._superCount++;" "\n"
    "var proto = this.__proto__;" "\n"
    "for (var i = 0; i < this._superCount; i++) {" "\n"
    "proto = proto.__proto__;" "\n"
    "}" "\n"
    "var superfunc = proto[name];" "\n"
//    "log(superfunc, name, proto, this._superCount);" "\n"
    "if (superfunc._native) {" "\n"
    "   objc._nativeSuper(this, name, arguments);" "\n"
    "} else {" "\n"
    "   superfunc.apply(this, arguments);" "\n"
    "}" "\n"
    "this._superCount--;";
    callSuperFunc = JS_CompileFunction(cx, obj, "_super", 0, NULL, superfuncbody, strlen(superfuncbody), "_super", 1);
    
    const char *extendargname[] = {"clsname", "protocols", "prop"};
    const char *extendfuncbody =
    "var newcls = objc._createClass(this.name, clsname, protocols);" "\n"
    "var prototype = newcls.prototype;" "\n"
    "for (var name in prop) {" "\n"
    "   objc._addMethod(newcls.name, name, prototype, prop[name]);" "\n"
    "}" "\n"
    "prototype.__proto__ = this.prototype;" "\n"
    "return newcls;";
    extendFunc = JS_CompileFunction(cx, obj, "_extend", 3, extendargname, extendfuncbody, strlen(extendfuncbody), "_extend", 1);
    
    internalOperation--;
}