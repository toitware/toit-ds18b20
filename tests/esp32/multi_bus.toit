// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import expect show *
import gpio

import ds18b20 show Ds18b20
import one_wire
import one_wire.family show FAMILY_DS18B20 family_id family_to_string

/**
Tests broadcast and alarm functionality on multiple DS18B20 sensors.

# Setup
Connect multiple DS18B20 sensors to pin 18 on the ESP32. The
  sensors can be parasitic or not (or a combination of them).
If all sensors are parasitic without any pull-up resistor, then
  the instantiation of the bus must be changed to use the internal
  pull-up resistor.
*/

GPIO_PIN_NUM ::= 18

main:
  pin := gpio.Pin GPIO_PIN_NUM
  bus := one_wire.Bus pin

  // A broadcast device to address all devices on the bus.
  broadcast := Ds18b20.broadcast --bus=bus

  devices := []
  bus.do: | id/int |
    family := family_id --device_id = id
    if family != FAMILY_DS18B20:
      print """
        This example uses a broadcast device which only works if all
        devices on the bus are DS18B20 sensors.
        """
      throw "Wrong device family: $(family_to_string family)"
    devices.add (Ds18b20 --bus=bus --id=id)

  expect devices.size > 1

  // Start a conversion on all devices.
  broadcast.do_conversion

  temperatures := []
  devices.do: | ds18b20/Ds18b20 |
    temperature := ds18b20.read_temperature_from_scratchpad
    temperatures.add temperature
  expect_equals devices.size temperatures.size

  // Set an alarm.
  // Since the sensors are likely in the same room, we are going to trigger
  // them all at the same time. (The resolution for alarms is only 1 degree C.)
  alarm_temperature := temperatures[0] - 5.0
  broadcast.write_scratchpad
      --low_alarm_temperature=-100.0
      --high_alarm_temperature=alarm_temperature

  // Start a conversion on all devices.
  broadcast.do_conversion

  alarmed_devices := []
  bus.do --alarm_only: | id/int |
    alarmed_devices.add id
  expect_equals devices.size alarmed_devices.size

  // Set the alarm range to something that will not trigger.
  broadcast.write_scratchpad
      --low_alarm_temperature=-100.0
      --high_alarm_temperature=100.0

  // Start a conversion on all devices.
  broadcast.do_conversion

  alarms_triggered := 0
  bus.do --alarm_only: | id/int |
    alarms_triggered++

  expect_equals 0 alarms_triggered

  // Now set the lower alarm to trigger.
  alarm_temperature = temperatures[0] + 5.0
  broadcast.write_scratchpad
      --low_alarm_temperature=alarm_temperature
      --high_alarm_temperature=100.0

  // Start a conversion on all devices.
  broadcast.do_conversion

  alarms_triggered = 0
  bus.do --alarm_only: | id/int |
    alarms_triggered++
  expect_equals devices.size alarms_triggered

  devices.do: it.close
  broadcast.close
  bus.close
  pin.close

  print "All tests passed."
