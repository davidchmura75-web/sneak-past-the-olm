# Programming #8 Homework Part 1
# B.Ramanathan
# 11-8-2026
# P8H_ramanathan_b - Pico and Matlab system for Neopixel LED strip
# Professor O'Connell helped with importing and using the necessary libraries
# Button Logic from P4H
# Buttons on Pico and Matlab inputs to control LEDs on LED strip
# Listens for matlab inputs to change the color pattern of the LEDs

import machine
import machine, neopixel
import sys
import select
import time

BUTTON_PIN = 16    # Pin for the pushbutton
debounce_interval = 0.3

# Variables that will change (Initialized to 0):
button_state = 0   # Variable for reading the pushbutton status
last_button_press_time = 0
current_time = 0
prev_time = 0

# Initialize LED Strip
n = 19 #Number of LED pixels on strip
p = 0 #Pin that the LED is connected to on the Pi Pico
pixels = neopixel.NeoPixel(machine.Pin(p), n)
 
# 8 COLORS
yellow = (255, 100, 0) # yellow
orange = (255, 50, 0) # orange
green = (0, 255, 0) # green
blue = (0, 0, 255) # blue
red = (255, 0, 0) # red
purple = (128, 0, 128) #Purple
magenta = (255, 0, 255) #Magenta
white = (255, 255, 255) #White

colors = [yellow, orange, green, blue, red, purple, magenta, white] # Creates list with all the colors

def set_pixel_brightness(r, g, b, brightness):
  """Scales RGB values (0-255) by a brightness factor (0.0 to 1.0)."""
  return (int(r * brightness), int(g * brightness), int(b * brightness))


bright_level = 0.7   # Can change brightness to what you want
i = 0
def color_pattern(offset = 0):
    """Give each LED the next color in the list, repeating every 8 LEDs.
    offset shifts the starting color (useful later for rotating)."""
    for i in range(n):
        color = colors[(i + offset) % len(colors)]
        pixels[i] = set_pixel_brightness(*color, bright_level)
    pixels.write()
    
def lights_off():
    """Turn every LED completely off."""
    pixels.fill((0, 0, 0))
    pixels.write()
    

# Initialize the pushbutton pin as a digital input:
button = machine.Pin(BUTTON_PIN, machine.Pin.IN, machine.Pin.PULL_UP)

leds_on = True   # Tracks whether the strip is on or off
offset = 0       # Last rotation value received from MATLAB

color_pattern(offset)   # Start with the lights on

# Set up a way to check for messages from MATLAB without pausing the loop
poll = select.poll()
poll.register(sys.stdin, select.POLLIN)

while True:
    current_time = time.ticks_ms() / 1000  # Current time in seconds

    # Check if the pushbutton is pressed
    button_state = button.value()
    #Condition that toggles the LED strip with button press with debounce.
    if button_state == 0 and ((current_time - last_button_press_time) > debounce_interval):
        #print(f"button state {button_state}") - For Debugging
        last_button_press_time = current_time
        leds_on = not leds_on
        if leds_on == True:
            color_pattern(offset)
            # Tell MATLAB the lights are on or off
            print("LEDS:1")     
        else:
            lights_off()
            print("LEDS:0")     
            
    # Check if MATLAB sent a new rotation value
    if poll.poll(0):                        # 0 = don't wait if nothing has arrived
        line = sys.stdin.readline().strip() 
        if line.isdigit():                  # Only use it if it's a number
            offset = int(line)
            if leds_on == True: # Make sure color only rotates when the LEDs are on.
                color_pattern(offset)
# End of Program
