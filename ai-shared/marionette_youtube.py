#!/usr/bin/env python3
"""Control Firefox via Marionette to play a YouTube video."""

from marionette_driver.marionette import Marionette
from marionette_driver.errors import MarionetteException
import time
import sys

def main():
    try:
        # Connect to existing Firefox instance
        print("Connecting to Firefox Marionette on port 2828...")
        client = Marionette(host='localhost', port=2828)
        client.start_session()
        print("Connected! Current URL:", client.get_url())
        
        # Navigate to YouTube
        print("\nNavigating to YouTube...")
        client.navigate("https://www.youtube.com")
        time.sleep(4)  # Wait for page to load
        
        # Search for a video (use "lofi" as a popular search)
        print("Searching for a video...")
        script = """
        // Try to search for "lofi hip hop"
        const searchBox = document.querySelector('input#search');
        if (searchBox) {
            searchBox.value = 'lofi hip hop radio';
            searchBox.dispatchEvent(new Event('input', {bubbles: true}));
            
            // Click search button
            setTimeout(() => {
                const searchBtn = document.querySelector('button#search-icon-legacy button, button#search button');
                if (searchBtn) searchBtn.click();
            }, 500);
            return 'Search initiated';
        }
        return 'Search box not found';
        """
        
        result = client.execute_script(script)
        print(f"Search result: {result}")
        time.sleep(4)  # Wait for search results
        
        # Click the first video
        print("Clicking first video...")
        click_script = """
        const videoLinks = document.querySelectorAll('ytd-video-renderer a#thumbnail, #video-title');
        if (videoLinks.length > 0) {
            videoLinks[0].click();
            return 'Clicked first video';
        }
        return 'No video links found';
        """
        
        result = client.execute_script(click_script)
        print(f"Click result: {result}")
        time.sleep(5)  # Wait for video page to load
        
        # Try to play the video (click play button if paused)
        print("Attempting to play video...")
        play_script = """
        const video = document.querySelector('video');
        if (video) {
            if (video.paused) {
                video.play();
                return 'Playing video';
            }
            return 'Video already playing';
        }
        return 'No video element found';
        """
        
        result = client.execute_script(play_script)
        print(f"Play result: {result}")
        
        print("\nDone! Check your Firefox window - the video should be playing.")
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        try:
            client.delete_session()
        except:
            pass

if __name__ == "__main__":
    main()
