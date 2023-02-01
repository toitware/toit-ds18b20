// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ds18b20 show Ds18b20
import gpio
import one_wire

GPIO_PIN_NUM ::= 32

main:
  pin := gpio.Pin GPIO_PIN_NUM
  bus := one_wire.Bus pin

  id := 0x753c01f095df0228
  driver := Ds18b20 --id=id --bus=bus

  is_parasitic := driver.is_parasitic
  print "is parasitic: $is_parasitic"
  if is_parasitic: return

  (Duration --s=5).periodic:
    print "Temperature: $(%.2f driver.read_temperature) C"

  // The following close isn't necessary, as the periodic timer above will
  // never stop. In other cases, it is important to close the driver.
  driver.close
  bus.close
  pin.close
