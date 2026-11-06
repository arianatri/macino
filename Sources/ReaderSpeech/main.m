#import <Foundation/Foundation.h>
#include "c-api.h"
#include <unistd.h>

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 4) return 2; // resources, language, wave destination; text is private stdin
    NSString *root = [NSString stringWithUTF8String:argv[1]], *language = [NSString stringWithUTF8String:argv[2]];
    if (![@[@"fa", @"en"] containsObject:language]) return 2;
    NSData *input = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
    NSString *text = [[NSString alloc] initWithData:input encoding:NSUTF8StringEncoding];
    if (!text.length || text.length > 1600) return 2;
    NSString *voice = [root stringByAppendingPathComponent:language];
    NSString *model = [voice stringByAppendingPathComponent:@"model.onnx"];
    NSString *tokens = [voice stringByAppendingPathComponent:@"tokens.txt"];
    NSString *data = [root stringByAppendingPathComponent:@"espeak-ng-data"];
    SherpaOnnxOfflineTtsConfig config = {0};
    config.model.vits.model = model.fileSystemRepresentation;
    config.model.vits.tokens = tokens.fileSystemRepresentation;
    config.model.vits.data_dir = data.fileSystemRepresentation;
    config.model.vits.noise_scale = 0.667f; config.model.vits.noise_scale_w = 0.8f; config.model.vits.length_scale = 1.0f;
    config.model.num_threads = 2; config.model.provider = "cpu";
    config.max_num_sentences = 1; config.silence_scale = 0.15f;
    const SherpaOnnxOfflineTts *tts = SherpaOnnxCreateOfflineTts(&config);
    if (!tts) return 3;
    SherpaOnnxGenerationConfig generation = {0}; generation.speed = 1.0f; generation.silence_scale = 0.15f;
    const SherpaOnnxGeneratedAudio *audio = SherpaOnnxOfflineTtsGenerateWithConfig(tts, text.UTF8String, &generation, NULL, NULL);
    int result = 4;
    if (audio && audio->n > 0 && audio->sample_rate > 0) {
        result = SherpaOnnxWriteWave(audio->samples, audio->n, audio->sample_rate, argv[3]) ? 0 : 5;
    }
    if (audio) SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
    SherpaOnnxDestroyOfflineTts(tts);
    return result; // process exit returns every ONNX/model allocation to the OS
} }
