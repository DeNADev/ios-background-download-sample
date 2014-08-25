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

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    [self showControlsWithLabel:@"Checking update..." progress:0.0f];
    
    void (^checkUpdateComplete)(BOOL, NSError *) = ^(BOOL updateAvailable, NSError *error) {
        if (!error) {
            if (updateAvailable) {
                [self showControlsWithLabel:@"Downloading update..." progress:0.0f];
                [[SimpleAssetManager sharedManager]
                 downloadUpdatedAssetDelegate:self onInitError:^(NSError *error) {
                    [self hideControlsWithLabel:[error localizedDescription]];
                }];
            } else {
                [self hideControlsWithLabel:@"Data is the latest.\nApp starts!"];
            }
        } else {
            [self hideControlsWithLabel:[error description]];
        }
    };
    
    [[SimpleAssetManager sharedManager] checkUpdate:checkUpdateComplete];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)showControlsWithLabel:(NSString*)label progress:(float)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_activityIndicator startAnimating];
        [_progressView setHidden:NO];
        [_progressView setProgress:progress];
        [_statusLabel setText:label];
    });
}

- (void)hideControlsWithLabel:(NSString*)label
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_activityIndicator stopAnimating];
        [_progressView setHidden:YES];
        [_statusLabel setText:label];
    });
}

- (void)didWriteData:(int64_t)bytesWritten
   totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    double progress = (double)totalBytesWritten/(double)totalBytesExpectedToWrite;
    [self showControlsWithLabel:[NSString stringWithFormat:@"Downloading update...\n%lld / %lld",
                                 totalBytesWritten, totalBytesExpectedToWrite]
                       progress:progress];
}

- (void)didDownloadCompleteWithError:(NSError *)error
{
    if (!error) {
        [self hideControlsWithLabel:@"Download finished!"];
    } else {
        [self hideControlsWithLabel:[error localizedDescription]];
    }
}

- (void)didPrepareDataMessage:(NSString *)message progress:(float)progress
{
    [self showControlsWithLabel:message progress:progress];
}

- (void)didDataPreparationCompleteWithError:(NSError *)error
{
    if (!error) {
        [self hideControlsWithLabel:@"Data ready.\nApp starts!"];
    } else {
        [self hideControlsWithLabel:[error localizedDescription]];
    }
}

@end
