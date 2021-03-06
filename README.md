# Cupertino.js - Compile Javascript to Cocoa

Cupertino.js is a implementation of the Javascript programming language designed
with Cocoa support as a primary consideration. It includes a static compiler and
_uber dynamic_ runtime that sits atop of the Objective-C runtime. 

It exposes a simple interface to Objective-C: Javascript code _is_ statically
compiled to Objective-C. Objects and functions are derived from NSObject,
strings are NSStrings, numbers are NSNumbers, and message dispatch uses
``objc_msgSend``.

### Declare variables
```javascript
var name = "Steve"
```

### Perform arithmetic
```javascript
var seven = 4 + 3
```

### Loop 
```javascript
for (var i = 99; i > 0; i--){
    console.log(i, " bottles of beer on the wall.") 
}
```

### Objects
```javascript
var tallBoy = {"label" : "Pabst", "size" : 24.0}
```

### Define functions, methods, and properties
```javascript
function Todo(){
    this.message = null

    this.log = function(){
        console.log(this.message)
    }
}
```

### Instantiate functions
```javascript
var beers = new Todo();
beers.message = "Drink some beers"
```

### Call functions 
```javascript
beers.log()
```

### Call Objective-C methods
```javascript
var bottlesOnTheWall = NSString.stringWithFormat("%@ of beer on the wall", 99)
bottlesOnTheWall.lowercaseString()

//short hand
bottlesOnTheWall.lowercaseString
```

### Message send struct
```javascript
//Structs are casted from c structs to Javascript objects
//cast functions take the struct as argument and are named after the type or typedef
var applicationFrame = CGRect(UIScreen.mainScreen.applicationFrame)

console.log("screen height ", applicationFrame.size.height)
```

### Mutate structs
```javascript
applicationFrame.origin.y = 10
```

### Pass structs back to Objective-C types
```javascript
var window = UIWindow.alloc.init
window.frame = applicationFrame
```

### Define class properties
```javascript
Todo.entityName = "Todo"
```

### Full support for 'this'
```javascript
this.fruits = ["apples", "banannas", "oranges"]
```

### Subclass Objective-C classes
```javascript
var TodoListController = UIViewController.extend("TodoListController")
```

### Prototype instance methods
```javascript
TodoListViewController.prototype.numberOfSectionsInTableView = function(tableView){
    return ObjCInt(1)
}
```

### Bind function objects as methods
```javascript
// Define function AppDelegate
function AppDelegate(){}

function DidLaunch(application, options){
    console.log("Launched! ", this)
}

// Implement  -[AppDelegate application:didFinishLaunchingWithOptions:]
// with the body of DidLaunch
//
// 'this' is an instance of AppDelegate
AppDelegate.prototype.applicationDidFinishLaunchingWithOptions = DidLaunch
```

### Import Objective-C
```javascript
//Use the objc_import macro to import objective-c headers
objc_import("TDNetworkRequest.h")

// Interfaces are exported to the global namespace
var request = TDNetworkRequest.get("latest-todos")
reqest.send()

```

## Examples

The examples directory contains a iPhone app that runs in the simulator
and comes complete with a UITableView implementation. 

## State of union:

Although the example app builds and runs in the simulator, Cupertino.js is not
yet production ready.

There several features not yet implemented including:

- Repl
- Standard lib (Strings, arrays, etc): partially done
- Garbage collection: currently it uses manual retain/release/autorelease
- Objective-C super
- [ECMAScript
  5](http://www.ecma-international.org/publications/files/ECMA-ST/Ecma-262.pdf) compliance

[Checkout the 0.1 Beta roadmap here](https://github.com/jerrymarino/cupertinojs/milestones)

## Project setup

Cupertino.js has the following dependencies:

- v8 
- llvm
- libclang
- Xcode
- Foundation & the Objective-C runtime

The install script will set up the development environment

    ./bootstrap.sh

## Installing the compiler

Run the scheme ``cujs`` in release configuration

The compiler ``cujs`` will be installed to /usr/local/bin

## Running the example "Todoie"

Once the compiler is installed, the example should run in the simulator.

[For more check the Wiki](https://github.com/jerrymarino/cupertinojs/wiki)


