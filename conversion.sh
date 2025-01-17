#!/bin/bash

# Input and output folders
INPUT_DIR="input"
OUTPUT_DIR="output"

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

    # Calculate new resolution
    NEW_WIDTH=$((ORIGINAL_WIDTH / 3))
    NEW_HEIGHT=$((ORIGINAL_HEIGHT / 3))

    # Target size in KB
    TARGET_SIZE_KB=3900

    # Initial bitrate guess
    BITRATE=$(calculate_bitrate $TARGET_SIZE_KB $DURATION)

    echo "Initial bitrate guess: ${BITRATE}kbit/s"

    # Start with superfast preset
    PRESET="superfast"

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

        # Check if the output size is within the target size range
        if [ $OUTPUT_SIZE_KB -le $TARGET_SIZE_KB ] && [ $OUTPUT_SIZE_KB -ge $((TARGET_SIZE_KB - 100)) ]; then
            echo "Successfully converted $INPUT_FILE to $OUTPUT_FILE within size limit."
            break
        fi

        # Adjust bitrate
        if [ $OUTPUT_SIZE_KB -gt $TARGET_SIZE_KB ]; then
            BITRATE=$((BITRATE - 100))
            echo "File too large. Reducing bitrate to ${BITRATE}kbit/s."
        else
            BITRATE=$((BITRATE + 100))
            echo "File too small. Increasing bitrate to ${BITRATE}kbit/s."
        fi

        # Adjust preset to slow if close to target size
        if [ $PRESET == "superfast" ] && [ $OUTPUT_SIZE_KB -le $((TARGET_SIZE_KB + 500)) ]; then
            PRESET="slow"
            echo "Switching to slow preset for final encoding."
        fi

    done

done

echo "All conversions completed."
