//
//  CYSampleHandlerClientSocketManager.m
//  CYReplayKit
//
//  Created by 李伟 on 2024/6/27.
//

#import "CYSampleHandlerClientSocketManager.h"
#import <ReplayKit/ReplayKit.h>
#import "NTESYUVConverter.h"
#import "NTESI420Frame.h"
#import "GCDAsyncSocket.h"
#import "NTESSocketPacket.h"
#import "NTESTPCircularBuffer.h"
@interface CYSampleHandlerClientSocketManager()<GCDAsyncSocketDelegate>
@property (nonatomic, strong) GCDAsyncSocket *videoSocket;
@property (nonatomic, strong) GCDAsyncSocket *audioSocket;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableArray *sockets;
@property (nonatomic, assign) NTESTPCircularBuffer *recvBuffer;
@property(nonatomic, strong) NSString *testText;
// 音频格式描述
@property(nonatomic, assign) CMAudioFormatDescriptionRef formatDescription;

@end

@implementation CYSampleHandlerClientSocketManager
+ (CYSampleHandlerClientSocketManager *)sharedManager{
    static CYSampleHandlerClientSocketManager *shareInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareInstance = [[self alloc] init];
    });
    return shareInstance;
}
#pragma mark - 屏幕共享

- (void)stopSocket
{
    if (_videoSocket) {
        [_videoSocket disconnect];
        _videoSocket = nil;
        [_sockets removeAllObjects];
        NTESTPCircularBufferCleanup(_recvBuffer);
    }
    if (_audioSocket) {
        [_audioSocket disconnect];
        _audioSocket = nil;
        [_sockets removeAllObjects];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSUserDefaultsDidChangeNotification object:nil];

}
/*
- (void)setupSocket
{
    self.sockets = [NSMutableArray array];
    _recvBuffer = (NTESTPCircularBuffer *)malloc(sizeof(NTESTPCircularBuffer)); // 需要释放
    NTESTPCircularBufferInit(_recvBuffer, kRecvBufferMaxSize);
//    self.queue = dispatch_queue_create("com.netease.edu.rp.server", DISPATCH_QUEUE_SERIAL);
    self.queue = dispatch_get_main_queue();
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.queue];
    self.socket.IPv6Enabled = NO;
    NSError *error;
    //    [self.socket acceptOnUrl:[NSURL fileURLWithPath:serverURL] error:&error];
    [self.socket acceptOnPort:8999 error:&error];
    [self.socket readDataWithTimeout:-1 tag:0];
    NSLog(@"%@", error);
    NSNotificationCenter *center =[NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(defaultsChanged:)
                   name:NSUserDefaultsDidChangeNotification
                 object:nil];
}
*/
-(void)setupVideoSocket {
    self.sockets = [NSMutableArray array];
    _recvBuffer = (NTESTPCircularBuffer *)malloc(sizeof(NTESTPCircularBuffer)); // 需要释放
    NTESTPCircularBufferInit(_recvBuffer, kRecvBufferMaxSize);
//    self.queue = dispatch_queue_create("com.netease.edu.rp.server", DISPATCH_QUEUE_SERIAL);
    self.queue = dispatch_get_main_queue();
    self.videoSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.queue];
    self.videoSocket.IPv6Enabled = NO;
    NSError *error;
    //    [self.socket acceptOnUrl:[NSURL fileURLWithPath:serverURL] error:&error];
    [self.videoSocket acceptOnPort:8999 error:&error];
    [self.videoSocket readDataWithTimeout:-1 tag:0];
    NSLog(@"%@", error);
    NSNotificationCenter *center =[NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(defaultsChanged:)
                   name:NSUserDefaultsDidChangeNotification
                 object:nil];
}

-(void)setupAudioSocket {
    self.sockets = [NSMutableArray array];
    self.queue = dispatch_get_main_queue();
    self.audioSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.queue];
    self.audioSocket.IPv6Enabled = NO;
    NSError *error;
    [self.audioSocket acceptOnPort:8999 error:&error];
    [self.audioSocket readDataWithTimeout:-1 tag:0];
    NSLog(@"%@", error);
//    NSNotificationCenter *center =[NSNotificationCenter defaultCenter];
//    [center addObserver:self
//               selector:@selector(defaultsChanged:)
//                   name:NSUserDefaultsDidChangeNotification
//                 object:nil];
}
#pragma mark - GCDAsyncSocketDelegate
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(nullable NSError *)err
{
    if (self.videoSocket) {
        NTESTPCircularBufferClear(self.recvBuffer);
    }
    [self.sockets removeObject:sock];
}

- (void)socketDidCloseReadStream:(GCDAsyncSocket *)sock
{
    if (self.videoSocket) {
        NTESTPCircularBufferClear(self.recvBuffer);
    }
    [self.sockets removeObject:sock];
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    if (self.videoSocket) {
        NTESTPCircularBufferClear(self.recvBuffer);
        [newSocket readDataWithTimeout:-1 tag:0];
    }
    if (self.audioSocket) {
        [newSocket readDataWithTimeout:-1 tag:0];
    }
    [self.sockets addObject:newSocket];
    
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    if (self.videoSocket){
        [self handleVideoData:data];
    }
    if (self.audioSocket) {
        [self handleAudioData:data];
    }
    [sock readDataWithTimeout:-1 tag:tag];
}

- (void)handleVideoData:(NSData *)data {
    static uint64_t currenDataSize = 0;
    static uint64_t targeDataSize = 0;

    BOOL isHeader = NO;
    if (data.length == sizeof(NTESPacketHead)) { // 检查是不是帧头
        NTESPacketHead *header = (NTESPacketHead *)data.bytes;
        if (header->version == 1 && header->command_id == 1 && header->service_id == 1) {
            isHeader = YES;
            targeDataSize = header->data_len;
            currenDataSize = 0;
        }
    } else {
        currenDataSize += data.length;
    }
    
    if (isHeader) { // a.接收到新的帧头，需要先把原来的缓存处理或者清空
        [self handleRecvBuffer];
        NTESTPCircularBufferProduceBytes(self.recvBuffer,
                                         data.bytes,
                                         (int32_t)data.length);
    } else if (currenDataSize >= targeDataSize
               && currenDataSize != -1) { // b.加上新来的数据后缓存中已经满足一帧
        NTESTPCircularBufferProduceBytes(self.recvBuffer,
                                         data.bytes,
                                         (int32_t)data.length);
        currenDataSize = -1;
        [self handleRecvBuffer];
    } else { // c.不够一帧，只添加不处理
        NTESTPCircularBufferProduceBytes(self.recvBuffer,
                                         data.bytes,
                                         (int32_t)data.length);
    }
}


- (void)handleAudioData:(NSData *)mergedData {
    if (!mergedData) {
        return;
    }
    // 分离数据
    NSData *formatDescriptionData = nil;
    NSData *audioData = nil;
    [self parseMergedData:mergedData
    formatDescriptionData:&formatDescriptionData
                audioData:&audioData];
    
    if (!formatDescriptionData || !audioData) {
        return;
    }
    
    // 恢复格式描述
    CMAudioFormatDescriptionRef formatDescription = [self deserializeAudioFormatDescription:formatDescriptionData];
    if (!formatDescription) {
        return;
    }
    
    // 创建 CMSampleBuffer
    CMSampleBufferRef sampleBuffer = [self createSampleBufferWithAudioData:audioData formatDescription:formatDescription];
    
    
    if (self.getAudioBufferBlock) {
        self.getAudioBufferBlock(sampleBuffer);
    }
//    
//    if (self.getAudioDataBufferBlock) {
//        self.getAudioDataBufferBlock(audioData, formatDescription);
//    }
//    
    // 释放格式描述
    CFRelease(formatDescription);
}
// 分离NSData
- (void)parseMergedData:(NSData *)mergedData
    formatDescriptionData:(NSData **)formatDescriptionData
                audioData:(NSData **)audioData {
    if (!mergedData) {
        return;
    }
    
    // 假设格式描述的长度为 AudioStreamBasicDescription 的大小
    NSUInteger formatDescriptionLength = sizeof(AudioStreamBasicDescription);
    if (mergedData.length < formatDescriptionLength) {
        return;
    }
    
    // 拆分数据
    *formatDescriptionData = [mergedData subdataWithRange:NSMakeRange(0, formatDescriptionLength)];
    *audioData = [mergedData subdataWithRange:NSMakeRange(formatDescriptionLength, mergedData.length - formatDescriptionLength)];
}
- (CMAudioFormatDescriptionRef)deserializeAudioFormatDescription:(NSData *)formatDescriptionData {
    if (!formatDescriptionData || formatDescriptionData.length != sizeof(AudioStreamBasicDescription)) {
        return NULL;
    }
    
    // 从 NSData 恢复 AudioStreamBasicDescription
    AudioStreamBasicDescription asbd;
    [formatDescriptionData getBytes:&asbd length:sizeof(asbd)];
    
    // 创建 CMAudioFormatDescriptionRef
    CMAudioFormatDescriptionRef formatDescription = NULL;
    OSStatus status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault, &asbd, 0, NULL, 0, NULL, NULL, &formatDescription);
    
    if (status != noErr) {
        return NULL;
    }
    
    return formatDescription;
}
- (CMSampleBufferRef)createSampleBufferWithAudioData:(NSData *)audioData
                               formatDescription:(CMAudioFormatDescriptionRef)formatDescription {
    if (!audioData || !formatDescription) {
        return NULL;
    }
    
    // 获取音频数据指针和大小
    const void *audioBytes = audioData.bytes;
    size_t audioDataSize = audioData.length;
    
    // 创建音频数据的 CMBlockBuffer
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault,
        (void *)audioBytes,
        audioDataSize,
        kCFAllocatorNull,
        NULL,
        0,
        audioDataSize,
        0,
        &blockBuffer);
    
    if (status != noErr) {
        return NULL;
    }
    
    // 创建 CMSampleBuffer
    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreate(
        kCFAllocatorDefault,
        blockBuffer,
        true,
        NULL,
        NULL,
        formatDescription,
        1,
        0,
        NULL,
        0,
        NULL,
        &sampleBuffer);
    
    if (status != noErr) {
        CFRelease(blockBuffer);
        return NULL;
    }
    
    // 释放 blockBuffer
    CFRelease(blockBuffer);
    
    return sampleBuffer;
}

- (AVAudioPCMBuffer *)convertWithAudioConverter:(CMSampleBufferRef)sampleBuffer {
    AVAudioFormat *targetFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                                    sampleRate:16000
                                                                      channels:1
                                                                   interleaved:NO];
    // 获取音频样本数据及格式描述
    CMAudioFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
    if (!asbd) {
        NSLog(@"无法获取音频格式描述");
        return nil;
    }
    AVAudioFormat *sourceFormat = [[AVAudioFormat alloc] initWithStreamDescription:asbd];
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length = CMBlockBufferGetDataLength(blockBuffer);
    void *audioData = malloc(length);
    if (CMBlockBufferCopyDataBytes(blockBuffer, 0, length, audioData) != kCMBlockBufferNoErr) {
        NSLog(@"无法提取音频数据");
        free(audioData);
        return nil;
    }

    // 创建 AVAudioBuffer
    AVAudioPCMBuffer *sourceBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:sourceFormat frameCapacity:CMSampleBufferGetNumSamples(sampleBuffer)];
    memcpy(sourceBuffer.int16ChannelData[0], audioData, length);
    sourceBuffer.frameLength = CMSampleBufferGetNumSamples(sampleBuffer);
    free(audioData);

    // 使用 AVAudioConverter
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:sourceFormat toFormat:targetFormat];
    AVAudioPCMBuffer *convertedBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:targetFormat frameCapacity:sourceBuffer.frameLength];

    NSError *error = nil;
    AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return sourceBuffer;
    };

    [converter convertToBuffer:convertedBuffer error:&error withInputFromBlock:inputBlock];
    if (error) {
        NSLog(@"转换失败: %@", error.localizedDescription);
        return nil;
    }

    return convertedBuffer;
}
/*
 - (void)handleAudioFormatData:(NSData *)formatData {
     // 恢复格式描述
     CMAudioFormatDescriptionRef formatDescription = [self deserializeAudioFormatDescriptionFromData:formatData];
     if (!formatDescription) {
         NSLog(@"Failed to deserialize audio format description");
         return;
     }
     self.formatDescription = formatDescription;
     
 }
- (void)handleAudioData:(NSData *)data {
    if (self.formatDescription) {
        CMSampleBufferRef sampleBuffer = [self dataToSampleBuffer:data formatDescription:self.formatDescription];
        if (sampleBuffer && self.getAudioBufferBlock) {
//            dispatch_async(dispatch_get_main_queue(), ^{
                self.getAudioBufferBlock(sampleBuffer);
                CFRelease(sampleBuffer);
//            });
        }
    }
}
/// 获取音频格式描述
- (CMAudioFormatDescriptionRef)deserializeAudioFormatDescriptionFromData:(NSData *)data {
    if (!data || data.length != sizeof(AudioStreamBasicDescription)) {
        return nil;
    }
    
    // 从 NSData 中恢复 AudioStreamBasicDescription
    AudioStreamBasicDescription asbd;
    [data getBytes:&asbd length:sizeof(asbd)];
    
    // 创建 CMAudioFormatDescriptionRef
    CMAudioFormatDescriptionRef formatDescription = NULL;
    OSStatus status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, NULL, 0, NULL, NULL, &formatDescription);
    if (status != noErr) {
        NSLog(@"Failed to create CMAudioFormatDescriptionRef: %d", (int)status);
        return nil;
    }
    return formatDescription;
}
/// 将 NSData 转换为 CMSampleBuffer
- (CMSampleBufferRef)dataToSampleBuffer:(NSData *)data formatDescription:(CMAudioFormatDescriptionRef)formatDescription {
    // 创建 CMBlockBuffer
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                         (void *)data.bytes,
                                                         data.length,
                                                         kCFAllocatorNull,
                                                         NULL,
                                                         0,
                                                         data.length,
                                                         0,
                                                         &blockBuffer);
    if (status != kCMBlockBufferNoErr || !blockBuffer) {
        return nil;
    }
    
    // 创建 CMSampleBuffer
    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreate(kCFAllocatorDefault,
                                  blockBuffer,
                                  YES,
                                  NULL,
                                  NULL,
                                  formatDescription,
                                  1,
                                  0,
                                  NULL,
                                  0,
                                  NULL,
                                  &sampleBuffer);
    CFRelease(blockBuffer); // 释放 CMBlockBuffer
    
    if (status != noErr) {
        return nil;
    }
    return sampleBuffer;
}*/

/*
- (CMSampleBufferRef)createAudioSampleBufferFromData:(NSData *)data {
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault,
        (void *)data.bytes,
        data.length,
        kCFAllocatorNull,
        NULL,
        0,
        data.length,
        0,
        &blockBuffer
    );
    
    if (status != kCMBlockBufferNoErr) {
        NSLog(@"CMBlockBuffer 创建失败");
        return NULL;
    }
    
    CMAudioFormatDescriptionRef formatDescription = NULL;
    AudioStreamBasicDescription asbd = {
        .mSampleRate = 44100,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 2,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = 2,
        .mChannelsPerFrame = 1,
        .mBitsPerChannel = 16
    };
    CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, NULL, 0, NULL, NULL, &formatDescription);
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, true, NULL, NULL, formatDescription, data.length / 2, 0, NULL, 0, NULL, &sampleBuffer);
    
    CFRelease(blockBuffer);
    CFRelease(formatDescription);
    return sampleBuffer;
}
*/
- (void)handleRecvBuffer {
    if (!self.sockets.count)
    {
        return;
    }
    
    int32_t availableBytes = 0;
    void * buffer = NTESTPCircularBufferTail(self.recvBuffer, &availableBytes);
    int32_t headSize = sizeof(NTESPacketHead);
    
    if(availableBytes <= headSize) {
        //        NSLog(@" > 不够文件头");
        NTESTPCircularBufferClear(self.recvBuffer);
        return;
    }
    
    NTESPacketHead head;
    memset(&head, 0, sizeof(head));
    memcpy(&head, buffer, headSize);
    uint64_t dataLen = head.data_len;
    
    if(dataLen > availableBytes - headSize && dataLen >0) {
        //        NSLog(@" > 不够数据体");
        NTESTPCircularBufferClear(self.recvBuffer);
        return;
    }
    
    void *data = malloc(dataLen);
    memset(data, 0, dataLen);
    memcpy(data, buffer + headSize, dataLen);
    NTESTPCircularBufferClear(self.recvBuffer); // 处理完一帧数据就清空缓存

    if([self respondsToSelector:@selector(onRecvData:)]) {
        @autoreleasepool {
            [self onRecvData:[NSData dataWithBytes:data length:dataLen]];
        };
    }
    
    free(data);
}

- (void)defaultsChanged:(NSNotification *)notification
{
    GCDAsyncSocket *socket = self.sockets.count ? self.sockets[0] : nil;

    NSUserDefaults *defaults = (NSUserDefaults*)[notification object];
    id setting = nil;
     // 分辨率
    static NSInteger quality;
    setting = [defaults objectForKey:@"videochat_preferred_video_quality"];
    if (quality != [setting integerValue] && setting)
    {
        quality = [setting integerValue];
        NTESPacketHead head;
        head.service_id = 0;
        head.command_id = 1; // 1：分辨率 2：裁剪比例 3：视频方向
        head.data_len = 0;
        head.version = 0;
        NSString *str = [NSString stringWithFormat:@"%d", [setting intValue]];
        [socket writeData:[NTESSocketPacket packetWithBuffer:[str dataUsingEncoding:NSUTF8StringEncoding] head:&head] withTimeout:-1 tag:0];
    }
    
    // 视频方向
    static NSInteger orientation;
    setting = [defaults objectForKey:@"videochat_preferred_video_orientation"];
    if (orientation != [setting integerValue] && setting)
    {
        orientation = [setting integerValue];
        NTESPacketHead head;
        head.service_id = 0;
        head.command_id = 3; // 1：分辨率 2：裁剪比例 3：视频方向
        head.data_len = 0;
        head.version = 0;
        head.serial_id = 0;
        NSString *str = [NSString stringWithFormat:@"%@", setting];
        [socket writeData:[NTESSocketPacket packetWithBuffer:[str dataUsingEncoding:NSUTF8StringEncoding] head:&head] withTimeout:-1 tag:0];

    }
}


#pragma mark - NTESSocketDelegate

- (void)onRecvData:(NSData *)data
{
    static int i = 0;
    i++;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NTESI420Frame *frame = [NTESI420Frame initWithData:data];
        CMSampleBufferRef sampleBuffer = [frame convertToSampleBuffer];
//        NSLog(@"收到了%d条数据", i);
        if (self.getBufferBlock) {
            self.getBufferBlock(sampleBuffer);
        }
        if (sampleBuffer == NULL) {//防止内存泄漏
            return;
        }
        CFRelease(sampleBuffer);
    });
    
}

@end
