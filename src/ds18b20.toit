// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import io show LITTLE-ENDIAN
import gpio
import one-wire

/**
Driver for the Ds18b20 temperature sensor.
*/
class Ds18b20:
  static RESOLUTION-9-BITS ::= 9
  static RESOLUTION-10-BITS ::= 10
  static RESOLUTION-11-BITS ::= 11
  static RESOLUTION-12-BITS ::= 12

  /** The index of the high alarm temperature when reading the scratchpad. */
  static ALARM-HIGH-READ-INDEX ::= 2
  /** The index of the low alarm temperature when reading the scratchpad. */
  static ALARM-LOW-READ-INDEX ::= 3
  /** The index of the high alarm temperature when writing the scratchpad. */
  static ALARM-HIGH-WRITE-INDEX ::= 0
  /** The index of the low alarm temperature when writing the scratchpad. */
  static ALARM-LOW-WRITE-INDEX ::= 1

  // Rom commands.
  static READ-ROM_ ::= 0x33
  static MATCH-ROM_ ::= 0x55

  static CONVERT-TEMPERATURE_ ::= 0x44
  static WRITE-SCRATCHPAD_ ::= 0x4E
  static READ-SCRATCHPAD_ ::= 0xBE
  static COPY-SCRATCHPAD_ ::= 0x48
  static RECALL-E2_ ::= 0xB8
  static READ-POWER-SUPPLY_ ::= 0xB4

  bus_ /one-wire.Bus? := ?
  owns-bus_ /bool

  /** Whether this device is the only one on the bus. */
  is-single_ /bool

  is-parasitic_/bool? := null

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

  If $pull-up is true, then uses the pin's pullup resistor to power the
    1-wire bus. Many modules that take 3 inputs (VCC, GND, DATA) already
    connect the DATA pin to the VCC using a 4.7k resistor. In that case,
    no additional pullup resistor is needed, and this parameter should
    not be used.

  If $skip-id-read is true, then the driver does not read the device id.
  */
  constructor pin/gpio.Pin --skip-id-read/bool=false --pull-up/bool=false:
    bus_ = one-wire.Bus pin --pull-up=pull-up
    owns-bus_ = true
    is-single_ = true
    id = skip-id-read ? null : bus_.read-device-id

  /**
  Constructs an instance of the DS18B20 sensor driver for the device with the
    given $id on the given $bus.

  Multiple devices may share the same bus.
  */
  constructor --id/int --bus/one-wire.Bus:
    bus_ = bus
    owns-bus_ = false
    is-single_ = false
    this.id = id

  /**
  Constructs an instance of the DS18B20 sensor driver for broadcasting.
  All commands are sent to all devices on the bus.

  If $is-single is true, then the driver assumes there is only one device on the
    bus. In that case, this instance behaves similarly to one constructed with
    $(Ds18b20.constructor pin).
  */
  constructor.broadcast --bus/one-wire.Bus --is-single/bool=false:
    bus_ = bus
    owns-bus_ = false
    is-single_ = is-single
    id = null

  /**
  Whether this driver is broadcast.

  If true, then all devices on the bus receive commands from this instance.
  Instances that control a single device, constructed with
    $(Ds18b20.constructor pin) are considered broadcast.
  */
  is-broadcast -> bool:
    return id == null

  /** Whether the driver is closed. */
  is-closed -> bool:
    return bus_ == null

  /**
  Closes the driver and releases any resources.
  */
  close:
    if bus_ and owns-bus_:
      bus_.close
    bus_ = null

  /**
  Reads the temperature and returns it in degrees Celsius.

  If the sensor is parasitic, automatically uses the 'power' feature of the
    bus, unless the $power parameter is set to false.
  */
  read-temperature --power/bool=true -> float:
    if is-closed: throw "CLOSED"
    return (read-temperature --raw --power=power) / 16.0

  /**
  Reads the temperature and returns the raw value as returned by the sensor.

  For the DS18B20, the raw value is 16 times the temperature in degrees Celsius.

  If the sensor is parasitic, automatically uses the 'power' feature of the
    bus, unless the $power parameter is set to false.
  */
  read-temperature --raw/bool --power/bool=true -> int:
    if not raw: throw "INVALID ARGUMENT"
    if id == null and not is-single_:
      throw "BROADCAST TEMPERATURE READ NOT SUPPORTED"
    do-conversion --power=power
    return read-temperature-from-scratchpad --raw

  /**
  Reads the temperature from the scratchpad and returns it in degrees Celsius.

  The scratchpad contains the last temperature measurement the device has
    performed. This method does not start a new measurement.
  */
  read-temperature-from-scratchpad -> float:
    return (read-temperature-from-scratchpad --raw) / 16.0

  /**
  Reads the temperature from the scratchpad and returns the raw value as
    returned by the sensor.

  The scratchpad contains the last temperature measurement the device has
    performed. This method does not start a new measurement.
  */
  read-temperature-from-scratchpad --raw/bool -> int:
    if not raw: throw "INVALID ARGUMENT"
    if is-closed: throw "CLOSED"
    if id == null and not is-single_:
      throw "BROADCAST TEMPERATURE READ NOT SUPPORTED"

    if not bus_.reset:
      throw "NO DEVICE FOUND"
    // Read scratchpad.
    select-self_
    bus_.write-byte READ-SCRATCHPAD_
    bytes := bus_.read 2
    return LITTLE-ENDIAN.int16 bytes 0

  /**
  Starts a temperature conversion (measurement).

  If $wait is true, then waits until the conversion is done.

  If the sensor is parasitic, automatically uses the 'power' feature of the
    bus, unless the $power parameter is set to false.

  A conversion can take up to 750ms. If $wait is false, then the conversion
    is started, but the method returns immediately. The caller can then
    use $(read-temperature) to obtain the result. It is generally not
    recommended to disable $wait.

  This function is primarily useful if this instance is a broadcast instance
    and multiple devices are connected to the bus. In that case, multiple
    sensors can start a conversion at the same time, and the caller can
    then use $(read-temperature) on the individual sensors to obtain the
    results.
  */
  do-conversion --power/bool=true --wait/bool=true:
    if is-closed: throw "CLOSED"

    // Check whether we are parasitic first.
    // We might need to communicate with the device to determine this.
    power = power and is-parasitic

    if not bus_.reset:
      throw "NO DEVICE FOUND"

    // Convert temperature.
    select-self_
    bus_.write-byte CONVERT-TEMPERATURE_ --activate-power=power
    if not wait: return

    if is-parasitic:
      sleep --ms=750
    else:
      conversion-done := false
      // Actively check whether the conversion is done.
      // The sensor responds with a '0' bit while it is busy, and
      // a '1' bit when it is done.
      for i := 0; i < 750; i += 5:
        sleep --ms=5
        if bus_.read-bit == 1:
          conversion-done = true
          break
      if not conversion-done:
        throw "CONVERSION TIMEOUT"

  /**
  Whether the sensor is in parasitic mode.

  If this driver $is-broadcast and there are multiple devices
    connected to the bus, then the result is true as long as
    at least one device is in parasitic mode.
  */
  is-parasitic -> bool:
    if is-closed: throw "CLOSED"
    if is-parasitic_ != null: return is-parasitic_
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select-self_
    bus_.write-byte READ-POWER-SUPPLY_
    result := bus_.read-bits 1
    is-parasitic_ = result == 0
    return is-parasitic_

  /**
  Reads the scratchpad and returns the raw bytes.

  The scratchpad is the DS18B20's memory. It contains the temperature, the
    alarm temperatures, the configuration register, and the CRC. Unless
    committed to EEPROM, the scratchpad is volatile and is reset to the
    EEPROM values on power up.

  If $check-crc is true, then verifies the CRC of the scratchpad (the last byte).

  The result contains the following bytes:
  - 0: temperature LSB
  - 1: temperature MSB
  - 2: high alarm temperature  ($ALARM-HIGH-READ-INDEX)
  - 3: low alarm temperature   ($ALARM-LOW-READ-INDEX)
  - 4: configuration register
  - 5: reserved
  - 6: reserved
  - 7: reserved
  - 8: CRC

  The raw temperature value can also be obtained with
    $(Ds18b20.read-temperature --raw) which simply reads the first two bytes of the
    scratchpad.
  */
  read-scratchpad --check-crc/bool=true -> ByteArray:
    if is-closed: throw "CLOSED"
    if id == null and not is-single_:
      throw "BROADCAST SCRATCHPAD READ NOT SUPPORTED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select-self_
    bus_.write-byte READ-SCRATCHPAD_
    result := bus_.read 9
    // Check that the crc is correct.
    if check-crc:
      crc := one-wire.Bus.crc8 --bytes=result[..8]
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
    $copy-scratchpad-to-eeprom to copy the scratchpad values to EEPROM.

  The $bytes must be an array of 3 bytes. The first two bytes are the high and
    low alarm temperatures (in that order). The third byte is the configuration
    register. Use $ALARM-HIGH-WRITE-INDEX and $ALARM-LOW-WRITE-INDEX to
    write to the alarm temperatures.

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
  write-scratchpad bytes/ByteArray --commit/bool=false:
    if bytes.size != 3: throw "INVALID ARGUMENT"
    if is-closed: throw "CLOSED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select-self_
    bus_.write-byte WRITE-SCRATCHPAD_
    bus_.write bytes
    if commit: copy-scratchpad-to-eeprom

  /**
  Writes the given values to the scratchpad.

  The scratchpad is the DS18B20's memory. It contains the temperature, the
    alarm temperatures, the configuration register, and the CRC. Unless
    committed to EEPROM, the scratchpad is volatile and is reset to the
    EEPROM values on power up. Use $commit to automatically copy the
    scratchpad values to EEPROM. Alternatively, call
    $copy-scratchpad-to-eeprom to copy the scratchpad values to EEPROM.

  Every time the sensor measures the temperature it compares the
    value with the $high-alarm-temperature and $low-alarm-temperature
    values. If the temperature is outside the range, then the alarm flag
    is set. The alarm flag is cleared automatically at the next read.

  The resolution can be either 9, 10, 11, or 12 bits. The higher the
    resolution, the longer the conversion (measurement) time:
  - $RESOLUTION-9-BITS, 93.75 ms
  - $RESOLUTION-10-BITS, 187.5 ms
  - $RESOLUTION-11-BITS, 375 ms
  - $RESOLUTION-12-BITS, 750 ms
  */
  write-scratchpad
      --high-alarm-temperature/float
      --low-alarm-temperature/float
      --resolution/int=RESOLUTION-12-BITS
      --commit/bool=false:
    high-int := high-alarm-temperature.round.to-int
    low-int := low-alarm-temperature.round.to-int
    if not -128 <= high-int <= 127: throw "HIGH ALARM TEMPERATURE OUT OF RANGE"
    if not -128 <= low-int <= 127: throw "LOW ALARM TEMPERATURE OUT OF RANGE"
    if not RESOLUTION-9-BITS <= resolution <= RESOLUTION-12-BITS: throw "INVALID_ARGUMENT"
    config-value := (resolution - RESOLUTION-9-BITS) << 5
    assert: ALARM-HIGH-WRITE-INDEX == 0 and ALARM-LOW-WRITE-INDEX == 1
    write-scratchpad
        #[high-int, low-int, config-value]
        --commit=commit

  /**
  Writes the scratchpad values to EEPROM.

  Commits the alarm temperatures and the configuration to the EEPROM. The
    next time the sensor is powered up, it automatically loads the values
    from the EEPROM.

  If the sensor is parasitic, automatically uses the 'power' feature of the
    bus, unless the $power parameter is set to false.
  */
  copy-scratchpad-to-eeprom --power/bool=true:
    if is-closed: throw "CLOSED"
    power = power and is-parasitic
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select-self_
    bus_.write-byte COPY-SCRATCHPAD_ --activate-power=power
    if is-parasitic: sleep --ms=10

  /**
  Reads the EEPROM values into the scratchpad.

  Reads the alarm temperatures and the configuration from the EEPROM into
    the scratchpad.
  */
  recall-eeprom:
    if is-closed: throw "CLOSED"
    if not bus_.reset:
      throw "NO DEVICE FOUND"
    select-self_
    bus_.write-byte RECALL-E2_

  select-self_:
    if not is-single_ and not is-broadcast:
      bus_.select id
    else:
      bus_.skip
