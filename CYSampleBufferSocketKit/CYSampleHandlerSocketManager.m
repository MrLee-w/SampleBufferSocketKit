//
//  CYSampleHandlerSocketManager.m
//  CYReplayKit
//
//  Created by 李伟 on 2024/6/27.
//

#import "CYSampleHandlerSocketManager.h"
#import "NTESYUVConverter.h"
#import "NTESI420Frame.h"
#import "GCDAsyncSocket.h"
#import "NTESSocketPacket.h"
#import "NTESTPCircularBuffer.h"
#import <mach/mach.h>
#import <CoreMedia/CoreMedia.h>

@interface CYSampleHandlerSocketManager()<GCDAsyncSocketDelegate>
{
    long evenlyMem;
}
@property (nonatomic, assign) CGFloat cropRate;
@property (nonatomic, assign) CGSize  targetSize;
@property (nonatomic, assign) NTESVideoPackOrientation orientation;

@property (nonatomic, copy) NSString *ip;
@property (nonatomic, copy) NSString *clientPort;
@property (nonatomic, copy) NSString *serverPort;
@property (nonatomic, strong) dispatch_queue_t videoQueue;
@property (nonatomic, strong) dispatch_queue_t audioQueue;

@property (nonatomic, assign) NSUInteger frameCount;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, strong) dispatch_source_t timer;

@property (nonatomic, strong) GCDAsyncSocket *videoSocket;
@property (nonatomic, strong) GCDAsyncSocket *audioSocket;

@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) NTESTPCircularBuffer *recvBuffer;
@property (nonatomic, assign) CMAudioFormatDescriptionRef formatDescription;


@end

@implementation CYSampleHandlerSocketManager
+ (CYSampleHandlerSocketManager *)sharedManager {
    static CYSampleHandlerSocketManager *shareInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareInstance = [[self alloc] init];
        shareInstance.videoQueue = dispatch_queue_create("com.netease.edu.rp.videoprocess", DISPATCH_QUEUE_SERIAL);
        shareInstance.audioQueue = dispatch_queue_create("com.netease.edu.rp.audioprocess", DISPATCH_QUEUE_SERIAL);

    });
    return shareInstance;
}

- (void)setupVideoSocket{
    _recvBuffer = (NTESTPCircularBuffer *)malloc(sizeof(NTESTPCircularBuffer)); // 需要释放
    NTESTPCircularBufferInit(_recvBuffer, kRecvBufferMaxSize);
    self.queue = dispatch_queue_create("com.netease.edu.rp.client", DISPATCH_QUEUE_SERIAL);
    self.videoSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.queue];
    //    self.socket.IPv6Enabled = NO;
    //    [self.socket connectToUrl:[NSURL fileURLWithPath:serverURL] withTimeout:5 error:nil];
    NSError *error;
    [self.videoSocket connectToHost:@"127.0.0.1" onPort:8999 error:&error];
    [self.videoSocket readDataWithTimeout:-1 tag:0];
    NSLog(@"setUpVideoSocket:%@",error);
}

- (void)setupAudioSocket {
    self.queue = dispatch_queue_create("com.netease.edu.rp.client", DISPATCH_QUEUE_SERIAL);
    self.audioSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.queue];
    //    self.socket.IPv6Enabled = NO;
    //    [self.socket connectToUrl:[NSURL fileURLWithPath:serverURL] withTimeout:5 error:nil];
    NSError *error;
    [self.audioSocket connectToHost:@"127.0.0.1" onPort:8999 error:&error];
    [self.audioSocket readDataWithTimeout:-1 tag:0];
    NSLog(@"setUpVideoSocket:%@",error);
}

- (void)socketDelloc{
    _connected = NO;
       
    if (_videoSocket) {
        [_videoSocket disconnect];
        _videoSocket = nil;
        NTESTPCircularBufferCleanup(_recvBuffer);
    }
    if (_audioSocket) {
        [_audioSocket disconnect];
        _audioSocket = nil;
    }
}

#pragma mark - 处理分辨率切换等
- (void)onRecvData:(NSData *)data head:(NTESPacketHead *)head
{
    if (!data)
    {
        return;
    }
    
    switch (head->command_id)
    {
        case 1:
        {
            NSString *qualityStr = [NSString stringWithUTF8String:[data bytes]];
            int qualit = [qualityStr intValue];
            switch (qualit) {
                case 0:
                    self.targetSize = CGSizeMake(480, 640);
                    break;
                case 1:
                    self.targetSize = CGSizeMake(144, 177);
                    break;
                case 2:
                    self.targetSize = CGSizeMake(288, 352);
                    break;
                case 3:
                    self.targetSize = CGSizeMake(320, 480);
                    break;
                case 4:
                    self.targetSize = CGSizeMake(480, 640);
                    break;
                case 5:
                    self.targetSize = CGSizeMake(540, 960);
                    break;
                case 6:
                    self.targetSize = CGSizeMake(720, 1280);
                    break;
                default:
                    break;
            }
            NSLog(@"change target size %@", @(self.targetSize));
        }
            break;
        case 2:
            break;
        case 3:
        {
            NSString *orientationStr = [NSString stringWithUTF8String:[data bytes]];
            int orient = [orientationStr intValue];
            self.orientation = NTESVideoPackOrientationPortrait;
            switch (orient) {
                case 0:
                    self.orientation = NTESVideoPackOrientationPortrait;
                    break;
                case 1:
                    self.orientation = NTESVideoPackOrientationLandscapeLeft;
                    break;
                case 2:
                    self.orientation = NTESVideoPackOrientationPortraitUpsideDown;
                    break;
                case 3:
                    self.orientation = NTESVideoPackOrientationLandscapeRight;
                    break;
                default:
                    break;
            };
            NSLog(@"change orientation %@", @(self.orientation));

        }
            break;
        default:
            break;
    }
}

#pragma mark - Process
- (void)sendAudioBufferToHostApp:(CMSampleBufferRef)sampleBuffer {
    if (!self.audioSocket) {
        return;
    }
//    long curMem = [self getCurUsedMemory];
//    if (evenlyMem > 0 && (curMem > (evenlyMem + (3 * 1024 * 1024))|| curMem > 30 * 1024 * 1024)) {
//        //当前内存暴增3M以上，或者总共超过45M，则不处理
//        NSLog(@"内存暴涨，不做处理");
//        NSLog(@"curMem:%@", @(curMem / 1024.0 / 1024.0));
//        return;
//    }
    
    CFRetain(sampleBuffer);
    dispatch_async(self.audioQueue, ^{ // queue optimal
        @autoreleasepool {
//            if (self.formatDescription == nil) {
//                // 获取格式描述
//                self.formatDescription = [self getAudioFormatDescriptionFromSampleBuffer:sampleBuffer];
//                NSData *formatData = [self serializeAudioFormatDescription:self.formatDescription];
//                [self.audioSocket writeData:formatData withTimeout:-1 tag:0];
//            }
            
            if ([self validateSampleBuffer:sampleBuffer]) {
                NSData *audioData = [self sampleBufferToData:sampleBuffer];
                NSData *formatData = [self serializeAudioFormatDescription:[self getAudioFormatDescriptionFromSampleBuffer:sampleBuffer]];
                NSData *mergedData = [self mergeAudioDataAndFormatDescription:audioData formatDescriptionData:formatData];
                CFRelease(sampleBuffer);
                if (!mergedData) {
                    NSLog(@"Failed to convert CMSampleBuffer to NSData");
                    return;
                }
                [self.audioSocket writeData:mergedData withTimeout:-1 tag:0];
            } else {
                CFRelease(sampleBuffer);
            }
        }
    });
    
}
- (BOOL)validateSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!CMSampleBufferIsValid(sampleBuffer)) {
        NSLog(@"Sample buffer is invalid.");
        return NO;
    }

    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuffer) {
        NSLog(@"Sample buffer does not contain a data buffer.");
        return NO;
    }

    // 获取数据缓冲区的大小
    size_t dataLength = CMBlockBufferGetDataLength(blockBuffer);
    NSLog(@"Data Length in CMSampleBuffer: %zu bytes", dataLength);
    
    // 如果数据大小为零，表示没有有效的数据
    if (dataLength == 0) {
        NSLog(@"Sample buffer contains no actual audio data.");
        return NO;
    }

    // 如果数据长度大于零，我们可以进一步检查数据内容是否为空（例如，是否是静音数据）
    uint8_t *data = malloc(dataLength);
    CMBlockBufferCopyDataBytes(blockBuffer, 0, dataLength, data);
    
    BOOL hasNonZeroData = NO;
       
    // 检查数据是否为全零（即无音频内容）
    for (size_t i = 0; i < dataLength; i++) {
        if (data[i] != 0) {
            hasNonZeroData = YES;
            break;
        }
    }

    free(data);

    if (hasNonZeroData) {
        NSLog(@"包含实际音频数据");
        return YES;
    } else {
        NSLog(@"不包含真实的音频数据");
        return NO;
    }
//    NSLog(@"Sample buffer validation passed.");
}
/// 获取 CMAudioFormatDescriptionRef
- (CMAudioFormatDescriptionRef)getAudioFormatDescriptionFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // 从 CMSampleBuffer 中获取音频格式描述
    CMAudioFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    return formatDescription;
}
/// 将格式描述转为可传输的 NSData
- (NSData *)serializeAudioFormatDescription:(CMAudioFormatDescriptionRef)formatDescription {
    if (!formatDescription) {
        return nil;
    }
    // 序列化为 NSData
    AudioStreamBasicDescription asbd = *CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
    NSData *data = [NSData dataWithBytes:&asbd length:sizeof(asbd)];
    return data;
}

- (NSData *)mergeAudioDataAndFormatDescription:(NSData *)audioData formatDescriptionData:(NSData *)formatDescriptionData {
    if (!audioData || !formatDescriptionData) {
        return  nil;
    }
    
    // 创建合并后的 NSData
    NSMutableData *mergedData = [NSMutableData data];
    [mergedData appendData:formatDescriptionData];
    [mergedData appendData:audioData];
    return [mergedData copy];
}

- (NSData *)sampleBufferToData:(CMSampleBufferRef)sampleBuffer {
    // 获取音频数据的 CMBlockBuffer
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuffer) {
        return nil;
    }
    
    // 获取 CMBlockBuffer 的指针和长度
    size_t length = 0;
    size_t totalLength = 0;
    char *dataPointer = NULL;
    OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, &length, &totalLength, &dataPointer);
    if (status != kCMBlockBufferNoErr) {
        return nil;
    }
    
    // 将指针内容复制到 NSData
    return [NSData dataWithBytes:dataPointer length:totalLength];
}

- (void)sendVideoBufferToHostApp:(CMSampleBufferRef)sampleBuffer {
    if (!self.videoSocket) {
        return;
    }
    
    long curMem = [self getCurUsedMemory];
    if (evenlyMem > 0 && (curMem > (evenlyMem + (3 * 1024 * 1024))|| curMem > 30 * 1024 * 1024)) {
        //当前内存暴增3M以上，或者总共超过45M，则不处理
        NSLog(@"内存暴涨，不做处理");
        NSLog(@"curMem:%@", @(curMem / 1024.0 / 1024.0));
        return;
    }
    
    CFRetain(sampleBuffer);
    dispatch_async(self.videoQueue, ^{ // queue optimal
        @autoreleasepool {
//            NSLog(@"正在处理");
            // To data
            NTESI420Frame *videoFrame = [NTESYUVConverter pixelBufferToI420:CMSampleBufferGetImageBuffer(sampleBuffer) scale:0.4];
            CFRelease(sampleBuffer);
//            NSLog(@"bufferW:%d, buffergH:%d", videoFrame.width, videoFrame.height);
//            NSLog(@"处理完成");
            // To Host App
            if (videoFrame) {
                __block NSUInteger length = 0;
                [videoFrame getBytesQueue:^(NSData *data, NSInteger index) {
                    length += data.length;
                    [self.videoSocket writeData:data withTimeout:5 tag:0];
                    data = NULL;
                    data = nil;
                }];
                [self.videoSocket writeData:[NTESSocketPacket packetWithBufferLength:length] withTimeout:5 tag:0];
            }
        }
        if (self->evenlyMem <= 0) {
            self->evenlyMem = [self getCurUsedMemory];
            NSLog(@"平均内存:%@", @(self->evenlyMem / 1024.0 / 1024.0));
        }
    });
}
#pragma mark - Socket

//- (void)setupSocket
//{
//    _recvBuffer = (NTESTPCircularBuffer *)malloc(sizeof(NTESTPCircularBuffer)); // 需要释放
//    NTESTPCircularBufferInit(_recvBuffer, kRecvBufferMaxSize);
//    self.queue = dispatch_queue_create("com.netease.edu.rp.client", DISPATCH_QUEUE_SERIAL);
//    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.queue];
//    //    self.socket.IPv6Enabled = NO;
//    //    [self.socket connectToUrl:[NSURL fileURLWithPath:serverURL] withTimeout:5 error:nil];
//    NSError *error;
//    [self.socket connectToHost:@"127.0.0.1" onPort:8999 error:&error];
//    [self.socket readDataWithTimeout:-1 tag:0];
//    NSLog(@"setupSocket:%@",error);
//}

- (void)socket:(GCDAsyncSocket *)sock didConnectToUrl:(NSURL *)url
{
    if (self.videoSocket) {
        [self.videoSocket readDataWithTimeout:-1 tag:0];
    }
    if (self.audioSocket) {
        [self.audioSocket readDataWithTimeout:-1 tag:0];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    if (self.videoSocket) {
        [self.videoSocket readDataWithTimeout:-1 tag:0];
    }
    if (self.audioSocket) {
        [self.audioSocket readDataWithTimeout:-1 tag:0];
    }
    self.connected = YES;
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    
}

//- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
//{
//    NTESTPCircularBufferProduceBytes(self.recvBuffer, data.bytes, (int32_t)data.length);
//    [self handleRecvBuffer];
//    [sock readDataWithTimeout:-1 tag:0];
//}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    self.connected = NO;
    if (self.videoSocket) {
        [self.videoSocket disconnect];
        self.videoSocket = nil;
        [self setupVideoSocket];
        [self.videoSocket readDataWithTimeout:-1 tag:0];
    }
    if (self.audioSocket) {
        [self.audioSocket disconnect];
        self.audioSocket = nil;
        [self setupAudioSocket];
        [self.audioSocket readDataWithTimeout:-1 tag:0];
    }
}
/*
- (void)handleRecvBuffer {
    if (!self.socket)
    {
        return;
    }
    
    int32_t availableBytes = 0;
    void * buffer = NTESTPCircularBufferTail(self.recvBuffer, &availableBytes);
    int32_t headSize = sizeof(NTESPacketHead);
    
    if (availableBytes <= headSize)
    {
        return;
    }
    
    NTESPacketHead head;
    memset(&head, 0, sizeof(head));
    memcpy(&head, buffer, headSize);
    uint64_t dataLen = head.data_len;
    
    if(dataLen > availableBytes - headSize && dataLen >0) {
        return;
    }
    
    void *data = malloc(dataLen);
    memset(data, 0, dataLen);
    memcpy(data, buffer + headSize, dataLen);
    NTESTPCircularBufferConsume(self.recvBuffer, (int32_t)(headSize+dataLen));
    
    
    if([self respondsToSelector:@selector(onRecvData:head:)]) {
        @autoreleasepool {
            [self onRecvData:[NSData dataWithBytes:data length:dataLen] head:&head];
        };
    }
    
    free(data);
    
    if (availableBytes - headSize - dataLen >= headSize)
    {
        [self handleRecvBuffer];
    }
}
 */
- (long)getCurUsedMemory {
    struct task_basic_info info;
    mach_msg_type_number_t size = TASK_BASIC_INFO_COUNT;//sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
    long cur_used_mem = (kerr == KERN_SUCCESS) ? info.resident_size : 0; // size in bytes
    return cur_used_mem;
}
@end
