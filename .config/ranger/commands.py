#!/usr/bin/env python
from ranger.api.commands import Command
from collections import deque
import os
fd_deq = deque()


class fd_search(Command):
    """:fd_search [-d<depth>] <query>

    Executes "fd -d<depth> <query>" in the current directory and focuses the
    first match. <depth> defaults to 1, i.e. only the contents of the current
    directory.
    """

    def execute(self):
        import subprocess
        from ranger.ext.get_executables import get_executables
        if not 'fd' in get_executables():
            self.fm.notify("Couldn't find fd on the PATH.", bad=True)
            return
        if self.arg(1):
            if self.arg(1)[:2] == '-d':
                depth = self.arg(1)
                target = self.rest(2)
            else:
                depth = '-d1'
                target = self.rest(1)
        else:
            self.fm.notify(":fd_search needs a query.", bad=True)
            return

        # For convenience, change which dict is used as result_sep to change
        # fd's behavior from splitting results by \0, which allows for newlines
        # in your filenames to splitting results by \n, which allows for \0 in
        # filenames.
        null_sep = {'arg': '-0', 'split': '\0'}
        # nl_sep = {'arg': '', 'split': '\n'}
        result_sep = null_sep

        process = subprocess.Popen(['fd', result_sep['arg'], depth, target],
                    universal_newlines=True, stdout=subprocess.PIPE)
        (search_results, _err) = process.communicate()
        global fd_deq
        fd_deq = deque((self.fm.thisdir.path + os.sep + rel for rel in
            sorted(search_results.split(result_sep['split']), key=str.lower)
            if rel != ''))
        if len(fd_deq) > 0:
            self.fm.select_file(fd_deq[0])


class fd_next(Command):
    """:fd_next

    Selects the next match from the last :fd_search.
    """

    def execute(self):
        if len(fd_deq) > 1:
            fd_deq.rotate(-1) # rotate left
            self.fm.select_file(fd_deq[0])
        elif len(fd_deq) == 1:
            self.fm.select_file(fd_deq[0])


class fd_prev(Command):
    """:fd_prev

    Selects the next match from the last :fd_search.
    """

    def execute(self):
        if len(fd_deq) > 1:
            fd_deq.rotate(1) # rotate right
            self.fm.select_file(fd_deq[0])
        elif len(fd_deq) == 1:
            self.fm.select_file(fd_deq[0])


class fasd(Command):
    """
    :fasd

    Jump to directory using fasd
    """
    def execute(self):
        import subprocess
        arg = self.rest(1)
        if arg:
            directory = subprocess.check_output(["fasd", "-d"]+arg.split(), universal_newlines=True).strip()
            self.fm.cd(directory)

class tmsu_tag(Command):
    """:tmsu_tag

    Tags the current file with tmsu
    """

    def execute(self):
        cf = self.fm.thisfile

        self.fm.run("tmsu tag \"{0}\" {1}".format(cf.basename, self.rest(1)))

class exif_filter(Command):
    """
    :exif_filter ...

    Filters files by Exif data

        exif_filter
        filter_stack add FILTER_TYPE ARGS...
        filter_stack pop
        filter_stack decompose
        filter_stack rotate [N=1]
        filter_stack clear
        filter_stack show
    """
    def execute(self):
        from ranger.ext.get_executables import get_executables
        from ranger.core.filter_stack import SIMPLE_FILTERS
        import subprocess
        tag = self.arg(1)
        if not 'exiftool' in get_executables():
            self.fm.notify("Couldn't find exif_filter on the PATH.", bad=True)
            return
        if not tag:
            self.fm.notify(":exif_filter needs a query.", bad=True)
            return

        process = subprocess.Popen(['/home/nexor/.local/bin/sit', tag],
                    universal_newlines=True, stdout=subprocess.PIPE)
        i = 0
        for l in iter(lambda: process.stdout.readline(), ''):
            self.fm.thisdir.filter_stack.append(
                SIMPLE_FILTERS['name'](l[2:])
            )
            if not i % 5:
                self.fm.thisdir.refilter()
            i+=1
        self.fm.thisdir.refilter()

        
        # (search_results, _err) = process.communicate()
        # search_results = search_results.split('\n')

        # i = 0
        # for search_result in search_results:
        #     # code.interact(local=globals().update(locals()) or globals())
        #     if search_result:
        #         self.fm.thisdir.filter_stack.append(
        #             SIMPLE_FILTERS['name'](search_result[2:])
        #         )
        #     if not i % 5:
        #         self.fm.thisdir.refilter()
        #     i+=1
        # self.fm.thisdir.refilter()
