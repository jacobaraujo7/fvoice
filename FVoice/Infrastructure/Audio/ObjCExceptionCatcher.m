#import "ObjCExceptionCatcher.h"

BOOL FVCatchObjCException(void (NS_NOESCAPE ^block)(void), NSError **error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *message = exception.reason ?: exception.name;
            *error = [NSError errorWithDomain:@"com.jacobmoura.fvoice.objc-exception"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey : message}];
        }
        return NO;
    }
}
