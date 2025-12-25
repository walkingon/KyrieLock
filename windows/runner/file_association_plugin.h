#ifndef RUNNER_FILE_ASSOCIATION_PLUGIN_H_
#define RUNNER_FILE_ASSOCIATION_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_plugin_registrar.h>

#include <memory>

void FileAssociationPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

class FileAssociationPlugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FileAssociationPlugin();
  virtual ~FileAssociationPlugin();

  FileAssociationPlugin(const FileAssociationPlugin&) = delete;
  FileAssociationPlugin& operator=(const FileAssociationPlugin&) = delete;
};

#endif