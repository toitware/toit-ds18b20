// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import binary show LITTLE_ENDIAN
import gpio
import one_wire

/**
Driver for the Ds18b20 temperature sensor.
*/
class Ds18b20:
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

  one_wire_bus_ /one_wire.Bus? := ?
  must_close_bus_ /bool

  /**
  Constructs an instance of the DS18B20 sensor driver.

  The given $one_wire_bus_ may be shared with other devices.
  */
  constructor.bus .one_wire_bus_:
    must_close_bus_ = false

  /**
  Constructs an instance of the DS18B20 sensor driver.
  */
  constructor pin/gpio.Pin:
    one_wire_bus_ = one_wire.Bus pin
    must_close_bus_ = true

  /** Whether the driver is closed. */
  is_closed -> bool:
    return one_wire_bus_ == null

  /**
  Closes the driver and releases any resources.
  */
  close:
    if one_wire_bus_ and must_close_bus_:
      one_wire_bus_.close
    one_wire_bus_ = null

  /**
  Reads the temperature and returns it in degrees Celsius.
  */
  read_temperature -> float:
    if is_closed: throw "CLOSED"
    return raw_read_ / 16.0

  raw_read_ -> int:
    if not one_wire_bus_.reset:
      throw "NO DEVICE FOUND"
    // Convert temperature.
    one_wire_bus_.write #[SKIP_ROM_, CONVERT_TEMPERATURE_]
    sleep --ms=750
    one_wire_bus_.reset
    // Read scratchpad.
    one_wire_bus_.write #[SKIP_ROM_, READ_SCRATCHPAD_]
    bytes := one_wire_bus_.read 2
    return LITTLE_ENDIAN.int16 bytes 0

  /** Whether the sensor is in parasitic mode (as reported by the sensor). */
  is_parasitic -> bool:
    if is_closed: throw "CLOSED"
    if not one_wire_bus_.reset:
      throw "NO DEVICE FOUND"
    one_wire_bus_.write #[SKIP_ROM_, READ_POWER_SUPPLY_]
    result := one_wire_bus_.read_bits 1
    return result == 0
