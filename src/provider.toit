// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import gpio
import one-wire
import sensors.providers

import .ds18b20 show Ds18b20

NAME ::= "toit.io/ds18b20"
MAJOR ::= 1
MINOR ::= 0

class TemperatureSensor implements providers.TemperatureSensor-v1:
  bus_/one-wire.Bus? := null
  pin_/gpio.Pin? := ?
  sensor_/Ds18b20? := ?

  constructor pin/int --id/int? --pull-up/bool=false:
    pin_ = gpio.Pin pin
    if id:
      bus_ = one-wire.Bus pin_ --pull-up=pull-up
      sensor_ = Ds18b20 --id=id --bus=bus_
    else:
      // There is no way to read the ID through the service interface API.
      sensor_ = Ds18b20 pin_ --skip-id-read --pull-up=pull-up

  temperature-read -> float:
    return sensor_.read_temperature

  close -> none:
    if bus_:
      bus_.close
      bus_ = null
    if sensor_:
      sensor_.close
      sensor_ = null
    if pin_:
      pin_.close
      pin_ = null

install pin/int --id/int?=null --pull-up/bool=false -> providers.Provider:
  provider := providers.Provider NAME
      --major=MAJOR
      --minor=MINOR
      --open=:: TemperatureSensor pin --id=id --pull-up=pull-up
      --close=:: it.close
      --handlers=[providers.TemperatureHandler-v1]
  provider.install
  return provider
