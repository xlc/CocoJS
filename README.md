CocoJS
======

Brief
-----
JavaScript binding for Objective-C. Everything is done automatically. No glue code required.

Common type are also automatically converted between JS and ObjC. e.g. js string can be used anywhere that NSString is expected

Support subclassing ObjC class from JS.

[SpiderMonkey](https://developer.mozilla.org/en-US/docs/SpiderMonkey) is used to interpreted JS code. This [fork](https://github.com/funkaster/spidermonkey) is used to compile it to static lib that can run on iOS platform.



Example
-------

    // everything is under namespace objc
    NSObject = objc.NSObject
    UIView = objc.UIView

    var o;
    // to create an object
    // in ObjC way
    o = NSObject.alloc().init();  // o = [[NSObject alloc] init];
    
    // in js way
    o = new NSObject;   // o = [NSObject alloc];
    // but remember to call init or other constructor
    o.init();           // [o init];

    // call a method
    var desc = o.description() // desc = [o description];
    log(desc) // NSLog(@"%@", desc); -- <NSObject: 0x75789e0>
    // NSString is also automatically converted into js string
    typeof s; // string
    // NSArray and NSNumber are also automatically converted
    var list = objc.NSArray.arrayWithArray([1,2,3])
    log(list);  // 1,2,3
    
    var view = UIView.alloc().init();
    // no property available yet, use setter and getter
    view.setBackgroundColor(objc.UIColor.redColor()); // [view setBackgroundColor:[UIColor redColor]];
    log(view.backgroundColor());  // NSLog(@"%@", [view backgroundColor]); -- UIDeviceRGBColorSpace 1 0 0 1
    
    
    // to subclass an ObjC class
    Parent = NSObject.extend('Parent', null, {
        init: function() {  // this method override `init` from NSObject
            this._super();  // [super init]; -- call `init` from NSObject
            log('parent');
        }, 
        test: function() {  // this is a normal js function because it does not override any existing objc method
            log('parent test');
        },
        t: 1
    });
    
    // subclass from ObjC class that created in JS
    Child = Parent.extend('Child', null, {
        init: function() {
            this._super();
            log('Child');
        },
        test: function() {
            log('child test');
            this._super();    //Parent.prototype.test.apply(this, arguments);
        },
    });
    
    