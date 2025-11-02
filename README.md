# Video + Music Merger

A desktop GUI application for merging video files with music tracks. Built with PySide6 and MoviePy, this tool provides an intuitive interface for adding background music to videos with professional audio ducking and volume control features.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python](https://img.shields.io/badge/python-3.8+-blue.svg)

## Features

- **Video Preview**: Built-in video player for previewing source and output videos
- **Music Preview**: Preview audio tracks before merging
- **Audio Ducking**: Keep original video audio mixed beneath the music at adjustable levels
- **Volume Control**: Independent sliders for music and original audio levels (0-100%)
- **Automatic Looping**: Music automatically loops to match video duration
- **Multi-threaded Processing**: Background processing prevents UI freezing during export
- **Progress Tracking**: Real-time progress bar during video processing
- **Format Support**: 
  - Video: MP4, MOV, MKV, AVI
  - Audio: MP3, WAV, M4A, AAC, FLAC

## Screenshots

```
┌─────────────────────────────────────────────────┐
│  Video + Music Merger                      ─ □ × │
├─────────────────────────────────────────────────┤
│  Video                                           │
│  ┌─────────────────────────────────────────┐    │
│  │                                          │    │
│  │         [Video Preview Area]            │    │
│  │                                          │    │
│  └─────────────────────────────────────────┘    │
│  Video: my_video.mp4                             │
│  [Select Video...]              [▶ Play]         │
├─────────────────────────────────────────────────┤
│  Music                                           │
│  Music: background_music.mp3                     │
│  [Select Music...]        [▶ Preview Music]      │
├─────────────────────────────────────────────────┤
│  Mixing & Ducking                                │
│  ☑ Keep original video audio (duck under music)│
│  Music level: 100%                               │
│  [═══════════════════════════════●]             │
│  Original level: 20%                             │
│  [═══●═══════════════════════════]             │
├─────────────────────────────────────────────────┤
│  Output: not created yet                         │
│  [Get FFmpeg...] [Merge & Preview...] [█░░░░░░] │
│  Engine: system-ffmpeg                           │
└─────────────────────────────────────────────────┘
```

## Requirements

### System Requirements
- Python 3.8 or higher Built and tested with 3.12 
- FFmpeg (required for video processing)

### if you are on non Windows - sorry - offering very ltd support!



### Python Dependencies
```
PySide6>=6.0.0
moviepy>=2.0.0
imageio-ffmpeg>=0.4.0
```

## Installation

### 1. Install FFmpeg

**Windows:**
```bash
# Using winget
winget install FFmpeg.FFmpeg

# Using Chocolatey
choco install ffmpeg

# Using Scoop
scoop install ffmpeg
```

**macOS:**
```bash
brew install ffmpeg
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install ffmpeg

# Fedora
sudo dnf install ffmpeg

# Arch Linux
sudo pacman -S ffmpeg
```

### 2. Install Python Dependencies

```bash
pip install PySide6 moviepy imageio-ffmpeg
```

### 3. Run the Application

```bash
python main.py
```

## Usage

### Basic Workflow

1. **Select Video**: Click "Select Video..." and choose your video file
2. **Select Music**: Click "Select Music..." and choose your audio file
3. **Preview (Optional)**: Use the play buttons to preview video and music
4. **Adjust Settings**:
   - Toggle "Keep original video audio" for audio ducking
   - Adjust music volume slider (default: 100%)
   - Adjust original audio level if ducking is enabled (default: 20%)
5. **Merge**: Click "Merge & Preview..." and choose output location
6. **Wait**: Progress bar shows processing status
7. **Preview**: Merged video automatically plays when complete

### Audio Ducking Explained

Audio ducking keeps the original video audio (dialogue, ambient sound) mixed with the music. This is useful when you want background music but still need to hear the original audio.

- **Enabled**: Both original audio and music are present
  - Original audio volume controlled by "Original level" slider
  - Music volume controlled by "Music level" slider
  - Default: Original at 20%, Music at 100%
  
- **Disabled**: Music completely replaces original audio
  - Only "Music level" slider applies

### Menu Options

**File Menu:**
- Open Video... - Select a video file
- Open Music... - Select an audio file
- Exit - Close the application

**Help Menu:**
- Get FFmpeg... - Display FFmpeg installation instructions

## Technical Details

### FFmpeg Detection

The application automatically detects FFmpeg in the following order:

1. **System FFmpeg** (preferred): Checks if `ffmpeg` is in system PATH
2. **Bundled FFmpeg**: Falls back to imageio-ffmpeg's bundled version
3. **Disabled**: If neither is found, merge functionality is disabled

System FFmpeg is significantly faster than the bundled version.

### Video Processing

- **Codec**: H.264 (libx264) for maximum compatibility
- **Audio Codec**: AAC
- **Threading**: Uses all available CPU cores
- **Frame Rate**: Preserves original video frame rate
- **Resolution**: Preserves original video resolution

### Audio Processing

- **Looping**: Music automatically loops to match video duration
- **Volume**: Applied using MoviePy's volume effects
- **Mixing**: CompositeAudioClip for ducking/mixing multiple audio tracks

### Thread Safety

Video processing runs in a separate QThread to prevent UI freezing. Progress updates are communicated via Qt signals.

## Troubleshooting

### "FFmpeg missing" Warning

**Problem**: Application shows "FFmpeg missing" or merge button is disabled.

**Solution**: 
1. Install FFmpeg using instructions above
2. Verify installation: `ffmpeg -version` in terminal
3. Restart the application

### "Bundled FFmpeg (slower)" Message

**Problem**: Using bundled FFmpeg which is slower than system version.

**Solution**: Install system FFmpeg for better performance (see Installation section).

### Merge Fails Immediately

**Possible Causes**:
1. Corrupted or unsupported video/audio file
2. Insufficient disk space for output file
3. Permission issues with output directory
4. FFmpeg not properly installed

**Solutions**:
1. Try a different video/audio file
2. Check available disk space
3. Choose a different output directory
4. Reinstall FFmpeg

### Video Plays Without Audio After Merge

**Problem**: Output video has no sound.

**Possible Causes**:
1. Music level set to 0%
2. Original audio missing and ducking enabled
3. Audio codec not supported by media player

**Solutions**:
1. Check music level slider is above 0%
2. If original video has no audio, disable ducking
3. Try playing in VLC media player

### Application Freezes During Processing

**Problem**: UI becomes unresponsive.

**Note**: This is normal during initial load of large files. The progress bar should still update during merge. If completely frozen for >5 minutes, the process may have crashed.

**Solution**: Check terminal/console for error messages and restart application.

## Performance Tips

1. **Use System FFmpeg**: 3-5x faster than bundled version
2. **Close Other Applications**: Video encoding is CPU-intensive
3. **Use Solid State Drive**: Faster read/write speeds improve processing time
4. **Reasonable Resolutions**: 4K videos take significantly longer than 1080p

## File Format Recommendations

### Video
- **Best**: MP4 (H.264)
- **Good**: MOV, MKV
- **Avoid**: Exotic or proprietary codecs

### Audio
- **Best**: MP3, M4A
- **Good**: WAV, AAC
- **Large**: FLAC (lossless, slower processing)

## Known Limitations

1. **Audio Length**: Music is looped to video length, cannot be trimmed
2. **Audio Sync**: Music always starts at video start time
3. **Multiple Tracks**: Only one music track can be added at a time
4. **Video Codecs**: Output is always H.264/AAC MP4
5. **Fade Effects**: No built-in fade in/out for audio

## Contributing

Contributions are welcome! Areas for improvement:

- [ ] Add fade in/out effects for audio
- [ ] Support multiple music tracks
- [ ] Add audio trim/offset controls
- [ ] Implement batch processing
- [ ] Add preset configurations
- [ ] Support for more output formats

## License

This project is available under the MIT License. See LICENSE file for details.

## Dependencies

- **PySide6**: Qt framework for Python (GUI)
- **MoviePy**: Video editing library
- **imageio-ffmpeg**: Bundled FFmpeg (fallback)
- **FFmpeg**: External dependency for video processing

## Credits

Built with:
- [PySide6](https://doc.qt.io/qtforpython-6/) - Python bindings for Qt
- [MoviePy](https://zulko.github.io/moviepy/) - Video editing framework
- [FFmpeg](https://ffmpeg.org/) - Multimedia processing framework

## Support

For issues, questions, or suggestions:
1. Check the Troubleshooting section above
2. Search existing issues
3. Open a new issue with:
   - Your OS and Python version
   - FFmpeg version (`ffmpeg -version`)
   - Steps to reproduce the problem
   - Error messages or screenshots

## Changelog

### Version 1.0.0
- Initial release
- Video and music merging
- Audio ducking support
- Volume controls
- Preview functionality
- Progress tracking
- MoviePy 2.1.2 compatibility
