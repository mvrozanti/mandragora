#!/usr/bin/env python3
import subprocess
import time
import threading
import os
import signal

# Configuration
HOLD_DURATION = 0.064  # seconds to hold highlight before fading
FADE_DURATION = 0.064  # seconds for fade effect
HIGHLIGHT_COLOR = "#ffffff"
NORMAL_COLOR = "#00000000"
HIGHLIGHT_WIDTH = 3      
NORMAL_WIDTH = 0        

class BorderManager:
    def __init__(self):
        self.current_window = None
        self.timer = None
        self.fade_thread = None
        self.stop_fade = threading.Event()
        
        # Store original bspwm border settings
        self.original_border_width = self.get_bspwm_setting("border_width")
        self.original_border_color = self.get_bspwm_setting("border_color")
        
        # Set initial transparent border globally
        self.set_global_border(NORMAL_WIDTH, NORMAL_COLOR)
    
    def get_bspwm_setting(self, setting):
        """Get current bspwm setting"""
        try:
            result = subprocess.check_output(
                ["bspc", "config", setting],
                text=True
            ).strip()
            return result
        except:
            return ""
    
    def set_global_border(self, width, color):
        """Set global border settings (affects new windows)"""
        subprocess.run(["bspc", "config", "border_width", str(width)], 
                      capture_output=True)
        subprocess.run(["bspc", "config", "border_color", color], 
                      capture_output=True)
    
    def set_window_border(self, window_id, width, color):
        """Set border for specific window"""
        if not window_id or window_id == "0x0":
            return False
        
        # Check if window exists
        try:
            subprocess.run(["xwininfo", "-id", window_id], 
                          capture_output=True, timeout=0.5)
        except:
            return False
        
        # Set border width and color
        subprocess.run(["bspc", "config", "-n", window_id, 
                       "border_width", str(width)], 
                      capture_output=True)
        subprocess.run(["bspc", "config", "-n", window_id, 
                       "border_color", color], 
                      capture_output=True)
        return True
    
    def get_window_count_in_desktop(self, window_id):
        """Count windows in the same desktop as given window"""
        try:
            # Get desktop ID for the window
            desktop_id = subprocess.check_output(
                ["bspc", "query", "-D", "-n", window_id],
                text=True
            ).strip()
            
            # Count windows in that desktop
            windows = subprocess.check_output(
                ["bspc", "query", "-N", "-d", desktop_id, "-n", ".window"],
                text=True
            ).strip().split('\n')
            
            return len([w for w in windows if w])
        except:
            return 1
    
    def clear_highlight(self, window_id):
        """Remove highlight from window"""
        if window_id:
            # Set to normal (transparent) border
            self.set_window_border(window_id, NORMAL_WIDTH, NORMAL_COLOR)
    
    def fade_out_border(self, window_id):
        """Smoothly fade out border"""
        self.stop_fade.clear()
        
        # First, check if we're still in a multi-window desktop
        if self.get_window_count_in_desktop(window_id) <= 1:
            self.clear_highlight(window_id)
            return
        
        # Fade steps
        steps = 15
        for i in range(steps, -1, -1):
            if self.stop_fade.is_set():
                break
            
            # Calculate current width (fading from HIGHLIGHT_WIDTH to NORMAL_WIDTH)
            ratio = i / steps
            current_width = int(HIGHLIGHT_WIDTH * ratio + NORMAL_WIDTH * (1 - ratio))
            
            # Apply border
            self.set_window_border(window_id, current_width, HIGHLIGHT_COLOR)
            
            time.sleep(FADE_DURATION / steps)
        
        # Ensure final state
        if not self.stop_fade.is_set():
            self.clear_highlight(window_id)
    
    def on_focus_change(self, window_id):
        """Handle window focus change"""
        # Stop any ongoing fade
        self.stop_fade.set()
        if self.fade_thread and self.fade_thread.is_alive():
            self.fade_thread.join(timeout=0.1)
        
        # Clear previous window highlight
        if self.current_window and self.current_window != window_id:
            self.clear_highlight(self.current_window)
        
        # Clear any timer
        if self.timer and self.timer.is_alive():
            self.timer = None
        
        if not window_id or window_id == "0x0":
            self.current_window = None
            return
        
        self.current_window = window_id
        
        # Check if we're in a multi-window desktop
        window_count = self.get_window_count_in_desktop(window_id)
        if window_count <= 1:
            # Single window - no border
            self.clear_highlight(window_id)
            return
        
        # Multi-window desktop - apply highlight
        if self.set_window_border(window_id, HIGHLIGHT_WIDTH, HIGHLIGHT_COLOR):
            # Start fade timer
            def delayed_fade():
                time.sleep(HOLD_DURATION)
                # Check if we're still on the same window
                if self.current_window == window_id:
                    self.fade_thread = threading.Thread(
                        target=self.fade_out_border,
                        args=(window_id,)
                    )
                    self.fade_thread.daemon = True
                    self.fade_thread.start()
            
            self.timer = threading.Thread(target=delayed_fade)
            self.timer.daemon = True
            self.timer.start()
    
    def run(self):
        """Main loop - subscribe to bspc events"""
        print("Border highlight manager started...")
        print(f"Hold duration: {HOLD_DURATION}s, Fade duration: {FADE_DURATION}s")
        
        # Subscribe to bspc focus events
        proc = subprocess.Popen(
            ["bspc", "subscribe", "node_focus", "node_remove", "node_add"],
            stdout=subprocess.PIPE,
            text=True
        )
        
        try:
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                
                parts = line.split()
                event_type = parts[0] if parts else ""
                
                if event_type == "node_focus" and len(parts) >= 4:
                    window_id = parts[3]
                    self.on_focus_change(window_id)
                elif event_type == "node_remove":
                    # If current window was removed, clear it
                    if self.current_window and self.current_window == parts[3]:
                        self.current_window = None
                        self.stop_fade.set()
                elif event_type == "node_add":
                    # Re-check current window's desktop count
                    if self.current_window:
                        self.on_focus_change(self.current_window)
                        
        except KeyboardInterrupt:
            print("\nExiting...")
        finally:
            # Restore original borders
            self.set_global_border(self.original_border_width, 
                                 self.original_border_color)
            proc.terminate()
            proc.wait()

if __name__ == "__main__":
    manager = BorderManager()
    manager.run()
