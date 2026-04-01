#include <windows.h>
#include <shellapi.h>

#include <string>

namespace {

constexpr wchar_t kCompatSwitchCount[] = L"FLUTTER_ENGINE_SWITCHES";
constexpr wchar_t kCompatSwitch1[] = L"FLUTTER_ENGINE_SWITCH_1";
constexpr wchar_t kCompatSwitch2[] = L"FLUTTER_ENGINE_SWITCH_2";
constexpr wchar_t kCompatTargetExe[] = L"Flclash.exe";

std::wstring GetExecutableDirectory() {
  std::wstring path(MAX_PATH, L'\0');
  DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                    static_cast<DWORD>(path.size()));
  while (length == path.size()) {
    path.resize(path.size() * 2, L'\0');
    length = GetModuleFileNameW(nullptr, path.data(),
                                static_cast<DWORD>(path.size()));
  }
  path.resize(length);
  const size_t separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return L".";
  }
  return path.substr(0, separator);
}

std::wstring QuoteArgument(const std::wstring& value) {
  if (value.find_first_of(L" \t\"") == std::wstring::npos) {
    return value;
  }
  std::wstring escaped = L"\"";
  for (const wchar_t ch : value) {
    if (ch == L'"') {
      escaped += L"\\\"";
    } else {
      escaped += ch;
    }
  }
  escaped += L"\"";
  return escaped;
}

std::wstring BuildForwardedArguments() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr || argc <= 1) {
    if (argv != nullptr) {
      ::LocalFree(argv);
    }
    return L"";
  }

  std::wstring args;
  for (int i = 1; i < argc; ++i) {
    if (!args.empty()) {
      args += L' ';
    }
    args += QuoteArgument(argv[i]);
  }
  ::LocalFree(argv);
  return args;
}

void ShowLaunchError(const wchar_t* message) {
  ::MessageBoxW(nullptr, message, L"Flclash Compatibility Mode",
                MB_OK | MB_ICONERROR);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  const std::wstring exeDir = GetExecutableDirectory();
  const std::wstring targetExe = exeDir + L"\\" + kCompatTargetExe;

  if (::GetFileAttributesW(targetExe.c_str()) == INVALID_FILE_ATTRIBUTES) {
    ShowLaunchError(L"Main program Flclash.exe was not found.");
    return ERROR_FILE_NOT_FOUND;
  }

  // Force safer rendering settings for machines with problematic GPU drivers.
  ::SetEnvironmentVariableW(kCompatSwitchCount, L"2");
  ::SetEnvironmentVariableW(kCompatSwitch1, L"enable-software-rendering=true");
  ::SetEnvironmentVariableW(kCompatSwitch2, L"enable-impeller=false");

  const std::wstring forwardedArguments = BuildForwardedArguments();

  SHELLEXECUTEINFOW execInfo{};
  execInfo.cbSize = sizeof(execInfo);
  execInfo.fMask = SEE_MASK_NOCLOSEPROCESS;
  execInfo.lpFile = targetExe.c_str();
  execInfo.lpParameters =
      forwardedArguments.empty() ? nullptr : forwardedArguments.c_str();
  execInfo.lpDirectory = exeDir.c_str();
  execInfo.nShow = show_command == 0 ? SW_SHOWNORMAL : show_command;

  if (!::ShellExecuteExW(&execInfo)) {
    ShowLaunchError(
        L"Compatibility mode failed to start. Try reinstalling the app.");
    return static_cast<int>(::GetLastError());
  }

  return 0;
}
