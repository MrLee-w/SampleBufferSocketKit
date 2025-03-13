//
//  CYSampleHandlerSocketManager.h
//  CYReplayKit
//
//  Created by 李伟 on 2024/6/27.
//

#import <Foundation/Foundation.h>
#import <ReplayKit/ReplayKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CYSampleHandlerSocketManager : NSObject
+ (CYSampleHandlerSocketManager *)sharedManager;
//- (void)setUpSocket;
- (void)setupVideoSocket;
- (void)setupAudioSocket;
- (void)socketDelloc;
- (void)sendVideoBufferToHostApp:(CMSampleBufferRef)sampleBuffer;
- (void)sendAudioBufferToHostApp:(CMSampleBufferRef)sampleBuffer;

//- (long)getCurUsedMemory;
@end

NS_ASSUME_NONNULL_END
