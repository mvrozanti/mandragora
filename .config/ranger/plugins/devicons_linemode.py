import ranger.api
from ranger.core.linemode import LinemodeBase
from ranger.ext.human_readable import human_readable
from devicons import *
import os

# Maximum depth to calculate cumulative size (1 = current dir only, 2 = one level deep, etc.)
# Lower values = faster but less accurate. Set to 1 for immediate results, higher for accuracy
# Set to 0 for unlimited depth (may be slow on large directories)
MAX_CALCULATION_DEPTH = 1

# Maximum number of entries to scan before giving up (prevents long waits)
# Increase this if you want more accurate sizes but are willing to wait longer
MAX_ENTRIES_TO_SCAN = 500

def get_dir_size_quick(path, max_depth=MAX_CALCULATION_DEPTH, current_depth=0, entry_count=None):
    """Quickly calculate directory size with depth and entry count limits"""
    if entry_count is None:
        entry_count = [0]  # Reset counter for each new calculation
    
    if max_depth > 0 and current_depth >= max_depth:
        return 0  # Return 0 for skipped subdirectories instead of None
    
    total_size = 0
    try:
        entries = list(os.scandir(path))
        # Limit the number of entries we process
        if entry_count[0] + len(entries) > MAX_ENTRIES_TO_SCAN:
            return None  # Too many entries, abort
        
        entry_count[0] += len(entries)
        
        for entry in entries:
            try:
                if entry.is_file(follow_symlinks=False):
                    total_size += entry.stat(follow_symlinks=False).st_size
                elif entry.is_dir(follow_symlinks=False):
                    if max_depth == 0 or current_depth < max_depth - 1:
                        sub_size = get_dir_size_quick(entry.path, max_depth, current_depth + 1, entry_count)
                        if sub_size is not None:
                            total_size += sub_size
                        else:
                            return None  # Abort if we hit the limit
                    # If depth limit reached, skip subdirectories (count as 0)
            except (OSError, PermissionError):
                continue
    except (OSError, PermissionError):
        return None
    
    return total_size

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
      if hasattr(file, 'path'):
        try:
          quick_size = get_dir_size_quick(file.path, MAX_CALCULATION_DEPTH)
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