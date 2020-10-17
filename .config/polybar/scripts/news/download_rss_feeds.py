#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
This script downloads RSS feeds listed in a file and writes title, site
and url of every RSS item in another file.
"""

import sys
import feedparser


def is_uri(path):
    """
    Check if path has a protocol https?://
    """
    return bool(path.startswith('http://') or path.startswith('https://'))


if __name__ == '__main__':

    if len(sys.argv) == 3:
        # file with list of RSS feeds
        FN_FEEDS = sys.argv[1]
        # output file
        FN_ITEMS = sys.argv[2]
    else:
        print("usage: python {} input_file output_file".format(sys.argv[0]))
        sys.exit(0)

    F_ITEMS = open(FN_ITEMS, 'w')

    with open(FN_FEEDS) as f_feeds:
        FEEDS = f_feeds.readlines()

        for url in FEEDS:
            if is_uri(url):
                feed = feedparser.parse(url)
            else:
                continue

            try:
                site = feed.feed.title
            except AttributeError:
                continue

            for entry in feed.entries:
                F_ITEMS.write("{}\n".format(site))
                F_ITEMS.write("{}\n".format(entry.title))
                #F_ITEMS.write("{}\n".format(entry.guid))

                try:
                    if entry.guid and is_uri(entry.guid):
                        F_ITEMS.write("{}\n".format(entry.guid))
                    elif entry.link and is_uri(entry.link):
                        F_ITEMS.write("{}\n".format(entry.link))
                except (KeyError, AttributeError):
                    try:
                        if entry.link and is_uri(entry.link):
                            F_ITEMS.write("{}\n".format(entry.link))
                    except (KeyError, AttributeError):
                        F_ITEMS.write("{}\n".format(feed.feed.link))

    del F_ITEMS

# vi:expandtab softtabstop=4 smarttab shiftwidth=4 tabstop=4
