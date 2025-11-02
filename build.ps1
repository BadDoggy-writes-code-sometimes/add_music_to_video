# ============================================================================
# Video Music Merger - Automated Build Script
# ============================================================================
# This script handles the complete build process from Python to signed EXE
#
# Usage:
#   .\build.ps1                    # Build with self-signed cert
#   .\build.ps1 -Sign              # Build and sign with trusted cert
#   .\build.ps1 -Sign -Clean       # Clean build with signing
#   .\build.ps1 -NoSign            # Build without any signing
# ============================================================================

param(
    [switch]$Sign,      # Sign with certificate
    [switch]$NoSign,    # Skip signing entirely
    [switch]$Clean,     # Clean build directories first
    [switch]$Test       # Run the EXE after building
)

# ============================================================================
# CONFIGURATION - EDIT THESE VALUES
# ============================================================================

# Certificate Configuration (choose one method)
$USE_CERT_STORE = $true          # Use certificate from Windows store (recommended)
$CERT_SUBJECT = "BadDoggy-writes-code-sometimes"  # Certificate subject name

# OR use PFX file (set USE_CERT_STORE = $false)
$CERT_PFX = "C:\Secure\cert.pfx"
$CERT_PASSWORD = "YourPassword"

# SignTool Configuration
$SIGNTOOL = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
$TIMESTAMP_SERVER = "http://timestamp.digicert.com"

# Build Configuration
$APP_NAME = "VideoMusicMerger"
$APP_VERSION = "1.0.0"
$ICON_FILE = "icon.ico"  # Set to $null if no icon

# Output Configuration
$OUTPUT_DIR = "dist"
$BUILD_DIR = "build"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

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

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "  x $Message" -ForegroundColor Red
}

function Test-Command {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
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

# ============================================================================
# VALIDATION
# ============================================================================

Write-Status "Validating Build Environment" "Cyan"

# Check Python
if (-not (Test-Command "python")) {
    Write-ErrorMsg "Python not found in PATH"
    exit 1
}
Write-Success "Python found: $(python --version)"

# Check PyInstaller
Write-Step "Checking PyInstaller..."
$pyinstallerCheck = python -c "import PyInstaller; print(PyInstaller.__version__)" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Step "Installing PyInstaller..."
    pip install pyinstaller
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Failed to install PyInstaller"
        exit 1
    }
}
Write-Success "PyInstaller ready"

# Check dependencies
Write-Step "Checking dependencies..."
$deps = @("PySide6", "moviepy", "imageio_ffmpeg")
foreach ($dep in $deps) {
    $check = python -c "import $dep" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Missing dependency: $dep"
        Write-Host "  Install with: pip install $dep" -ForegroundColor Yellow
        exit 1
    }
}
Write-Success "All dependencies installed"

# Check SignTool if signing is requested
if ($Sign -or (-not $NoSign)) {
    if (-not (Test-Path $SIGNTOOL)) {
        Write-ErrorMsg "SignTool not found at: $SIGNTOOL"
        Write-Host "  Install Windows SDK or update path in script" -ForegroundColor Yellow

        # Try to find SignTool automatically
        Write-Step "Searching for SignTool..."
        $found = Get-ChildItem "C:\Program Files (x86)\Windows Kits" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-Host "  Found at: $($found.FullName)" -ForegroundColor Yellow
            Write-Host "  Update `$SIGNTOOL in script with this path" -ForegroundColor Yellow
        }

        $NoSign = $true
        Write-Host "  Continuing without signing..." -ForegroundColor Yellow
    } else {
        Write-Success "SignTool found"
    }
}

# ============================================================================
# CLEAN BUILD (OPTIONAL)
# ============================================================================

if ($Clean) {
    Write-Status "Cleaning Build Directories" "Cyan"

    if (Test-Path $BUILD_DIR) {
        Write-Step "Removing $BUILD_DIR..."
        Remove-Item -Path $BUILD_DIR -Recurse -Force
        Write-Success "Build directory cleaned"
    }

    if (Test-Path $OUTPUT_DIR) {
        Write-Step "Removing $OUTPUT_DIR..."
        Remove-Item -Path $OUTPUT_DIR -Recurse -Force
        Write-Success "Output directory cleaned"
    }

    # Remove spec file to force regeneration
    if (Test-Path "$APP_NAME.spec") {
        Remove-Item "$APP_NAME.spec" -Force
    }
}

# ============================================================================
# CREATE/UPDATE SPEC FILE
# ============================================================================

Write-Status "Creating PyInstaller Spec File" "Cyan"

$iconParam = if ($ICON_FILE -and (Test-Path $ICON_FILE)) { "icon='$ICON_FILE'," } else { "icon=None," }

# Create spec file content
$specContent = "# -*- mode: python ; coding: utf-8 -*-`n"
$specContent += "# Auto-generated spec file for $APP_NAME`n`n"
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
$specContent += "        'moviepy',`n"
$specContent += "        'moviepy.video.io.VideoFileClip',`n"
$specContent += "        'moviepy.audio.io.AudioFileClip',`n"
$specContent += "        'moviepy.audio.AudioClip',`n"
$specContent += "        'moviepy.Clip',`n"
$specContent += "        'imageio_ffmpeg',`n"
$specContent += "        'proglog',`n"
$specContent += "        'tqdm',`n"
$specContent += "    ],`n"
$specContent += "    hookspath=[],`n"
$specContent += "    hooksconfig={},`n"
$specContent += "    runtime_hooks=[],`n"
$specContent += "    excludes=[`n"
$specContent += "        'matplotlib',`n"
$specContent += "        'tkinter',`n"
$specContent += "        'test',`n"
$specContent += "        'unittest',`n"
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
$specContent += "    upx=True,`n"
$specContent += "    upx_exclude=[],`n"
$specContent += "    runtime_tmpdir=None,`n"
$specContent += "    console=False,`n"
$specContent += "    disable_windowed_traceback=False,`n"
$specContent += "    argv_emulation=False,`n"
$specContent += "    target_arch=None,`n"
$specContent += "    codesign_identity=None,`n"
$specContent += "    entitlements_file=None,`n"
$specContent += "    $iconParam`n"
$specContent += ")`n"

$specContent | Out-File -FilePath "$APP_NAME.spec" -Encoding UTF8
Write-Success "Spec file created: $APP_NAME.spec"

# ============================================================================
# BUILD WITH PYINSTALLER
# ============================================================================

Write-Status "Building with PyInstaller" "Cyan"
Write-Step "This may take 2-5 minutes..."

$buildStart = Get-Date

# Run PyInstaller
pyinstaller "$APP_NAME.spec" --clean --noconfirm

if ($LASTEXITCODE -ne 0) {
    Write-ErrorMsg "PyInstaller build failed"
    exit 1
}

$buildTime = (Get-Date) - $buildStart
Write-Success "Build completed in $($buildTime.TotalSeconds.ToString('F1')) seconds"

# Check output file
$exePath = Join-Path $OUTPUT_DIR "$APP_NAME.exe"
if (-not (Test-Path $exePath)) {
    Write-ErrorMsg "Output file not found: $exePath"
    exit 1
}

$fileSize = Get-FileSize $exePath
Write-Success "EXE created: $exePath ($fileSize)"

# ============================================================================
# CODE SIGNING
# ============================================================================

if (-not $NoSign) {
    Write-Status "Code Signing" "Cyan"

    # Build signtool command
    $signArgs = @("sign")

    if ($USE_CERT_STORE) {
        Write-Step "Using certificate from store: $CERT_SUBJECT"
        $signArgs += @("/n", $CERT_SUBJECT)

        # Verify certificate exists
        $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object {$_.Subject -like "*$CERT_SUBJECT*"} | Select-Object -First 1
        if (-not $cert) {
            Write-ErrorMsg "Certificate not found in store: $CERT_SUBJECT"
            Write-Host "  Available certificates:" -ForegroundColor Yellow
            Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | ForEach-Object {
                Write-Host "    - $($_.Subject)" -ForegroundColor Gray
            }
            exit 1
        }
        Write-Step "Certificate found: $($cert.Thumbprint)"
    } else {
        Write-Step "Using PFX file: $CERT_PFX"
        if (-not (Test-Path $CERT_PFX)) {
            Write-ErrorMsg "PFX file not found: $CERT_PFX"
            exit 1
        }
        $signArgs += @("/f", $CERT_PFX, "/p", $CERT_PASSWORD)
    }

    # Add timestamp and hash algorithm
    $signArgs += @(
        "/tr", $TIMESTAMP_SERVER,
        "/td", "SHA256",
        "/fd", "SHA256",
        "/v"
    )

    # Add the file to sign
    $signArgs += $exePath

    # Execute signing
    Write-Step "Signing executable..."
    & $SIGNTOOL $signArgs

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Signing successful"

        # Verify signature
        Write-Step "Verifying signature..."
        & $SIGNTOOL verify /pa /v $exePath | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Signature verification passed"

            # Display signature info
            $sig = Get-AuthenticodeSignature $exePath
            Write-Host "    Signer: $($sig.SignerCertificate.Subject)" -ForegroundColor Gray
            Write-Host "    Valid until: $($sig.SignerCertificate.NotAfter)" -ForegroundColor Gray
        } else {
            Write-ErrorMsg "Signature verification failed"
        }
    } else {
        Write-ErrorMsg "Signing failed"
        Write-Host "  Check certificate configuration in script" -ForegroundColor Yellow
        Write-Host "  Run with -NoSign to skip signing" -ForegroundColor Yellow
    }
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================

Write-Status "Build Summary" "Green"

Write-Host ""
Write-Host "  Application: $APP_NAME v$APP_VERSION" -ForegroundColor White
Write-Host "  Location:    $exePath" -ForegroundColor White
Write-Host "  Size:        $fileSize" -ForegroundColor White

if (-not $NoSign) {
    $sig = Get-AuthenticodeSignature $exePath
    if ($sig.Status -eq 'Valid') {
        Write-Host "  Signed:      Yes ($($sig.SignerCertificate.Subject))" -ForegroundColor Green
    } else {
        Write-Host "  Signed:      No or Invalid" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Signed:      Skipped" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# TEST RUN (OPTIONAL)
# ============================================================================

if ($Test) {
    Write-Status "Running Application" "Cyan"
    Write-Step "Launching $APP_NAME..."
    Start-Process $exePath
    Write-Success "Application launched"
}

# ============================================================================
# ADDITIONAL OPTIONS
# ============================================================================

Write-Host "Additional options:" -ForegroundColor Cyan
Write-Host "  Test run:    .\$exePath" -ForegroundColor Gray
Write-Host "  Clean build: .\build.ps1 -Clean" -ForegroundColor Gray
Write-Host "  No signing:  .\build.ps1 -NoSign" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# SUCCESS
# ============================================================================

Write-Status "Build Complete!" "Green"
exit 0