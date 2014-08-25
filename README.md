ios-background-download-sample
==============================

A sample iOS application to show how to use Background Transfer to download large application data in the background.

This sample is developed using the following:
- Xcode 5.1.1
- tested on iPhone 4S @ iOS 7.1.2 / iOS Simulator @ iOS 7.0

Usage
-----
You can test the app using the following steps:

First, Prepare the following files and host them on a HTTP server. Localhost is fine.

- A large file that needs certain amount of time to download, preferably 30 secs to 1 min.
- latest.json with the following content:

```
{
  "timestamp": 1407384447,
  "version": 1,
  "checksum": "8bf27900ada3d66c6f6ffaacc641cfc6",
  "url": "http://www.example.com/appdata/data_20140807.zip" // URL to above large file
}
```

Then, specify the URL to latest.json in SimpleAssetManager.m as follow:

```
#define ASSET_METADATA_URL  @"http://www.example.com/appdata/latest.json"
```

Run the app!

You can see that it starts to download the file specified in latest.json. 
Verify that it is downloading in the background by pressing home button and bring it back up a few times.

Finally, send it back to the background and wait for the notification to come up.

