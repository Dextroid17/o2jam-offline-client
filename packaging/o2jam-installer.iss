; ============================================================================
;  O2Jam Offline Client -- Inno Setup script
;
;  Wraps dist\O2Jam-Installer.exe in a classic Windows setup wizard.
;
;      iscc /DAppVersion=1.2 packaging\o2jam-installer.iss
;
;  Designed for people who want a normal setup.exe rather than a bare .exe.
;  PrivilegesRequired=lowest: installs into %LOCALAPPDATA%, never asks for
;  admin rights -- matching the project's rule that nothing needs sudo/admin.
; ============================================================================

#ifndef AppVersion
  #define AppVersion "1.2"
#endif
#ifndef SourceExe
  #define SourceExe "..\dist\O2Jam-Installer.exe"
#endif

#define AppName    "O2Jam Offline Client Installer"
#define AppShort   "O2Jam Installer"
#define AppPublisher "Dextroid17"
#define AppUrl     "https://github.com/Dextroid17/o2jam-offline-client"

[Setup]
AppId={{8F3C1A54-6B2E-4D71-9E0A-2C5B7A1D4E90}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={localappdata}\Programs\O2Jam Installer
DefaultGroupName=O2Jam
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=O2Jam-Installer-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#AppShort}
; An installer that installs an installer is small: no need for a big banner
DisableWelcomePage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &Desktop shortcut for the installer"; \
    GroupDescription: "Shortcuts:"; Flags: checkedonce

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppShort}"; Filename: "{app}\O2Jam-Installer.exe"
Name: "{group}\Uninstall {#AppShort}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppShort}"; Filename: "{app}\O2Jam-Installer.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\O2Jam-Installer.exe"; Description: "Start the O2Jam installer now"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
