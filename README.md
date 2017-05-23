# wifi-manager
Wifi manager utilities for the Omega


# Use
wifi-manager.sh
Wifi manager script is a bash script that attempts to
connect to configured networks as listed in priority.

needs following packages installed:
1) ubus
2) uci
3) iwinfo
4) wifisetup
5) wifi

## Testing Functions

```
ubus call onion wifi-scan '{"device":"ra0"}'
```