# DS18B20
Driver for the DS18B20 temperature sensor.

## Example

```toit
import ds18b20 show Ds18b20
import gpio

GPIO-PIN-NUM ::= 32

main:
  pin := gpio.Pin GPIO-PIN-NUM
  ds18b20 := Ds18b20 pin
  print "Temperature: $(%.2f ds18b20.read-temperature) C"
  ds18b20.close
  pin.close
```
