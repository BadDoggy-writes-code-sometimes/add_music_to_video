# ============================================================================
# Video Music Merger - OPTIMIZED FOR SIZE Build Script
# ============================================================================

param(
    [switch]$Sign,
    [switch]$NoSign,
    [switch]$Clean
)

# Configuration (same as before)
$USE_CERT_STORE = $true
$CERT_SUBJECT = "BadDoggy-writes-code-sometimes"
$CERT_PFX = "C:\Secure\cert.pfx"
$CERT_PASSWORD = "YourPassword"
$SIGNTOOL = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
$TIMESTAMP_SERVER = "http://timestamp.digicert.com"
$APP_NAME = "VideoMusicMerger"
$OUTPUT_DIR = "dist"
$BUILD_DIR = "build"

# Helper functions (same as original script)
function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "`n=== $Message ===" -ForegroundColor $Color
}

function Write-Step {
    param([string]$Message)
    Write-Host "  -> $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "  + $Message" -ForegroundColor Green
}

function Get-FileSize {
    param([string]$Path)
    if (Test-Path $Path) {
        $size = (Get-Item $Path).Length
        if ($size -gt 1MB) {
            return "{0:N2} MB" -f ($size / 1MB)
        } else {
            return "{0:N2} KB" -f ($size / 1KB)
        }
    }
    return "N/A"
}

# Clean if requested
if ($Clean) {
    Write-Status "Cleaning" "Cyan"
    Remove-Item -Path $BUILD_DIR -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $OUTPUT_DIR -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$APP_NAME.spec" -Force -ErrorAction SilentlyContinue
}

# Create optimized spec file
Write-Status "Creating Optimized Spec File" "Cyan"

$specContent = "# -*- mode: python ; coding: utf-8 -*-`n"
$specContent += "# SIZE-OPTIMIZED spec file`n`n"
$specContent += "block_cipher = None`n`n"
$specContent += "a = Analysis(`n"
$specContent += "    ['main.py'],`n"
$specContent += "    pathex=[],`n"
$specContent += "    binaries=[],`n"
$specContent += "    datas=[],`n"
$specContent += "    hiddenimports=[`n"
$specContent += "        'PySide6.QtCore',`n"
$specContent += "        'PySide6.QtGui',`n"
$specContent += "        'PySide6.QtWidgets',`n"
$specContent += "        'PySide6.QtMultimedia',`n"
$specContent += "        'PySide6.QtMultimediaWidgets',`n"
$specContent += "        'moviepy.video.io.VideoFileClip',`n"
$specContent += "        'moviepy.audio.io.AudioFileClip',`n"
$specContent += "    ],`n"
$specContent += "    hookspath=[],`n"
$specContent += "    hooksconfig={},`n"
$specContent += "    runtime_hooks=[],`n"
$specContent += "    excludes=[`n"
$specContent += "        'matplotlib',`n"
$specContent += "        'tkinter',`n"
$specContent += "        'test',`n"
$specContent += "        'unittest',`n"
$specContent += "        'PIL',`n"
$specContent += "        'numpy.testing',`n"
$specContent += "        # Exclude unused PySide6 modules`n"
$specContent += "        'PySide6.Qt3DAnimation',`n"
$specContent += "        'PySide6.Qt3DCore',`n"
$specContent += "        'PySide6.Qt3DExtras',`n"
$specContent += "        'PySide6.Qt3DInput',`n"
$specContent += "        'PySide6.Qt3DLogic',`n"
$specContent += "        'PySide6.Qt3DRender',`n"
$specContent += "        'PySide6.QtBluetooth',`n"
$specContent += "        'PySide6.QtCharts',`n"
$specContent += "        'PySide6.QtDataVisualization',`n"
$specContent += "        'PySide6.QtDesigner',`n"
$specContent += "        'PySide6.QtHelp',`n"
$specContent += "        'PySide6.QtLocation',`n"
$specContent += "        'PySide6.QtNfc',`n"
$specContent += "        'PySide6.QtNetworkAuth',`n"
$specContent += "        'PySide6.QtPdf',`n"
$specContent += "        'PySide6.QtPositioning',`n"
$specContent += "        'PySide6.QtQuick',`n"
$specContent += "        'PySide6.QtQuickControls2',`n"
$specContent += "        'PySide6.QtQuickWidgets',`n"
$specContent += "        'PySide6.QtRemoteObjects',`n"
$specContent += "        'PySide6.QtScxml',`n"
$specContent += "        'PySide6.QtSensors',`n"
$specContent += "        'PySide6.QtSerialPort',`n"
$specContent += "        'PySide6.QtSql',`n"
$specContent += "        'PySide6.QtSvg',`n"
$specContent += "        'PySide6.QtSvgWidgets',`n"
$specContent += "        'PySide6.QtTest',`n"
$specContent += "        'PySide6.QtWebChannel',`n"
$specContent += "        'PySide6.QtWebEngineCore',`n"
$specContent += "        'PySide6.QtWebEngineWidgets',`n"
$specContent += "        'PySide6.QtWebSockets',`n"
$specContent += "        'PySide6.QtXml',`n"
$specContent += "        # Exclude MoviePy extras`n"
$specContent += "        'moviepy.editor',`n"
$specContent += "        'moviepy.video.tools',`n"
$specContent += "        # Optional: Exclude bundled FFmpeg (users install system FFmpeg)`n"
$specContent += "        # 'imageio_ffmpeg',`n"
$specContent += "    ],`n"
$specContent += "    win_no_prefer_redirects=False,`n"
$specContent += "    win_private_assemblies=False,`n"
$specContent += "    cipher=block_cipher,`n"
$specContent += "    noarchive=False,`n"
$specContent += ")`n`n"
$specContent += "pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)`n`n"
$specContent += "exe = EXE(`n"
$specContent += "    pyz,`n"
$specContent += "    a.scripts,`n"
$specContent += "    a.binaries,`n"
$specContent += "    a.zipfiles,`n"
$specContent += "    a.datas,`n"
$specContent += "    [],`n"
$specContent += "    name='$APP_NAME',`n"
$specContent += "    debug=False,`n"
$specContent += "    bootloader_ignore_signals=False,`n"
$specContent += "    strip=False,`n"
$specContent += "    upx=True,           # UPX compression enabled`n"
$specContent += "    upx_exclude=[],`n"
$specContent += "    runtime_tmpdir=None,`n"
$specContent += "    console=False,`n"
$specContent += "    disable_windowed_traceback=False,`n"
$specContent += "    argv_emulation=False,`n"
$specContent += "    target_arch=None,`n"
$specContent += "    codesign_identity=None,`n"
$specContent += "    entitlements_file=None,`n"
$specContent += "    icon=None,`n"
$specContent += ")`n"

$specContent | Out-File -FilePath "$APP_NAME.spec" -Encoding UTF8
Write-Success "Optimized spec file created"

# Build
Write-Status "Building (Optimized for Size)" "Cyan"
pyinstaller "$APP_NAME.spec" --clean --noconfirm

$exePath = Join-Path $OUTPUT_DIR "$APP_NAME.exe"
if (Test-Path $exePath) {
    $fileSize = Get-FileSize $exePath
    Write-Success "EXE created: $fileSize"
} else {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

# Sign if requested (same as original)
if ($Sign -and -not $NoSign) {
    Write-Status "Signing" "Cyan"
    $signArgs = @("sign", "/n", $CERT_SUBJECT, "/tr", $TIMESTAMP_SERVER, "/td", "SHA256", "/fd", "SHA256", "/v", $exePath)
    & $SIGNTOOL $signArgs
}

Write-Status "Build Complete - Optimized Size: $(Get-FileSize $exePath)" "Green"