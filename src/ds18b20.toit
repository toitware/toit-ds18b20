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
  static RESOLUTION_9_BITS ::= 9
  static RESOLUTION_10_BITS ::= 10
  static RESOLUTION_11_BITS ::= 11
  static RESOLUTION_12_BITS ::= 12

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

  is_parasitic_/bool? := null

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
    bus. In that case, this instance behaves similar to one constructed with
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

  If the sensor is parasitic, automatically uses the 'power' feature of the
    bus, unless the $power parameter is set to false.
  */
  read_temperature --power/bool=true -> float:
    if is_closed: throw "CLOSED"
    return (read_temperature --raw --power=power) / 16.0

  /**
  Reads the temperature and returns the raw value as returned by the sensor.

  For the DS18B20, the raw value is 16 times the temperature in degrees Celsius.

  If the sensor is parasitic, automatically uses the 'power' feature of the
    bus, unless the $power parameter is set to false.
  */
  read_temperature --raw/bool --power/bool=true -> int:
    if not raw: throw "INVALID ARGUMENT"
    if id == null and not is_single_:
      throw "BROADCAST TEMPERATURE READ NOT SUPPORTED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    // Check whether we are parasitic first.
    // We might need to communicate with the device to determine this.
    power = power and is_parasitic
    // Convert temperature.
    select_self_
    bus_.write_byte CONVERT_TEMPERATURE_ --activate_power=power
    if is_parasitic:
      sleep --ms=750
    else:
      // Actively check whether the conversion is done.
      // The sensor responsd with a '0' bit while it is busy, and
      // a '1' bit when it is done.
      for i := 0; i < 750; i += 5:
        sleep --ms=5
        if bus_.read_bit == 1: break

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
    if is_parasitic_ != null: return is_parasitic_
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select_self_
    bus_.write_byte READ_POWER_SUPPLY_
    result := bus_.read_bits 1
    is_parasitic_ = result == 0
    return is_parasitic_

  /**
  Reads the scratchpad and returns the raw bytes.

  The scratchpad is the DS18B20's memory. It contains the temperature, the
    alarm temperatures, the configuration register, and the CRC. Unless
    committed to EEPROM, the scratchpad is volatile and is reset to the
    EEPROM values on power up.

  If $check_crc is true, then verifies the CRC of the scratchpad (the last byte).

  The result contains the following bytes:
  - 0: temperature LSB
  - 1: temperature MSB
  - 2: high alarm temperature
  - 3: low alarm temperature
  - 4: configuration register
  - 5: reserved
  - 6: reserved
  - 7: reserved
  - 8: CRC

  The raw temperature value can also be obtained with
    $(Ds18b20.read_temperature --raw) which simply reads the first two bytes of the
    scratchpad.
  */
  read_scratchpad --check_crc/bool=true -> ByteArray:
    if is_closed: throw "CLOSED"
    if id == null and not is_single_:
      throw "BROADCAST SCRATCHPAD READ NOT SUPPORTED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select_self_
    bus_.write_byte READ_SCRATCHPAD_
    result := bus_.read 9
    // Check that the crc is correct.
    if check_crc:
      crc := one_wire.Bus.crc8 --bytes=result[..8]
      if crc != result[8]:
        throw "CRC ERROR"
    return result

  /**
  Writes the given $bytes to the scratchpad.

  The scratchpad is the DS18B20's memory. It contains the temperature, the
    alarm temperatures, the configuration register, and the CRC. Unless
    committed to EEPROM, the scratchpad is volatile and is reset to the
    EEPROM values on power up. Use $commit to automatically copy the
    scratchpad values to EEPROM. Alternatively, call
    $copy_scratchpad_to_eeprom to copy the scratchpad values to EEPROM.

  The $bytes must be an array of 3 bytes. The first two bytes are the high and
    low alarm temperatures (in that order). The third byte is the configuration
    register.

  The low and high alarm temperatures are 8-bit values. They are compared
    against the temperature in the scratchpad. If the temperature is outside
    the range, then the alarm flag is set. The alarm flag is cleared when the
    temperature is read. Since raw temperature values have a resolution of 12
    bits, but the alarm registers are limited to 8 bits, only bits
    11 through 4 of the raw temperature values are used for the comparison.
    Practically speaking, this means that the alarm temperatures can only
    be accurate to up to 1 degree Celsius.

  If the alarm functionality of the DS18B20 is not used, these registers can
    be used to store arbitrary data.

  The configuration register is a 8-bit value. Bit 7, and bits 0 through 4 are
    reserved for internal use and can't be overwritten. Only bits 5 and 6
    can be changed. They are used, to set the resolution of the temperature
    readings. The resolution is set by the following table:

  ```
  | Bits 5 and 6 | Resolution | Register value |
  | ------------ | ---------- | -------------- |
  | 0 0          | 9 bits     | 0x1F           |
  | 0 1          | 10 bits    | 0x3F           |
  | 1 0          | 11 bits    | 0x5F           |
  | 1 1          | 12 bits    | 0x7F           |
  ```
  */
  write_scratchpad bytes/ByteArray --commit/bool=false:
    if bytes.size != 3: throw "INVALID ARGUMENT"
    if is_closed: throw "CLOSED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select_self_
    bus_.write_byte WRITE_SCRATCHPAD_
    bus_.write bytes
    if commit: copy_scratchpad_to_eeprom

  /**
  Writes the given values to the scratchpad.

  The scratchpad is the DS18B20's memory. It contains the temperature, the
    alarm temperatures, the configuration register, and the CRC. Unless
    committed to EEPROM, the scratchpad is volatile and is reset to the
    EEPROM values on power up. Use $commit to automatically copy the
    scratchpad values to EEPROM. Alternatively, call
    $copy_scratchpad_to_eeprom to copy the scratchpad values to EEPROM.

  Every time the sensor measures the temperature it compares the
    value with the $high_alarm_temperature and $low_alarm_temperature
    values. If the temperature is outside the range, then the alarm flag
    is set. The alarm flag is cleared automatically at the next read.

  The resolution can be either 9, 10, 11, or 12 bits. The higher the
    resolution, the longer the conversion (measurement) time:
  - $RESOLUTION_9_BITS, 93.75 ms
  - $RESOLUTION_10_BITS, 187.5 ms
  - $RESOLUTION_11_BITS, 375 ms
  - $RESOLUTION_12_BITS, 750 ms
  */
  write_scratchpad
      --high_alarm_temperature/float
      --low_alarm_temperature/float
      --resolution/int=RESOLUTION_12_BITS
      --commit/bool=false:
    high_int := high_alarm_temperature.round.to_int
    low_int := low_alarm_temperature.round.to_int
    if not -128 <= high_int <= 127: throw "HIGH ALARM TEMPERATURE OUT OF RANGE"
    if not -128 <= low_int <= 127: throw "LOW ALARM TEMPERATURE OUT OF RANGE"
    if not RESOLUTION_9_BITS <= resolution <= RESOLUTION_12_BITS: throw "INVALID_ARGUMENT"
    config_value := (12 - resolution) << 5
    write_scratchpad
        #[high_int, low_int, config_value]
        --commit=commit

  /**
  Writes the scratchpad values to EEPROM.

  Commits the alarm temperatures and the configuration to the EEPROM. The
    next time the sensor is powered up, it automatically loads the values
    from the EEPROM.

  If the sensor is parasitic, automatically uses the 'power' feature of the
    bus, unless the $power parameter is set to false.
  */
  copy_scratchpad_to_eeprom --power/bool=true:
    if is_closed: throw "CLOSED"
    power = power and is_parasitic
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select_self_
    bus_.write_byte COPY_SCRATCHPAD_ --activate_power=power
    if is_parasitic: sleep --ms=10

  /**
  Reads the EEPROM values into the scratchpad.

  Reads the alarm temperatures and the configuration from the EEPROM into
    the scratchpad.
  */
  recall_eeprom:
    if is_closed: throw "CLOSED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select_self_
    bus_.write_byte RECALL_E2_

  select_self_:
    if not is_single_ and not is_broadcast:
      bus_.select id
    else:
      bus_.skip
