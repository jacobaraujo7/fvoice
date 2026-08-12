#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs the block, converting any Objective-C NSException (which Swift cannot
/// catch and which would otherwise abort the process) into an NSError.
BOOL FVCatchObjCException(void (NS_NOESCAPE ^block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
