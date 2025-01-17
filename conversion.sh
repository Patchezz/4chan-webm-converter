#!/bin/bash

# Load configuration
source config.sh

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Function to calculate bitrate based on file size and duration
calculate_bitrate() {
    local target_size_kb=$1
    local duration_s=$2
    echo $((target_size_kb * 8 / duration_s))
}

# Loop through all .mp4 files in the input directory
for INPUT_FILE in "$INPUT_DIR"/*.mp4; do
    # Extract filename without extension
    FILENAME=$(basename -- "$INPUT_FILE")
    FILENAME_NO_EXT="${FILENAME%.*}"

    # Output file path
    OUTPUT_FILE="$OUTPUT_DIR/$FILENAME_NO_EXT.webm"

    echo "Processing $INPUT_FILE..."

    # Get video duration in seconds
    DURATION=$(ffprobe -i "$INPUT_FILE" -show_entries format=duration -v quiet -of csv="p=0" | awk '{printf("%d\n", $1)}')

    # Get original resolution
    RESOLUTION=$(ffprobe -i "$INPUT_FILE" -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0)
    ORIGINAL_WIDTH=$(echo $RESOLUTION | cut -d'x' -f1)
    ORIGINAL_HEIGHT=$(echo $RESOLUTION | cut -d'x' -f2)

    # Maintain aspect ratio if either dimension exceeds max dimensions
    if [ $ORIGINAL_WIDTH -gt $MAX_WIDTH ] || [ $ORIGINAL_HEIGHT -gt $MAX_HEIGHT ]; then
        if [ $ORIGINAL_WIDTH -ge $ORIGINAL_HEIGHT ]; then
            NEW_WIDTH=$MAX_WIDTH
            NEW_HEIGHT=$((MAX_WIDTH * ORIGINAL_HEIGHT / ORIGINAL_WIDTH))
        else
            NEW_HEIGHT=$MAX_HEIGHT
            NEW_WIDTH=$((MAX_HEIGHT * ORIGINAL_WIDTH / ORIGINAL_HEIGHT))
        fi
    else
        NEW_WIDTH=$ORIGINAL_WIDTH
        NEW_HEIGHT=$ORIGINAL_HEIGHT
    fi

    echo "New resolution: ${NEW_WIDTH}x${NEW_HEIGHT}"

    # Initial bitrate guess
    BITRATE=$(calculate_bitrate $TARGET_SIZE_KB $DURATION)

    echo "Initial bitrate guess: ${BITRATE}kbit/s"

    PRESET=$INITIAL_PRESET
    LAST_RUN=false

    while true; do
        echo "Converting $INPUT_FILE with bitrate ${BITRATE}kbit/s and preset $PRESET..."

        # Run HandBrakeCLI with the specified options
        HandBrakeCLI \
            --input "$INPUT_FILE" \
            --output "$OUTPUT_FILE" \
            --width $NEW_WIDTH \
            --height $NEW_HEIGHT \
            --vb $BITRATE \
            --encoder VP9 \
            --two-pass \
            --audio none \
            --subtitle none \
            --encoder-preset $PRESET \
            --turbo

        # Check if the conversion was successful
        if [ $? -ne 0 ]; then
            echo "Failed to convert $INPUT_FILE. Skipping..."
            break
        fi

        # Get output file size in KB
        OUTPUT_SIZE_KB=$(du -k "$OUTPUT_FILE" | cut -f1)

        echo "Output file size: ${OUTPUT_SIZE_KB}KB"

        if [ "$LAST_RUN" = true ]; then
            echo "Final run completed. File saved as $OUTPUT_FILE."
            break
        fi

        if [ $OUTPUT_SIZE_KB -le $TARGET_SIZE_KB ] && [ $OUTPUT_SIZE_KB -ge $((TARGET_SIZE_KB - CLOSE_TO_LIMIT_THRESHOLD)) ]; then
            echo "File is within acceptable size range."
            LAST_RUN=true
            BITRATE=$((BITRATE + (BITRATE * FINAL_RUN_EXTRA_PERCENT / 100)))
            echo "Final run with increased bitrate: ${BITRATE}kbit/s."
            PRESET="slow"
            continue
        fi

        # Adjust bitrate based on file size distance from target
        if [ $OUTPUT_SIZE_KB -gt $TARGET_SIZE_KB ]; then
            if [ $((OUTPUT_SIZE_KB - TARGET_SIZE_KB)) -gt $FAR_FROM_LIMIT_THRESHOLD ]; then
                BITRATE=$((BITRATE - LARGE_ADJUSTMENT_STEP))
            else
                BITRATE=$((BITRATE - SMALL_ADJUSTMENT_STEP))
            fi
            echo "File too large. Reducing bitrate to ${BITRATE}kbit/s."
        else
            if [ $((TARGET_SIZE_KB - OUTPUT_SIZE_KB)) -gt $FAR_FROM_LIMIT_THRESHOLD ]; then
                BITRATE=$((BITRATE + LARGE_ADJUSTMENT_STEP))
            else
                BITRATE=$((BITRATE + SMALL_ADJUSTMENT_STEP))
            fi
            echo "File too small. Increasing bitrate to ${BITRATE}kbit/s."
        fi

        # Adjust preset to slow if within close range of the target size
        if [ $PRESET == "fast" ] && [ $OUTPUT_SIZE_KB -le $((TARGET_SIZE_KB + CLOSE_TO_LIMIT_THRESHOLD)) ] && [ $OUTPUT_SIZE_KB -ge $((TARGET_SIZE_KB - CLOSE_TO_LIMIT_THRESHOLD)) ]; then
            PRESET="slow"
            echo "Switching to slow preset for final encoding."
        fi
    done
done

echo "All conversions completed."
