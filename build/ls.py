#!/usr/bin/python
# Copyright 2015 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Recursively list files of the target directory. Ignores dot files."""

import argparse
import os
import sys

def main(target_directory, file_type):
  for root, dirs, files in os.walk(target_directory):
    files = [f for f in files if not f[0] == '.']
    dirs[:] = [d for d in dirs if not d[0] == '.']
    for f in files:
      if file_type is None or os.path.splitext(f)[-1] == file_type:
        path = os.path.join(root, f)
        print path

if __name__ == '__main__':
  parser = argparse.ArgumentParser(
      description="Recursively list files of the target directory")
  parser.add_argument("--target-directory",
                      dest="target_directory",
                      metavar="<target-directory>",
                      type=str,
                      required=True,
                      help="The target directory")
  parser.add_argument("--file-type",
                      dest="file_type",
                      metavar="<file-type>",
                      type=str,
                      required=False,
                      help="File types to filter")

  args = parser.parse_args()
  sys.exit(main(args.target_directory, args.file_type))
