import ranger.api
import subprocess
import os
from ranger.ext.get_executables import get_executables
from ranger.api.commands import Command

# Cache for media lengths: {path: (length, mtime)}
_media_length_cache = {}
MAX_CACHE_SIZE = 1000

HOOK_INIT_OLD = ranger.api.hook_init

def get_media_length(path):
    """Get the duration of a media file (video or audio) in seconds."""
    # Check cache first
    if path in _media_length_cache:
        cached_length, cached_mtime = _media_length_cache[path]
        try:
            current_mtime = os.path.getmtime(path)
            if current_mtime == cached_mtime:
                return cached_length
        except (OSError, PermissionError):
            pass
    
    # Try ffprobe first (most common)
    if 'ffprobe' in get_executables():
        try:
            result = subprocess.run(
                ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                 '-of', 'default=noprint_wrappers=1:nokey=1', path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                universal_newlines=True
            )
            if result.returncode == 0:
                duration = float(result.stdout.strip())
                # Update cache
                try:
                    mtime = os.path.getmtime(path)
                    if len(_media_length_cache) >= MAX_CACHE_SIZE:
                        # Remove oldest entry (simple FIFO)
                        _media_length_cache.pop(next(iter(_media_length_cache)))
                    _media_length_cache[path] = (duration, mtime)
                    return duration
                except (OSError, PermissionError):
                    return duration
        except (subprocess.TimeoutExpired, ValueError, subprocess.SubprocessError):
            pass
    
    # Fallback to mediainfo
    if 'mediainfo' in get_executables():
        try:
            result = subprocess.run(
                ['mediainfo', '--Inform=General;%Duration%', path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                universal_newlines=True
            )
            if result.returncode == 0:
                duration_str = result.stdout.strip()
                if duration_str and duration_str.isdigit():
                    # mediainfo returns duration in milliseconds
                    duration = float(duration_str) / 1000.0
                    # Update cache
                    try:
                        mtime = os.path.getmtime(path)
                        if len(_media_length_cache) >= MAX_CACHE_SIZE:
                            _media_length_cache.pop(next(iter(_media_length_cache)))
                        _media_length_cache[path] = (duration, mtime)
                        return duration
                    except (OSError, PermissionError):
                        return duration
        except (subprocess.TimeoutExpired, ValueError, subprocess.SubprocessError):
            pass
    
    # Return None for non-media files or if extraction fails
    return None

def media_length_sort_key(file, fm=None):
    """Sort key function for media length sorting."""
    if file.is_directory:
        # Directories come first (or last, depending on sort_directories_first)
        # Use a value that will sort before or after files based on the setting
        if fm and fm.settings.sort_directories_first:
            return (0, 0)
        else:
            return (2, 0)
    
    length = get_media_length(file.path)
    if length is None:
        # Non-media files or files where length couldn't be determined
        # Sort them after media files
        return (1, float('inf'))
    
    return (1, length)

def hook_init(fm):
    """Hook to initialize the plugin."""
    HOOK_INIT_OLD(fm)

ranger.api.hook_init = hook_init

def _sort_by_media_length(fm, reverse=False):
    """Helper function to sort by media length."""
    thisdir = fm.thisdir
    if thisdir:
        # Create a sort key function that has access to fm
        def sort_key(file):
            return media_length_sort_key(file, fm)
        
        # Sort using our custom key
        thisdir.files.sort(key=sort_key, reverse=reverse)
        thisdir.files_all.sort(key=sort_key, reverse=reverse)
        thisdir.refilter()
        fm.ui.redraw()

class sort_media_length(Command):
    """:sort_media_length

    Sort files by media (video/audio) length (shortest first).
    """
    
    def execute(self):
        _sort_by_media_length(self.fm, reverse=False)

class sort_media_length_reverse(Command):
    """:sort_media_length_reverse

    Sort files by media (video/audio) length (longest first).
    """
    
    def execute(self):
        _sort_by_media_length(self.fm, reverse=True)

