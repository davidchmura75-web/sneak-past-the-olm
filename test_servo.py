import time
from machine import Pin, PWM

# Same settings as D7_Pico.py
SERVO_PIN = 13          # GP13 = physical pin 17
SERVO_MIN_US = 500      # pulse width at 0 degrees
SERVO_MAX_US = 2500     # pulse width at 180 degrees

servo = PWM(Pin(SERVO_PIN))
servo.freq(50)          # 20 ms period

def set_servo(angle):
    angle = max(0, min(180, angle))
    pulse_us = SERVO_MIN_US + (SERVO_MAX_US - SERVO_MIN_US) * angle / 180
    servo.duty_u16(int(pulse_us * 65535 / 20000))
    print("Servo ->", angle, "deg  (", int(pulse_us), "us )")

print("Servo test on GP%d" % SERVO_PIN)

try:
    # 1. Game positions: home (0) and lose (180)
    for angle in (0, 180, 0):
        set_servo(angle)
        time.sleep(1.5)

    # 2. Slow sweep both ways to check the full range
    print("Sweeping...")
    for angle in list(range(0, 181, 10)) + list(range(180, -1, -10)):
        set_servo(angle)
        time.sleep_ms(150)

    # 3. Keep toggling between the game positions until stopped (Ctrl+C)
    print("Toggling 0 <-> 180, Ctrl+C to stop")
    while True:
        set_servo(180)
        time.sleep(2)
        set_servo(0)
        time.sleep(2)
finally:
    servo.deinit()
    print("Servo test stopped")
