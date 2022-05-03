// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import binary show LITTLE_ENDIAN
import one_wire

class Driver:
  // Rom commands
  static READ_ROM_ ::= 0x33
  static MATCH_ROM_ ::= 0x55
  static SKIP_ROM_ ::= 0xCC

  static ALARM_SEARCH_ ::= 0xEC
  static CONVERT_TEMPERATURE_ ::= 0x44
  static WRITE_SCRATCHPAD_ ::= 0x4E
  static READ_SCRATCHPAD_ ::= 0xBE
  static COPY_SCRATCHPAD_ ::= 0x48
  static RECALL_E2_ ::= 0xB8
  static READ_POWER_SUPPLY_ ::= 0xB4


  ow_ /one_wire.Protocol

  /**
  Constructs an instance of the DS18B20 sensor driver.
  */
  constructor .ow_:

  /**
  Reads the temperature and returns it in degrees Celsius.
  */
  read_temperature -> float:
    return raw_read_ / 16.0

  raw_read_ -> int:
    ow_.reset
    // Convert temperature.
    ow_.write_byte SKIP_ROM_
    ow_.write_byte CONVERT_TEMPERATURE_
    sleep --ms=750
    ow_.reset
    // Read scratchpad.
    bytes := ow_.write_then_read #[SKIP_ROM_, READ_SCRATCHPAD_] 2
    return LITTLE_ENDIAN.int16 bytes 0

  /** Whether the sensor is in parasitic mode (as reported by the sensor). */
  is_parasitic -> bool:
    ow_.reset
    ow_.write_byte SKIP_ROM_
    ow_.write_byte READ_POWER_SUPPLY_
    result := ow_.read_bits 1
    return result == 0
