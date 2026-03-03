#include "proxy_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <WinInet.h>
#include <Ras.h>
#include <RasError.h>
#include <vector>
#include <iostream>
#include <string>
#include <cwctype>

#pragma comment(lib, "wininet")
#pragma comment(lib, "Rasapi32")
#pragma comment(lib, "Advapi32")

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

// ========== 注册表兜底（HKCU\Internet Settings） ==========
// 部分系统环境下，仅调用 WinInet 的 INTERNET_OPTION_PER_CONNECTION_OPTION 可能出现：
// - 代理服务器值已写入，但 UI“使用代理服务器”开关未勾选
// - 仅对默认连接生效，而用户实际使用的是 RAS/VPN 连接
// 因此这里增加注册表写入作为兜底，并在 stop 时尽量恢复之前的用户设置。

static constexpr wchar_t kInternetSettingsKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

static bool ReadRegDword(HKEY key, const wchar_t* name, DWORD* outValue) {
  if (!outValue) return false;
  DWORD type = 0;
  DWORD value = 0;
  DWORD size = sizeof(value);
  const auto status = RegQueryValueExW(
      key, name, nullptr, &type, reinterpret_cast<LPBYTE>(&value), &size);
  if (status != ERROR_SUCCESS || type != REG_DWORD) {
    return false;
  }
  *outValue = value;
  return true;
}

static bool ReadRegSz(HKEY key, const wchar_t* name, std::wstring* outValue) {
  if (!outValue) return false;
  DWORD type = 0;
  DWORD size = 0;
  auto status = RegQueryValueExW(key, name, nullptr, &type, nullptr, &size);
  if (status != ERROR_SUCCESS || type != REG_SZ || size == 0) {
    return false;
  }

  std::wstring buf;
  buf.resize(size / sizeof(wchar_t));
  status = RegQueryValueExW(
      key,
      name,
      nullptr,
      &type,
      reinterpret_cast<LPBYTE>(buf.data()),
      &size);
  if (status != ERROR_SUCCESS || type != REG_SZ) {
    return false;
  }

  // 去掉结尾的 '\0'
  if (!buf.empty() && buf.back() == L'\0') {
    buf.pop_back();
  }
  *outValue = buf;
  return true;
}

static bool WriteRegDword(HKEY key, const wchar_t* name, DWORD value) {
  const auto status = RegSetValueExW(
      key,
      name,
      0,
      REG_DWORD,
      reinterpret_cast<const BYTE*>(&value),
      sizeof(value));
  return status == ERROR_SUCCESS;
}

static bool WriteRegSz(HKEY key, const wchar_t* name, const std::wstring& value) {
  // REG_SZ 需要包含结尾 '\0'
  const DWORD bytes =
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const auto status = RegSetValueExW(
      key,
      name,
      0,
      REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()),
      bytes);
  return status == ERROR_SUCCESS;
}

struct ProxyRegistrySnapshot {
  DWORD proxyEnable = 0;
  std::wstring proxyServer;
  std::wstring proxyOverride;
};

static bool g_hasProxySnapshot = false;
static ProxyRegistrySnapshot g_proxySnapshot;

static bool OpenInternetSettingsKey(HKEY* outKey, REGSAM extraSam = 0) {
  if (!outKey) return false;
  HKEY key = nullptr;
  const REGSAM sam = KEY_QUERY_VALUE | KEY_SET_VALUE | extraSam;
  // 使用 RegCreateKeyExW：避免极端情况下键不存在导致失败。
  DWORD disposition = 0;
  const auto status = RegCreateKeyExW(
      HKEY_CURRENT_USER,
      kInternetSettingsKeyPath,
      0,
      nullptr,
      REG_OPTION_NON_VOLATILE,
      sam,
      nullptr,
      &key,
      &disposition);
  if (status != ERROR_SUCCESS) return false;
  *outKey = key;
  return true;
}

static void SaveProxySnapshotIfNeeded() {
  if (g_hasProxySnapshot) return;
  HKEY key = nullptr;
  // 优先读取 64 位视图（若当前进程为 32 位也能读到系统主要视图）。
  if (!OpenInternetSettingsKey(&key, KEY_WOW64_64KEY)) {
    if (!OpenInternetSettingsKey(&key)) return;
  }

  ProxyRegistrySnapshot snap;
  (void)ReadRegDword(key, L"ProxyEnable", &snap.proxyEnable);
  (void)ReadRegSz(key, L"ProxyServer", &snap.proxyServer);
  (void)ReadRegSz(key, L"ProxyOverride", &snap.proxyOverride);

  RegCloseKey(key);
  g_proxySnapshot = std::move(snap);
  g_hasProxySnapshot = true;
}

static bool SetProxyViaRegistryImpl(
    bool enable,
    const std::wstring& proxyServer,
    const std::wstring& proxyOverride,
    REGSAM extraSam) {
  HKEY key = nullptr;
  if (!OpenInternetSettingsKey(&key, extraSam)) return false;

  bool ok = true;
  ok = WriteRegDword(key, L"ProxyEnable", enable ? 1 : 0) && ok;
  if (enable) {
    ok = WriteRegSz(key, L"ProxyServer", proxyServer) && ok;
    ok = WriteRegSz(key, L"ProxyOverride", proxyOverride) && ok;
  }

  RegCloseKey(key);
  return ok;
}

static void NotifyInternetSettingsChanged() {
  // 通知系统（含设置 UI）刷新 Internet Settings。
  SendNotifyMessageW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                     reinterpret_cast<LPARAM>(L"Internet Settings"));
}

static bool SetProxyViaRegistry(
    bool enable,
    const std::wstring& proxyServer,
    const std::wstring& proxyOverride) {
  // 兼容 32/64 位视图差异：尽量双写，避免“写了但 regedit 看不到/系统不认”的情况。
  const bool ok64 = SetProxyViaRegistryImpl(enable, proxyServer, proxyOverride, KEY_WOW64_64KEY);
  const bool ok32 = SetProxyViaRegistryImpl(enable, proxyServer, proxyOverride, KEY_WOW64_32KEY);
  const bool okDefault = SetProxyViaRegistryImpl(enable, proxyServer, proxyOverride, 0);

  if (ok64 || ok32 || okDefault) {
    NotifyInternetSettingsChanged();
  }
  return ok64 || ok32 || okDefault;
}

static bool RestoreProxyViaRegistryIfPossible() {
  if (!g_hasProxySnapshot) {
    // 没有快照就尽量只关闭开关，避免误覆盖用户配置。
    return SetProxyViaRegistry(false, L"", L"");
  }

  // 恢复时同样双写，尽量让系统/UI 与用户原设置一致。
  const bool ok = SetProxyViaRegistry(
      g_proxySnapshot.proxyEnable != 0,
      g_proxySnapshot.proxyServer,
      g_proxySnapshot.proxyOverride);
  return ok;
}

static bool ContainsLocalBypassToken(const std::wstring& bypassList) {
  // 简单判断：包含 "<local>"（不区分大小写）
  std::wstring lower = bypassList;
  for (auto& c : lower) {
    c = static_cast<wchar_t>(towlower(c));
  }
  return lower.find(L"<local>") != std::wstring::npos;
}

static bool ApplyProxyOptions(INTERNET_PER_CONN_OPTION_LIST* list, DWORD dwBufSize)
{
  if (!list) {
    return false;
  }

  // INTERNET_OPTION_PER_CONNECTION_OPTION：为当前连接应用代理配置。
  const BOOL ok = InternetSetOption(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, list, dwBufSize);
  return ok == TRUE;
}

static bool ApplyProxyOptionsToRasEntries(INTERNET_PER_CONN_OPTION_LIST* list, DWORD dwBufSize)
{
  if (!list) {
    return false;
  }

  // RAS（拨号/VPN）连接需要逐个设置，否则系统代理可能对这些连接不生效。
  DWORD size = 0;
  DWORD count = 0;
  auto ret = RasEnumEntries(nullptr, nullptr, nullptr, &size, &count);
  if (ret != ERROR_BUFFER_TOO_SMALL || size == 0 || count == 0) {
    // 没有 RAS 连接属于正常情况：不视为失败。
    return false;
  }

  std::vector<RASENTRYNAME> entries;
  entries.resize(count);
  for (auto& e : entries) {
    e.dwSize = sizeof(RASENTRYNAME);
  }

  DWORD bufSize = static_cast<DWORD>(entries.size() * sizeof(RASENTRYNAME));
  ret = RasEnumEntries(nullptr, nullptr, entries.data(), &bufSize, &count);
  if (ret != ERROR_SUCCESS || count == 0) {
    // 枚举失败不影响默认连接的代理设置：这里视为非致命错误。
    return false;
  }

  bool anyOk = false;
  for (DWORD i = 0; i < count; i++) {
    list->pszConnection = entries[i].szEntryName;
    if (ApplyProxyOptions(list, dwBufSize)) {
      anyOk = true;
    }
  }
  return anyOk;
}

static void RefreshProxySettings()
{
  // 通知系统代理设置已变更
  InternetSetOption(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  // 某些系统/组件只监听该事件（尤其是代理相关），补一次更稳。
  InternetSetOption(nullptr, INTERNET_OPTION_PROXY_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOption(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

static bool startProxy(const int port, const flutter::EncodableList& bypassDomain)
{
  // 保存注册表快照，stop 时用于尽量恢复用户设置。
  SaveProxySnapshotIfNeeded();

  INTERNET_PER_CONN_OPTION_LIST list{};
  DWORD dwBufSize = sizeof(list);
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;

  const auto url = "127.0.0.1:" + std::to_string(port);
  const auto wUrl = std::wstring(url.begin(), url.end());
  std::vector<WCHAR> fullAddr(wUrl.size() + 1);
  wcscpy_s(fullAddr.data(), fullAddr.size(), wUrl.c_str());

  std::wstring wBypassList;
  for (const auto& domain : bypassDomain) {
    if (!wBypassList.empty()) {
      wBypassList += L";";
    }
    const auto s = std::get<std::string>(domain);
    wBypassList += std::wstring(s.begin(), s.end());
  }

  // Windows 习惯在 ProxyOverride 里追加 <local>，用于绕过本地地址（无点域名等）。
  if (!ContainsLocalBypassToken(wBypassList)) {
    if (!wBypassList.empty()) {
      wBypassList += L";";
    }
    wBypassList += L"<local>";
  }
  std::vector<WCHAR> bypassAddr(wBypassList.size() + 1);
  wcscpy_s(bypassAddr.data(), bypassAddr.size(), wBypassList.c_str());

  // 同时设置 FLAGS 与 FLAGS_UI，确保在部分系统/连接类型下 UI 与实际配置保持一致。
  // 否则可能出现：调用成功但系统“代理开关”未被勾选，表现为需要手动去设置里开启。
  list.dwOptionCount = 4;
  list.pOptions = new INTERNET_PER_CONN_OPTION[4];

  if (!list.pOptions)
  {
    return false;
  }

  list.pOptions[0].dwOption = INTERNET_PER_CONN_FLAGS;
  list.pOptions[0].Value.dwValue = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;

  list.pOptions[1].dwOption = INTERNET_PER_CONN_FLAGS_UI;
  list.pOptions[1].Value.dwValue = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;

  list.pOptions[2].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  list.pOptions[2].Value.pszValue = fullAddr.data();

  list.pOptions[3].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  list.pOptions[3].Value.pszValue = bypassAddr.data();

  // 先应用到默认连接，再尝试应用到所有 RAS 连接。
  const bool ok = ApplyProxyOptions(&list, dwBufSize);
  const bool rasOk = ApplyProxyOptionsToRasEntries(&list, dwBufSize);

  delete[] list.pOptions;

  // 注册表兜底：确保 ProxyEnable/ProxyServer/ProxyOverride 与 UI 状态一致。
  const bool regOk = SetProxyViaRegistry(true, wUrl, wBypassList);

  RefreshProxySettings();
  // 返回“至少一个连接应用成功”的结果，避免某些机器只使用 RAS 连接时误判成功。
  return ok || rasOk || regOk;
}

static bool stopProxy()
{
  INTERNET_PER_CONN_OPTION_LIST list{};
  DWORD dwBufSize = sizeof(list);

  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;
  // 同时清理 FLAGS 与 FLAGS_UI，确保 UI 状态不会残留。
  list.dwOptionCount = 2;
  list.pOptions = new INTERNET_PER_CONN_OPTION[2];
  if (nullptr == list.pOptions)
  {
    return false;
  }
  list.pOptions[0].dwOption = INTERNET_PER_CONN_FLAGS;
  list.pOptions[0].Value.dwValue = PROXY_TYPE_DIRECT;

  list.pOptions[1].dwOption = INTERNET_PER_CONN_FLAGS_UI;
  list.pOptions[1].Value.dwValue = PROXY_TYPE_DIRECT;

  const bool ok = ApplyProxyOptions(&list, dwBufSize);
  const bool rasOk = ApplyProxyOptionsToRasEntries(&list, dwBufSize);
  delete[] list.pOptions;

  // 尽量恢复用户原有的系统代理配置。
  const bool regOk = RestoreProxyViaRegistryIfPossible();

  RefreshProxySettings();
  return ok || rasOk || regOk;
}

namespace proxy
{

  // static
  void ProxyPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "proxy",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<ProxyPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  ProxyPlugin::ProxyPlugin() {}

  ProxyPlugin::~ProxyPlugin() {}

  void ProxyPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name().compare("StopProxy") == 0)
    {
      result->Success(stopProxy());
    }
    else if (method_call.method_name().compare("StartProxy") == 0)
    {
      auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto port = std::get<int>(arguments->at(flutter::EncodableValue("port")));
      auto bypassDomain = std::get<flutter::EncodableList>(arguments->at(flutter::EncodableValue("bypassDomain")));
      result->Success(startProxy(port, bypassDomain));
    }
    else
    {
      result->NotImplemented();
    }
  }
} // namespace proxy
