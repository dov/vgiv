# Build a Unicode installer (ANSI targets are deprecated since NSIS 3.07).
Unicode true

#----- Include Modern UI -----#
!include "MUI2.nsh"
!include "FileFunc.nsh"

# VERSION and SHORTSHA1 are passed in by BuildInstaller.bat (/DVERSION=...).
!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef SHORTSHA1
  !define SHORTSHA1 "local"
!endif
# Directory holding the `cmake --install` output to package.
!ifndef STAGING
  !define STAGING "tmp"
!endif

Name "vgiv"
OutFile "InstallVgiv-v${VERSION}-${SHORTSHA1}.exe"
BrandingText "vgiv Installer"
Icon "giv-logo.ico"
UninstallIcon "giv-logo-install.ico"

SetCompress force
CRCCheck on
XPStyle on

# Machine-wide install: UAC asks for permission, files go under
# C:\Program Files\vgiv and registry entries under HKLM (64-bit view).
RequestExecutionLevel admin
InstallDir "$PROGRAMFILES64\vgiv"
InstallDirRegKey HKLM "Software\vgiv" ""

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\vgiv"

!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_UNFINISHPAGE_NOAUTOCLOSE

!define MUI_LICENSEPAGE_TEXT_TOP "vgiv is free software. Here is its license."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "COPYING.dos"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  SetRegView 64
  SetShellVarContext all
FunctionEnd

Function un.onInit
  SetRegView 64
  SetShellVarContext all
FunctionEnd

Section "Install"
  SetOutPath "$INSTDIR"
  # bin (vgiv.exe, DLLs, Qt plugins), lib/vgiv/plugins, share/vgiv/shaders, examples
  File /r "${STAGING}\*"
  File "..\README.md"
  File "..\COPYING"

  CreateDirectory "$SMPROGRAMS\vgiv"
  CreateShortCut "$SMPROGRAMS\vgiv\vgiv.lnk" "$INSTDIR\bin\vgiv.exe" "" "$INSTDIR\bin\vgiv.exe" 0
  CreateShortCut "$SMPROGRAMS\vgiv\Examples.lnk" "$INSTDIR\examples"
  CreateShortCut "$SMPROGRAMS\vgiv\Uninstall vgiv.lnk" "$INSTDIR\uninst.exe"

  WriteRegStr HKLM "Software\vgiv" "" "$INSTDIR"

  # Add/Remove Programs entry
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "vgiv"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninst.exe"'
  WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninst.exe" /S'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" "$0"

  # Associate .giv files with vgiv (all users). As giv's installer does,
  # drop a stale per-user choice first, or it would override our association.
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.giv"
  DeleteRegKey HKLM "Software\Classes\vgiv.GivFile"
  WriteRegStr HKLM "Software\Classes\.giv" "" "vgiv.GivFile"
  WriteRegStr HKLM "Software\Classes\vgiv.GivFile" "" "giv File"
  WriteRegStr HKLM "Software\Classes\vgiv.GivFile\DefaultIcon" "" "$INSTDIR\bin\vgiv.exe,1"
  WriteRegStr HKLM "Software\Classes\vgiv.GivFile\shell" "" "open"
  WriteRegStr HKLM "Software\Classes\vgiv.GivFile\shell\open\command" "" '"$INSTDIR\bin\vgiv.exe" "%1"'
  System::Call 'Shell32::SHChangeNotify(i 0x8000000, i 0, i 0, i 0)'

  # Pre-build the font atlas cache (~3 s per face) so the first scene opens fast
  DetailPrint "Building font cache..."
  ExecWait '"$INSTDIR\bin\vgiv.exe" --warm-fonts'

  WriteUninstaller "$INSTDIR\uninst.exe"
SectionEnd

Section "Uninstall"
  DeleteRegKey HKLM "Software\Classes\.giv"
  DeleteRegKey HKLM "Software\Classes\vgiv.GivFile"
  DeleteRegKey HKLM "${UNINST_KEY}"
  DeleteRegKey HKLM "Software\vgiv"
  System::Call 'Shell32::SHChangeNotify(i 0x8000000, i 0, i 0, i 0)'

  # Leave $INSTDIR first so the directory isn't locked by the uninstaller.
  SetOutPath "$TEMP"
  RMDir /r "$SMPROGRAMS\vgiv"
  RMDir /r "$INSTDIR"
SectionEnd
