; Agent Pack Installer — Inno Setup Script
; Requires Inno Setup 6.x

#define MyAppName "Agent Pack"
#define MyAppVersion "1.0.9"
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
OutputBaseFilename=AgentPack-{#MyAppVersion}-windows-x64
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
  // Set by AbortInstall before raising Abort.  Inno Setup can't cancel the
  // install once ssPostInstall runs (files are already copied), so the only
  // way to avoid a misleading "Setup completed successfully" finish page is
  // to rewrite its labels in CurPageChanged(wpFinished) when this flag is set.
  InstallFailed: Boolean;

// Set the failure flag THEN raise Inno Setup's Abort.  Always call this
// instead of Abort directly so the finish page reflects the failure.
procedure AbortInstall;
begin
  InstallFailed := True;
  Abort;
end;

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

// Build the shared verify-llm.py invocation suffix (args after the script
// path). Used by the WSL fallback verifier.
function BuildVerifyArgs(const Provider: String): String;
var
  Args: String;
begin
  Args := ' --provider ' + Provider
    + ' --api-key "' + ApiKeyEdit.Text + '"';
  if Trim(ModelEdit.Text) <> '' then begin
    Args := Args + ' --model "' + ModelEdit.Text + '"';
  end;
  if Provider = 'custom' then begin
    Args := Args + ' --base-url "' + BaseUrlEdit.Text + '"';
  end;
  Result := Args;
end;

function StripTrailingSlash(const S: String): String;
begin
  Result := S;
  while (Result <> '') and (Result[Length(Result)] = '/') do begin
    Delete(Result, Length(Result), 1);
  end;
end;

function JsonEscape(const S: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do begin
    if S[i] = '\' then begin
      Result := Result + '\\';
    end else if S[i] = '"' then begin
      Result := Result + '\"';
    end else if S[i] = #8 then begin
      Result := Result + '\b';
    end else if S[i] = #9 then begin
      Result := Result + '\t';
    end else if S[i] = #10 then begin
      Result := Result + '\n';
    end else if S[i] = #12 then begin
      Result := Result + '\f';
    end else if S[i] = #13 then begin
      Result := Result + '\r';
    end else begin
      Result := Result + S[i];
    end;
  end;
end;

function LoadTextFile(const Path: String): String;
var
  Lines: TArrayOfString;
  i: Integer;
begin
  Result := '';
  if not FileExists(Path) then begin
    Exit;
  end;
  if not LoadStringsFromFile(Path, Lines) then begin
    Exit;
  end;
  for i := 0 to GetArrayLength(Lines) - 1 do begin
    if i > 0 then begin
      Result := Result + #13#10;
    end;
    Result := Result + Lines[i];
  end;
end;

procedure AppendLogSection(const LogPath, Title, SourcePath: String);
var
  Body: String;
begin
  Body := Trim(LoadTextFile(SourcePath));
  if Body = '' then begin
    Exit;
  end;
  SaveStringToFile(
    LogPath,
    '' + #13#10 + '--- ' + Title + ' ---' + #13#10 + Body + #13#10,
    True
  );
end;

function ReadLastHttpStatusCode(const HeadersPath: String): Integer;
var
  Lines: TArrayOfString;
  i, SpacePos: Integer;
  Line, Rest, CodeText: String;
begin
  Result := 0;
  if not FileExists(HeadersPath) then begin
    Exit;
  end;
  if not LoadStringsFromFile(HeadersPath, Lines) then begin
    Exit;
  end;
  for i := 0 to GetArrayLength(Lines) - 1 do begin
    Line := Trim(Lines[i]);
    if Copy(Line, 1, 5) = 'HTTP/' then begin
      SpacePos := Pos(' ', Line);
      if SpacePos > 0 then begin
        Rest := Trim(Copy(Line, SpacePos + 1, MaxInt));
        CodeText := Copy(Rest, 1, 3);
        Result := StrToIntDef(CodeText, 0);
      end;
    end;
  end;
end;

function BodyLooksSuccessful(const Provider, BodyPath: String): Boolean;
var
  Body: String;
begin
  Body := LoadTextFile(BodyPath);
  if Provider = 'anthropic' then begin
    Result := Pos('"content"', Body) > 0;
  end else begin
    Result := Pos('"choices"', Body) > 0;
  end;
end;

function BuildVerifyPayload(const Provider, Model: String): String;
begin
  if Provider = 'anthropic' then begin
    Result := '{"model":"' + JsonEscape(Model)
      + '","max_tokens":5,"messages":[{"role":"user","content":"Say OK"}]}';
  end else begin
    Result := '{"model":"' + JsonEscape(Model)
      + '","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}';
  end;
end;

function BuildVerifyUrl(const Provider: String): String;
var
  BaseUrl: String;
begin
  BaseUrl := Trim(BaseUrlEdit.Text);
  if BaseUrl = '' then begin
    BaseUrl := GetDefaultBaseUrl(GetSelectedProviderIndex);
  end;
  BaseUrl := StripTrailingSlash(BaseUrl);
  if Provider = 'anthropic' then begin
    Result := BaseUrl + '/v1/messages';
  end else begin
    Result := BaseUrl + '/chat/completions';
  end;
end;

function BuildCurlVerifyParams(
  const Provider, PayloadPath, BodyPath, HeadersPath, ErrPath: String
): String;
begin
  Result := '--silent --show-error --request POST --connect-timeout 15 --max-time 30'
    + ' --url "' + BuildVerifyUrl(Provider) + '"'
    + ' --header "Content-Type: application/json"';
  if Provider = 'anthropic' then begin
    Result := Result
      + ' --header "x-api-key: ' + ApiKeyEdit.Text + '"'
      + ' --header "anthropic-version: 2023-06-01"';
  end else begin
    Result := Result
      + ' --header "Authorization: Bearer ' + ApiKeyEdit.Text + '"';
  end;
  Result := Result
    + ' --data-binary "@' + PayloadPath + '"'
    + ' --dump-header "' + HeadersPath + '"'
    + ' --output "' + BodyPath + '"'
    + ' --stderr "' + ErrPath + '"';
end;

// Read up to MaxBytes of LogPath; return a trimmed string. Used to grab the
// verify log so we can show the user the actual error instead of a blanket
// "failed".
function ReadLogTail(const LogPath: String; MaxBytes: Integer): String;
var
  Lines: TArrayOfString;
  i, StartIdx: Integer;
  Body: String;
begin
  Result := '';
  if not FileExists(LogPath) then begin
    Exit;
  end;
  if not LoadStringsFromFile(LogPath, Lines) then begin
    Exit;
  end;
  // Show the last ~20 lines — enough for a python traceback + the
  // "ERROR: <urllib.error ...>" line that verify-llm.py emits.
  StartIdx := GetArrayLength(Lines) - 20;
  if StartIdx < 0 then StartIdx := 0;
  Body := '';
  for i := StartIdx to GetArrayLength(Lines) - 1 do begin
    Body := Body + Lines[i] + #13#10;
  end;
  if Length(Body) > MaxBytes then begin
    Body := Copy(Body, Length(Body) - MaxBytes + 1, MaxBytes);
  end;
  Result := Trim(Body);
end;

// Try to verify directly from the Windows host using curl.exe. Captures curl
// stderr plus any HTTP response headers/body into LogPath. If curl launches and
// receives an HTTP response, we do not fall back to WSL - the API already told
// us whether the config is valid. WSL is reserved for cases where curl cannot
// be launched or cannot reach the endpoint.
function TryVerifyViaHostCurl(const Provider, LogPath: String;
  var NeedsWslFallback: Boolean): Boolean;
var
  CurlPath, PayloadPath, BodyPath, HeadersPath, ErrPath: String;
  Payload, Params, Model: String;
  ResultCode, StatusCode: Integer;
begin
  Result := False;
  NeedsWslFallback := True;
  SaveStringToFile(LogPath, '=== host curl.exe ===' + #13#10, False);

  Model := Trim(ModelEdit.Text);
  if Model = '' then begin
    Model := GetDefaultModel(GetSelectedProviderIndex);
  end;
  Payload := BuildVerifyPayload(Provider, Model);

  PayloadPath := ExpandConstant('{tmp}') + '\agent-pack-verify-payload.json';
  BodyPath := ExpandConstant('{tmp}') + '\agent-pack-verify-body.json';
  HeadersPath := ExpandConstant('{tmp}') + '\agent-pack-verify-headers.txt';
  ErrPath := ExpandConstant('{tmp}') + '\agent-pack-verify-curl.stderr.txt';

  if not SaveStringToFile(PayloadPath, Payload, False) then begin
    SaveStringToFile(LogPath, 'ERROR: Failed to write curl payload file.' + #13#10, True);
    Exit;
  end;
  SaveStringToFile(BodyPath, '', False);
  SaveStringToFile(HeadersPath, '', False);
  SaveStringToFile(ErrPath, '', False);

  CurlPath := ExpandConstant('{sys}\curl.exe');
  Params := BuildCurlVerifyParams(Provider, PayloadPath, BodyPath, HeadersPath, ErrPath);

  if not Exec(CurlPath, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then begin
    SaveStringToFile(LogPath, 'ERROR: curl.exe could not be launched.' + #13#10, True);
    Exit;
  end;

  AppendLogSection(LogPath, 'curl stderr', ErrPath);
  AppendLogSection(LogPath, 'response headers', HeadersPath);
  AppendLogSection(LogPath, 'response body', BodyPath);

  StatusCode := ReadLastHttpStatusCode(HeadersPath);
  if StatusCode <> 0 then begin
    NeedsWslFallback := False;
    Result := (StatusCode >= 200) and (StatusCode < 300)
      and BodyLooksSuccessful(Provider, BodyPath);
    Exit;
  end;

  if ResultCode <> 0 then begin
    SaveStringToFile(
      LogPath,
      '' + #13#10 + 'ERROR: curl exit code ' + IntToStr(ResultCode) + #13#10,
      True
    );
  end;
end;

// Replace each ' in S with '\'' so S can be embedded inside a bash
// single-quoted literal.  Inno Setup's Pascal doesn't have
// StringReplace(..., [rfReplaceAll]) exposed, so do it manually.
function BashSingleQuoteEscape(const S: String): String;
var
  i: Integer;
  Buf: String;
begin
  Buf := '';
  for i := 1 to Length(S) do begin
    if S[i] = '''' then begin
      Buf := Buf + '''\''''';
    end else begin
      Buf := Buf + S[i];
    end;
  end;
  Result := Buf;
end;

// Fallback: run verify-llm.py through WSL's python3.  Every Windows install
// target already has WSL2 + a distro set up (Agent Pack requires it), so
// python3 is reliably available there even when the user hasn't installed
// Python on the Windows host.  Captures combined stdout+stderr into LogPath.
// Returns True iff wsl.exe ran AND exited 0.
function TryVerifyViaWsl(const ScriptPath, Args, LogPath: String): Boolean;
var
  ResultCode: Integer;
  WslPath, BashCmd, Cmd: String;
begin
  SaveStringToFile(LogPath, #13#10 + '=== WSL python3 ===' + #13#10, True);
  // wslpath -a converts C:\foo\bar.py → /mnt/c/foo/bar.py; easier to shell
  // the conversion out than to translate path separators ourselves.
  // We wrap the full bash program in single quotes and escape any ' inside
  // the user-supplied args (e.g. an API key containing ') so it can't
  // prematurely terminate the quoting.
  WslPath := ExpandConstant('{app}') + '\shared\verify-llm.py';
  BashCmd := 'python3 "$(wslpath -a "' + WslPath + '")"'
    + BashSingleQuoteEscape(Args);
  Cmd := '/c wsl.exe -- bash -lc ''' + BashCmd + ''' >> "' + LogPath + '" 2>&1';
  Result := Exec('cmd.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
    and (ResultCode = 0);
end;

procedure OnVerifyClick(Sender: TObject);
var
  ScriptPath, Args, Provider, LogPath, LogTail, Dialog: String;
  Ok, NeedsWslFallback: Boolean;
begin
  Provider := GetProviderName(GetSelectedProviderIndex);
  ScriptPath := ExpandConstant('{app}') + '\shared\verify-llm.py';
  Args := BuildVerifyArgs(Provider);
  // Redirect both attempts' stdout+stderr to one log so we can replay the
  // full story in the error dialog.  Lives in %TEMP% so it doesn't leak
  // the API key beyond this session (deleted on logoff with the rest).
  LogPath := ExpandConstant('{tmp}') + '\agent-pack-verify.log';

  VerifyLabel.Caption := 'Verifying...';
  VerifyLabel.Font.Color := clBlue;

  // Try host curl.exe first so Windows users do not need Python installed
  // ANY reason — missing python.exe, network error, bad key, wrong model —
  // fall through to WSL.  That way a teammate without Windows Python still
  // cannot run or cannot reach the endpoint.
  Ok := TryVerifyViaHostCurl(Provider, LogPath, NeedsWslFallback);
  if (not Ok) and NeedsWslFallback then begin
    Ok := TryVerifyViaWsl(ScriptPath, Args, LogPath);
  end;

  if Ok then begin
    VerifyLabel.Caption := 'Connection verified!';
    VerifyLabel.Font.Color := clGreen;
  end else begin
    VerifyLabel.Caption := 'Verification failed. Click Verify for details.';
    VerifyLabel.Font.Color := clRed;
    // Show the actual error in a dialog.  Common cases:
    //   - "'python' is not recognized..."  → no host Python (fell through
    //     to WSL, which also failed — usually because WSL isn't set up yet)
    //   - "ERROR: HTTP Error 401: Unauthorized"       → wrong API key
    //   - "ERROR: Unknown model ..."                  → typo in model id
    //   - "ERROR: <urlopen error ...>"                → no network / DNS
    LogTail := ReadLogTail(LogPath, 3000);
    if LogTail = '' then begin
      LogTail := '(no output captured — the verify command probably could not be launched)';
    end;
    Dialog := 'Verification failed.' + #13#10#13#10
      + 'Details:' + #13#10 + LogTail + #13#10#13#10
      + 'Full log: ' + LogPath + #13#10#13#10
      + 'You can continue the install and fix the config later.';
    MsgBox(Dialog, mbError, MB_OK);
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
      AbortInstall;
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
function ExecVisiblePwshWithRetry(const ScriptPath, ExtraArgs, FailMessage, LogPath: String): Boolean;
var
  Params, FullMsg: String;
  ResultCode, Response: Integer;
begin
  Result := False;
  Params :=
    '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"';
  if Trim(ExtraArgs) <> '' then begin
    Params := Params + ' ' + ExtraArgs;
  end;

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
      AbortInstall;
    end;
    // IDRETRY: loop re-invokes powershell.exe with the same -File script,
    // giving the user a fresh attempt (e.g. after they fix WSL2 / networking).
  end;
end;

// Build the `-Provider ... -ApiKey ... [-Model ...] [-BaseUrl ...]` suffix
// shared by install-hermes.ps1 and install-openclaw.ps1.  Returns an empty
// string if the user left ApiKey blank — the per-product PS scripts skip
// apply_llm_config_for in that case.
function BuildLlmArgs: String;
var
  Args: String;
begin
  if Trim(ApiKeyEdit.Text) = '' then begin
    Result := '';
    Exit;
  end;

  if ProviderRadios[0].Checked then Args := '-Provider openrouter'
  else if ProviderRadios[1].Checked then Args := '-Provider openai'
  else if ProviderRadios[2].Checked then Args := '-Provider anthropic'
  else Args := '-Provider custom';

  Args := Args + ' -ApiKey "' + ApiKeyEdit.Text + '"';
  if Trim(ModelEdit.Text) <> '' then begin
    Args := Args + ' -Model "' + ModelEdit.Text + '"';
  end;
  // Always forward BaseUrl, not just for custom providers — OpenClaw's
  // `models.providers.<name>.baseUrl` is required (fails schema validation
  // with "Too small: expected string to have >=1 character" otherwise).
  // For bundled providers BaseUrlEdit.Text was pre-seeded by
  // UpdateProviderFieldLayout via GetDefaultBaseUrl, so this is always a
  // non-empty string.
  Args := Args + ' -BaseUrl "' + BaseUrlEdit.Text + '"';
  Result := Args;
end;

function GetAgentPackMarkerDir: String;
begin
  Result := ExpandConstant('{localappdata}') + '\AgentPack\markers';
end;

function GetMarkerPath(const Name: String): String;
begin
  Result := GetAgentPackMarkerDir + '\' + Name;
end;

// Start a per-product install PowerShell script without waiting for it to
// exit.  The PS script: (a) installs the product, (b) writes
// <prod>-installed.marker, (c) execs the agent, taking over the console.
// Because the PS1 never returns (it's hosting an interactive agent / long-
// running server), we MUST use ewNoWait or Inno Setup would hang forever.
procedure SpawnProductInstall(const ScriptPath, ExtraArgs: String);
var
  Params: String;
  ResultCode: Integer;
begin
  Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"';
  if Trim(ExtraArgs) <> '' then begin
    Params := Params + ' ' + ExtraArgs;
  end;
  Exec('powershell.exe', Params, '', SW_SHOW, ewNoWait, ResultCode);
end;

// Poll each selected product's marker directory until every product has
// either an <prod>-installed.marker (success) or <prod>-failed.marker.
// Returns True if all succeeded.  Shows install log + Retry/Cancel dialog
// on any failure, mirroring ExecVisiblePwshWithRetry's old behavior.
function WaitForProductMarkers(const WantHermes, WantOpenClaw: Boolean): Boolean;
var
  MarkerDir, HermesOk, HermesFail, OpenClawOk, OpenClawFail: String;
  HermesDone, OpenClawDone, AllDone: Boolean;
  TimeoutMs, Elapsed, SleepMs: Integer;
  Response: Integer;
  FailMsg, FailLog: String;
  FailLogLines: TArrayOfString;
begin
  Result := False;
  MarkerDir := GetAgentPackMarkerDir;
  HermesOk    := MarkerDir + '\hermes-installed.marker';
  HermesFail  := MarkerDir + '\hermes-failed.marker';
  OpenClawOk  := MarkerDir + '\openclaw-installed.marker';
  OpenClawFail:= MarkerDir + '\openclaw-failed.marker';

  // 15 minutes — WSL first-boot + apt + npm installs can be slow.
  TimeoutMs := 15 * 60 * 1000;
  SleepMs := 1000;
  Elapsed := 0;

  while Elapsed < TimeoutMs do begin
    HermesDone := (not WantHermes) or FileExists(HermesOk) or FileExists(HermesFail);
    OpenClawDone := (not WantOpenClaw) or FileExists(OpenClawOk) or FileExists(OpenClawFail);
    AllDone := HermesDone and OpenClawDone;

    // Bail early if any failed — no point waiting out the timeout.
    if WantHermes and FileExists(HermesFail) then begin
      FailMsg := 'Hermes Agent installation failed.';
      if LoadStringsFromFile(HermesFail, FailLogLines) and (GetArrayLength(FailLogLines) > 0) then begin
        FailLog := FailLogLines[0];
      end else begin
        FailLog := GetAgentPackLogPath('install-hermes');
      end;
      Response := MsgBox(FailMsg + #13#10 + 'Log: ' + FailLog + #13#10#13#10 +
        'Click Retry to re-run the installer script, Cancel to abort.',
        mbError, MB_RETRYCANCEL);
      if Response = IDCANCEL then AbortInstall;
      Exit; // caller retries
    end;
    if WantOpenClaw and FileExists(OpenClawFail) then begin
      FailMsg := 'OpenClaw installation failed.';
      if LoadStringsFromFile(OpenClawFail, FailLogLines) and (GetArrayLength(FailLogLines) > 0) then begin
        FailLog := FailLogLines[0];
      end else begin
        FailLog := GetAgentPackLogPath('install-openclaw');
      end;
      Response := MsgBox(FailMsg + #13#10 + 'Log: ' + FailLog + #13#10#13#10 +
        'Click Retry to re-run the installer script, Cancel to abort.',
        mbError, MB_RETRYCANCEL);
      if Response = IDCANCEL then AbortInstall;
      Exit;
    end;

    if AllDone then begin
      Result := True;
      Exit;
    end;

    Sleep(SleepMs);
    Elapsed := Elapsed + SleepMs;
    // Keep Inno Setup's wizard responsive (repaint, process messages).
    WizardForm.Refresh;
  end;

  // Timed out — windows are probably still doing something; let the user
  // decide whether to wait longer or bail.
  Response := MsgBox(
    'Timed out waiting for product installations to report success.' + #13#10 +
    'The install windows may still be working.  Click Retry to keep waiting,' +
    ' or Cancel to abort.',
    mbError, MB_RETRYCANCEL);
  if Response = IDCANCEL then AbortInstall;
  // Retry just re-enters the while loop by returning False to caller.
end;

procedure RunInstallScripts;
var
  ScriptsDir, LlmArgs: String;
  WantHermes, WantOpenClaw, AllDone: Boolean;
begin
  ScriptsDir := ExpandConstant('{app}') + '\scripts';
  LlmArgs := BuildLlmArgs;
  WantHermes := HermesCheckbox.Checked;
  WantOpenClaw := OpenClawCheckbox.Checked;

  // Run WSL2 readiness check + agent_pack prefetch in a visible console so
  // the user can read the multi-line install guidance that Assert-Wsl2Ready
  // prints on failure (wsl --install, Microsoft Store link, etc.) and watch
  // the clone progress.  install-deps.ps1 does both steps so the later
  // per-product installers can copy from a shared cache.
  ExecVisiblePwshWithRetry(
    ScriptsDir + '\install-deps.ps1',
    '',
    'WSL2 setup or agent_pack prefetch failed. See the console window for details, then click Retry. ' +
    'Typical fix: open PowerShell as Administrator and run `wsl --install` (then reboot).',
    GetAgentPackLogPath('install-deps'));

  // Clear any stale markers from a previous run so the poll loop doesn't
  // return instantly on the first tick.
  ForceDirectories(GetAgentPackMarkerDir);
  DeleteFile(GetMarkerPath('hermes-installed.marker'));
  DeleteFile(GetMarkerPath('hermes-failed.marker'));
  DeleteFile(GetMarkerPath('openclaw-installed.marker'));
  DeleteFile(GetMarkerPath('openclaw-failed.marker'));

  // Per-product PS scripts run install_<prod> + apply_llm_config_for <prod>
  // inside WSL, then exec the agent in the same console — so we start them
  // with ewNoWait and use marker files to know when they're done installing.
  // Retry loop: if any product fails, delete its markers, respawn, poll again.
  while True do begin
    if WantHermes and (not FileExists(GetMarkerPath('hermes-installed.marker'))) then begin
      DeleteFile(GetMarkerPath('hermes-failed.marker'));
      SpawnProductInstall(ScriptsDir + '\install-hermes.ps1', LlmArgs);
    end;
    if WantOpenClaw and (not FileExists(GetMarkerPath('openclaw-installed.marker'))) then begin
      DeleteFile(GetMarkerPath('openclaw-failed.marker'));
      SpawnProductInstall(ScriptsDir + '\install-openclaw.ps1', LlmArgs);
    end;

    AllDone := WaitForProductMarkers(WantHermes, WantOpenClaw);
    if AllDone then Break;
    // else: a product failed, user clicked Retry — loop respawns only the
    //       one(s) missing an installed.marker.
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
  HermesParams, OpenClawParams, UserHome, HermesCmd, OpenClawCmd: String;
begin
  if CurStep = ssPostInstall then begin
    RunInstallScripts;

    // Inno Setup does not expose {userprofile} as a path constant when the
    // installer runs elevated (PrivilegesRequired=admin), so resolve the
    // home directory via the USERPROFILE environment variable instead.
    UserHome := GetEnv('USERPROFILE');

    HermesCmd := ExpandConstant('{localappdata}\AgentPack\bin\hermes.cmd');
    OpenClawCmd := ExpandConstant('{localappdata}\AgentPack\bin\openclaw.cmd');

    // Create desktop and start menu shortcuts based on selection.  The
    // per-product install PS windows are already running the agents, so we
    // don't spawn fresh windows here — just lay down the shortcuts for later.
    if HermesCheckbox.Checked then begin
      HermesParams := '';
      CreateShortcutViaPS(
        ExpandConstant('{userdesktop}\Hermes Agent.lnk'),
        HermesCmd, HermesParams, UserHome, 'Hermes Agent');
      CreateShortcutViaPS(
        ExpandConstant('{group}\Hermes Agent.lnk'),
        HermesCmd, HermesParams, UserHome, 'Hermes Agent');
    end;
    if OpenClawCheckbox.Checked then begin
      OpenClawParams := 'gateway --verbose';
      CreateShortcutViaPS(
        ExpandConstant('{userdesktop}\OpenClaw.lnk'),
        OpenClawCmd, OpenClawParams, UserHome, 'OpenClaw Gateway');
      CreateShortcutViaPS(
        ExpandConstant('{group}\OpenClaw.lnk'),
        OpenClawCmd, OpenClawParams, UserHome, 'OpenClaw Gateway');
    end;
  end;
end;

// Rewrite the finish page labels when AbortInstall fired during ssPostInstall.
// Inno Setup always shows wpFinished after the install step completes —
// including when Abort was raised — and defaults to the cheerful
// "Setup was completed successfully" wording, which is misleading if the
// post-install scripts bailed.  Detect the flag and surface the failure.
procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and InstallFailed then begin
    WizardForm.FinishedHeadingLabel.Caption := 'Setup did not complete';
    WizardForm.FinishedLabel.Caption :=
      'Agent Pack installation was aborted because a post-install step failed ' +
      'or was cancelled.  Files may have been copied to the install directory, ' +
      'but one or more agents were not fully configured.' + #13#10#13#10 +
      'Check the install logs under %LOCALAPPDATA%\AgentPack\logs for details, ' +
      'then re-run the installer once the underlying issue is fixed.';
  end;
end;

// ---- Init ----
procedure InitializeWizard;
begin
  CreateProductPage;
  CreateProviderPage;
end;
