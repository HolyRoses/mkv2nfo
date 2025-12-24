#!/bin/bash

# Function to display usage
usage() {
    cat << EOF
Usage: $0 <video_file> --title "Title" --source "SOURCE" --url "URL" [OPTIONS]

Required arguments:
    <video_file>            Path to the video file (MKV, MP4, AVI, M4V, etc.)
    --title "Title"         Title of the release
    --source "SOURCE"       Source (e.g., DISNEYPLUS, NETFLIX, WEB-DL)
    --url "URL"             URL (e.g., tvmaze or imdb link)

Optional arguments:
    -h, --help              Display this help message and exit
    --notes "Notes"         Additional notes (default: "none")
    --release-date "DATE"   Release date in YYYY-MM-DD format (default: today)
    --use-filename          Use the video filename as the release name (default: uses parent directory name)
                            Example: /path/to/Release.Name/file.mkv
                            Default: "Release.Name" is used as release name
                            With --use-filename: "file" is used as release name
    --keepcase              Keep original case for NFO filename (default: lowercase)

Examples:
    # Default behavior (uses directory name as release)
    $0 /path/to/Release.Name.2024.1080p/video.mkv --title "Episode 1" --source "DISNEYPLUS" --url "https://example.com"
    
    # Works with any video format
    $0 /path/to/Release.Name.2024.1080p/video.mp4 --title "Episode 1" --source "NETFLIX" --url "https://example.com"
    
    # Use filename as release instead
    $0 /path/to/Release.Name.2024.1080p/video.mkv --title "Episode 1" --source "DISNEYPLUS" --url "https://example.com" --use-filename
EOF
    exit 1
}

# Check if file is provided
if [ -z "$1" ]; then
    usage
fi

# Check for help flag before processing VIDEO_FILE
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

VIDEO_FILE="$1"
shift

# Check if file exists
if [ ! -f "$VIDEO_FILE" ]; then
    echo "Error: File not found: $VIDEO_FILE"
    exit 1
fi

# Initialize variables
TITLE=""
SOURCE=""
URL=""
NOTES="none"
SUB_COUNT="0"
USE_FILENAME=0
KEEPCASE=0
RELEASE_DATE=$(date +%Y-%m-%d)

# Valid sources array
VALID_SOURCES=("AMAZON" "APPLE" "BluRay" "DISNEYPLUS" "DVD" "HBOMAX" "HULU" "ITUNES" "MOVIESANYWHERE" "NETFLIX" "PEACOCKTV" "PRIMEVIDEO" "WEB" "WEB-DL")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --title)
            TITLE="$2"
            shift 2
            ;;
        --source)
            SOURCE="$2"
            shift 2
            ;;
        --url)
            URL="$2"
            shift 2
            ;;
        --notes)
            NOTES="$2"
            shift 2
            ;;
        --release-date)
            RELEASE_DATE="$2"
            shift 2
            ;;
        --use-filename)
            USE_FILENAME=1
            shift
            ;;
        --keepcase)
            KEEPCASE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check mandatory fields
if [ -z "$TITLE" ] || [ -z "$SOURCE" ] || [ -z "$URL" ]; then
    echo "Error: --title, --source, and --url are mandatory"
    echo ""
    usage
fi

# Validate source
VALID_SOURCE=0
for valid in "${VALID_SOURCES[@]}"; do
    if [ "$SOURCE" = "$valid" ]; then
        VALID_SOURCE=1
        break
    fi
done

if [ $VALID_SOURCE -eq 0 ]; then
    echo "Error: Invalid source '$SOURCE'"
    echo ""
    echo "Valid sources are:"
    printf '  %s\n' "${VALID_SOURCES[@]}"
    exit 1
fi

# Get the directory where the video file is located
VIDEO_DIR=$(dirname "$VIDEO_FILE")

# Extract video filename without extension (for NFO filename)
# This handles any extension by removing everything after the last dot
VIDEO_BASENAME=$(basename "$VIDEO_FILE")
VIDEO_BASENAME="${VIDEO_BASENAME%.*}"

# Apply lowercase to NFO filename unless --keepcase is specified
if [ $KEEPCASE -eq 1 ]; then
    NFO_BASENAME="$VIDEO_BASENAME"
else
    NFO_BASENAME=$(echo "$VIDEO_BASENAME" | tr '[:upper:]' '[:lower:]')
fi

# Determine release name based on --use-filename flag
if [ $USE_FILENAME -eq 1 ]; then
    # Use the video filename (without extension) as release name
    RELEASE_NAME="$VIDEO_BASENAME"
else
    # Use the parent directory name as release name (default, matches GRACE/ETHEL)
    RELEASE_NAME=$(basename "$VIDEO_DIR")
fi

# Full path to the output NFO file (always matches video filename, lowercased by default)
NFO_FILE="${VIDEO_DIR}/${NFO_BASENAME}.nfo"

# Extract information using MediaInfo
FILE_SIZE_BYTES=$(mediainfo --Inform="General;%FileSize%" "$VIDEO_FILE")
DURATION_MS=$(mediainfo --Inform="General;%Duration%" "$VIDEO_FILE")
VIDEO_FORMAT=$(mediainfo --Inform="Video;%Format%" "$VIDEO_FILE")
VIDEO_PROFILE=$(mediainfo --Inform="Video;%Format_Profile%" "$VIDEO_FILE")
BITRATE=$(mediainfo --Inform="Video;%BitRate/String%" "$VIDEO_FILE")
WIDTH=$(mediainfo --Inform="Video;%Width%" "$VIDEO_FILE")
HEIGHT=$(mediainfo --Inform="Video;%Height%" "$VIDEO_FILE")
FPS=$(mediainfo --Inform="Video;%FrameRate%" "$VIDEO_FILE")
FPS_NUM=$(mediainfo --Inform="Video;%FrameRate_Num%" "$VIDEO_FILE")
FPS_DEN=$(mediainfo --Inform="Video;%FrameRate_Den%" "$VIDEO_FILE")

# Build FPS display string
if [ -n "$FPS_NUM" ] && [ -n "$FPS_DEN" ] && [ "$FPS_DEN" != "1" ]; then
    FPS_DISPLAY="$FPS ($FPS_NUM/$FPS_DEN) FPS"
else
    FPS_DISPLAY="$FPS FPS"
fi

# Audio info
AUDIO_COUNT=$(mediainfo --Inform="General;%AudioCount%" "$VIDEO_FILE")

if [ "$AUDIO_COUNT" = "1" ]; then
    # Single audio track - simple format
    AUDIO_LANG=$(mediainfo --Inform="Audio;%Language/String%" "$VIDEO_FILE")
    AUDIO_FORMAT=$(mediainfo --Inform="Audio;%Format%" "$VIDEO_FILE")
    AUDIO_BITRATE=$(mediainfo --Inform="Audio;%BitRate/String%" "$VIDEO_FILE")
    AUDIO_CHANNELS=$(mediainfo --Inform="Audio;%Channels%" "$VIDEO_FILE")
    AUDIO_COMMERCIAL=$(mediainfo --Inform="Audio;%Format_Commercial_IfAny%" "$VIDEO_FILE")
    
    # Capitalize first letter of audio language
    AUDIO_LANG_CAP="$(echo ${AUDIO_LANG:0:1} | tr '[:lower:]' '[:upper:]')${AUDIO_LANG:1}"
    
    AUDIO_FORMATTED="Audio        : $AUDIO_LANG_CAP $AUDIO_FORMAT $AUDIO_BITRATE @ $AUDIO_CHANNELS channels${AUDIO_COMMERCIAL:+ ($AUDIO_COMMERCIAL)}"
else
    # Multiple audio tracks - format each on separate line
    AUDIO_LINES=$(mediainfo --Output='Audio;%Language/String%|%Format%|%BitRate/String%|%Channels%|%Format_Commercial_IfAny%\n' "$VIDEO_FILE")
    AUDIO_FORMATTED=$(echo "$AUDIO_LINES" | awk -F'|' 'BEGIN {first=1} NF==5 {
        lang=$1
        format=$2
        bitrate=$3
        channels=$4
        commercial=$5
        
        # Capitalize first letter
        lang_cap = toupper(substr(lang,1,1)) substr(lang,2)
        
        # Build line
        if (commercial != "") {
            line = lang_cap " " format " " bitrate " @ " channels " channels (" commercial ")"
        } else {
            line = lang_cap " " format " " bitrate " @ " channels " channels"
        }
        
        # First line gets "Audio        : " prefix, rest get indentation
        if (first) {
            print "Audio        : " line
            first=0
        } else {
            print "               " line
        }
    }')
fi

# Subtitle count and languages with flags
SUB_COUNT=$(mediainfo --Inform="General;%TextCount%" "$VIDEO_FILE")

# Check if there are any subtitles
if [ -z "$SUB_COUNT" ] || [ "$SUB_COUNT" = "0" ]; then
    SUB_FORMATTED="Subs         : None"
else
    SUB_LANGS=$(mediainfo --Inform="Text;%Language/String% %Title%\$" "$VIDEO_FILE" | awk -F'$' '{
    result = ""
    for (i=1; i<=NF; i++) {
        if ($i != "") {
            # Remove leading/trailing spaces
            gsub(/^[ \t]+|[ \t]+$/, "", $i)

            # Split by first space only
            match($i, /^([^ ]+) (.+)$/, arr)
            if (arr[1] != "") {
                lang = arr[1]
                title = arr[2]
                handled = 0

                # If title exists, check if it contains parentheses
                if (title != "") {
                    # Special handling for Norwegian variants
                    if (lang == "Norwegian") {
                        if (title ~ /Bokmal|Bokmål/) {
                            result = result "Norwegian Bokmal, "
                            handled = 1
                        } else if (title ~ /Nynorsk/) {
                            result = result "Norwegian Nynorsk, "
                            handled = 1
                        }
                    }
                    
                    # Special handling for Chinese variants (before checking parentheses)
                    if (handled == 0 && lang == "Chinese") {
                        # Check for English text variants
                        if (title ~ /Simplified|简体|简/) {
                            result = result lang " (Simplified), "
                            handled = 1
                        } else if (title ~ /Traditional|繁體|繁/) {
                            result = result lang " (Traditional), "
                            handled = 1
                        } else if (title ~ /Cantonese|廣東話|粤语/) {
                            result = result lang " (Cantonese), "
                            handled = 1
                        }
                    }
                    
                    # Special conditions for various lang (before checking parentheses)
                    if (handled == 0) {
                        if (toupper(lang) ~ /ENGLISH|ITALIAN|FRENCH|SPANISH/) {
                            if (toupper(title) ~ /(^|\s|\(|\[)SDH(\s|\)|\]|$)/) {
                                result = result lang " (SDH), "
                                handled = 1
                            }
                            else if (toupper(title) ~ /(^|\s|\(|\[)CC(\s|\)|\]|$)/) {
                                result = result lang " (CC), "
                                handled = 1
                            }
                            else if (toupper(title) ~ /(^|\s|\(|\[)FORCED(\s|\)|\]|$)/) {
                                result = result lang " (Forced), "
                                handled = 1
                            }
                            else if (toupper(title) ~ /(^|\s|\(|\[)BRITISH(\s|\)|\]|$)/) {
                                result = result lang " (British), "
                                handled = 1
                            }
                        }
                    }

                    # Only process further if title wasn'\''t handled above
                    if (handled == 0) {
                        # Check for ASCII parentheses first
                        if (match(title, /\(([^)]+)\)/, paren)) {
                            result = result lang " (" paren[1] "), "
                        }
                        # Check for full-width parentheses (Chinese/Japanese)
                        else if (match(title, /（([^）]+)）/, paren)) {
                            result = result lang " (" paren[1] "), "
                        }
                        # No parentheses found, just use language name
                        else {
                            result = result lang ", "
                        }
                    }
                } else {
                    result = result lang ", "
                }
            } else {
                # Just language, no title
                split($i, parts, " ")
                result = result parts[1] ", "
            }
        }
    }
    # Remove trailing comma and space
    sub(/, $/, "", result)
    print result
}')

    # Format subtitle list with wrapping at ~85 characters per line
    SUB_LINE="Subs         : $SUB_COUNT: $SUB_LANGS"
    if [ ${#SUB_LINE} -gt 85 ]; then
        # Wrap subtitle list at approximately 85 characters
        SUB_FORMATTED=$(echo "$SUB_LANGS" | fold -s -w 75 | awk 'NR==1{print "Subs         : '$SUB_COUNT': " $0} NR>1{print "               " $0}')
    else
        SUB_FORMATTED="Subs         : $SUB_COUNT: $SUB_LANGS"
    fi
fi

# Convert file size to GiB using awk
FILE_SIZE_GIB=$(awk "BEGIN {printf \"%.1f\", $FILE_SIZE_BYTES / 1073741824}")

# Format bytes with commas
FILE_SIZE_FORMATTED=$(printf "%d" $FILE_SIZE_BYTES | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')

# Convert duration from milliseconds to appropriate format
DURATION_SECONDS=$((DURATION_MS / 1000))
DURATION_MINUTES=$((DURATION_SECONDS / 60))
DURATION_SECS=$((DURATION_SECONDS % 60))

# If duration is 1 hour or more, use "X h YY min" format, otherwise "XX min YY s"
if [ $DURATION_MINUTES -ge 60 ]; then
    DURATION_HOURS=$((DURATION_MINUTES / 60))
    DURATION_MINS=$((DURATION_MINUTES % 60))
    DURATION_FORMATTED="${DURATION_HOURS} h ${DURATION_MINS} min"
else
    DURATION_FORMATTED="${DURATION_MINUTES} min ${DURATION_SECS} s"
fi

# Format output
cat > "$NFO_FILE" << EOF
$RELEASE_NAME

Release Date : $RELEASE_DATE
Title        : $TITLE

Size         : ${FILE_SIZE_GIB} GiB (${FILE_SIZE_FORMATTED} bytes)
Duration     : $DURATION_FORMATTED
Video        : $VIDEO_FORMAT ($VIDEO_PROFILE)
Bitrate      : $BITRATE
Resolution   : $WIDTH x $HEIGHT ($FPS_DISPLAY)
$AUDIO_FORMATTED
$SUB_FORMATTED

Source       : $SOURCE
URL          : $URL
Notes        : $NOTES
EOF

echo "NFO created: $NFO_FILE"
