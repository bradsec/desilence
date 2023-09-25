# desilence.sh

A Bash script that leverages FFmpeg to remove silence from audio files. This script performs functions similar to other Python applications like Audio Slicer, etc. It can be used to clean audio for creating AI training datasets. In testing, this pure FFmpeg bash script was found to be easier to use and performed just as well as other Python solutions, without the setup requirements and dependency hell sometimes associated with Python.

## Compatibility

This script is for Linux systems and requires a bash shell. It may however may work if you have Windows Subsystem for Linux (WSL) installed on Windows (untested). Should work on macOS, you may need to update your bash version (easiest way is to use homebrew).

## Features

- Converts input audio file to a standard WAV format.
- Segments the audio based on silence detection.
- Concatenates the segmented audio clips into a single audio file.
- Supports grouping segments into time-based groups before concatenation.

## Requirements

- Bash (version 4 or later)
- FFmpeg

## Usage

1. Clone this repository or download the `desilence.sh` script.
2. Make the script executable:

```bash
# Make script executable (ie. don't need to prefix with bash)
chmod +x desilence.sh

# Run as follows
./desilence.sh input-file
```

```
# Alternatively

bash desilence.sh input-file
```

Replace `input-file`` with the path to the audio file you want to process.

## Configuration

You can adjust various settings within the script. Refer to the global variables at the top of the script. However, deviating from default values may result in audio segments being lost, if you make values too large etc.  

For training sets which require set length audio segments this can be adjusted in the `main` function. Default is 10 second segments / chunks.

The script creates several directories (temp, source, segments, concat) to hold intermediate and final processed audio files.

- The `segments` directory contains individual audio segments with silence removed. This is purely segmenting / chunking based on the `MIN_LENGTH` and `SILENCE_DURATION` values at the top of the script.  
- If you have significant background noise in your audio you may have to clean first or try increasing the `SILENCE_DB` value. Default is set to `-30dB`.
- The `concat` directory contains concatenated audio files. One file contains all segments concatenated together, and other files contain segments grouped into time-based chunks (e.g., every 10 seconds of audio).

## License

- MIT License - desilence.sh
- [Mixed Licence](https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md) - [FFmpeg](https://github.com/FFmpeg/FFmpeg)