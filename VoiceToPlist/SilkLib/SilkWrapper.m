//
//  SilkWrapper.m
//  VoiceToPlist
//
//  Objective-C wrapper for SILK codec
//

#import "SilkWrapper.h"
#include "SKP_Silk_SDK_API.h"
#include <stdlib.h>
#include <string.h>

// SILK V3 header
static const char SILK_HEADER[] = "#!SILK_V3";
static const int SILK_HEADER_LEN = 9;

// Frame duration in ms
static const int FRAME_DURATION_MS = 20;

@implementation SilkWrapper

+ (nullable NSData *)encodePCMToSilk:(NSData *)pcmData sampleRate:(int)sampleRate {
    if (pcmData.length == 0) {
        return nil;
    }

    // Get encoder size
    SKP_int32 encSizeBytes = 0;
    SKP_int ret = SKP_Silk_SDK_Get_Encoder_Size(&encSizeBytes);
    if (ret != 0) {
        NSLog(@"SKP_Silk_SDK_Get_Encoder_Size failed: %d", ret);
        return nil;
    }

    // Allocate encoder state
    void *encState = malloc(encSizeBytes);
    if (!encState) {
        return nil;
    }

    // Initialize encoder
    SKP_SILK_SDK_EncControlStruct encControl;
    memset(&encControl, 0, sizeof(encControl));

    ret = SKP_Silk_SDK_InitEncoder(encState, &encControl);
    if (ret != 0) {
        NSLog(@"SKP_Silk_SDK_InitEncoder failed: %d", ret);
        free(encState);
        return nil;
    }

    // Set encoder parameters
    encControl.API_sampleRate = sampleRate;
    encControl.maxInternalSampleRate = sampleRate;
    encControl.packetSize = (sampleRate / 1000) * FRAME_DURATION_MS;  // 20ms frame
    encControl.bitRate = 25000;  // 25kbps
    encControl.packetLossPercentage = 0;
    encControl.complexity = 2;  // Highest quality
    encControl.useInBandFEC = 0;
    encControl.useDTX = 0;

    // Calculate sizes
    int samplesPerFrame = encControl.packetSize;
    int bytesPerSample = 2;  // 16-bit
    int bytesPerFrame = samplesPerFrame * bytesPerSample;
    int totalSamples = (int)(pcmData.length / bytesPerSample);
    int numFrames = (totalSamples + samplesPerFrame - 1) / samplesPerFrame;

    // Output buffer (estimate: max 250 bytes per frame + header)
    NSMutableData *output = [NSMutableData dataWithCapacity:SILK_HEADER_LEN + numFrames * 260];

    // Write SILK header with prefix byte
    uint8_t headerPrefix = 0x02;  // Tencent SILK header prefix
    [output appendBytes:&headerPrefix length:1];
    [output appendBytes:SILK_HEADER length:SILK_HEADER_LEN];

    const int16_t *samples = (const int16_t *)pcmData.bytes;
    uint8_t outBuffer[1024];

    for (int frame = 0; frame < numFrames; frame++) {
        int offset = frame * samplesPerFrame;
        int remaining = totalSamples - offset;
        int samplesToEncode = (remaining < samplesPerFrame) ? remaining : samplesPerFrame;

        // Prepare input (pad with zeros if needed)
        int16_t frameBuffer[samplesPerFrame];
        memset(frameBuffer, 0, sizeof(frameBuffer));
        memcpy(frameBuffer, samples + offset, samplesToEncode * bytesPerSample);

        SKP_int16 nBytesOut = sizeof(outBuffer);
        ret = SKP_Silk_SDK_Encode(encState, &encControl,
                                   frameBuffer, samplesPerFrame,
                                   outBuffer, &nBytesOut);

        if (ret != 0) {
            NSLog(@"SKP_Silk_SDK_Encode failed at frame %d: %d", frame, ret);
            free(encState);
            return nil;
        }

        if (nBytesOut > 0) {
            // Write frame size (2 bytes, little-endian)
            uint16_t frameSize = (uint16_t)nBytesOut;
            [output appendBytes:&frameSize length:2];
            // Write frame data
            [output appendBytes:outBuffer length:nBytesOut];
        }
    }

    // Write end marker (frame size = 0)
    uint16_t endMarker = 0;
    [output appendBytes:&endMarker length:2];

    free(encState);
    return output;
}

+ (nullable NSData *)decodeSilkToPCM:(NSData *)silkData sampleRate:(int)sampleRate {
    if (silkData.length < SILK_HEADER_LEN + 1) {
        return nil;
    }

    const uint8_t *bytes = (const uint8_t *)silkData.bytes;
    int offset = 0;

    // Check for Tencent header prefix (0x02)
    if (bytes[0] == 0x02) {
        offset = 1;
    }

    // Check SILK header
    if (memcmp(bytes + offset, SILK_HEADER, SILK_HEADER_LEN) != 0) {
        NSLog(@"Invalid SILK header");
        return nil;
    }
    offset += SILK_HEADER_LEN;

    // Get decoder size
    SKP_int32 decSizeBytes = 0;
    SKP_int ret = SKP_Silk_SDK_Get_Decoder_Size(&decSizeBytes);
    if (ret != 0) {
        NSLog(@"SKP_Silk_SDK_Get_Decoder_Size failed: %d", ret);
        return nil;
    }

    // Allocate decoder state
    void *decState = malloc(decSizeBytes);
    if (!decState) {
        return nil;
    }

    // Initialize decoder
    ret = SKP_Silk_SDK_InitDecoder(decState);
    if (ret != 0) {
        NSLog(@"SKP_Silk_SDK_InitDecoder failed: %d", ret);
        free(decState);
        return nil;
    }

    // Set decoder parameters
    SKP_SILK_SDK_DecControlStruct decControl;
    memset(&decControl, 0, sizeof(decControl));
    decControl.API_sampleRate = sampleRate;

    // Output buffer (estimate: 20ms at sample rate = samples per frame * 2 bytes)
    int maxSamplesPerFrame = (sampleRate / 1000) * FRAME_DURATION_MS * 2;  // *2 for safety
    NSMutableData *output = [NSMutableData data];
    int16_t outBuffer[maxSamplesPerFrame];

    // Decode frames
    while (offset + 2 <= silkData.length) {
        // Read frame size (2 bytes, little-endian)
        uint16_t frameSize = bytes[offset] | (bytes[offset + 1] << 8);
        offset += 2;

        if (frameSize == 0) {
            // End of stream
            break;
        }

        if (offset + frameSize > silkData.length) {
            NSLog(@"Truncated SILK frame");
            break;
        }

        SKP_int16 nSamplesOut = maxSamplesPerFrame;
        ret = SKP_Silk_SDK_Decode(decState, &decControl, 0,
                                   bytes + offset, frameSize,
                                   outBuffer, &nSamplesOut);

        if (ret != 0) {
            NSLog(@"SKP_Silk_SDK_Decode failed: %d", ret);
            // Continue decoding remaining frames
        }

        if (nSamplesOut > 0) {
            [output appendBytes:outBuffer length:nSamplesOut * sizeof(int16_t)];
        }

        offset += frameSize;

        // Handle internal decoder frames
        while (decControl.moreInternalDecoderFrames) {
            nSamplesOut = maxSamplesPerFrame;
            ret = SKP_Silk_SDK_Decode(decState, &decControl, 0,
                                       NULL, 0,
                                       outBuffer, &nSamplesOut);
            if (ret == 0 && nSamplesOut > 0) {
                [output appendBytes:outBuffer length:nSamplesOut * sizeof(int16_t)];
            }
        }
    }

    free(decState);
    return output;
}

@end
