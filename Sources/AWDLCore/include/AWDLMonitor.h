//
//  AWDLMonitor.h
//  AWDLCore
//
//  Derived from AWDLControl by James Howard (MIT License).
//  https://github.com/james-howard/AWDLControl
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AWDLInterfaceState) {
    AWDLInterfaceStateMissing = -1,
    AWDLInterfaceStateDown = 0,
    AWDLInterfaceStateUp = 1,
};

/*! Tracks the state of the AWDL interface and brings it up or down as needed. */
@interface AWDLMonitor : NSObject

//! YES lets macOS manage awdl0 as usual; NO holds it down.
@property (nonatomic) BOOL awdlEnabled;

//! Current flags of awdl0, read directly from the kernel.
+ (AWDLInterfaceState)currentInterfaceState;

//! Stop monitoring AWDL state
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
