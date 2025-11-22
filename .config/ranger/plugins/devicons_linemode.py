import ranger.api
from ranger.core.linemode import LinemodeBase
from ranger.ext.human_readable import human_readable
from devicons import *
import os

# Maximum depth to calculate cumulative size (1 = current dir only, 2 = one level deep, etc.)
# Set to 0 for unlimited depth (may be slow on large directories)
MAX_CALCULATION_DEPTH = 2

# Cache for directory sizes: {path: (size, mtime)}
_size_cache = {}
# Maximum cache size (to prevent memory issues)
MAX_CACHE_SIZE = 1000

def get_dir_mtime(path):
    """Get the modification time of a directory"""
    try:
        return os.stat(path).st_mtime
    except (OSError, PermissionError):
        return None

def get_dir_size_quick(path, max_depth=MAX_CALCULATION_DEPTH, current_depth=0):
    """Quickly calculate directory size with depth limit"""
    if max_depth > 0 and current_depth >= max_depth:
        return 0  # Return 0 for skipped subdirectories instead of None
    
    total_size = 0
    try:
        entries = list(os.scandir(path))
        
        for entry in entries:
            try:
                if entry.is_file(follow_symlinks=False):
                    total_size += entry.stat(follow_symlinks=False).st_size
                elif entry.is_dir(follow_symlinks=False):
                    if max_depth == 0 or current_depth < max_depth - 1:
                        sub_size = get_dir_size_quick(entry.path, max_depth, current_depth + 1)
                        if sub_size is not None:
                            total_size += sub_size
                        else:
                            return None  # Abort if subdirectory calculation failed
                    # If depth limit reached, skip subdirectories (count as 0)
            except (OSError, PermissionError):
                continue
    except (OSError, PermissionError):
        return None
    
    return total_size

def invalidate_parent_caches(path):
    """Invalidate cache entries for all parent directories of the given path"""
    global _size_cache
    
    # Normalize and ensure path ends with separator for proper prefix matching
    normalized_path = os.path.normpath(path) + os.sep
    
    # Build list of paths to invalidate (parents of the changed path)
    paths_to_invalidate = []
    for cached_path in _size_cache.keys():
        # Normalize cached path for comparison
        normalized_cached = os.path.normpath(cached_path) + os.sep
        # If changed path is a subdirectory of cached path, invalidate the parent
        if normalized_path.startswith(normalized_cached) and normalized_path != normalized_cached:
            paths_to_invalidate.append(cached_path)
    
    # Remove invalidated entries
    for path_to_invalidate in paths_to_invalidate:
        del _size_cache[path_to_invalidate]

def get_cached_dir_size(path, max_depth=MAX_CALCULATION_DEPTH):
    """Get directory size from cache or calculate if needed"""
    global _size_cache
    
    # Get current directory mtime (single stat call)
    current_mtime = get_dir_mtime(path)
    if current_mtime is None:
        return None
    
    # Check cache for this specific directory first (most common case - O(1) lookup)
    if path in _size_cache:
        cached_size, cached_mtime = _size_cache[path]
        # If mtime matches exactly, return cached size immediately (fast path)
        if cached_mtime == current_mtime:
            return cached_size
        # mtime changed - invalidate this entry and all its parent directories
        del _size_cache[path]
        invalidate_parent_caches(path)
    else:
        # Directory not in cache - check if any cached subdirectories have changed
        # This handles edge cases where filesystem mtime propagation might be delayed
        # Limit checks for performance (most filesystems update parent mtime automatically)
        normalized_path = os.path.normpath(path) + os.sep
        subdirs_checked = 0
        MAX_SUBDIR_CHECKS = 5  # Limit subdirectory checks for performance
        
        for cached_path, (cached_size, cached_mtime) in list(_size_cache.items()):
            normalized_cached = os.path.normpath(cached_path) + os.sep
            
            # If cached path is a subdirectory of current path
            if normalized_cached.startswith(normalized_path) and normalized_cached != normalized_path:
                # Check if subdirectory's mtime changed from when it was cached
                sub_mtime = get_dir_mtime(cached_path)
                if sub_mtime is not None and sub_mtime != cached_mtime:
                    # Subdirectory changed, invalidate parent cache
                    invalidate_parent_caches(path)
                    break
                subdirs_checked += 1
                if subdirs_checked >= MAX_SUBDIR_CHECKS:
                    # Limit checks to avoid performance issues
                    break
    
    # Calculate size
    size = get_dir_size_quick(path, max_depth)
    
    # Store in cache if calculation succeeded
    if size is not None:
        # Clean cache if it's too large (remove oldest entries)
        if len(_size_cache) >= MAX_CACHE_SIZE:
            # Remove 20% of oldest entries (by mtime)
            items_to_remove = MAX_CACHE_SIZE // 5
            sorted_items = sorted(_size_cache.items(), key=lambda x: x[1][1])
            for key, _ in sorted_items[:items_to_remove]:
                del _size_cache[key]
        
        _size_cache[path] = (size, current_mtime)
    
    return size

@ranger.api.register_linemode
class DevIconsLinemode(LinemodeBase):
  name = "devicons"

  uses_metadata = False

  def filetitle(self, file, metadata):
    return devicon(file) + ' ' + file.relative_path

  def infostring(self, file, metadata):
    """Display directory size instead of file count"""
    if file.is_directory:
      # Check if cumulative size has been calculated by ranger
      # When cumulative_size_calculated is True, file.size contains cumulative size
      if hasattr(file, 'cumulative_size_calculated') and file.cumulative_size_calculated:
        # Cumulative size has been calculated and stored in file.size
        if hasattr(file, 'size') and file.size is not None:
          return ' ' + human_readable(file.size)
      
      # If ranger hasn't calculated it yet, do a quick calculation with depth limit
      # This avoids blocking for too long on very large directories
      # Uses caching to avoid recalculating unchanged directories
      if hasattr(file, 'path'):
        try:
          quick_size = get_cached_dir_size(file.path, MAX_CALCULATION_DEPTH)
          if quick_size is not None:
            return ' ' + human_readable(quick_size)
        except:
          pass
      
      # If no size available yet, raise NotImplementedError to show default
      # (which will be file count until cumulative size is calculated)
      raise NotImplementedError
    else:
      # For files, use default size display
      raise NotImplementedError

@ranger.api.register_linemode
class DevIconsLinemodeFile(LinemodeBase):
  name = "filename"

  def filetitle(self, file, metadata):
    return devicon(file) + ' ' + file.relative_path