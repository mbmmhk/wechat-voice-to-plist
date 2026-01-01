//
//  SilkWrapper.h
//  VoiceToPlist
//
//  Objective-C wrapper for SILK codec
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SilkWrapper : NSObject

/// Encode PCM data to SILK format
/// @param pcmData Raw PCM data (16-bit signed, mono)
/// @param sampleRate Sample rate of PCM data (typically 24000)
/// @return SILK encoded data with #!SILK_V3 header, or nil on error
+ (nullable NSData *)encodePCMToSilk:(NSData *)pcmData sampleRate:(int)sampleRate;

/// Decode SILK data to PCM format
/// @param silkData SILK encoded data (with or without #!SILK_V3 header)
/// @param sampleRate Output sample rate (typically 24000)
/// @return Raw PCM data (16-bit signed, mono), or nil on error
+ (nullable NSData *)decodeSilkToPCM:(NSData *)silkData sampleRate:(int)sampleRate;

@end

NS_ASSUME_NONNULL_END
