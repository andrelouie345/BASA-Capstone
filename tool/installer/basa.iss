; tool/installer/basa.iss
; Windows installer for one BASA variant (Inno Setup 6), made by
; tool\build_release.ps1 from build\dist\windows-<variant>:
;
;   ISCC.exe /DVariant=admin /DAppVersion=1.0.0 tool\installer\basa.iss
;
; Per-user install (no administrator rights needed, as on school PCs). Each
; variant has its own AppId, folder and shortcut, so both install side by side.
; The app's data lives in Documents\BASA\<variant>\, which neither installing
; nor uninstalling touches. Not code-signed: SmartScreen asks once
; (More info -> Run anyway).
;
; The guide (a Zim notebook, tool\installer\guide\<variant>) goes to
; Documents\BASA\Guide\<Admin|Tutor>. A file is copied only when it is not
; there yet, so the ticks in a coordinator's checklists survive updates (new
; pages arrive, changed pages don't). Uninstalling leaves it.
; /DZimSetup=<path to Zim's Windows installer> adds an optional task that
; runs it (build_release.ps1 passes the newest tool\installer\vendor\zim*.exe).

#ifndef Variant
  #error Pass /DVariant=admin or /DVariant=tutor
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#if Variant == "admin"
  #define AppName "BASA"
  #define AppGuid "{{26EAB76F-4957-4166-A828-1CFB518C8CD6}"
  #define SetupName "BASA-Admin-Setup"
  #define GuideName "Admin"
#elif Variant == "tutor"
  #define AppName "BASA Tutor"
  #define AppGuid "{{B99299AD-7C4D-4F32-A47C-01C7A94C50CA}"
  #define SetupName "BASA-Tutor-Setup"
  #define GuideName "Tutor"
#else
  #error Variant must be admin or tutor
#endif

; Paths are relative to this script (tool\installer).
#define SourceDir "..\..\build\dist\windows-" + Variant
#define GuideDir "{userdocs}\BASA\Guide\" + GuideName

[Setup]
AppId={#AppGuid}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=BASA (ARAL-Read)
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\dist
OutputBaseFilename={#SetupName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\basa_capstone.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
#ifdef ZimSetup
Name: "zim"; Description: "Install Zim Desktop Wiki (opens the BASA guide; skip if Zim is already installed)"; GroupDescription: "BASA guide:"
#endif

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "guide\{#Variant}\*"; DestDir: "{#GuideDir}"; Flags: onlyifdoesntexist uninsneveruninstall recursesubdirs createallsubdirs
#ifdef ZimSetup
Source: "{#ZimSetup}"; DestDir: "{tmp}"; DestName: "zim-setup.exe"; Flags: deleteafterinstall; Tasks: zim
#endif

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\basa_capstone.exe"
Name: "{group}\{#AppName} Guide"; Filename: "{#GuideDir}"; Comment: "The BASA guide (open it with Zim: see Read me first.txt)"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\basa_capstone.exe"; Tasks: desktopicon

[Run]
#ifdef ZimSetup
; Zim's own installer (it may ask for an administrator on school PCs).
Filename: "{tmp}\zim-setup.exe"; StatusMsg: "Installing Zim Desktop Wiki..."; Flags: waituntilterminated; Tasks: zim
#endif
Filename: "{app}\basa_capstone.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
