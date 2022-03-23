// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ds18b20
import one_wire
import rmt
import gpio

GPIO_PIN_NUM ::=  17

RX_CHANNEL_NUM ::= 0
TX_CHANNEL_NUM ::= 1

main:
  pin := gpio.Pin GPIO_PIN_NUM
  rx_channel := rmt.Channel pin RX_CHANNEL_NUM
  tx_channel := rmt.Channel pin TX_CHANNEL_NUM

  driver := ds18b20.Driver
      one_wire.Protocol --rx=rx_channel --tx=tx_channel

  (Duration --s=5).periodic:
    print "Temperature: $(%.2f driver.read_temperature_C) C"
