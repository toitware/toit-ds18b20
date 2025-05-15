// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import encoding.tison
import system.assets
import ds18b20.provider

install-from-args_ args/List:
  if args.size != 3:
    throw "Usage: main <pin> <id> <pull-up>"
  pin := int.parse args[0]
  id-str := args[1]
  id/int? := id-str == "" ? null : (int.parse args[1] --radix=16)
  pull-up := args[2].to-ascii-lower == "true"
  provider.install pin --id=id --pull-up=pull-up

install-from-assets_ configuration/Map:
  pin := configuration.get "pin"
  if not pin: throw "No 'pin' found in assets."
  if pin is not int: throw "Pin must be an integer."
  id/int? := null
  id-str := configuration.get "id"
  if id-str:
    if id-str is not string: throw "ID must be a string."
    id = int.parse id-str --radix=16
  pull-up := configuration.get "pull-up"
  if pull-up != null and pull-up is not bool: throw "Pull-up must be a boolean."
  provider.install pin --id=id --pull-up=pull-up

main args:
  // Arguments take priority over assets.
  if args.size != 0:
    install-from-args_ args
    return

  decoded := assets.decode
  ["configuration", "artemis.defines"].do: | key/string |
    configuration := decoded.get key
    if configuration:
      install-from-assets_ configuration
      return

  throw "No configuration found."
