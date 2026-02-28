#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static constexpr UINT kTrayIconMessage = WM_APP + 100;
  static constexpr UINT kTrayMenuOpen = 2001;
  static constexpr UINT kTrayMenuExit = 2002;

  void ConfigureMethodChannel();
  void EnsureTrayIcon();
  void RemoveTrayIcon();
  void RestoreFromTray();
  void ShowTrayContextMenu();
  void ShowDownloadAttemptBalloon(const std::wstring& text);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  NOTIFYICONDATAW tray_icon_data_{};
  bool tray_icon_added_ = false;
  bool minimize_to_tray_enabled_ = true;
  bool force_exit_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
