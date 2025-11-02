"""
Video + Music Merger GUI (MoviePy 2.1.2 compatible, final)

A desktop application for merging video files with music tracks.
Supports audio ducking, volume control, and real-time preview.
"""
from __future__ import annotations
import os, sys, shutil
from dataclasses import dataclass
from typing import Optional

from PySide6.QtCore import Qt, QObject, QThread, Signal, Slot, QUrl
from PySide6.QtGui import QAction
from PySide6.QtWidgets import (
    QApplication, QFileDialog, QLabel, QMainWindow, QMessageBox, QPushButton,
    QVBoxLayout, QHBoxLayout, QWidget, QProgressBar, QStyle, QGroupBox, QSlider, QCheckBox
)
from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer
from PySide6.QtMultimediaWidgets import QVideoWidget

import imageio_ffmpeg

# Global variables for FFmpeg availability tracking
FFMPEG_ERROR = None
ENGINE = "disabled"  # Tracks which FFmpeg engine is available: "system-ffmpeg", "bundled-ffmpeg", or "disabled"

def ensure_ffmpeg_available() -> str:
    """
    Check for FFmpeg availability in the following order:
    1. System-installed FFmpeg (via PATH)
    2. Bundled FFmpeg from imageio-ffmpeg package
    
    Returns:
        str: Path to the FFmpeg executable
        
    Raises:
        FileNotFoundError: If no FFmpeg executable is found
    """
    global ENGINE
    
    # Try to find system-installed FFmpeg first (faster)
    ffmpeg_path = shutil.which("ffmpeg")
    if ffmpeg_path:
        ENGINE = "system-ffmpeg"
        return ffmpeg_path
    
    # Fall back to bundled FFmpeg from imageio-ffmpeg
    try:
        ffmpeg_path = imageio_ffmpeg.get_ffmpeg_exe()
        if os.path.exists(ffmpeg_path):
            ENGINE = "bundled-ffmpeg"
            return ffmpeg_path
    except Exception:
        pass
    
    # No FFmpeg found
    ENGINE = "disabled"
    raise FileNotFoundError("No FFmpeg executable found. Install FFmpeg or keep 'imageio-ffmpeg' installed.")

# Attempt to set up FFmpeg at module load time
try:
    os.environ["IMAGEIO_FFMPEG_EXE"] = ensure_ffmpeg_available()
except Exception as e:
    FFMPEG_ERROR = str(e)

# MoviePy imports - must come after FFmpeg setup
from moviepy import VideoFileClip, AudioFileClip, CompositeAudioClip

# Try to import volume effect (varies across MoviePy versions)
try:
    from moviepy.audio.fx.MultiplyVolume import multiply_volume as volumex
except Exception:
    try:
        from moviepy.audio.fx.MultiplyVolume import volumex
    except Exception:
        volumex = None

# Try to import audio looping effect (MoviePy 2.1.2+)
try:
    from moviepy.audio.fx.AudioLoop import audio_loop
except Exception:
    audio_loop = None

def _safe_vol(clip, level: float):
    """
    Apply volume adjustment safely across different MoviePy versions.
    
    Tries multiple methods in order of preference:
    1. Native clip.volumex() method
    2. Effect function via clip.fx(volumex, level)
    3. Manual lambda using clip.fl()
    4. No-op if level is approximately 1.0
    
    Args:
        clip: AudioClip to adjust volume for
        level: Volume multiplier (1.0 = original, 0.5 = half volume, 2.0 = double)
        
    Returns:
        AudioClip with adjusted volume
        
    Raises:
        RuntimeError: If no volume method is available and level != 1.0
    """
    # Method 1: Native volumex method
    try:
        if hasattr(clip, "volumex"):
            return clip.volumex(level)
    except Exception:
        pass
    
    # Method 2: Effect function via fx
    if callable(volumex):
        try:
            return clip.fx(volumex, level)
        except Exception:
            pass
    
    # Method 3: Manual fallback using AudioClip.fl (works in 2.1.2)
    try:
        if hasattr(clip, "fl") and callable(getattr(clip, "fl")):
            return clip.fl(lambda gf, t: gf(t) * float(level))
    except Exception:
        pass
    
    # Method 4: No-op if level is essentially 1.0
    if abs(level - 1.0) < 1e-9:
        return clip
    
    # No method available - raise error
    raise RuntimeError("Volume effect not available in this MoviePy build.")

@dataclass
class SelectionState:
    """
    Data class to track user's file selections and output path.
    
    Attributes:
        video_path: Path to the selected video file
        audio_path: Path to the selected music file
        output_path: Path where the merged video will be saved
    """
    video_path: Optional[str] = None
    audio_path: Optional[str] = None
    output_path: Optional[str] = None

class MergeWorker(QObject):
    """
    Background worker for video/audio merging operations.
    
    Runs in a separate thread to prevent UI freezing during processing.
    Emits signals to update progress and report completion/errors.
    
    Signals:
        finished: Emitted when merge completes successfully (with output path)
        failed: Emitted when merge fails (with error message)
        progress: Emitted periodically with progress percentage (0-100)
    """
    finished = Signal(str)
    failed = Signal(str)
    progress = Signal(int)

    def __init__(self, video_path, audio_path, output_path, music_level, original_level, duck):
        """
        Initialize the merge worker.
        
        Args:
            video_path: Path to input video file
            audio_path: Path to input music file
            output_path: Path for output merged video
            music_level: Volume multiplier for music (0.0-1.0)
            original_level: Volume multiplier for original video audio (0.0-1.0)
            duck: Whether to keep original audio mixed with music
        """
        super().__init__()
        self.video_path = video_path
        self.audio_path = audio_path
        self.output_path = output_path
        self.music_level = music_level
        self.original_level = original_level
        self.duck = duck

    @Slot()
    def run(self):
        """
        Execute the video/audio merge operation.
        
        Process:
        1. Load video and extract properties
        2. Load and adjust music volume
        3. Loop music to match video duration
        4. Mix with original audio if ducking is enabled
        5. Write final video file
        
        Emits progress signals at key stages and finished/failed on completion.
        """
        try:
            # Check FFmpeg availability
            if ENGINE == "disabled":
                raise RuntimeError("FFmpeg unavailable.")
            
            self.progress.emit(5)
            
            # Load video file
            with VideoFileClip(self.video_path) as v:
                duration = v.duration or 0
                v_fps = v.fps or 25
                original_audio = v.audio
                
                self.progress.emit(20)
                
                # Load and adjust music volume
                with AudioFileClip(self.audio_path) as music:
                    music = _safe_vol(music, self.music_level)

                    # Loop music to fit video duration (if audio_loop is available)
                    if duration > 0 and audio_loop is not None:
                        try:
                            music = audio_loop(music, duration=duration)
                        except Exception:
                            pass  # Fall back to raw length if fx fails

                    # Mix original audio with music (ducking)
                    if self.duck and original_audio is not None:
                        bed = _safe_vol(original_audio, self.original_level)
                        mixed = CompositeAudioClip([bed, music])
                        merged_clip = v.with_audio(mixed)
                    else:
                        # Replace original audio entirely
                        merged_clip = v.with_audio(music)

                    self.progress.emit(55)
                    
                    # Write the final video file
                    merged_clip.write_videofile(
                        self.output_path,
                        codec="libx264",           # H.264 video codec
                        audio_codec="aac",         # AAC audio codec
                        temp_audiofile="_temp_audio.m4a",
                        remove_temp=True,          # Clean up temporary files
                        threads=0,                 # Use all available CPU cores
                        fps=v_fps,                 # Preserve original frame rate
                    )
            
            self.progress.emit(100)
            self.finished.emit(self.output_path)
            
        except Exception as e:
            self.failed.emit(str(e))

class MainWindow(QMainWindow):
    """
    Main application window for the Video + Music Merger.
    
    Provides:
    - Video and music file selection
    - Preview playback for both files
    - Volume controls and audio ducking
    - Background merge processing with progress tracking
    - Output preview after merge completion
    """
    
    def __init__(self):
        """Initialize the main window and all UI components."""
        super().__init__()
        self.setWindowTitle("Video + Music Merger")
        self.setMinimumSize(900, 600)
        
        # Initialize selection state
        self.state = SelectionState()
        
        # Show FFmpeg status message
        if ENGINE == "bundled-ffmpeg":
            QMessageBox.information(self, "Speed tip", "Bundled FFmpeg (slower). Install system FFmpeg for better speed.")
        elif ENGINE == "disabled":
            QMessageBox.warning(self, "FFmpeg missing", "Install FFmpeg to enable merging.")
        
        # Set up video player for preview
        self.video_player = QMediaPlayer(self)
        self.video_output = QVideoWidget(self)
        self.video_player.setVideoOutput(self.video_output)
        self.video_audio = QAudioOutput(self)
        self.video_player.setAudioOutput(self.video_audio)
        
        # Set up music player for preview
        self.music_player = QMediaPlayer(self)
        self.music_audio = QAudioOutput(self)
        self.music_player.setAudioOutput(self.music_audio)
        
        # Status labels
        self.video_label = QLabel("No video selected")
        self.audio_label = QLabel("No music selected")
        self.output_label = QLabel("Output: not created yet")
        
        # Video selection and playback controls
        pick_video_btn = QPushButton("Select Video…")
        pick_video_btn.clicked.connect(self.pick_video)
        
        self.play_video_btn = QPushButton(self.style().standardIcon(QStyle.SP_MediaPlay), " Play")
        self.play_video_btn.clicked.connect(self.toggle_video_play)
        self.play_video_btn.setEnabled(False)
        
        # Music selection and playback controls
        pick_audio_btn = QPushButton("Select Music…")
        pick_audio_btn.clicked.connect(self.pick_audio)
        
        self.play_audio_btn = QPushButton(self.style().standardIcon(QStyle.SP_MediaPlay), " Preview Music")
        self.play_audio_btn.clicked.connect(self.toggle_audio_play)
        self.play_audio_btn.setEnabled(False)
        
        # Merge button and progress bar
        self.merge_btn = QPushButton("Merge & Preview…")
        self.merge_btn.setEnabled(False)
        self.merge_btn.clicked.connect(self.merge_and_preview)
        
        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        
        # Video group with preview widget
        video_group = QGroupBox("Video")
        vbox_video = QVBoxLayout()
        vbox_video.addWidget(self.video_output, 1)  # Give video widget stretch priority
        vbox_video.addWidget(self.video_label)
        vcontrols = QHBoxLayout()
        vcontrols.addWidget(pick_video_btn)
        vcontrols.addStretch(1)
        vcontrols.addWidget(self.play_video_btn)
        vbox_video.addLayout(vcontrols)
        video_group.setLayout(vbox_video)
        
        # Music group
        audio_group = QGroupBox("Music")
        vbox_audio = QVBoxLayout()
        vbox_audio.addWidget(self.audio_label)
        acontrols = QHBoxLayout()
        acontrols.addWidget(pick_audio_btn)
        acontrols.addStretch(1)
        acontrols.addWidget(self.play_audio_btn)
        vbox_audio.addLayout(acontrols)
        audio_group.setLayout(vbox_audio)
        
        # Mixing controls group
        mixing_group = QGroupBox("Mixing & Ducking")
        mix_layout = QVBoxLayout()
        
        # Checkbox to enable/disable audio ducking
        self.keep_original_chk = QCheckBox("Keep original video audio (duck under music)")
        self.keep_original_chk.setChecked(True)
        
        # Music volume slider (0-100%)
        self.music_slider = QSlider(Qt.Horizontal)
        self.music_slider.setRange(0, 100)
        self.music_slider.setValue(100)
        self.music_slider.valueChanged.connect(lambda v: self.music_label.setText(f"Music level: {v}%"))
        self.music_label = QLabel("Music level: 100%")
        
        # Original audio volume slider (0-100%)
        self.original_slider = QSlider(Qt.Horizontal)
        self.original_slider.setRange(0, 100)
        self.original_slider.setValue(20)
        self.original_slider.valueChanged.connect(lambda v: self.original_label.setText(f"Original level: {v}%"))
        self.original_label = QLabel("Original level: 20%")
        
        mix_layout.addWidget(self.keep_original_chk)
        mix_layout.addWidget(self.music_label)
        mix_layout.addWidget(self.music_slider)
        mix_layout.addWidget(self.original_label)
        mix_layout.addWidget(self.original_slider)
        mixing_group.setLayout(mix_layout)
        
        # Bottom control bar
        bottom_controls = QHBoxLayout()
        self.get_ffmpeg_btn = QPushButton("Get FFmpeg…")
        self.get_ffmpeg_btn.clicked.connect(self.show_ffmpeg_help)
        bottom_controls.addWidget(self.get_ffmpeg_btn)
        bottom_controls.addWidget(self.merge_btn)
        bottom_controls.addWidget(self.progress)
        
        # Engine status label
        self.engine_label = QLabel(f"Engine: {ENGINE}")
        
        # Assemble main layout
        central = QWidget()
        root = QVBoxLayout(central)
        root.addWidget(video_group, 2)     # Give video group more space
        root.addWidget(audio_group, 1)
        root.addWidget(mixing_group, 0)    # Fixed size for controls
        root.addWidget(self.output_label)
        root.addLayout(bottom_controls)
        root.addWidget(self.engine_label)
        self.setCentralWidget(central)
        
        # Create menu bar
        file_menu = self.menuBar().addMenu("&File")
        
        open_video_act = QAction("Open Video…", self)
        open_video_act.triggered.connect(self.pick_video)
        file_menu.addAction(open_video_act)
        
        open_audio_act = QAction("Open Music…", self)
        open_audio_act.triggered.connect(self.pick_audio)
        file_menu.addAction(open_audio_act)
        
        file_menu.addSeparator()
        
        exit_act = QAction("E&xit", self)
        exit_act.triggered.connect(self.close)
        file_menu.addAction(exit_act)
        
        help_menu = self.menuBar().addMenu("&Help")
        get_ffmpeg_act = QAction("Get FFmpeg…", self)
        get_ffmpeg_act.triggered.connect(self.show_ffmpeg_help)
        help_menu.addAction(get_ffmpeg_act)
        
        # Connect playback state changes to update button icons/text
        self.video_player.playbackStateChanged.connect(self.update_video_play_button)
        self.music_player.playbackStateChanged.connect(self.update_music_play_button)

    def pick_video(self):
        """Open file dialog to select a video file and load it for preview."""
        path, _ = QFileDialog.getOpenFileName(self, "Select video", "", "Video Files (*.mp4 *.mov *.mkv *.avi)")
        if path:
            self.state.video_path = path
            self.video_label.setText(f"Video: {os.path.basename(path)}")
            self.video_player.setSource(QUrl.fromLocalFile(path))
            self.play_video_btn.setEnabled(True)
            self.enable_merge_if_ready()

    def pick_audio(self):
        """Open file dialog to select a music file and load it for preview."""
        path, _ = QFileDialog.getOpenFileName(self, "Select music", "", "Audio Files (*.mp3 *.wav *.m4a *.aac *.flac)")
        if path:
            self.state.audio_path = path
            self.audio_label.setText(f"Music: {os.path.basename(path)}")
            self.music_player.setSource(QUrl.fromLocalFile(path))
            self.play_audio_btn.setEnabled(True)
            self.enable_merge_if_ready()

    def enable_merge_if_ready(self):
        """Enable the merge button only when both video and audio are selected and FFmpeg is available."""
        self.merge_btn.setEnabled(bool(self.state.video_path and self.state.audio_path and ENGINE != "disabled"))

    def toggle_video_play(self):
        """Toggle video playback between play and pause states."""
        if self.video_player.playbackState() == QMediaPlayer.PlaybackState.PlayingState:
            self.video_player.pause()
        else:
            self.video_player.play()

    def toggle_audio_play(self):
        """Toggle music playback between play and pause states."""
        if self.music_player.playbackState() == QMediaPlayer.PlaybackState.PlayingState:
            self.music_player.pause()
        else:
            self.music_player.play()

    def update_video_play_button(self):
        """Update video play button icon and text based on current playback state."""
        playing = self.video_player.playbackState() == QMediaPlayer.PlaybackState.PlayingState
        icon = self.style().standardIcon(QStyle.SP_MediaPause if playing else QStyle.SP_MediaPlay)
        self.play_video_btn.setIcon(icon)
        self.play_video_btn.setText(" Pause" if playing else " Play")

    def update_music_play_button(self):
        """Update music play button icon and text based on current playback state."""
        playing = self.music_player.playbackState() == QMediaPlayer.PlaybackState.PlayingState
        icon = self.style().standardIcon(QStyle.SP_MediaPause if playing else QStyle.SP_MediaPlay)
        self.play_audio_btn.setIcon(icon)
        self.play_audio_btn.setText(" Pause Music" if playing else " Preview Music")

    def show_ffmpeg_help(self):
        """Display a dialog with information about installing FFmpeg."""
        msg = QMessageBox(self)
        msg.setWindowTitle("Get FFmpeg")
        msg.setIcon(QMessageBox.Information)
        msg.setText("Install FFmpeg for better performance. Use winget/choco/scoop on Windows or brew on macOS.")
        msg.exec()

    def merge_and_preview(self):
        """
        Start the video/audio merge process in a background thread.
        
        Process:
        1. Validate that both files are selected
        2. Prompt user for output file location
        3. Create worker thread for merge operation
        4. Connect signals for progress updates and completion
        5. Start the merge
        """
        # Validation
        if not (self.state.video_path and self.state.audio_path):
            QMessageBox.warning(self, "Missing files", "Select both video and music first.")
            return
        if ENGINE == "disabled":
            QMessageBox.warning(self, "FFmpeg missing", "Install FFmpeg to enable export.")
            return
        
        # Get output file path from user
        suggested = self.suggest_output_path(self.state.video_path)
        out_path, _ = QFileDialog.getSaveFileName(self, "Export merged video", suggested, "MP4 Video (*.mp4)")
        if not out_path:
            return
        if not out_path.lower().endswith(".mp4"):
            out_path += ".mp4"
        
        self.state.output_path = out_path
        self.merge_btn.setEnabled(False)
        self.progress.setValue(0)
        
        # Create worker thread
        self.thread = QThread(self)
        self.worker = MergeWorker(
            self.state.video_path,
            self.state.audio_path,
            out_path,
            self.music_slider.value() / 100.0,    # Convert percentage to 0.0-1.0
            self.original_slider.value() / 100.0,
            self.keep_original_chk.isChecked(),
        )
        
        # Move worker to thread and connect signals
        self.worker.moveToThread(self.thread)
        self.thread.started.connect(self.worker.run)
        self.worker.progress.connect(self.progress.setValue)
        self.worker.finished.connect(self.on_merge_finished)
        self.worker.failed.connect(self.on_merge_failed)
        
        # Clean up thread and worker when done
        self.worker.finished.connect(self.thread.quit)
        self.worker.failed.connect(self.thread.quit)
        self.worker.finished.connect(self.worker.deleteLater)
        self.worker.failed.connect(self.worker.deleteLater)
        self.thread.finished.connect(self.thread.deleteLater)
        
        # Start the merge
        self.thread.start()

    @Slot(str)
    def on_merge_finished(self, output_path: str):
        """
        Handle successful merge completion.
        
        Updates UI, shows success message, and automatically plays the merged video.
        
        Args:
            output_path: Path to the newly created merged video file
        """
        self.output_label.setText(f"Output: {os.path.basename(output_path)}")
        QMessageBox.information(self, "Done", f"Merged video saved to:\n{output_path}")
        
        # Load and play the merged video
        self.video_player.setSource(QUrl.fromLocalFile(output_path))
        self.video_player.play()
        
        self.enable_merge_if_ready()

    @Slot(str)
    def on_merge_failed(self, err: str):
        """
        Handle merge failure.
        
        Displays error message and re-enables merge button.
        
        Args:
            err: Error message describing what went wrong
        """
        QMessageBox.critical(self, "Merge failed", err)
        self.enable_merge_if_ready()

    @staticmethod
    def suggest_output_path(video_path: str) -> str:
        """
        Generate a suggested output filename based on the input video.
        
        Args:
            video_path: Path to the input video file
            
        Returns:
            Suggested output path with "_with_music" suffix
        """
        base, _ = os.path.splitext(video_path)
        return f"{base}_with_music.mp4"

def main():
    """Application entry point."""
    app = QApplication(sys.argv)
    w = MainWindow()
    w.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
