// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ds18b20 show Ds18b20
import expect show *
import gpio

GPIO_PIN_NUM ::= 18

main:
  pin := gpio.Pin GPIO_PIN_NUM
  ds18b20 := Ds18b20 pin

  // Use the low and high temperature registers as external memory.
  scratchpad := ds18b20.read_scratchpad

  // Since we don't want to change the resolution of the sensor, we only
  // change the alarm registers.
  ds18b20.write_scratchpad #[
    0x12,
    0x34,
    scratchpad[4],  // The resolution is the 5th byte of the read bytes.
  ]

  // We can read the scratchpad back:
  scratchpad = ds18b20.read_scratchpad
  // Now our stored values are in position 2 and 3.
  expect_equals 0x12 scratchpad[2]
  expect_equals 0x34 scratchpad[3]

  // Commit the values to the sensor's EEPROM.
  // After this call, the values will be restored when the sensor is powered up.
  ds18b20.copy_scratchpad_to_eeprom

  // We can still modify the scratchpad.
  ds18b20.write_scratchpad #[
    0x56,
    0x78,
    scratchpad[4],
  ]

  // Again: we can read them back:
  scratchpad = ds18b20.read_scratchpad
  expect_equals 0x56 scratchpad[2]
  expect_equals 0x78 scratchpad[3]

  // We can also restore the values that were stored in the EEPROM.
  ds18b20.recall_eeprom

  // And read them back:
  scratchpad = ds18b20.read_scratchpad
  expect_equals 0x12 scratchpad[2]
  expect_equals 0x34 scratchpad[3]

  ds18b20.close
  pin.close
