#!/bin/bash

# Input and output folders
INPUT_DIR="input"
OUTPUT_DIR="output"

# Target size in KB
TARGET_SIZE_KB=3900

# Maximum resolution dimensions
MAX_WIDTH=700
MAX_HEIGHT=700

# Initial encoding preset
INITIAL_PRESET="fast"

# Threshold for big bitrate adjustments and step
FAR_FROM_LIMIT_THRESHOLD=300
LARGE_ADJUSTMENT_STEP=100

# Threshold for small bitrate adjustments and step
CLOSE_TO_LIMIT_THRESHOLD=200
SMALL_ADJUSTMENT_STEP=3

# Final run adjustment percentage
FINAL_RUN_EXTRA_PERCENT=2
