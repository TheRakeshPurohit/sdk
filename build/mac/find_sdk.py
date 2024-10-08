#!/usr/bin/env python3
# Copyright (c) 2012 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Prints the lowest locally available SDK version greater than or equal to a
given minimum sdk version to standard output.

Usage:
  python3 find_sdk.py 10.6  # Ignores SDKs < 10.6
"""

import os
import re
import subprocess
import sys

from optparse import OptionParser


# sdk/build/xcode_links
ROOT_SRC_DIR = os.path.join(
    os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__)))))


def CreateSymlinkForSDKAt(src, dst):
    """
    Create symlink to Xcode directory at target location, which can be absolute or
    relative to `ROOT_SRC_DIR`.
    """

    # If `dst` is relative, it is assumed to be relative to src root.
    if not os.path.isabs(dst):
        dst = os.path.join(ROOT_SRC_DIR, dst)

    if not os.path.isdir(dst):
        os.makedirs(dst, exist_ok=True)

    dst = os.path.join(dst, os.path.basename(src))

    # Update the symlink if exists.
    if os.path.islink(dst):
        current_src = os.readlink(dst)
        if current_src == src:
            return dst

        os.unlink(dst)
        sys.stderr.write('existing symlink %s points %s; want %s. Removed.' %
                         (dst, current_src, src))

    os.symlink(src, dst)
    return dst


def parse_version(version_str):
    """'10.6' => [10, 6]"""
    return list(map(int, re.findall(r'(\d+)', version_str)))


def main():
    parser = OptionParser()
    parser.add_option(
        "--verify",
        action="store_true",
        dest="verify",
        default=False,
        help="return the sdk argument and warn if it doesn't exist")
    parser.add_option(
        "--sdk_path",
        action="store",
        type="string",
        dest="sdk_path",
        default="",
        help="user-specified SDK path; bypasses verification")
    parser.add_option(
        "--print_sdk_path",
        action="store_true",
        dest="print_sdk_path",
        default=False,
        help="Additionally print the path the SDK (appears first).")
    parser.add_option(
        "--create_symlink_at",
        action="store",
        dest="create_symlink_at",
        help=
        "Create symlink to SDK at given location and return symlink path as SDK "
        "info instead of the original location.")
    parser.add_option("--platform",
                      action="store",
                      type="choice",
                      choices=[
                          "mac", "iphone", "iphone_simulator", "watch",
                          "watch_simulator"
                      ],
                      dest="platform",
                      default="mac",
                      help="SDK Platform")
    (options, args) = parser.parse_args()
    min_sdk_version = args[0]

    job = subprocess.Popen(['xcode-select', '-print-path'],
                           stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT,
                           universal_newlines=True)
    platform = {
        'mac': 'MacOSX',
        'iphone': 'iPhoneOS',
        'iphone_simulator': 'iPhoneSimulator',
        'watch': 'WatchOS',
        'watch_simulator': 'WatchSimulator'
    }[options.platform]
    out, err = job.communicate()
    if job.returncode != 0:
        print(out, file=sys.stderr)
        print(err, file=sys.stderr)
        raise Exception('Error %d running xcode-select' % job.returncode)
    sdk_dir = os.path.join(out.rstrip(),
                           f'Platforms/{platform}.platform/Developer/SDKs')
    if not os.path.isdir(sdk_dir):
        raise Exception(
            'Install Xcode, launch it, accept the license ' +
            'agreement, and run `sudo xcode-select -s /path/to/Xcode.app` ' +
            'to continue.')
    sdks = [
        re.findall(fr'^{platform}(\d+\.\d+)\.sdk$', s)
        for s in os.listdir(sdk_dir)
    ]
    sdks = [s[0] for s in sdks if s]  # [['10.5'], ['10.6']] => ['10.5', '10.6']
    sdks = [
        s for s in sdks  # ['10.5', '10.6'] => ['10.6']
        if parse_version(s) >= parse_version(min_sdk_version)
    ]
    if not sdks:
        raise Exception('No %s+ SDK found' % min_sdk_version)
    best_sdk = sorted(sdks, key=parse_version)[0]

    if options.verify and best_sdk != min_sdk_version and not options.sdk_path:
        print('''
                                           vvvvvvv

This build requires the %s SDK, but it was not found on your system.

Either install it, or explicitly set mac_sdk in your GYP_DEFINES.

                                           ^^^^^^^'
''' % min_sdk_version,
              file=sys.stderr)
        return min_sdk_version

    if options.print_sdk_path:
        sdk_path = subprocess.check_output([
            'xcodebuild', '-version', '-sdk',
            platform.lower() + best_sdk, 'Path'
        ],
                                           universal_newlines=True).strip()
        if options.create_symlink_at:
            print(CreateSymlinkForSDKAt(sdk_path, options.create_symlink_at))
        else:
            print(sdk_path)

    return best_sdk


if __name__ == '__main__':
    if sys.platform != 'darwin':
        raise Exception("This script only runs on Mac")
    print(main())
