; Agent Pack Installer — Inno Setup Script
; Requires Inno Setup 6.x

#define MyAppName "Agent Pack"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Agent Pack"
#define MyAppURL "https://github.com/SenseTime-FVG/agent_pack"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\AgentPack
DefaultGroupName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=AgentPack-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; Requires Inno Setup 6.1+ with Chinese language pack installed.
; If ChineseSimplified.isl is missing, install it from:
;   https://raw.githubusercontent.com/jrsoftware/issrc/main/Files/Languages/Unofficial/ChineseSimplified.isl
; and place it in the Inno Setup "Languages" folder.
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
; Bundle scripts and shared files
Source: "scripts\*"; DestDir: "{app}\scripts"; Flags: recursesubdirs
Source: "..\shared\*"; DestDir: "{app}\shared"; Flags: recursesubdirs
Source: "..\config\*"; DestDir: "{app}\config"; Flags: recursesubdirs
; linux/lib is sourced from Windows PS scripts via WSL bash; ship it too so the
; WSL side can find install-hermes.sh / install-openclaw.sh without re-cloning.
Source: "..\linux\lib\*"; DestDir: "{app}\linux\lib"; Flags: recursesubdirs
; repos/ is NO LONGER bundled — installers clone agent_pack from GitHub at
; install time (with CN mirror fallback) so users always get the latest
; vendored sources without paying a huge installer download.

[Icons]
; Created conditionally in code section based on product selection
Name: "{group}\Uninstall Agent Pack"; Filename: "{uninstallexe}"

[UninstallDelete]
Type: dirifempty; Name: "{app}"

[Code]
var
  ProductPage: TWizardPage;
  HermesCheckbox: TNewCheckBox;
  OpenClawCheckbox: TNewCheckBox;
  ProviderPage: TWizardPage;
  ProviderRadios: array of TNewRadioButton;
  ApiKeyEdit: TNewEdit;
  BaseUrlLabel: TLabel;
  BaseUrlEdit: TNewEdit;
  ModelLabel: TLabel;
  ModelEdit: TNewEdit;
  CustomPanel: TPanel;
  VerifyButton: TNewButton;
  VerifyLabel: TLabel;
  ProviderModels: array[0..3] of String;
  ProviderBaseUrls: array[0..3] of String;
  ActiveProviderIndex: Integer;

function MaxValueInt(const A, B: Integer): Integer;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

function GetSelectedProviderIndex: Integer;
begin
  if ProviderRadios[0].Checked then
    Result := 0
  else if ProviderRadios[1].Checked then
    Result := 1
  else if ProviderRadios[2].Checked then
    Result := 2
  else
    Result := 3;
end;

function GetProviderName(const ProviderIndex: Integer): String;
begin
  case ProviderIndex of
    0: Result := 'openrouter';
    1: Result := 'openai';
    2: Result := 'anthropic';
  else
    Result := 'custom';
  end;
end;

function GetDefaultBaseUrl(const ProviderIndex: Integer): String;
begin
  case ProviderIndex of
    0: Result := 'https://openrouter.ai/api/v1';
    1: Result := 'https://api.openai.com/v1';
    2: Result := 'https://api.anthropic.com';
  else
    Result := '';
  end;
end;

function GetDefaultModel(const ProviderIndex: Integer): String;
begin
  case ProviderIndex of
    0: Result := 'nousresearch/hermes-3-llama-3.1-8b';
    1: Result := 'gpt-4o-mini';
    2: Result := 'claude-sonnet-4-20250514';
  else
    Result := '';
  end;
end;

procedure SaveProviderFieldValues;
begin
  if (ActiveProviderIndex < 0) or (ActiveProviderIndex > 3) then begin
    Exit;
  end;

  if ModelEdit <> nil then begin
    ProviderModels[ActiveProviderIndex] := Trim(ModelEdit.Text);
  end;

  if BaseUrlEdit <> nil then begin
    ProviderBaseUrls[ActiveProviderIndex] := Trim(BaseUrlEdit.Text);
  end;
end;

procedure UpdateProviderFieldLayout;
var
  SelectedIndex: Integer;
  LabelGap, RowGap: Integer;
begin
  if (CustomPanel = nil) or (BaseUrlLabel = nil) or (BaseUrlEdit = nil) or
     (ModelLabel = nil) or (ModelEdit = nil) then begin
    Exit;
  end;

  SaveProviderFieldValues;
  SelectedIndex := GetSelectedProviderIndex;
  ActiveProviderIndex := SelectedIndex;

  if ProviderModels[SelectedIndex] = '' then begin
    ProviderModels[SelectedIndex] := GetDefaultModel(SelectedIndex);
  end;
  if ProviderBaseUrls[SelectedIndex] = '' then begin
    ProviderBaseUrls[SelectedIndex] := GetDefaultBaseUrl(SelectedIndex);
  end;

  LabelGap := ScaleY(6);
  RowGap := ScaleY(4);

  CustomPanel.Visible := True;
  BaseUrlLabel.Visible := (SelectedIndex = 3);
  BaseUrlEdit.Visible := (SelectedIndex = 3);

  if BaseUrlLabel.Visible then begin
    BaseUrlLabel.Top := 0;
    BaseUrlEdit.Top := BaseUrlLabel.Top + BaseUrlLabel.Height + LabelGap;
    ModelLabel.Top := BaseUrlEdit.Top + BaseUrlEdit.Height + RowGap;
    BaseUrlEdit.Text := ProviderBaseUrls[SelectedIndex];
  end else begin
    ModelLabel.Top := 0;
    BaseUrlEdit.Text := GetDefaultBaseUrl(SelectedIndex);
  end;

  ModelEdit.Text := ProviderModels[SelectedIndex];
  ModelEdit.Top := ModelLabel.Top + ModelLabel.Height + LabelGap;
  CustomPanel.Height := ModelEdit.Top + ModelEdit.Height;
end;

// ---- Product Selection Page ----
procedure CreateProductPage;
var
  lbl: TLabel;
  note: TLabel;
  yPos: Integer;
  LabelGap, RowGap, SectionGap: Integer;
  SideIndent, CheckHeight: Integer;
begin
  ProductPage := CreateCustomPage(wpSelectDir,
    'Select Products', 'Choose which AI agents to install.');

  LabelGap := ScaleY(6);
  RowGap := ScaleY(6);
  SectionGap := ScaleY(10);
  SideIndent := ScaleX(20);
  CheckHeight := ScaleY(20);

  lbl := TLabel.Create(WizardForm);
  lbl.Parent := ProductPage.Surface;
  lbl.Caption := 'Select one or more products to install:';
  lbl.Top := ScaleY(8);
  lbl.Left := 0;
  lbl.Width := ProductPage.SurfaceWidth;
  yPos := lbl.Top + lbl.Height + SectionGap;

  HermesCheckbox := TNewCheckBox.Create(WizardForm);
  HermesCheckbox.Parent := ProductPage.Surface;
  HermesCheckbox.Caption := 'Hermes Agent — Self-improving AI agent by Nous Research';
  HermesCheckbox.Top := yPos;
  HermesCheckbox.Left := SideIndent;
  HermesCheckbox.Width := ProductPage.SurfaceWidth - (SideIndent * 2);
  HermesCheckbox.Height := MaxValueInt(HermesCheckbox.Height, CheckHeight);
  HermesCheckbox.Checked := True;
  yPos := HermesCheckbox.Top + HermesCheckbox.Height + RowGap;

  OpenClawCheckbox := TNewCheckBox.Create(WizardForm);
  OpenClawCheckbox.Parent := ProductPage.Surface;
  OpenClawCheckbox.Caption := 'OpenClaw — Multi-channel AI gateway';
  OpenClawCheckbox.Top := yPos;
  OpenClawCheckbox.Left := SideIndent;
  OpenClawCheckbox.Width := ProductPage.SurfaceWidth - (SideIndent * 2);
  OpenClawCheckbox.Height := MaxValueInt(OpenClawCheckbox.Height, CheckHeight);
  OpenClawCheckbox.Checked := False;
  yPos := OpenClawCheckbox.Top + OpenClawCheckbox.Height + SectionGap;

  note := TLabel.Create(WizardForm);
  note.Parent := ProductPage.Surface;
  note.Caption := 'Windows installs run inside WSL2. If no WSL2 distro is available, setup will stop and ask you to install one first.';
  note.Top := yPos;
  note.Left := SideIndent;
  note.Width := ProductPage.SurfaceWidth - (SideIndent * 2);
  note.WordWrap := True;
end;

// ---- Provider Selection Page ----
procedure OnProviderChange(Sender: TObject);
begin
  UpdateProviderFieldLayout;
end;

procedure OnVerifyClick(Sender: TObject);
var
  ResultCode: Integer;
  Provider, Cmd: String;
begin
  Provider := GetProviderName(GetSelectedProviderIndex);

  Cmd := 'python "' + ExpandConstant('{app}') + '\shared\verify-llm.py"'
    + ' --provider ' + Provider
    + ' --api-key "' + ApiKeyEdit.Text + '"';

  if Trim(ModelEdit.Text) <> '' then begin
    Cmd := Cmd + ' --model "' + ModelEdit.Text + '"';
  end;

  if Provider = 'custom' then begin
    Cmd := Cmd + ' --base-url "' + BaseUrlEdit.Text + '"';
  end;

  VerifyLabel.Caption := 'Verifying...';
  VerifyLabel.Font.Color := clBlue;

  if Exec('cmd.exe', '/c ' + Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then begin
    if ResultCode = 0 then begin
      VerifyLabel.Caption := 'Connection verified!';
      VerifyLabel.Font.Color := clGreen;
    end else begin
      VerifyLabel.Caption := 'Verification failed. You can configure later.';
      VerifyLabel.Font.Color := clRed;
    end;
  end else begin
    VerifyLabel.Caption := 'Could not run verification.';
    VerifyLabel.Font.Color := clRed;
  end;
end;

procedure CreateProviderPage;
var
  lbl: TLabel;
  providerNames: array of String;
  i, yPos: Integer;
  LabelGap, RowGap, SectionGap: Integer;
  RadioIndent, ButtonGap, ButtonWidth, RadioHeight: Integer;
begin
  ProviderPage := CreateCustomPage(ProductPage.ID,
    'LLM Provider', 'Configure your AI model provider.');

  LabelGap := ScaleY(6);
  RowGap := ScaleY(4);
  SectionGap := ScaleY(10);
  RadioIndent := ScaleX(20);
  ButtonGap := ScaleX(10);
  ButtonWidth := ScaleX(100);
  RadioHeight := ScaleY(18);

  lbl := TLabel.Create(WizardForm);
  lbl.Parent := ProviderPage.Surface;
  lbl.Caption := 'Select your LLM provider:';
  lbl.Top := ScaleY(5);
  lbl.Left := 0;
  yPos := lbl.Top + lbl.Height + LabelGap;

  SetArrayLength(providerNames, 4);
  providerNames[0] := 'OpenRouter (recommended - 200+ models, free tier)';
  providerNames[1] := 'OpenAI';
  providerNames[2] := 'Anthropic';
  providerNames[3] := 'Custom endpoint';

  SetArrayLength(ProviderRadios, 4);
  for i := 0 to 3 do begin
    ProviderRadios[i] := TNewRadioButton.Create(WizardForm);
    ProviderRadios[i].Parent := ProviderPage.Surface;
    ProviderRadios[i].Caption := providerNames[i];
    ProviderRadios[i].Top := yPos;
    ProviderRadios[i].Left := RadioIndent;
    ProviderRadios[i].Width := ProviderPage.SurfaceWidth - (RadioIndent * 2);
    ProviderRadios[i].Height := MaxValueInt(ProviderRadios[i].Height, RadioHeight);
    ProviderRadios[i].OnClick := @OnProviderChange;
    yPos := ProviderRadios[i].Top + ProviderRadios[i].Height + RowGap;
  end;
  yPos := yPos + SectionGap;

  // API Key
  lbl := TLabel.Create(WizardForm);
  lbl.Parent := ProviderPage.Surface;
  lbl.Caption := 'API Key:';
  lbl.Top := yPos;
  lbl.Left := 0;
  yPos := lbl.Top + lbl.Height + LabelGap;

  ApiKeyEdit := TNewEdit.Create(WizardForm);
  ApiKeyEdit.Parent := ProviderPage.Surface;
  ApiKeyEdit.Top := yPos;
  ApiKeyEdit.Left := 0;
  ApiKeyEdit.PasswordChar := '*';

  // Verify button
  VerifyButton := TNewButton.Create(WizardForm);
  VerifyButton.Parent := ProviderPage.Surface;
  VerifyButton.Caption := 'Verify';
  VerifyButton.Width := ButtonWidth;
  VerifyButton.Left := ProviderPage.SurfaceWidth - VerifyButton.Width;
  VerifyButton.OnClick := @OnVerifyClick;

  ApiKeyEdit.Width := VerifyButton.Left - ButtonGap;
  VerifyButton.Top := ApiKeyEdit.Top + ((ApiKeyEdit.Height - VerifyButton.Height) div 2);

  VerifyLabel := TLabel.Create(WizardForm);
  VerifyLabel.Parent := ProviderPage.Surface;
  VerifyLabel.AutoSize := False;
  VerifyLabel.Left := 0;
  VerifyLabel.Width := ProviderPage.SurfaceWidth;
  VerifyLabel.Height := ScaleY(14);
  VerifyLabel.Top := ApiKeyEdit.Top + ApiKeyEdit.Height + LabelGap;
  VerifyLabel.Caption := '';
  yPos := VerifyLabel.Top + VerifyLabel.Height + RowGap;

  // Custom endpoint fields (hidden by default)
  CustomPanel := TPanel.Create(WizardForm);
  CustomPanel.Parent := ProviderPage.Surface;
  CustomPanel.Top := yPos;
  CustomPanel.Left := 0;
  CustomPanel.Width := ProviderPage.SurfaceWidth;
  CustomPanel.BevelOuter := bvNone;
  CustomPanel.Visible := True;

  BaseUrlLabel := TLabel.Create(WizardForm);
  BaseUrlLabel.Parent := CustomPanel;
  BaseUrlLabel.Caption := 'Base URL:';
  BaseUrlLabel.Top := 0;
  BaseUrlLabel.Left := 0;

  BaseUrlEdit := TNewEdit.Create(WizardForm);
  BaseUrlEdit.Parent := CustomPanel;
  BaseUrlEdit.Top := BaseUrlLabel.Top + BaseUrlLabel.Height + LabelGap;
  BaseUrlEdit.Left := 0;
  BaseUrlEdit.Width := ProviderPage.SurfaceWidth;

  ModelLabel := TLabel.Create(WizardForm);
  ModelLabel.Parent := CustomPanel;
  ModelLabel.Caption := 'Model name:';
  ModelLabel.Left := 0;

  ModelEdit := TNewEdit.Create(WizardForm);
  ModelEdit.Parent := CustomPanel;
  ModelEdit.Top := BaseUrlEdit.Top + BaseUrlEdit.Height + RowGap;
  ModelEdit.Left := 0;
  ModelEdit.Width := ProviderPage.SurfaceWidth;

  ActiveProviderIndex := -1;
  ProviderRadios[0].Checked := True;
  UpdateProviderFieldLayout;
end;

// ---- Validation ----
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = ProductPage.ID then begin
    if (not HermesCheckbox.Checked) and (not OpenClawCheckbox.Checked) then begin
      MsgBox('Please select at least one product.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

// ---- Post-Install: Run Scripts ----

function GetAgentPackLogPath(const Name: String): String;
begin
  Result := ExpandConstant('{localappdata}') + '\AgentPack\logs\' + Name + '.log';
end;

// Run a command, returning True on success.  If it fails, show a dialog
// offering Retry / Skip / Abort.  Retry reruns the same command.  Skip
// continues the overall flow (returns False so the caller can decide).
// Abort terminates the installation.
function ExecWithRetry(const FileName, Params, FailMessage: String; const ShowCmd: Integer): Boolean;
var
  ResultCode, Response: Integer;
  Prompt: String;
begin
  Result := False;
  while True do begin
    if Exec(FileName, Params, '', ShowCmd, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then begin
      Result := True;
      Exit;
    end;

    Prompt := FailMessage + #13#10#13#10
      + 'Exit code: ' + IntToStr(ResultCode) + #13#10#13#10
      + 'Click Retry to try again, Cancel to abort installation.';
    Response := MsgBox(Prompt, mbError, MB_RETRYCANCEL);
    if Response = IDCANCEL then begin
      Abort;
    end;
    // IDRETRY: loop and try again
  end;
end;

// Launch a PowerShell install script in a VISIBLE console window.
// We invoke powershell.exe directly (no cmd /k wrapper) to avoid the nested
// quoting pitfall where """<path>""" gets re-expanded into a literally-quoted
// path like '"D:\tmp\...\foo.ps1"' that PowerShell then rejects as
// "Illegal characters in path".
// The PS scripts themselves dump their log and call Wait-ForKeyIfConsole
// on failure, so the window stays open long enough to read the transcript.
function ExecVisiblePwshWithRetry(const ScriptPath, FailMessage, LogPath: String): Boolean;
var
  Params, FullMsg: String;
  ResultCode, Response: Integer;
begin
  Result := False;
  Params :=
    '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"';

  while True do begin
    // SW_SHOW: open a new console so the user can watch progress and read
    // the log dump that the PS trap emits on failure.
    if Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then begin
      Result := True;
      Exit;
    end;

    FullMsg := FailMessage + #13#10#13#10
      + 'Exit code: ' + IntToStr(ResultCode) + #13#10
      + 'Log file: ' + LogPath + #13#10#13#10
      + 'Click Retry to re-run the installer script, Cancel to abort installation.';
    Response := MsgBox(FullMsg, mbError, MB_RETRYCANCEL);
    if Response = IDCANCEL then begin
      Abort;
    end;
    // IDRETRY: loop re-invokes powershell.exe with the same -File script,
    // giving the user a fresh attempt (e.g. after they fix WSL2 / networking).
  end;
end;

procedure RunInstallScripts;
var
  ScriptsDir, SharedDir, Params: String;
begin
  ScriptsDir := ExpandConstant('{app}') + '\scripts';
  SharedDir := ExpandConstant('{app}') + '\shared';

  // Run the WSL2 readiness check in a visible console so the user can read the
  // multi-line install guidance that Assert-Wsl2Ready prints on failure
  // (wsl --install, Microsoft Store link, etc.).  With SW_HIDE those messages
  // were invisible and the user only saw a vague "WSL2 is required" dialog.
  ExecVisiblePwshWithRetry(
    ScriptsDir + '\install-deps.ps1',
    'WSL2 is not ready. See the console window for install instructions, then click Retry. ' +
    'Typical fix: open PowerShell as Administrator and run `wsl --install` (then reboot).',
    GetAgentPackLogPath('install-deps'));

  if HermesCheckbox.Checked then begin
    ExecVisiblePwshWithRetry(
      ScriptsDir + '\install-hermes.ps1',
      'Failed to install Hermes Agent inside WSL2.',
      GetAgentPackLogPath('install-hermes'));
  end;

  if OpenClawCheckbox.Checked then begin
    ExecVisiblePwshWithRetry(
      ScriptsDir + '\install-openclaw.ps1',
      'Failed to install OpenClaw inside WSL2.',
      GetAgentPackLogPath('install-openclaw'));
  end;

  if ApiKeyEdit.Text <> '' then begin
    Params := '-ExecutionPolicy Bypass -File "' + ScriptsDir + '\configure-llm.ps1"';
    if ProviderRadios[0].Checked then Params := Params + ' -Provider openrouter'
    else if ProviderRadios[1].Checked then Params := Params + ' -Provider openai'
    else if ProviderRadios[2].Checked then Params := Params + ' -Provider anthropic'
    else Params := Params + ' -Provider custom';
    Params := Params + ' -ApiKey "' + ApiKeyEdit.Text + '"';
    if Trim(ModelEdit.Text) <> '' then begin
      Params := Params + ' -Model "' + ModelEdit.Text + '"';
    end;
    if ProviderRadios[3].Checked then begin
      Params := Params + ' -BaseUrl "' + BaseUrlEdit.Text + '"';
    end;
    if HermesCheckbox.Checked then Params := Params + ' -Hermes';
    if OpenClawCheckbox.Checked then Params := Params + ' -OpenClaw';
    Params := Params + ' -SharedDir "' + SharedDir + '"';
    ExecWithRetry('powershell.exe', Params, 'Failed to write WSL2 LLM configuration.', SW_HIDE);
  end;

end;

procedure CreateShortcutViaPS(const ShortcutPath, TargetExe, Params, WorkDir, Description: String);
var
  PSCmd: String;
  ResultCode: Integer;
begin
  PSCmd := '$ws = New-Object -ComObject WScript.Shell; '
    + '$s = $ws.CreateShortcut(''' + ShortcutPath + '''); '
    + '$s.TargetPath = ''' + TargetExe + '''; '
    + '$s.Arguments = ''' + Params + '''; '
    + '$s.WorkingDirectory = ''' + WorkDir + '''; '
    + '$s.Description = ''' + Description + '''; '
    + '$s.Save()';
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "' + PSCmd + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  HermesParams, OpenClawParams, UserHome: String;
begin
  if CurStep = ssPostInstall then begin
    RunInstallScripts;

    // Inno Setup does not expose {userprofile} as a path constant when the
    // installer runs elevated (PrivilegesRequired=admin), so resolve the
    // home directory via the USERPROFILE environment variable instead.
    UserHome := GetEnv('USERPROFILE');

    // Create desktop and start menu shortcuts based on selection
    if HermesCheckbox.Checked then begin
      HermesParams := '';
      CreateShortcutViaPS(
        ExpandConstant('{userdesktop}\Hermes Agent.lnk'),
        ExpandConstant('{localappdata}\AgentPack\bin\hermes.cmd'), HermesParams,
        UserHome, 'Hermes Agent');
      CreateShortcutViaPS(
        ExpandConstant('{group}\Hermes Agent.lnk'),
        ExpandConstant('{localappdata}\AgentPack\bin\hermes.cmd'), HermesParams,
        UserHome, 'Hermes Agent');
    end;
    if OpenClawCheckbox.Checked then begin
      OpenClawParams := 'gateway --verbose';
      CreateShortcutViaPS(
        ExpandConstant('{userdesktop}\OpenClaw.lnk'),
        ExpandConstant('{localappdata}\AgentPack\bin\openclaw.cmd'), OpenClawParams,
        UserHome, 'OpenClaw Gateway');
      CreateShortcutViaPS(
        ExpandConstant('{group}\OpenClaw.lnk'),
        ExpandConstant('{localappdata}\AgentPack\bin\openclaw.cmd'), OpenClawParams,
        UserHome, 'OpenClaw Gateway');
    end;
  end;
end;

// ---- Init ----
procedure InitializeWizard;
begin
  CreateProductPage;
  CreateProviderPage;
end;
