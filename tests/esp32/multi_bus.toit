// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import expect show *
import gpio

import ds18b20 show Ds18b20
import one-wire
import one-wire.family show FAMILY-DS18B20 family-id family-to-string

/**
Tests broadcast and alarm functionality on multiple DS18B20 sensors.

# Setup
Connect multiple DS18B20 sensors to pin 18 on the ESP32. The
  sensors can be parasitic or not (or a combination of them).
If all sensors are parasitic without any pull-up resistor, then
  the instantiation of the bus must be changed to use the internal
  pull-up resistor.
*/

GPIO-PIN-NUM ::= 18

main:
  pin := gpio.Pin GPIO-PIN-NUM
  bus := one-wire.Bus pin

  // A broadcast device to address all devices on the bus.
  broadcast := Ds18b20.broadcast --bus=bus

  devices := []
  bus.do: | id/int |
    family := family-id --device-id = id
    if family != FAMILY-DS18B20:
      print """
        This example uses a broadcast device which only works if all
        devices on the bus are DS18B20 sensors.
        """
      throw "Wrong device family: $(family-to-string family)"
    devices.add (Ds18b20 --bus=bus --id=id)

  expect devices.size > 1

  // Start a conversion on all devices.
  broadcast.do-conversion

  temperatures := []
  devices.do: | ds18b20/Ds18b20 |
    temperature := ds18b20.read-temperature-from-scratchpad
    temperatures.add temperature
  expect-equals devices.size temperatures.size

  // Set an alarm.
  // Since the sensors are likely in the same room, we are going to trigger
  // them all at the same time. (The resolution for alarms is only 1 degree C.)
  alarm-temperature := temperatures[0] - 5.0
  broadcast.write-scratchpad
      --low-alarm-temperature=-100.0
      --high-alarm-temperature=alarm-temperature

  // Start a conversion on all devices.
  broadcast.do-conversion

  alarmed-devices := []
  bus.do --alarm-only: | id/int |
    alarmed-devices.add id
  expect-equals devices.size alarmed-devices.size

  // Set the alarm range to something that will not trigger.
  broadcast.write-scratchpad
      --low-alarm-temperature=-100.0
      --high-alarm-temperature=100.0

  // Start a conversion on all devices.
  broadcast.do-conversion

  alarms-triggered := 0
  bus.do --alarm-only: | id/int |
    alarms-triggered++

  expect-equals 0 alarms-triggered

  // Now set the lower alarm to trigger.
  alarm-temperature = temperatures[0] + 5.0
  broadcast.write-scratchpad
      --low-alarm-temperature=alarm-temperature
      --high-alarm-temperature=100.0

  // Start a conversion on all devices.
  broadcast.do-conversion

  alarms-triggered = 0
  bus.do --alarm-only: | id/int |
    alarms-triggered++
  expect-equals devices.size alarms-triggered

  devices.do: it.close
  broadcast.close
  bus.close
  pin.close

  print "All tests passed."
