//
//  CYSampleHandlerClientSocketManager.h
//  CYReplayKit
//
//  Created by 李伟 on 2024/6/27.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef void(^GetBufferBlock) (CMSampleBufferRef sampleBuffer);
typedef void(^GetAudioBufferBlock) (CMSampleBufferRef sampleBuffer);
typedef void(^GetAudioPCMBufferBlock) (AVAudioPCMBuffer *pcmBuffer);
typedef void(^GetAudioDataBufferBlock) (NSData *dataBuffer, CMAudioFormatDescriptionRef audioFormatDescription);

@interface CYSampleHandlerClientSocketManager : NSObject
+ (CYSampleHandlerClientSocketManager *)sharedManager;
- (void)stopSocket;
- (void)setupVideoSocket;
- (void)setupAudioSocket;
//- (void)setupSocket;
@property(nonatomic, copy) GetBufferBlock getBufferBlock;
@property(nonatomic, copy) GetAudioBufferBlock getAudioBufferBlock;
@property(nonatomic, copy) GetAudioPCMBufferBlock GetAudioPCMBufferBlock;
@property(nonatomic, copy) GetAudioDataBufferBlock getAudioDataBufferBlock;

@end

NS_ASSUME_NONNULL_END
