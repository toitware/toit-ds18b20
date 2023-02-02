// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import binary show LITTLE_ENDIAN
import gpio
import one_wire

/**
Driver for the Ds18b20 temperature sensor.
*/
class Ds18b20:
  // Rom commands.
  static READ_ROM_ ::= 0x33
  static MATCH_ROM_ ::= 0x55

  static CONVERT_TEMPERATURE_ ::= 0x44
  static WRITE_SCRATCHPAD_ ::= 0x4E
  static READ_SCRATCHPAD_ ::= 0xBE
  static COPY_SCRATCHPAD_ ::= 0x48
  static RECALL_E2_ ::= 0xB8
  static READ_POWER_SUPPLY_ ::= 0xB4

  bus_ /one_wire.Bus? := ?
  owns_bus_ /bool

  /** Whether this device is the only one on the bus. */
  is_single_ /bool

  /**
  The id of the device.
  Null, if this is an instance of a broadcast driver (see
    $Ds18b20.broadcast, or if the $(Ds18b20.constructor pin) was invoked
    with '--skip_id_read'.
  */
  id/int?

  /**
  Constructs an instance of the DS18B20 sensor driver.

  Assumes there is only one sensor connected to the given $pin.
  If there are multiple sensors, then the driver misbehaves. In that
    case use $(Ds18b20.constructor --id --bus) instead.

  If $pull_up is true, then uses the pin's pullup resistor to power the
    1-wire bus. Many modules that take 3 inputs (VCC, GND, DATA) already
    connect the DATA pin to the VCC using a 4.7k resistor. In that case,
    no additional pullup resistor is needed, and this parameter should
    not be used.

  If $skip_id_read is true, then the driver does not read the device id.
  */
  constructor pin/gpio.Pin --skip_id_read/bool=false --pull_up/bool=false:
    bus_ = one_wire.Bus pin --pull_up=pull_up
    owns_bus_ = true
    is_single_ = true
    id = skip_id_read ? null : bus_.read_device_id

  /**
  Constructs an instance of the DS18B20 sensor driver for the device with the
    given $id on the given $bus.

  Multiple devices may share the same bus.
  */
  constructor --id/int --bus/one_wire.Bus:
    bus_ = bus
    owns_bus_ = false
    is_single_ = false
    this.id = id

  /**
  Constructs an instance of the DS18B20 sensor driver for broadcasting.
  All commands are sent to all devices on the bus.

  If $is_single is true, then the driver assumes there is only one device on the
    bus. In that case, this instance behaves similarly to one constructed with
    $(Ds18b20.constructor pin).
  */
  constructor.broadcast --bus/one_wire.Bus --is_single/bool=false:
    bus_ = bus
    owns_bus_ = false
    is_single_ = is_single
    id = null

  /**
  Whether this driver is broadcast.

  If true, then all devices on the bus receive commands from this instance.
  Instances that control a single device, constructed with
    $(Ds18b20.constructor pin) are considered broadcast.
  */
  is_broadcast -> bool:
    return id == null

  /** Whether the driver is closed. */
  is_closed -> bool:
    return bus_ == null

  /**
  Closes the driver and releases any resources.
  */
  close:
    if bus_ and owns_bus_:
      bus_.close
    bus_ = null

  /**
  Reads the temperature and returns it in degrees Celsius.
  */
  read_temperature -> float:
    if is_closed: throw "CLOSED"
    return (read_temperature --raw) / 16.0

  /**
  Reads the temperature and returns the raw value as returned by the sensor.

  For the DS18B20, the raw value is 16 times the temperature in degrees Celsius.
  */
  read_temperature --raw/bool -> int:
    if not raw: throw "INVALID ARGUMENT"
    if id == null and not is_single_:
      throw "BROADCAST TEMPERATURE READ NOT SUPPORTED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    // Convert temperature.
    select_self_
    bus_.write_byte CONVERT_TEMPERATURE_
    sleep --ms=750
    bus_.reset
    // Read scratchpad.
    select_self_
    bus_.write_byte READ_SCRATCHPAD_
    bytes := bus_.read 2
    return LITTLE_ENDIAN.int16 bytes 0

  /**
  Whether the sensor is in parasitic mode.

  If this driver $is_broadcast and there are multiple devices
    connected to the bus, then the result is true as long as
    at least one device is in parasitic mode.
  */
  is_parasitic -> bool:
    if is_closed: throw "CLOSED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select_self_
    bus_.write_byte READ_POWER_SUPPLY_
    result := bus_.read_bits 1
    return result == 0

  select_self_:
    if not is_single_ and not is_broadcast:
      bus_.select id
    else:
      bus_.skip
