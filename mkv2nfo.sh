#!/usr/bin/env bash

# Function to display usage
usage() {
    cat << EOF
Usage: $0 <video_file> --title "Title" --source "SOURCE" --url "URL" [OPTIONS]

Required arguments:
    <video_file>            Path to the video file (MKV, MP4, AVI, M4V, etc.)
    --source "SOURCE"       Source (e.g., DISNEYPLUS, NETFLIX, WEB-DL)

    AND either:
    --title "Title"         Title of the release
    --url "URL"             URL (e.g., tvmaze or imdb link)

    OR:
    --imdb "tt1234567"      IMDB ID (will fetch title and construct URL automatically)

    OR:
    --tvmaze "49041"        TVMaze show ID (will auto-detect season/episode from release name)

Optional arguments:
    -h, --help              Display this help message and exit
    --notes "Notes"         Additional notes (default: "none")
    --release-date "DATE"   Release date in YYYY-MM-DD format (default: today)
    --omdb-api-key "KEY"    OMDb API key (can also be set via config or environment)
    --auto-source           Auto-detect source from release name
    --use-filename          Use the video filename as the release name (default: uses parent directory name)
                            Example: /path/to/Release.Name/file.mkv
                            Default: "Release.Name" is used as release name
                            With --use-filename: "file" is used as release name
    --keepcase              Keep original case for NFO filename (default: lowercase)

Configuration:
    Settings can be configured via:
    1. Config file: ~/.mkv2nfo.conf or .mkv2nfo.conf in script directory
    2. Environment variables: MKV2NFO_SOURCE, MKV2NFO_OMDB_API_KEY, etc.
    3. Command-line flags (highest priority)

    Example ~/.mkv2nfo.conf:
    MKV2NFO_SOURCE="PRIMEVIDEO"
    MKV2NFO_OMDB_API_KEY="your_api_key_here"
    MKV2NFO_KEEPCASE=0
    MKV2NFO_USE_FILENAME=0
    MKV2NFO_AUTO_SOURCE=0
    MKV2NFO_NOTES="Encoded by Me"

Examples:
    # Using manual title and URL
    $0 /path/to/Release.Name.2024.1080p/video.mkv --title "Episode 1" --source "DISNEYPLUS" --url "https://example.com"
    
    # Using IMDB ID (auto-fetches title and constructs URL)
    $0 /path/to/Release.Name.2024.1080p/video.mkv --imdb "tt7766378" --source "NETFLIX"
    
    # Using TVMaze show ID (auto-detects S/E from release name)
    $0 /path/to/ShowName.S02E02.1080p/video.mkv --tvmaze "49041" --source "PRIMEVIDEO"
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

# Get script directory for config file lookup
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Source config file if it exists (prefer ~/.mkv2nfo.conf, fallback to script directory)
if [ -f ~/.mkv2nfo.conf ]; then
    source ~/.mkv2nfo.conf
elif [ -f "${SCRIPT_DIR}/.mkv2nfo.conf" ]; then
    source "${SCRIPT_DIR}/.mkv2nfo.conf"
fi

# Initialize variables with defaults from config/environment or built-in defaults
TITLE=""
SOURCE=""
URL=""
IMDB_ID=""
TVMAZE_ID=""
NOTES="${MKV2NFO_NOTES:-none}"
OMDB_API_KEY="${MKV2NFO_OMDB_API_KEY:-}"
SUB_COUNT="0"
USE_FILENAME="${MKV2NFO_USE_FILENAME:-0}"
KEEPCASE="${MKV2NFO_KEEPCASE:-0}"
AUTO_SOURCE="${MKV2NFO_AUTO_SOURCE:-0}"
RELEASE_DATE=$(date +%Y-%m-%d)

# Store config SOURCE as fallback (don't use it yet)
FALLBACK_SOURCE="${MKV2NFO_SOURCE:-}"

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
        --imdb)
            IMDB_ID="$2"
            shift 2
            ;;
        --tvmaze)
            TVMAZE_ID="$2"
            shift 2
            ;;
        --notes)
            NOTES="$2"
            shift 2
            ;;
        --omdb-api-key)
            OMDB_API_KEY="$2"
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
        --auto-source)
            AUTO_SOURCE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Get the directory where the video file is located (needed early for auto-source detection)
VIDEO_DIR=$(dirname "$(readlink -f "$VIDEO_FILE")")

# Extract video filename without extension (for NFO filename)
VIDEO_BASENAME=$(basename "$VIDEO_FILE")
VIDEO_BASENAME="${VIDEO_BASENAME%.*}"

# Check mandatory fields
# Priority: 1. --source flag, 2. Auto-detect, 3. Fallback to MKV2NFO_SOURCE
if [ -z "$SOURCE" ]; then
    if [ "$AUTO_SOURCE" -eq 1 ]; then
        # Auto-detect source from release name
        TEMP_RELEASE=$(basename "$VIDEO_DIR")

        # Convert spaces to dots, then convert to uppercase for matching
        TEMP_RELEASE_UPPER=$(echo "$TEMP_RELEASE" | tr ' ' '.' | tr '[:lower:]' '[:upper:]')

        # Try to match source patterns (order matters - check specific sources first, WEB/WEB-DL last)
        if [[ "$TEMP_RELEASE_UPPER" =~ \.(AMZN|AMAZON)\. ]]; then
            SOURCE="AMAZON"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(NF|NFLX|NETFLIX)\. ]]; then
            SOURCE="NETFLIX"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(DSNP|DISNEYPLUS)\. ]]; then
            SOURCE="DISNEYPLUS"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.HULU\. ]]; then
            SOURCE="HULU"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(IT|ITUNES)\. ]]; then
            SOURCE="ITUNES"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(PCOK|PEACOCK)\. ]]; then
            SOURCE="PEACOCKTV"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(ATVP|ATV|APPLE)\. ]]; then
            SOURCE="APPLE"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(HMAX|HBO)\. ]]; then
            SOURCE="HBOMAX"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(MA|MOVIESANYWHERE)\. ]]; then
            SOURCE="MOVIESANYWHERE"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(BLURAY|BDRIP|BRRIP)\. ]]; then
            SOURCE="BluRay"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(DVD|DVDRIP)\. ]]; then
            SOURCE="DVD"
        elif [[ "$TEMP_RELEASE_UPPER" =~ \.(WEB-DL|WEB)\. ]]; then
            SOURCE="WEB-DL"
        fi

        # If auto-detect found something, announce it
        if [ -n "$SOURCE" ]; then
            echo "Auto-detected source: $SOURCE"
        # If auto-detect failed, try fallback
        elif [ -n "$FALLBACK_SOURCE" ]; then
            SOURCE="$FALLBACK_SOURCE"
            echo "Using fallback source from config: $SOURCE"
        else
            echo "Error: Could not auto-detect source from release name: $TEMP_RELEASE"
            echo "Please specify source manually with --source or set MKV2NFO_SOURCE in config"
            exit 1
        fi
    elif [ -n "$FALLBACK_SOURCE" ]; then
        # Not using auto-source, use fallback from config
        SOURCE="$FALLBACK_SOURCE"
    else
        echo "Error: --source is mandatory (or use --auto-source to detect automatically)"
        echo ""
        usage
    fi
fi

# Check if either IMDB, TVMAZE, or (TITLE and URL) are provided
if [ -n "$IMDB_ID" ]; then
    # IMDB mode - fetch title and construct URL
    # Check if API key is available
    if [ -z "$OMDB_API_KEY" ]; then
        echo "Error: OMDb API key not found"
        echo "Please set it via:"
        echo "  1. Config file: ~/.mkv2nfo.conf or .mkv2nfo.conf in script directory"
        echo "  2. Environment variable: MKV2NFO_OMDB_API_KEY"
        echo "  3. Command-line flag: --omdb-api-key KEY"
        exit 1
    fi

    # Fetch data from OMDb API
    echo "Fetching data from OMDb API for $IMDB_ID..."
    OMDB_RESPONSE=$(curl -s "https://www.omdbapi.com/?i=${IMDB_ID}&apikey=${OMDB_API_KEY}")

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required for JSON parsing but not found"
        echo "Please install jq: sudo apt-get install jq"
        exit 1
    fi

    # Check if API call was successful
    RESPONSE_STATUS=$(echo "$OMDB_RESPONSE" | jq -r '.Response')
    if [ "$RESPONSE_STATUS" = "False" ]; then
        ERROR_MSG=$(echo "$OMDB_RESPONSE" | jq -r '.Error')
        echo "Error: OMDb API returned an error: $ERROR_MSG"
        exit 1
    fi

    # Extract title from JSON response
    TITLE=$(echo "$OMDB_RESPONSE" | jq -r '.Title')

    if [ -z "$TITLE" ] || [ "$TITLE" = "null" ]; then
        echo "Error: Could not extract title from OMDb API response"
        exit 1
    fi

    # Construct IMDB URL
    URL="https://www.imdb.com/title/${IMDB_ID}/"

    echo "Found: $TITLE"
elif [ -n "$TVMAZE_ID" ]; then
    # TVMaze mode - auto-detect season/episode from release name and fetch title
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required for JSON parsing but not found"
        echo "Please install jq: sudo apt-get install jq"
        exit 1
    fi

    # Extract season and episode from RELEASE_NAME (which will be set later)
    # For now, we need to determine it from the directory/filename
    TEMP_RELEASE=$(basename "$VIDEO_DIR")

    # Try to extract SxxExx or SxEx pattern
    if [[ "$TEMP_RELEASE" =~ [Ss]([0-9]+)[Ee]([0-9]+) ]]; then
        SEASON="${BASH_REMATCH[1]}"
        EPISODE="${BASH_REMATCH[2]}"
        # Remove leading zeros for API call
        SEASON=$((10#$SEASON))
        EPISODE=$((10#$EPISODE))
    else
        echo "Error: Could not detect season/episode from release name: $TEMP_RELEASE"
        echo "Expected format: S##E## (e.g., S02E03)"
        exit 1
    fi

    echo "Detected: Season $SEASON, Episode $EPISODE"
    echo "Fetching data from TVMaze API for show $TVMAZE_ID..."

    # Fetch episode data from TVMaze API
    TVMAZE_RESPONSE=$(curl -s "https://api.tvmaze.com/shows/${TVMAZE_ID}/episodebynumber?season=${SEASON}&number=${EPISODE}")

    # Check if API call returned valid data
    if echo "$TVMAZE_RESPONSE" | jq -e '.name' > /dev/null 2>&1; then
        TITLE=$(echo "$TVMAZE_RESPONSE" | jq -r '.name')
        EPISODE_URL=$(echo "$TVMAZE_RESPONSE" | jq -r '.url')

        if [ -z "$TITLE" ] || [ "$TITLE" = "null" ]; then
            echo "Error: Could not extract title from TVMaze API response"
            exit 1
        fi

        SHOW_NAME=$(echo "$TVMAZE_RESPONSE" | jq -r '._links.show.name')
        SHOW_SLUG=$(echo "$SHOW_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        URL="https://www.tvmaze.com/shows/${TVMAZE_ID}/${SHOW_SLUG}"

        echo "Found: $TITLE (S${SEASON}E${EPISODE})"
    else
        echo "Error: TVMaze API did not return valid episode data"
        echo "Response: $TVMAZE_RESPONSE"
        exit 1
    fi
elif [ -z "$TITLE" ] || [ -z "$URL" ]; then
    echo "Error: Either --imdb, --tvmaze, OR both --title and --url are required"
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
    # Use the parent directory name as release name
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
