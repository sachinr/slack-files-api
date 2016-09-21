require 'chunky_png'
avatar = ChunkyPNG::Image.from_file('./files/avatar.png')
badge  = ChunkyPNG::Image.from_file('./files/overlay.png')
avatar.compose!(badge, 100, 100)
avatar.save('composited.png', :fast_rgba) # Force the fast saving routine.
