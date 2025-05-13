// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

/**
Tests the scratchpad and EEPROM functionality.

# Setup
Connect a single powered DS18B20 to GPIO pin 18.
Connect a single parasitic DS18B20 to GPIO pin 19.
*/

import expect show *
import gpio

import ds18b20

POWERED-PIN := 18
PARASITIC-PIN := 19

main:
  powered := ds18b20.Ds18b20 (gpio.Pin POWERED-PIN)
  run-test powered --parasitic=false

  parasitic := ds18b20.Ds18b20 (gpio.Pin PARASITIC-PIN) --pull-up
  run-test parasitic --parasitic

  print "All tests passed."

run-test device/ds18b20.Ds18b20 --parasitic/bool:
  print "Testing parasitic: $parasitic"
  expect-equals parasitic device.is-parasitic

  // Test that reading the scratchpad works.
  // The driver automatically checks the CRC, so this is already testing a bit.
  scratchpad := device.read-scratchpad
  expect-equals 9 scratchpad.size

  // Test that writing the scratchpad works.
  resolution-register-value := 0b11 << 5
  high := random 255
  low := random 255
  device.write-scratchpad #[high, low, resolution-register-value]

  // Read the values back.
  scratchpad = device.read-scratchpad
  expect-equals 9 scratchpad.size
  expect-equals high scratchpad[2]
  expect-equals low scratchpad[3]
  // The DS18B20 forces the configuration bit 8 to 0, and bits 0-4 to 1.
  expect-equals 0x7F scratchpad[4]

  // Commit the values to the EEPROM.
  device.copy-scratchpad-to-eeprom

  // Read the values back.
  // They should still be the same.
  scratchpad = device.read-scratchpad
  expect-equals 9 scratchpad.size
  expect-equals high scratchpad[2]
  expect-equals low scratchpad[3]
  expect-equals 0x7F scratchpad[4]

  // Write new values into the scratchad.
  resolution-register-value = 0b00 << 5
  device.write-scratchpad #[0x12, 0x34, resolution-register-value]

  // Read the values back.
  scratchpad = device.read-scratchpad
  expect-equals 9 scratchpad.size
  expect-equals 0x12 scratchpad[2]
  expect-equals 0x34 scratchpad[3]
  // As before: the DS18B20 forces the configuration bit 8 to 0, and bits 0-4 to 1.
  expect-equals 0x1F scratchpad[4]

  // Recall the values from the EEPROM.
  device.recall-eeprom

  // Read the scratchpad again. It should be back to the values
  // we stored in the EEPROM.
  scratchpad = device.read-scratchpad
  expect-equals 9 scratchpad.size
  expect-equals high scratchpad[2]
  expect-equals low scratchpad[3]
  expect-equals 0x7F scratchpad[4]

