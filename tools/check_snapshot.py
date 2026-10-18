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


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: check_snapshot.py <snapshot.json>")
    try:
        with open(sys.argv[1]) as source:
            validate(json.load(source))
    except (OSError, ValueError, KeyError, TypeError, OverflowError) as error:
        sys.exit(f"Native snapshot validation failed: {error}")
