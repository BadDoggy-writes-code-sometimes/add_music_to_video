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
    Write-Host "  → $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
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
    Write-Error "Python not found in PATH"
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
        Write-Error "Failed to install PyInstaller"
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
        Write-Error "Missing dependency: $dep"
        Write-Host "  Install with: pip install $dep" -ForegroundColor Yellow
        exit 1
    }
}
Write-Success "All dependencies installed"

# Check SignTool if signing is requested
if ($Sign -or (-not $NoSign)) {
    if (-not (Test-Path $SIGNTOOL)) {
        Write-Error "SignTool not found at: $SIGNTOOL"
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

$specContent = @"
# -*- mode: python ; coding: utf-8 -*-
# Auto-generated spec file for $APP_NAME

block_cipher = None

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[
        'PySide6.QtCore',
        'PySide6.QtGui',
        'PySide6.QtWidgets',
        'PySide6.QtMultimedia',
        'PySide6.QtMultimediaWidgets',
        'moviepy',
        'moviepy.video.io.VideoFileClip',
        'moviepy.audio.io.AudioFileClip',
        'moviepy.audio.AudioClip',
        'moviepy.Clip',
        'imageio_ffmpeg',
        'proglog',
        'tqdm',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'matplotlib',
        'tkinter',
        'test',
        'unittest',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='$APP_NAME',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,  # Set to True for debugging
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    $iconParam
    version='version_info.txt',  # Will be created if exists
)
"@

$specContent | Out-File -FilePath "$APP_NAME.spec" -Encoding UTF8
Write-Success "Spec file created: $APP_NAME.spec"

# ============================================================================
# CREATE VERSION INFO (OPTIONAL)
# ============================================================================

Write-Status "Creating Version Info" "Cyan"

$versionInfo = @"
VSVersionInfo(
  ffi=FixedFileInfo(
    filevers=($($APP_VERSION.Replace('.', ', ')), 0),
    prodvers=($($APP_VERSION.Replace('.', ', ')), 0),
    mask=0x3f,
    flags=0x0,
    OS=0x40004,
    fileType=0x1,
    subtype=0x0,
    date=(0, 0)
  ),
  kids=[
    StringFileInfo(
      [
      StringTable(
        u'040904B0',
        [StringStruct(u'CompanyName', u'BadDoggy-writes-code-sometimes'),
        StringStruct(u'FileDescription', u'Video Music Merger'),
        StringStruct(u'FileVersion', u'$APP_VERSION'),
        StringStruct(u'InternalName', u'$APP_NAME'),
        StringStruct(u'LegalCopyright', u'Copyright © 2025'),
        StringStruct(u'OriginalFilename', u'$APP_NAME.exe'),
        StringStruct(u'ProductName', u'Video Music Merger'),
        StringStruct(u'ProductVersion', u'$APP_VERSION')])
      ]
    ),
    VarFileInfo([VarStruct(u'Translation', [1033, 1200])])
  ]
)
"@

$versionInfo | Out-File -FilePath "version_info.txt" -Encoding UTF8
Write-Success "Version info created"

# ============================================================================
# BUILD WITH PYINSTALLER
# ============================================================================

Write-Status "Building with PyInstaller" "Cyan"
Write-Step "This may take 2-5 minutes..."

$buildStart = Get-Date

# Run PyInstaller
pyinstaller "$APP_NAME.spec" --clean --noconfirm

if ($LASTEXITCODE -ne 0) {
    Write-Error "PyInstaller build failed"
    exit 1
}

$buildTime = (Get-Date) - $buildStart
Write-Success "Build completed in $($buildTime.TotalSeconds.ToString('F1')) seconds"

# Check output file
$exePath = Join-Path $OUTPUT_DIR "$APP_NAME.exe"
if (-not (Test-Path $exePath)) {
    Write-Error "Output file not found: $exePath"
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
            Write-Error "Certificate not found in store: $CERT_SUBJECT"
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
            Write-Error "PFX file not found: $CERT_PFX"
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
            Write-Error "Signature verification failed"
        }
    } else {
        Write-Error "Signing failed"
        Write-Host "  Check certificate configuration in script" -ForegroundColor Yellow
        Write-Host "  Run with -NoSign to skip signing" -ForegroundColor Yellow
    }
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================

Write-Status "Build Summary" "Green"

Write-Host ""
Write-Host "  📦 Application: $APP_NAME v$APP_VERSION" -ForegroundColor White
Write-Host "  📁 Location:    $exePath" -ForegroundColor White
Write-Host "  💾 Size:        $fileSize" -ForegroundColor White

if (-not $NoSign) {
    $sig = Get-AuthenticodeSignature $exePath
    if ($sig.Status -eq 'Valid') {
        Write-Host "  ✓ Signed:       Yes ($($sig.SignerCertificate.Subject))" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Signed:       No or Invalid" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ○ Signed:       Skipped" -ForegroundColor Gray
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
Write-Host "  • Test run:    .\$exePath" -ForegroundColor Gray
Write-Host "  • Clean build: .\build.ps1 -Clean" -ForegroundColor Gray
Write-Host "  • No signing:  .\build.ps1 -NoSign" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# SUCCESS
# ============================================================================

Write-Status "Build Complete!" "Green"
exit 0
