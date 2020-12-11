# Copyright (c) 2012 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import errno
import os

def mkdir_p(path):
  try:
    os.makedirs(path)
  except OSError as exc:
    if exc.errno == errno.EEXIST and os.path.isdir(path):
      pass
    else:
      raise


def symlink(target, link):
  mkdir_p(os.path.dirname(link))
  tmp_link = link + '.tmp'
  try:
    os.remove(tmp_link)
  except OSError:
    pass
  os.symlink(target, tmp_link)
  os.rename(tmp_link, link)
