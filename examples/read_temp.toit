// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ds18b20
import one_wire
import gpio

GPIO_PIN_NUM ::=  25

main:
  pin := gpio.Pin GPIO_PIN_NUM
  ow := one_wire.Protocol pin
  driver := ds18b20.Driver ow

  is_parasitic := driver.is_parasitic
  print "is parasitic: $is_parasitic"
  if is_parasitic: return

  (Duration --s=5).periodic:
    print "Temperature: $(%.2f driver.read_temperature) C"
