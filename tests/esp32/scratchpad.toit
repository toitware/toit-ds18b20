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

POWERED_PIN := 18
PARASITIC_PIN := 19

main:
  powered := ds18b20.Ds18b20 (gpio.Pin POWERED_PIN)
  run_test powered --parasitic=false

  parasitic := ds18b20.Ds18b20 (gpio.Pin PARASITIC_PIN) --pull_up
  run_test parasitic --parasitic

  print "All tests passed."

run_test device/ds18b20.Ds18b20 --parasitic/bool:
  print "Testing parasitic: $parasitic"
  expect_equals parasitic device.is_parasitic

  // Test that reading the scratchpad works.
  // The driver automatically checks the CRC, so this is already testing a bit.
  scratchpad := device.read_scratchpad
  expect_equals 9 scratchpad.size

  // Test that writing the scratchpad works.
  resolution_register_value := 0b11 << 5
  high := random 255
  low := random 255
  device.write_scratchpad #[high, low, resolution_register_value]

  // Read the values back.
  scratchpad = device.read_scratchpad
  expect_equals 9 scratchpad.size
  expect_equals high scratchpad[2]
  expect_equals low scratchpad[3]
  // The ds18b20 forces the configuration bit 8 to 0, and bits 0-4 to 1.
  expect_equals 0x7F scratchpad[4]

  // Commit the values to the EEPROM.
  device.copy_scratchpad_to_eeprom

  // Read the values back.
  // They should still be the same.
  scratchpad = device.read_scratchpad
  expect_equals 9 scratchpad.size
  expect_equals high scratchpad[2]
  expect_equals low scratchpad[3]
  expect_equals 0x7F scratchpad[4]

  // Write new values into the scratchad.
  resolution_register_value = 0b00 << 5
  device.write_scratchpad #[0x12, 0x34, resolution_register_value]

  // Read the values back.
  scratchpad = device.read_scratchpad
  expect_equals 9 scratchpad.size
  expect_equals 0x12 scratchpad[2]
  expect_equals 0x34 scratchpad[3]
  // As before: the ds18b20 forces the configuration bit 8 to 0, and bits 0-4 to 1.
  expect_equals 0x1F scratchpad[4]

  // Recall the values from the EEPROM.
  device.recall_eeprom

  // Read the scratchpad again. It should be back to the values
  // we stored in the EEPROM.
  scratchpad = device.read_scratchpad
  expect_equals 9 scratchpad.size
  expect_equals high scratchpad[2]
  expect_equals low scratchpad[3]
  expect_equals 0x7F scratchpad[4]

