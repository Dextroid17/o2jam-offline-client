; Inno Setup script for the Windows build.
; Godot doesn't make installers natively — a ZIP is honestly fine for a
; rhythm game (portable, no registry), but if you want a proper installer:
;
;   1. Export the "Windows Desktop" preset into builds\windows\
;   2. Install Inno Setup 6
;   3. iscc packaging\windows\o2jam-installer.iss
;
; Output: builds\O2Jam-Setup.exe

#define AppName "O2Jam Offline Client"
#define AppVersion "1.0"
#define BuildDir "..\..\builds\windows"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\O2Jam
DefaultGroupName=O2Jam
OutputDir=..\..\builds
OutputBaseFilename=O2Jam-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Files]
Source: "{#BuildDir}\o2jam.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.pck"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#BuildDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\O2Jam"; Filename: "{app}\o2jam.exe"
Name: "{autodesktop}\O2Jam"; Filename: "{app}\o2jam.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\o2jam.exe"; Description: "Launch O2Jam"; Flags: postinstall nowait skipifsilent
