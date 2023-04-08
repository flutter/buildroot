#!/usr/bin/env python3
#
# Copyright (c) 2013 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

from optparse import OptionParser
import re
import subprocess
import sys


def get_default_target(compiler_path):
    """
    should work with both gcc and clang.

    example outputs: "aarch64-unknown-linux-gnu", "x86_64-alpine-linux-musl",
    "x86_64-redhat-linux", "armv7-unknown-linux-musleabihf",
    "mipsel-linux-muslhf"
    """
    machine = subprocess.check_output([compiler_path,
                                       '-dumpmachine']).decode('utf-8').strip()

    # multiarch has a more normalized output, if it works
    if machine.endswith('-linux'):
        try:
            multiarch = subprocess.check_output(
                [compiler_path, '-print-multiarch']).decode('utf-8').strip()
            if multiarch:
                return multiarch
        except subprocess.CalledProcessError:
            pass

    return machine


def determine_libc_from_triplet(triplet):
    generic_error = ('Could not resolve host libc by compiler '
                     f'default target: "{triplet}".')

    if triplet.endswith('-linux'):
        # only a gnu distro would assume libc is not
        # an important enough factor to say it openly
        return 'gnu'

    host_libc_re = re.match(
        r'^(?:[^-]+-){1,2}linux-(?P<libc>gnu|musl|uclibc)(?:eabi)?(?:hf)?$',
        triplet)
    if host_libc_re is None:
        raise Exception(generic_error)

    return host_libc_re.group('libc')


def determine_libc_from_compiler_path(compiler_path):
    return determine_libc_from_triplet(get_default_target(compiler_path))


def main():
    if 'linux' not in sys.platform:
        return 1

    parser = OptionParser()
    parser.add_option('--compiler-path',
                      action='store',
                      type='string',
                      default='clang')
    (options, args) = parser.parse_args()

    host_libc = determine_libc_from_compiler_path(options.compiler_path)

    # print would add a newline
    sys.stdout.write(host_libc)
    return 0


if __name__ == '__main__':
    sys.exit(main())
