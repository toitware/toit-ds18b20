// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ds18b20 show Ds18b20
import one-wire
import one-wire.family show FAMILY-DS18B20 family-id family-to-string
import gpio

/**
Demonstrates how to use multiple DS18B20 sensors on the same bus.
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

  is-parasitic := broadcast.is-parasitic
  print "is at least one device parasitic: $is-parasitic"

  // Start a conversion on all devices.
  print "Starting a conversion on all devices."
  broadcast.do-conversion

  print "Reading the temperatures from the scratchpads."
  temperatures := []
  devices.do: | ds18b20/Ds18b20 |
    temperature := ds18b20.read-temperature-from-scratchpad
    temperatures.add temperature
    print "$(%x ds18b20.id): $(%.2f temperature) C"

  // Set an alarm.
  // Since the sensors are likely in the same room, we are going to trigger
  // them all at the same time. (The resolution for alarms is only 1 degree C.)
  alarm-temperature := temperatures[0] - 5.0
  broadcast.write-scratchpad
      --low-alarm-temperature=-100.0
      --high-alarm-temperature=alarm-temperature

  // Start a conversion on all devices.
  print "Starting a conversion on all devices."
  broadcast.do-conversion

  bus.do --alarm-only: | id/int |
    print "Alarm on device $(%x id)"

  // Set the alarm range to something that will not trigger.
  broadcast.write-scratchpad
      --low-alarm-temperature=-100.0
      --high-alarm-temperature=100.0

  // Start a conversion on all devices.
  print "Starting a conversion on all devices."
  broadcast.do-conversion

  alarms-triggered := 0
  bus.do --alarm-only: | id/int |
    alarms-triggered++
    print "Alarm on device $(%x id)"

  if alarms-triggered == 0:
    print "As expected, no alarms were triggered."
  else:
    throw "Expected no alarms to be triggered."

  devices.do: it.close
  broadcast.close
  bus.close
  pin.close
