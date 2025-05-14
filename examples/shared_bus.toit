// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ds18b20 show Ds18b20
import gpio
import one-wire

GPIO-PIN-NUM ::= 32

main:
  pin := gpio.Pin GPIO-PIN-NUM
  bus := one-wire.Bus pin

  id := 0x753c01f095df0228
  driver := Ds18b20 --id=id --bus=bus

  is-parasitic := driver.is-parasitic
  print "is parasitic: $is-parasitic"
  if is-parasitic: return

  (Duration --s=5).periodic:
    print "Temperature: $(%.2f driver.read-temperature) C"

  // The following close isn't necessary, as the periodic timer above will
  // never stop. In other cases, it is important to close the driver.
  driver.close
  bus.close
  pin.close
