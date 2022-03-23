// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import binary show LITTLE_ENDIAN
import one_wire

class Driver:
  static SKIP_ROM_ ::= 0xCC
  static CONVERT_TEMPERATURE_ ::= 0x44
  static READ_SCRATCHPAD_ ::= 0xBE

  ow/one_wire.Protocol

  constructor .ow:

  read_temperature_C -> float:
    return raw_read_ / 16.0

  raw_read_ -> int:
    ow.reset
    // Convert temperature.
    ow.write_byte SKIP_ROM_
    ow.write_byte CONVERT_TEMPERATURE_
    sleep --ms=750
    ow.reset
    // Read scratchpad.
    bytes := ow.write_then_read #[SKIP_ROM_, READ_SCRATCHPAD_] 2
    // Abort reading scratchpad.
    return LITTLE_ENDIAN.int16 bytes 0
