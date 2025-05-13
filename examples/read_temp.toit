// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ds18b20 show Ds18b20
import gpio

GPIO-PIN-NUM ::= 32

main:
  pin := gpio.Pin GPIO-PIN-NUM

  // For parasitic devices, the data-pin is frequently not yet pulled up
  // by a resistor. In this case, use the '--pull_up' flag to use the pin's
  // internal pull-up resistor. The internal pull-up is, in theory, too
  // strong for the 1-wire bus, but it works in practice.
  ds18b20 := Ds18b20 pin

  is-parasitic := ds18b20.is-parasitic
  print "is parasitic: $is-parasitic"

  (Duration --s=5).periodic:
    print "Temperature: $(%.2f ds18b20.read-temperature) C"

  // The following close isn't necessary, as the periodic timer above will
  // never stop. In other cases, it is important to close the DS18B20.
  ds18b20.close
  pin.close
