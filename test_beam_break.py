import time
from machine import Pin

sensors = [
    {"name": "Beam 1", "pin": Pin(16, Pin.IN, Pin.PULL_UP)},  # GP16 = physical pin 21
    {"name": "Beam 2", "pin": Pin(17, Pin.IN, Pin.PULL_UP)},  # GP17 = physical pin 22
]

for s in sensors:
    s["last"] = s["pin"].value()
    s["broken_at"] = None

print("Beam sensors ready")

while True:
    for s in sensors:
        state = s["pin"].value()
        if state != s["last"]:
            s["last"] = state
            now = time.ticks_ms()
            if state == 0:
                s["broken_at"] = now
                print(s["name"], "broken")
            elif s["broken_at"] is not None:
                print(s["name"], "restored after", time.ticks_diff(now, s["broken_at"]), "ms")
            else:
                print(s["name"], "restored")
    time.sleep_ms(5)