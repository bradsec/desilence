#!/usr/bin/env bash

##########################################################
## Name:          desilence.sh                          ##
## Description:   A bash script which uses FFmpeg       ##
##                to remove silence from audio files.   ##
## Requirements:  Bash >= version 4                     ##
## Author:        github/bradsec                        ##
## License:       MIT License                           ##
##########################################################

shopt -s nullglob
SCRIPT_PATH="$(realpath ${BASH_SOURCE:-$0})"
SCRIPT_DIR="$(dirname ${SCRIPT_PATH})"

# Input file taken from command line
INPUT_FILE=${1}

# Get filename and clean without extension
INPUT_FILENAME=${INPUT_FILE##*/}

# Adjust values as required.
# Note: lower values for min_length segments and silence_duration of like 0.20 ensures short words or sounds are not missed.
# Used by fetch_segments function
MIN_LENGTH=0.20
SILENCE_DURATION=0.20
SILENCE_DB=-30dB

# PATHS
TEMP_DIR="${SCRIPT_DIR}/temp"
SOURCE_DIR="${SCRIPT_DIR}/source"
SEGMENT_DIR="${SCRIPT_DIR}/segments"
CONCAT_DIR="${SCRIPT_DIR}/concat"

# Make required directories if they don't exist.
mkdir -p ${TEMP_DIR}
mkdir -p ${SOURCE_DIR}
mkdir -p ${SEGMENT_DIR}
mkdir -p ${CONCAT_DIR}

banner() {
    printf "${GREEN}         
 ____  _____ ____ ___ _     _____ _   _  ____ _____ 
|  _ \| ____/ ___|_ _| |   | ____| \ | |/ ___| ____|
| | | |  _| \___ \| || |   |  _| |  \| | |   |  _|  
| |_| | |___ ___) | || |___| |___| |\  | |___| |___ 
|____/|_____|____|___|_____|_____|_| \_|\____|_____|
${YELLOW}                                                    
A Bash script that leverages FFmpeg to remove silence from audio files.
${RESET}
"
}


# Set colors for use in task terminal output functions
function message_colors() {
    if [[ -t 1 ]]; then
        RED=$(printf '\033[31m')
        GREEN=$(printf '\033[32m')
        CYAN=$(printf '\033[36m')
        YELLOW=$(printf '\033[33m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[0m')
    else
        RED=""
        GREEN=""
        CYAN=""
        YELLOW=""
        BOLD=""
        RESET=""
    fi
}
# Init terminal message colors
message_colors

# Terminal message output formatting
# message() function displays formatted and coloured terminal messages.
# TASK messages overwrite the same line of information.
# Usage example: message INFO "This is a information message"
function message() {
    local option=${1}
    local text=${2}
    case "${option}" in
        TASKSTART) echo -ne "[${CYAN}TASK${RESET}] ${text}";;
        TASKDONE) echo -e "\r[${GREEN}${BOLD}DONE${RESET}] ${GREEN}${text}${RESET}$(tput el)";;
        TASKFAIL) echo -e "\r[${RED}${BOLD}FAIL${RESET}] ${RED}${text}${RESET}$(tput el)";;
        TASKSKIP) echo -e "\r[${YELLOW}${BOLD}SKIP${RESET}] ${YELLOW}${text}${RESET}$(tput el)";;
        DONE) echo -e "[${GREEN}DONE${RESET}] ${GREEN}${text}${RESET}";;
        FAIL) echo -e "[${RED}${BOLD}FAIL${RESET}] ${text}";;
        INFO) echo -e "[${CYAN}INFO${RESET}] ${text}";;
        INFOFULL) echo -e "[${CYAN}INFO${RESET}] ${CYAN}${text}${RESET}";;
        WARN) echo -e "[${YELLOW}WARN${RESET}] ${text}";;
        WARNFULL) echo -e "[${YELLOW}WARN${RESET}] ${YELLOW}${text}${RESET}";;
        USER) echo -e "[${GREEN}USER${RESET}] ${text}";;
        DBUG) echo -e "[${YELLOW}${BOLD}DBUG${RESET}] ${YELLOW}${text}${RESET}";;
        *) echo -e "${text}";;
    esac
}


function check_ffmpeg() {
    if ! command -v ffmpeg &> /dev/null
    then
        message FAIL "The required ffmpeg command could not be found."
        message INFO "Install ffmpeg or check ffmpeg is in command PATH and try again."
        exit 1
    fi
}

function check_input_file() {
    # Check if $1 (input argument) is provided
    if [[ -z "${INPUT_FILE}" ]]; then
        message FAIL "No input audio file provided."
        echo "Usage: $0 <input-file>"
        exit 1
    fi

    # Check if INPUT_FILE exists
    if [[ ! -f "${INPUT_FILE}" ]]; then
        message FAIL "The specified input audio file does not exist: ${INPUT_FILE}"
        exit 1
    fi
}

# Display press any key or do you wish to continue y/N.
# Example usage: wait_for user_anykey OR wait_for user_continue
function wait_for() {
    echo
    if [ -z "${2}" ]; then
        message="Do you wish to continue"
    else
        message="${2}"
    fi

    case "${1}" in
        user_anykey) read -n 1 -s -r -p "[${GREEN}USER${RESET}] Press any key to continue. "
        echo -e "\n"
        ;;
        user_continue) local response
        while true; do
            read -r -p "[${GREEN}USER${RESET}] ${message} (y/N)?${RESET} " response
            case "${response}" in
            [yY][eE][sS] | [yY])
                echo
                break
                ;;
            *)
                echo
                exit
                ;;
            esac
        done;;
        *) message FAIL "Invalid function usage.";;
    esac
}

clean_string() {
  local input="$1"
  cleaned="${input//[^[:alnum:]]/}"
  cleaned="${cleaned,,}"
  echo "$cleaned"
}

convert_to_wav() {
    message INFO "convert_to_wav commenced..."
    local clean_name=$(clean_string ${INPUT_FILENAME%.*})
    local wav_file_name="${SOURCE_DIR}/${clean_name}.wav"
    ffmpeg -y -i "${INPUT_FILE}" -acodec pcm_s16le -ar 44100 "${wav_file_name}"
    message DONE "convert_to_wav completed."
}

function reset_dir() {
    wait_for user_continue "Confirm removal of all previously created desilenced audio files"
    rm -rf "${SOURCE_DIR}"/*
    rm -rf "${TEMP_DIR}"/*
    rm -rf "${SEGMENT_DIR}"/*
    rm -rf "${CONCAT_DIR}"/*
}

function fetch_segments() {
    message INFO "fetch_segment commenced..."
    # Initialise variables
    local previous_end=-0.0
    local segment_counter=0
    local silence_start=""
    local silence_end=""
    local clean_name=$(clean_string ${INPUT_FILENAME%.*})
    local input_wav_file="${SOURCE_DIR}/${clean_name}.wav"

    # Process the silencedetect output line by line
    ffmpeg -y -i "${input_wav_file}" -af "silencedetect=noise=${SILENCE_DB}:d=${SILENCE_DURATION}" -f null - 2>&1 | grep silence_ | while read -r line
    do
        # Check if the line contains silence_start
        if [[ ${line} == *silence_start* ]]; then
            # Extract the silence_start time
            silence_start=$(echo "${line}" | awk '{print $5}')
        fi

        # Check if the line contains silence_end
        if [[ ${line} == *silence_end* ]]; then
            # Extract the silence_end time
            silence_end=$(echo "${line}" | awk '{print $5}')
        fi

        # Check if we have both silence_start and silence_end
        if [[ -n ${silence_start} ]] && [[ -n ${silence_end} ]]; then
            # Calculate the segment duration
            segment_duration=$(echo "${silence_start} - ${previous_end}" | bc)

            # Check if the segment duration is within the desired range
            if (( $(echo "$segment_duration >= $MIN_LENGTH" | bc -l) )); then
                # Increment the segment counter
                segment_counter=$((segment_counter + 1))
                temp_output_file=$(printf "temp_${clean_name}%03d.wav" "${segment_counter}")

                # Extract the segment with additional silence at the end
                ffmpeg -y -i "${INPUT_FILE}" -ss "${previous_end}" -to "${silence_start}" -c copy "${TEMP_DIR}/${temp_output_file}"
                echo "Extracted segment ${segment_counter} to ${TEMP_DIR}/${temp_output_file}"
                
                segment_file=$(printf "${clean_name}_segment_%03d.wav" "${segment_counter}")

                # Trim silence from the end of the segment
                ffmpeg -y -i "${TEMP_DIR}/${temp_output_file}" -af "silenceremove=stop_periods=-1:stop_duration=1:stop_threshold=${SILENCE_DB}" "${SEGMENT_DIR}/${segment_file}"
                echo "Trimmed silence from ${temp_output_file} and saved to ${SEGMENT_DIR}/${segment_file}"
                
                # Optionally, remove the temporary file
                rm "${TEMP_DIR}/${temp_output_file}"
            fi

            previous_end=${silence_end}

            # Reset silence_start and silence_end for the next iteration
            silence_start=""
            silence_end=""
        fi
    done

    message DONE "fetch_segment completed."
}

function concat_all_segments() {
    message INFO "concat_all_segments commenced..."
    local clean_name=$(clean_string ${INPUT_FILENAME%.*})
    local segment_list_name="${clean_name}_segments.txt"
    local concat_filename="${clean_name}_concat_all.wav"

    [ -e "${segment_list_name}" ] && rm "${segment_list_name}"
    for f in segments/${clean_name}*.wav; do echo "file '$f'" >> "${segment_list_name}"; done

    ffmpeg -y -f concat -safe 0 -i ${segment_list_name} -c copy "${CONCAT_DIR}/${concat_filename}"
    message DONE "concat_all_segments completed."
}


function concat_timed_segments() {
    message INFO "concat_timed_segments commenced..."

    # Max duration of each concat segment in seconds
    local max_duration=${1}

    local clean_name=$(clean_string ${INPUT_FILENAME%.*})
    local segment_list_name="${clean_name}_segments.txt"
    local segment_duration=0
    local segment_counter=0
    local temp_list=()

    # Remove existing segment list file if it exists
    [ -e "${segment_list_name}" ] && rm "${segment_list_name}"

    for f in segments/${clean_name}*.wav; do
        # Get the duration of the current segment using ffprobe
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f")

        # Check if adding the current segment exceeds the max duration
        if (( $(echo "$segment_duration + $duration > $max_duration" | bc -l) )); then
            # If adding the current segment would exceed the max duration, create a new concat segment
            segment_counter=$((segment_counter + 1))
            concat_segment="${CONCAT_DIR}/${clean_name}_concat_max${max_duration}secs_$(printf "%03d" $segment_counter).wav"

            # Create a temporary list file with a list of input files in the current working directory
            temp_list_file="./temp_list.txt"
            printf "file '%s'\n" "${temp_list[@]}" > "${temp_list_file}"

            # Concatenate the segments using ffmpeg's concat demuxer with the temporary list file
            ffmpeg -y -f concat -safe 0 -i "${temp_list_file}" -c:a pcm_s16le -ar 44100 "${concat_segment}"

            # Clean up the temporary list file
            rm "${temp_list_file}"
            
            echo "Created concat segment: ${concat_segment}"

            # Reset segment_duration and temp_list
            segment_duration=0
            temp_list=()
        fi

        # Add the current segment to temp_list
        temp_list+=("${f}")
        segment_duration=$(echo "$segment_duration + $duration" | bc -l)
    done

    # If there are remaining segments in temp_list, create one final concat segment
    if [ ${#temp_list[@]} -gt 0 ]; then
        segment_counter=$((segment_counter + 1))
        concat_segment="${CONCAT_DIR}/${clean_name}_concat_max${max_duration}secs_$(printf "%03d" $segment_counter).wav"

        # Create a temporary list file with a list of input files in the current working directory
        temp_list_file="./temp_list.txt"
        printf "file '%s'\n" "${temp_list[@]}" > "${temp_list_file}"

        # Concatenate the remaining segments using ffmpeg's concat demuxer with the temporary list file
        ffmpeg -y -f concat -safe 0 -i "${temp_list_file}" -c:a pcm_s16le -ar 44100 "${concat_segment}"

        rm "${temp_list_file}"

        echo "Created final concat segment: ${concat_segment}"
    fi

    message DONE "concat_timed_segments completed."
}


function main() {
    banner
    # Check valid input file
    check_input_file
    # Check for FFmpeg
    check_ffmpeg
    # Remove all files from default directories, temp, source
    reset_dir
    # Convert input file to standard .wav format
    convert_to_wav
    # Fetch audio segments without silence
    fetch_segments 
    # Join all segments into one large file without original file silence
    concat_all_segments
    # Combine segments in timed groups value in seconds.
    # A minimum value of 10 seconds is recommended.
    concat_timed_segments 10
    message DONE "Desilence script completed."
}

main "${@}"