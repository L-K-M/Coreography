#!/usr/bin/env python3
"""Require usable native CPU/memory readings before packaging or publication."""

import json
import math
import sys


def reading(snapshot, key, availability):
    metric = snapshot[key]
    if metric["availability"] != availability:
        raise ValueError(f"{key} must be {availability}")
    value = metric["numericValue"]
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(f"{key} must contain a finite number")
    return value


PRESSURE_LEVELS = (0, 1, 2)  # MemoryPressureLevel ordinals: normal, warning, critical
THERMAL_LEVELS = (0, 1, 2, 3, 4)  # ThermalPressureLevel: nominal ... sleeping


def bounded(snapshot, key, availability, upper):
    value = reading(snapshot, key, availability)
    if not 0 <= value <= upper:
        raise ValueError(f"{key} must be between zero and {upper}")
    return value


def validate_memory(snapshot, used, capacity):
    memory = snapshot["memory"]
    app = bounded(memory, "appBytes", "estimated", capacity)
    wired = bounded(memory, "wiredBytes", "measured", capacity)
    compressed = bounded(memory, "compressedBytes", "measured", capacity)
    bounded(memory, "cachedBytes", "estimated", capacity)
    if app + wired + compressed != used:
        raise ValueError("app, wired and compressed memory must sum to used memory")

    swap_total = reading(memory, "swapTotalBytes", "measured")
    bounded(memory, "swapUsedBytes", "measured", swap_total)
    for key in ("pageInBytesPerSecond", "swapInBytesPerSecond", "swapOutBytesPerSecond"):
        if reading(memory, key, "measured") < 0:
            raise ValueError(f"{key} must not be negative")
    if reading(memory, "pressure", "measured") not in PRESSURE_LEVELS:
        raise ValueError("pressure must be a known level")

    # An empty compressor has no ratio; it must say so rather than report zero.
    ratio = memory["compressionRatio"]
    if ratio["availability"] == "unavailable" and compressed == 0:
        return
    if reading(memory, "compressionRatio", "measured") <= 0:
        raise ValueError("compressionRatio must be positive")


def validate(snapshot):
    cpu = reading(snapshot, "cpuPercentOfMachine", "measured")
    memory = reading(snapshot, "memoryUsedBytes", "estimated")
    capacity = snapshot["inventory"]["physicalMemoryBytes"]
    if type(capacity) is not int or capacity <= 0:
        raise ValueError("physicalMemoryBytes must be a positive integer")
    if not 0 <= cpu <= 100:
        raise ValueError("CPU must be between 0 and 100 percent of the machine")
    if not 0 <= memory <= capacity:
        raise ValueError("used memory must be between zero and physical memory")
    validate_memory(snapshot, memory, capacity)
    if reading(snapshot, "thermalPressure", "measured") not in THERMAL_LEVELS:
        raise ValueError("thermalPressure must be a known level")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: check_snapshot.py <snapshot.json>")
    try:
        with open(sys.argv[1]) as source:
            validate(json.load(source))
    except (OSError, ValueError, KeyError, TypeError, OverflowError) as error:
        sys.exit(f"Native snapshot validation failed: {error}")
