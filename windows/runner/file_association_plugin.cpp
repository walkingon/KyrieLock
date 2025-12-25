#include "file_association_plugin.h"

#include <windows.h>
#include <shlobj.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

static void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

static void RegisterFileAssociation();
static std::string GetInitialFile();

void FileAssociationPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar_ref) {
  auto registrar = flutter::PluginRegistrarManager::GetInstance()
                       ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_ref);

  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.kyrie.kyrie_lock/file_association",
          &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

void FileAssociationPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.kyrie.kyrie_lock/file_association",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  
  channel_ = std::move(channel);
}

FileAssociationPlugin::FileAssociationPlugin() {}

FileAssociationPlugin::~FileAssociationPlugin() {}

static void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "registerFileAssociation") {
    RegisterFileAssociation();
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "getInitialFile") {
    std::string file_path = GetInitialFile();
    if (!file_path.empty()) {
      result->Success(flutter::EncodableValue(file_path));
    } else {
      result->Success();
    }
  } else {
    result->NotImplemented();
  }
}

static void RegisterFileAssociation() {
  HKEY hKey;
  WCHAR exePath[MAX_PATH];
  GetModuleFileNameW(NULL, exePath, MAX_PATH);

  std::wstring progId = L"KyrieLock.kyl";
  std::wstring fileExt = L".kyl";
  std::wstring appName = L"KyrieLock";
  std::wstring description = L"KyrieLock Encrypted File";
  
  std::wstring progIdPath = L"Software\\Classes\\" + progId;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, progIdPath.c_str(), 0, NULL, 0,
                      KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
    RegSetValueExW(hKey, NULL, 0, REG_SZ, (BYTE*)description.c_str(),
                   static_cast<DWORD>((description.length() + 1) * sizeof(WCHAR)));
    RegCloseKey(hKey);
  }

  std::wstring defaultIconPath = progIdPath + L"\\DefaultIcon";
  if (RegCreateKeyExW(HKEY_CURRENT_USER, defaultIconPath.c_str(), 0, NULL, 0,
                      KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
    std::wstring iconPath = std::wstring(exePath) + L",0";
    RegSetValueExW(hKey, NULL, 0, REG_SZ, (BYTE*)iconPath.c_str(),
                   static_cast<DWORD>((iconPath.length() + 1) * sizeof(WCHAR)));
    RegCloseKey(hKey);
  }

  std::wstring openCommandPath = progIdPath + L"\\shell\\open\\command";
  if (RegCreateKeyExW(HKEY_CURRENT_USER, openCommandPath.c_str(), 0, NULL, 0,
                      KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
    std::wstring command = L"\"" + std::wstring(exePath) + L"\" \"%1\"";
    RegSetValueExW(hKey, NULL, 0, REG_SZ, (BYTE*)command.c_str(),
                   static_cast<DWORD>((command.length() + 1) * sizeof(WCHAR)));
    RegCloseKey(hKey);
  }

  std::wstring extPath = L"Software\\Classes\\" + fileExt;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, extPath.c_str(), 0, NULL, 0,
                      KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
    RegSetValueExW(hKey, NULL, 0, REG_SZ, (BYTE*)progId.c_str(),
                   static_cast<DWORD>((progId.length() + 1) * sizeof(WCHAR)));
    RegCloseKey(hKey);
  }

  std::wstring openWithProgidsPath = extPath + L"\\OpenWithProgids";
  if (RegCreateKeyExW(HKEY_CURRENT_USER, openWithProgidsPath.c_str(), 0, NULL,
                      0, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
    BYTE empty = 0;
    RegSetValueExW(hKey, progId.c_str(), 0, REG_NONE, &empty, 0);
    RegCloseKey(hKey);
  }

  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);
}

static std::string GetInitialFile() {
  int argc;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  
  std::string filePath;
  if (argc > 1) {
    std::wstring wFilePath(argv[1]);
    
    if (wFilePath.length() >= 2 && wFilePath.front() == L'"' && wFilePath.back() == L'"') {
      wFilePath = wFilePath.substr(1, wFilePath.length() - 2);
    }
    
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wFilePath.c_str(),
                                          -1, NULL, 0, NULL, NULL);
    if (size_needed > 0) {
      filePath = std::string(size_needed - 1, 0);
      WideCharToMultiByte(CP_UTF8, 0, wFilePath.c_str(), -1,
                          &filePath[0], size_needed, NULL, NULL);
    }
  }
  
  LocalFree(argv);
  return filePath;
}