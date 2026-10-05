#ifndef AppVersion
  #define AppVersion "1.3.8"
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
[Setup]
AppId={{C982C24D-F95E-4B12-BA2C-77D128E4E390}
AppName=Nekoloc
AppVersion={#AppVersion}
AppPublisher=Zerexa
DefaultDirName={localappdata}\Programs\Nekoloc
DefaultGroupName=Nekoloc
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Nekoloc-Windows-Setup
SetupIconFile={#OutputDir}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\nodeloc_app.exe
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{autoprograms}\Nekoloc"; Filename: "{app}\nodeloc_app.exe"
Name: "{autodesktop}\Nekoloc"; Filename: "{app}\nodeloc_app.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\nodeloc_app.exe"; Description: "Launch Nekoloc"; Flags: nowait postinstall skipifsilent
