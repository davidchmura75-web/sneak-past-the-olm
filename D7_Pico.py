# Dinosaucers P2M4 Pico Code
# D.Chmura
# 11/9/2026
# Milestone 4
# Broadcasts accelerometer data and beam break detection and listens for LED brightness and listens for LED signals

from machine import I2C, Pin
import time
import struct
import select
import sys
import neopixel

# set up i2c communication with the accelerometer
i2c = I2C(0, sda=Pin(0), scl=Pin(1), freq=400000)
ADDR = 0x53
def wake_accel():
    # set up the I2C Communication between pico and accelerometer
    # (wrapped so a loose wire doesn't crash the whole script)
    try:
        i2c.writeto_mem(ADDR, 0x2D, b'\x08')
        return True
    except OSError:
        return False

wake_accel()
last_accel_error = time.ticks_add(time.ticks_ms(), -2000) # last time we reported an accelerometer error

# Set up LED Strip
LED_PIN = 18
NUM_LEDS = 19 # number of LEDs on strip
strip = neopixel.NeoPixel(Pin(LED_PIN), NUM_LEDS)
LED_COLOR = (255, 0, 0) # full brightness color
strip.fill((0, 0, 0)) # start with strip off
strip.write()

# Beam Break Sensor Pins
StartBeamPin = 16
start_beam = Pin(StartBeamPin, Pin.IN, Pin.PULL_UP)
EndBeamPin = 17
end_beam = Pin(EndBeamPin, Pin.IN, Pin.PULL_UP)

# Board LED pin to show if code crashed or not
BoardLEDPIN = 25
boardled = Pin(BoardLEDPIN, Pin.OUT)

# Start Pin
StartButtonPin = 22
start_button = Pin(StartButtonPin, Pin.IN, Pin.PULL_UP)

# Accelerometer Values
accel_x = 0
accel_y = 0
accel_z = 0
accel_magnitude = 0

# values to use to adjust raw data
g = 9.81
sensor_multiplier = (1 / 256.0) * g # 1 / 256 * 9.81(g)

# Start Button Debounce Values
DEBOUNCE_MS = 50 # button settle time
button_state = 1 # 1 = not pressed
last_button_reading = 1 # last raw reading
last_button_change = time.ticks_ms() # last change time

# Beam Break Debounce Values
BEAM_WINDOW_MS = 20 # beam settle time
start_beam_state = start_beam.value() # 0 = part on
last_start_beam_reading = start_beam_state # last raw reading
last_start_beam_change = time.ticks_ms() # last change time
end_beam_state = end_beam.value() # 0 = part on
last_end_beam_reading = end_beam_state # last raw reading
last_end_beam_change = time.ticks_ms() # last change time
# Tell MATLAB the current beam states on boot so it's in sync after a restart
print(f"B2:{1 - start_beam_state}")
print(f"B3:{1 - end_beam_state}")

try:
    while True:
        boardled.on()
        # HANDLE ACCELEROMETER DATA
        # A bad I2C read (loose wire, bump) used to raise OSError and kill the script.
        # Now we skip that sample, try to wake the sensor back up, and tell MATLAB (max once a second)
        try:
            x, y, z = struct.unpack('<hhh', i2c.readfrom_mem(ADDR, 0x32, 6))
        except OSError:
            x = None
            wake_accel()
            if time.ticks_diff(time.ticks_ms(), last_accel_error) > 1000:
                last_accel_error = time.ticks_ms()
                print("E1:accelerometer read failed - check wiring")

        if x is not None:
            accel_x = x*sensor_multiplier
            accel_y = y*sensor_multiplier
            accel_z = z*sensor_multiplier
            # print("x=%.2fg y=%.2fg z=%.2fg" % (accel_x, accel_y, accel_z))
            accel_magnitude = (((accel_x)**2) + ((accel_y+g)**2) + ((accel_z)**2))**0.5 # combine the magnitude of X and Y accelerations, as well as the z acceleration, accounting for earth's gravity by removing 1g
            # print(accel_magnitude)

            # OUTPUT onto serial
            print(f"S1:{accel_magnitude}")

        # HANDLE START BUTTON - debounced so one press only sends one message
        button_reading = start_button.value()

        # If the raw reading changed, restart the debounce timer
        if button_reading != last_button_reading:
            last_button_change = time.ticks_ms()
            last_button_reading = button_reading

        # If the reading has stayed the same long enough and is different, accept it as the real state
        if time.ticks_diff(time.ticks_ms(), last_button_change) > DEBOUNCE_MS and button_reading != button_state:
            button_state = button_reading

            # Button reads 0 when pressed because of the pull up, so only send on the press
            if button_state == 0:
                print("B1:1")

        # HANDLE START BEAM - sends 1 when a part is on the beam and 0 when it leaves
        start_beam_reading = start_beam.value()

        # If the raw reading changed, restart the window timer
        if start_beam_reading != last_start_beam_reading:
            last_start_beam_change = time.ticks_ms()
            last_start_beam_reading = start_beam_reading

        # If the reading has stayed the same for the whole window and is different, send the change
        if time.ticks_diff(time.ticks_ms(), last_start_beam_change) > BEAM_WINDOW_MS and start_beam_reading != start_beam_state:
            start_beam_state = start_beam_reading
            print(f"B2:{1 - start_beam_state}") # flip it so 1 = part on the beam, 0 = clear

        # HANDLE END BEAM - sends 1 when a part is on the beam and 0 when it leaves
        end_beam_reading = end_beam.value()

        # If the raw reading changed, restart the window timer
        if end_beam_reading != last_end_beam_reading:
            last_end_beam_change = time.ticks_ms()
            last_end_beam_reading = end_beam_reading

        # If the reading has stayed the same for the whole window and is different, send the change
        if time.ticks_diff(time.ticks_ms(), last_end_beam_change) > BEAM_WINDOW_MS and end_beam_reading != end_beam_state:
            end_beam_state = end_beam_reading
            print(f"B3:{1 - end_beam_state}") # flip it so 1 = part on the beam, 0 = clear

        # check for serial data - This shows how much vibrations the olm detects, sent as a brightness percentage
        if select.select([sys.stdin], [], [], 0)[0]:
            
            # Read a character from the buffer
            ser_code = sys.stdin.read(1)

            # IF that character is our identifier
            if ser_code == 'a':

                # Get following number
                number_string = sys.stdin.readline().strip()
                try:
                    data_in = int(float(number_string))  # float first so "50.0" also works
                except ValueError:
                    data_in = None  # ignore garbage instead of crashing

                if data_in is not None:
                    # Clamp to 0-100 so a bad value can't index past the strip
                    data_in = max(0, min(100, data_in))

                    # Scale the strip color by the 0-100 brightness percentage
                    led_brightness = data_in / 100
                    r, g_val, b = LED_COLOR
                    color = (int(r * led_brightness * 0.5), int(g_val * led_brightness * 0.5), int(b * led_brightness * 0.5))

                    strip.fill((0, 0, 0))  # clear the strip (fill takes ONE tuple)
                    for i in range(int(NUM_LEDS * led_brightness)):
                        strip[i] = color  # light LEDs one at a time

                    # Write that color to the LED strip
                    strip.write()
        
        time.sleep(1 / 120.0) # sleep to assure reading quality
finally:
    boardled.off()
    strip.fill((0, 0, 0)) # turn the strip off if the code stops
    strip.write()

