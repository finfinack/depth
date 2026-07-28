#!/usr/bin/env python3
"""Write dive_profile.fit, a FIT activity whose records carry a dive profile.

The simulator hands a data field whatever the loaded FIT holds, so this is the
only way to see the depth apps react to a changing pressure without getting
into the water. The profile is two breath-hold dives with a surface interval
between them, one sample a second, which is the rate compute() is called at.

The pressures are what a fresh-water dive would read at sea level:

    pressure = 101325 Pa + depth_m * 9806.65 Pa

Fresh water because that is the default of the waterType setting. Set the
setting to salt and the apps will read about 2% shallow against this file,
which is the convention difference and not a bug.

Run it from this directory to regenerate the file:

    python3 make_dive_fit.py

Nothing in the build or the tests depends on it — dive_profile.fit is checked
in so the usual case is loading it, not making it. Regenerate when the profile
itself needs to change.

Written by hand rather than with the Garmin FIT SDK: this needs one message
type and about eighty lines, and the SDK is a dependency the repository would
otherwise not have.
"""

import struct
import time

# FIT's own CRC-16, from the FIT protocol specification.
CRC_TABLE = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
             0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]

# FIT counts seconds from 1989-12-31T00:00:00Z, not from the Unix epoch.
FIT_EPOCH = 631065600

# FIT base types, as they appear in a definition message.
ENUM, UINT16, UINT32, UINT32Z = 0x00, 0x84, 0x86, 0x8C

SURFACE_PA = 101325.0
FRESH_PA_PER_M = 9806.65

OUTPUT = "dive_profile.fit"


def crc16(data, crc=0):
    for byte in data:
        tmp = CRC_TABLE[crc & 0xF]
        crc = ((crc >> 4) & 0x0FFF) ^ tmp ^ CRC_TABLE[byte & 0xF]
        tmp = CRC_TABLE[crc & 0xF]
        crc = ((crc >> 4) & 0x0FFF) ^ tmp ^ CRC_TABLE[(byte >> 4) & 0xF]
    return crc


def definition(local, global_num, fields):
    """A definition message: what the data messages that follow will contain."""
    out = bytes([0x40 | local, 0x00, 0x00])  # header, reserved, little endian
    out += struct.pack("<HB", global_num, len(fields))
    for number, size, base in fields:
        out += bytes([number, size, base])
    return out


def data(local, values):
    """A data message, packed to match the definition of the same local type."""
    out = bytes([local])
    for value, base in values:
        out += struct.pack("<B" if base == ENUM else
                           "<H" if base == UINT16 else "<I", value)
    return out


def profile():
    """Depth in metres, one sample a second.

    Two dives rather than one: the second shows that the maximum holds after
    the first dive ends, which a single descent cannot.
    """
    for second in range(150):
        if second < 15:
            depth = 0.0                                   # on the surface
        elif second < 45:
            depth = 12.0 * (second - 15) / 30.0           # down to 12 m
        elif second < 75:
            depth = 12.0 + 0.4 * ((second % 6) - 3)       # holding, with swell
        elif second < 100:
            depth = 12.0 * (100 - second) / 25.0          # back up
        elif second < 115:
            depth = 0.0                                   # surface interval
        elif second < 130:
            depth = 6.0 * (second - 115) / 15.0           # a shallower dive
        else:
            depth = 6.0 * (150 - second) / 20.0
        yield second, max(depth, 0.0)


def build():
    start = int(time.time()) - FIT_EPOCH - 200

    body = definition(0, 0, [   # file_id, which every FIT file opens with
        (0, 1, ENUM),           # type: 4 = activity
        (1, 2, UINT16),         # manufacturer: 1 = garmin
        (2, 2, UINT16),         # product
        (3, 4, UINT32Z),        # serial_number
        (4, 4, UINT32),         # time_created
    ])
    body += data(0, [(4, ENUM), (1, UINT16), (1, UINT16),
                     (12345, UINT32Z), (start, UINT32)])

    body += definition(1, 20, [  # record
        (253, 4, UINT32),        # timestamp
        (91, 4, UINT32),         # absolute_pressure, in pascal
    ])
    for second, depth in profile():
        pascals = round(SURFACE_PA + depth * FRESH_PA_PER_M)
        body += data(1, [(start + second, UINT32), (pascals, UINT32)])

    header = struct.pack("<BBHI4s", 14, 0x20, 2178, len(body), b".FIT")
    header += struct.pack("<H", crc16(header))   # header CRC, over bytes 0-11
    return header + body + struct.pack("<H", crc16(header + body))


if __name__ == "__main__":
    with open(OUTPUT, "wb") as handle:
        handle.write(build())
    print("wrote " + OUTPUT)
