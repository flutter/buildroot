#!/usr/bin/python
# Copyright 2015 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Pulls down the current dart sdk to third_party/dart-sdk/.

You can manually force this to run again by removing
third_party/dart-sdk/STAMP_FILE, which contains the URL of the SDK that
was downloaded. Rolling works by updating LINUX_64_SDK to a new URL.
"""

import os
import shutil
import sys
import urllib
import zipfile

# How to roll the dart sdk: Just change this url! We write this to the stamp
# file after we download, and then check the stamp file for differences.
SDK_URL_BASE = ('http://gsdview.appspot.com/dart-archive/channels/stable/raw/'
                '1.21.0/sdk/')

LINUX_64_SDK = 'dartsdk-linux-x64-release.zip'
MACOS_64_SDK = 'dartsdk-macos-x64-release.zip'
WINDOWS_64_SDK = 'dartsdk-windows-x64-release.zip'

# Path constants. (All of these should be absolute paths.)
THIS_DIR = os.path.abspath(os.path.dirname(__file__))
MOJO_DIR = os.path.abspath(os.path.join(THIS_DIR, '..', '..'))
DART_SDKS_DIR = os.path.join(MOJO_DIR, 'dart/tools/sdks')
PATCH_FILE = os.path.join(MOJO_DIR, 'tools', 'dart', 'patch_sdk.diff')

def main():
  # Only get the SDK if we don't have a stamp for or have an out of date stamp
  # file.
  get_sdk = False
  if sys.platform.startswith('linux'):
    os_infix = 'linux'
    zip_filename = LINUX_64_SDK
  elif sys.platform.startswith('darwin'):
    os_infix = 'mac'
    zip_filename = MACOS_64_SDK
  elif sys.platform.startswith('win'):
    os_infix = 'win'
    zip_filename = WINDOWS_64_SDK
  else:
    print "Platform not supported"
    return 1

  sdk_url = SDK_URL_BASE + zip_filename
  dart_sdk_dir = os.path.join(DART_SDKS_DIR, os_infix)
  output_file = os.path.join(dart_sdk_dir, zip_filename)

  stamp_file = os.path.join(dart_sdk_dir, 'dart-sdk/STAMP_FILE')
  if not os.path.exists(stamp_file):
    get_sdk = True
  else:
    # Get the contents of the stamp file.
    with open(stamp_file, "r") as stamp_file:
      stamp_url = stamp_file.read().replace('\n', '')
      if stamp_url != sdk_url:
        get_sdk = True

  if get_sdk:
    # Completely remove all traces of the previous SDK.
    if os.path.exists(dart_sdk_dir):
      shutil.rmtree(dart_sdk_dir)
    os.mkdir(dart_sdk_dir)

    urllib.urlretrieve(sdk_url, output_file)
    with zipfile.ZipFile(output_file, 'r') as zip_ref:
      for zip_info in zip_ref.infolist():
        zip_ref.extract(zip_info, path=dart_sdk_dir)
        mode = (zip_info.external_attr >> 16) & 0xFFF
        os.chmod(os.path.join(dart_sdk_dir, zip_info.filename), mode)

    # Write our stamp file so we don't redownload the sdk.
    with open(stamp_file, "w") as stamp_file:
      stamp_file.write(sdk_url)

  return 0

if __name__ == '__main__':
  sys.exit(main())
