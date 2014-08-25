/**
 * Copyright (c) 2014 DeNA Co., Ltd.
 *
 *
 * The MIT License (MIT)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "SimpleAssetManager.h"

// TODO: modify this to point to your latest app data json file
// Example file content:
// {
//   "timestamp": 1407384447,
//   "version": 1,
//   "checksum": "8bf27900ada3d66c6f6ffaacc641cfc6",
//   "url": "http://www.example.com/appdata/data_20140807.zip"
// }
#define ASSET_METADATA_URL  @"http://www.example.com/appdata/latest.json"

#define kAssetTimestamp @"timestamp"
#define kAssetVersion   @"version"
#define kAssetChecksum  @"checksum"
#define kAssetURL       @"url"

@interface SimpleAssetManager ()

@property (nonatomic, strong) id<SimpleAssetManagerDelegate> delegate;

@property (nonatomic, strong) NSMutableDictionary *currentAsset; // last processed app data
@property (nonatomic, strong) NSDictionary*latestAsset; // latest app data on server

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *downloadTask;

// utility functions for download data storage
- (NSURL*)noBackupDownloadDirectory;
- (BOOL)noBackupDownloadDirectoryExists;
- (NSError *)createNoBackupDownloadDirectory;

// utility functions for checking data integrity and unpacking
// TODO: these are not implemented so please implement them
- (BOOL)verifyChecksum:(NSString*)checksum fileURL:(NSURL*)fileURL;
- (BOOL)unpackFiles:(NSURL*)fileURL;

@end

@implementation SimpleAssetManager

+ (SimpleAssetManager *)sharedManager {
    static SimpleAssetManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[SimpleAssetManager alloc] init];
    });
    return sharedManager;
}

- (id)init {
    if (self = [super init]) {
        // create session for downloading app data
        NSURLSessionConfiguration *configuration =
            [NSURLSessionConfiguration
             backgroundSessionConfiguration:@"com.mobage.sample.BackgroundDownloadSample.session"];
        self.session = [NSURLSession sessionWithConfiguration:configuration
                                                     delegate:self delegateQueue:nil];
        
        // load last processed app data into currentAsset
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        self.currentAsset = [[NSMutableDictionary alloc] init];
        
        [_currentAsset setObject:[NSNumber numberWithInt:[ud integerForKey:kAssetTimestamp]]
                          forKey:kAssetTimestamp];
        [_currentAsset setObject:[NSNumber numberWithInt:[ud integerForKey:kAssetVersion]]
                          forKey:kAssetVersion];
        if ([ud stringForKey:kAssetChecksum])
            [_currentAsset setObject:[ud stringForKey:kAssetChecksum]
                              forKey:kAssetChecksum];
        if ([ud stringForKey:kAssetURL])
            [_currentAsset setObject:[ud stringForKey:kAssetURL]
                              forKey:kAssetURL];
    }
    return self;
}

- (void)checkUpdate:(void (^)(BOOL updateAvailable, NSError *error))completion {
    // download latest app data metadata from server
    NSURL *metadataURL = [NSURL URLWithString:ASSET_METADATA_URL];
    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
         dataTaskWithURL:metadataURL
         completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
             if (!error) {
                 NSError *JsonParseError = nil;
                 NSDictionary *metadata = [NSJSONSerialization
                                           JSONObjectWithData:data options:0 error:&JsonParseError];
                 if (!JsonParseError) {
                     NSLog(@"Metadata: %@", metadata);
                     self.latestAsset = metadata;
                     
                     // compare timestamp to determine whether to download
                     NSInteger latestTimestamp = [[_latestAsset
                                                   objectForKey:kAssetTimestamp] intValue];
                     NSInteger currentTimestamp = [[_currentAsset
                                                    objectForKey:kAssetTimestamp] intValue];
                     NSLog(@"current: %d   latest: %d", currentTimestamp, latestTimestamp);
                     if (latestTimestamp > currentTimestamp) {
                         // latest app data found, download
                         if (completion) completion(YES, nil);
                     } else {
                         if (completion) completion(NO, nil);
                     }
                 } else {
                     if (completion) completion(NO, JsonParseError);
                 }
             } else {
                 if (completion) completion(NO, error);
             }
         }];
    [task resume];
}

- (void)downloadUpdatedAssetDelegate:(id<SimpleAssetManagerDelegate>)delegate
                         onInitError:(void (^)(NSError *))errorHandler
{
    // we need to call checkUpdate first
    if (!_latestAsset || ![_latestAsset objectForKey:kAssetURL]) {
        NSError *error = [NSError
                          errorWithDomain:SIMPLE_ASSET_MANAGER_ERROR_DOMAIN
                          code:kErrorLatestMetadataNotInit
                          userInfo:@{ NSLocalizedDescriptionKey: @"Please call checkUpdate first" }];
        if (errorHandler) errorHandler(error);
        return;
    }
    
    // currently we only limit one download each time
    if (self.downloadTask) {
        NSError *error = [NSError
                          errorWithDomain:SIMPLE_ASSET_MANAGER_ERROR_DOMAIN
                          code:kErrorDownloadAlreadyStarted
                          userInfo:@{ NSLocalizedDescriptionKey: @"Download has already started" }];
        if (errorHandler) errorHandler(error);
        return;
    }
    
    // set the delegate to report download and data preparation progress
    self.delegate = delegate;
    
    // kick start download
    // download continues in the background after this point
    NSURL *assetURL = [NSURL URLWithString:[_latestAsset objectForKey:kAssetURL]];
    self.downloadTask = [self.session downloadTaskWithURL:assetURL];
    [_downloadTask resume];
}

#pragma mark Private utility functions

// define the location of storage for downloaded data
- (NSURL*)noBackupDownloadDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSArray *URLs = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *documentsDirectory = [URLs objectAtIndex:0];
    
    NSURL *noBackupDownloadDirectory = [documentsDirectory URLByAppendingPathComponent:@"no_backup"];
    
    return noBackupDownloadDirectory;
}

// check if download data storage directory exists
- (BOOL)noBackupDownloadDirectoryExists
{
    NSURL *dir = [self noBackupDownloadDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:[dir path]];
}

// create download data storage directory if it does not exist
- (NSError *)createNoBackupDownloadDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([self noBackupDownloadDirectoryExists]) return nil;
    
    NSURL *noBackupDownloadDirectory = [self noBackupDownloadDirectory];
    
    NSError *error = nil;
    BOOL created = [fileManager createDirectoryAtURL:noBackupDownloadDirectory
                         withIntermediateDirectories:YES
                                          attributes:nil
                                               error:&error];
    if (! created) {
        return error;
    }
    
    // mark do not backup
    // https://developer.apple.com/library/IOS/qa/qa1719/_index.html
    error = nil;
    BOOL success = [noBackupDownloadDirectory
                    setResourceValue:[NSNumber numberWithBool:YES]
                    forKey:NSURLIsExcludedFromBackupKey error:&error];
    if(!success){
        return error;
    }
    
    return nil;
}

// TODO: verify file integrity here
// assume verification successful here
- (BOOL)verifyChecksum:(NSString*)checksum fileURL:(NSURL*)fileURL
{
    NSLog(@"Verifying file checksum...");
    for (int i=0; i<5; i++) {
        if (_delegate) {
            [_delegate didPrepareDataMessage:@"Checking file integrity..."
                                    progress:(float)i/5.0];
        }
        sleep(1);
    }
    return YES;
}

// TODO: unpack file here
// assume unpack successful here
- (BOOL)unpackFiles:(NSURL*)fileURL
{
    NSLog(@"Unpacking file...");
    for (int i=0; i<5; i++) {
        if (_delegate) {
            [_delegate didPrepareDataMessage:@"Unpacking file..."
                                    progress:(float)i/5.0];
        }
        sleep(1);
    }
    return YES;
}

#pragma mark NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    NSLog(@"didFinishDownloadingToURL: %@", location);
    
    NSError *error = [self createNoBackupDownloadDirectory];
    if (error) {
        if (_delegate) {
            [_delegate didDataPreparationCompleteWithError:error];
        }
        return;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *destinationURL = [[self noBackupDownloadDirectory]
                             URLByAppendingPathComponent:[location lastPathComponent]];
    [fileManager removeItemAtURL:destinationURL error:nil];
    
    error = nil;
    BOOL copied = [fileManager copyItemAtURL:location toURL:destinationURL error:&error];
    if (!copied) {
        if (_delegate) {
            [_delegate didDataPreparationCompleteWithError:error];
        }
        self.delegate = nil;
        return;
    }
    
    // do the heavy lifting in another thread to unblock delegate method.
    // note that we are using gloabl queue here, so it will not continue to run in the background as the download did.
    // using main thread here will allow it to run in background but this will block UI update.
    // make the best decision here for your app.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        BOOL verified = [self verifyChecksum:[_latestAsset objectForKey:kAssetChecksum]
                                     fileURL:destinationURL];
        if (!verified) {
            NSError *error = [NSError
                              errorWithDomain:SIMPLE_ASSET_MANAGER_ERROR_DOMAIN
                              code:kErrorFileIntegrityNotRight
                              userInfo:@{ NSLocalizedDescriptionKey: @"Download file failed checksum verification" }];
            if (_delegate) {
                [_delegate didDataPreparationCompleteWithError:error];
            }
            self.delegate = nil;
            
            return;
        }
        
        BOOL extracted = [self unpackFiles:destinationURL];
        if (!extracted) {
            NSError *error = [NSError
                              errorWithDomain:SIMPLE_ASSET_MANAGER_ERROR_DOMAIN
                              code:kErrorFileExtractionProblem
                              userInfo:@{ NSLocalizedDescriptionKey: @"failed to unpack downloaded file" }];
            if (_delegate) {
                [_delegate didDataPreparationCompleteWithError:error];
            }
            self.delegate = nil;
            
            return;
        }
        
        self.currentAsset = [NSMutableDictionary dictionaryWithDictionary:self.latestAsset];
        
        // update our NSUserDefaults
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:[_currentAsset objectForKey:kAssetTimestamp]
               forKey:kAssetTimestamp];
        [ud setObject:[_currentAsset objectForKey:kAssetVersion]
               forKey:kAssetVersion];
        [ud setObject:[_currentAsset objectForKey:kAssetChecksum]
               forKey:kAssetChecksum];
        [ud setObject:[_currentAsset objectForKey:kAssetURL]
               forKey:kAssetURL];
        [ud synchronize];
        
        if (_delegate) {
            [_delegate didDataPreparationCompleteWithError:nil];
        }
        
        self.delegate = nil;
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    NSLog(@"didWriteData: %lld totalBytesWritten: %lld totalBytesExpectedToWrite: %lld",
          bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
    
    if (_delegate) {
        [_delegate didWriteData:bytesWritten
            totalBytesWritten:totalBytesWritten
    totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
}

// required delegate method but not used in this sample
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes
{
    NSLog(@"didResumeAtOffset: %lld expectedTotalBytes: %lld",
          fileOffset, expectedTotalBytes);
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    NSLog(@"didCompleteWithError: %@", error);
    
    if (_delegate) {
        [_delegate didDownloadCompleteWithError:error];
    }
    
    self.downloadTask = nil;
}

#pragma mark NSURLSessionDelegate

// This delegate method is invoked if the app is in the background when download is done
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
    NSLog(@"URLSessionDidFinishEventsForBackgroundURLSession");
    if (_backgroundURLSessionCompletionHandler) {
        void (^completionHandler)() = _backgroundURLSessionCompletionHandler;
        self.backgroundURLSessionCompletionHandler = nil;
        completionHandler();
    }
}

@end
