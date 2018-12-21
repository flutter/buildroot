# Android SDK Downloader

This program assits with downloading the Android SDK and NDK artifacts. for
Flutter engine development.

## Usage

```
-r, --repository-xml            Specifies the location of the Android Repository XML file.
                                (defaults to "https://dl.google.com/android/repository/repository2-1.xml")

-p, --platform                  Specifies the Android platform version, e.g. 28
                                [28 (default), 22]

    --platform-revision         Specifies the Android platform revision, e.g. 6 for 28_r06
                                (defaults to "6")

-o, --out                       The directory to write downloaded files to.
                                (defaults to ".")

    --os                        The OS type to download for.  Defaults to current platform.
                                [windows, macos (default), linux]

    --build-tools-version       The build-tools version to download.  Must be in format of <major>.<minor>.<micro>, e.g. 28.0.3; or <major>.<minor>.<micro>.<rc/preview>, e.g. 28.0.0.2
                                (defaults to "28.0.3")

    --platform-tools-version    The platform-tools version to download.  Must be in format of <major>.<minor>.<micro>, e.g. 28.0.1; or <major>.<minor>.<micro>.<rc/preview>, e.g. 28.0.0.2
                                (defaults to "28.0.1")

    --tools-version             The tools version to download.  Must be in format of <major>.<minor>.<micro>, e.g. 26.1.1; or <major>.<minor>.<micro>.<rc/preview>, e.g. 28.1.1.2
                                (defaults to "26.1.1")

    --ndk-version               The ndk version to download.  Must be in format of <major>.<minor>.<micro>, e.g. 28.0.3; or <major>.<minor>.<micro>.<rc/preview>, e.g. 28.0.0.2
                                (defaults to "18.1.5063045")

-y, --[no-]accept-licenses      Automatically accept Android SDK licenses.
    --[no-]overwrite            Skip download if the target directory exists.
```