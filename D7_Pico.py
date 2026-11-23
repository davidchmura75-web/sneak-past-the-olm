# Dinosaucers P2M4 Pico Code
# D.Chmura
# 11/9/2026
# Milestone 4
# Broadcasts accelerometer data and beam break detection and listens for servo commands
# Serial out: S1 accel, B1 button, B2 start beam, B3 end beam, B4-B6 special event beams, V1 servo, E1 errors

from machine import I2C, Pin, PWM
import time
import struct
import select
import sys

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

# Beam Break Sensor Pins
StartBeamPin = 15
start_beam = Pin(StartBeamPin, Pin.IN, Pin.PULL_UP)
EndBeamPin = 16
end_beam = Pin(EndBeamPin, Pin.IN, Pin.PULL_UP)

# Special Event Beam Break Sensor Pins - sent to MATLAB as B4, B5 and B6
SpecialBeamPins = [27, 17, 14] # side path 1 = GP14 (pin 19), side path 2 = GP17 (pin 22), side path 3 = GP27 (pin 32)
special_beams = []
for i, pin_num in enumerate(SpecialBeamPins):
    special_beams.append({
        "code": f"B{4 + i}", # B4 = special event 1, B5 = event 2, B6 = event 3
        "pin": Pin(pin_num, Pin.IN, Pin.PULL_UP),
    })

# Board LED pin to show if code crashed or not
BoardLEDPIN = 25
boardled = Pin(BoardLEDPIN, Pin.OUT)

# Start Pin
StartButtonPin = 18
start_button = Pin(StartButtonPin, Pin.IN, Pin.PULL_UP)

# Servo Pin - standard hobby servo driven with 50 Hz PWM
ServoPin = 13
servo = PWM(Pin(ServoPin))
servo.freq(50) # 20 ms period
SERVO_MIN_US = 500 # pulse width at 0 degrees
SERVO_MAX_US = 2500 # pulse width at 180 degrees
def set_servo(angle):
    # Clamp to 0-180 and convert the angle to a pulse width, then to a 16-bit duty cycle
    angle = max(0, min(180, angle))
    pulse_us = SERVO_MIN_US + (SERVO_MAX_US - SERVO_MIN_US) * angle / 180
    servo.duty_u16(int(pulse_us * 65535 / 20000))

set_servo(0) # start at the home position

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
for beam in special_beams:
    beam["state"] = beam["pin"].value() # 0 = part on
    beam["last_reading"] = beam["state"] # last raw reading
    beam["last_change"] = time.ticks_ms() # last change time
# Tell MATLAB the current beam states on boot so it's in sync after a restart
print(f"B2:{1 - start_beam_state}")
print(f"B3:{1 - end_beam_state}")
for beam in special_beams:
    print(f"{beam['code']}:{1 - beam['state']}")
print("V1:0") # servo starts at home

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

        # HANDLE SPECIAL EVENT BEAMS - same debounce as the start/end beams, sends B4/B5/B6
        for beam in special_beams:
            reading = beam["pin"].value()

            # If the raw reading changed, restart the window timer
            if reading != beam["last_reading"]:
                beam["last_change"] = time.ticks_ms()
                beam["last_reading"] = reading

            # If the reading has stayed the same for the whole window and is different, send the change
            if time.ticks_diff(time.ticks_ms(), beam["last_change"]) > BEAM_WINDOW_MS and reading != beam["state"]:
                beam["state"] = reading
                print(f"{beam['code']}:{1 - reading}") # flip it so 1 = part on the beam, 0 = clear

        # check for serial data from MATLAB (servo commands)
        if select.select([sys.stdin], [], [], 0)[0]:
            
            # Read a character from the buffer
            ser_code = sys.stdin.read(1)

            # IF that character is the servo identifier, move the servo to that angle (e.g. "s180")
            if ser_code == 's':
                angle_string = sys.stdin.readline().strip()
                try:
                    angle = max(0, min(180, int(float(angle_string))))
                    set_servo(angle)
                    print(f"V1:{angle}") # confirm the move back to MATLAB
                except ValueError:
                    pass  # ignore garbage instead of crashing
        
        time.sleep(1 / 120.0) # sleep to assure reading quality
finally:
    boardled.off()
    servo.deinit() # stop sending pulses to the servo

