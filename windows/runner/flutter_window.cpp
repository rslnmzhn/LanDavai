#include "flutter_window.h"

#include <optional>
#include <sstream>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size_needed = MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  if (size_needed <= 0) {
    return std::wstring();
  }
  std::wstring wide(size_needed, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), &wide[0], size_needed);
  return wide;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  ConfigureMethodChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  method_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ConfigureMethodChannel() {
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "landa/network",
          &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

        if (call.method_name() == "setMinimizeToTrayEnabled") {
          bool enabled = true;
          if (args != nullptr) {
            const auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              if (const auto* value = std::get_if<bool>(&it->second)) {
                enabled = *value;
              }
            }
          }
          minimize_to_tray_enabled_ = enabled;
          if (!enabled) {
            RemoveTrayIcon();
          }
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "showDownloadAttemptNotification") {
          std::wstring requester = L"Device";
          std::wstring share_label = L"Shared files";
          int requested_files_count = 0;

          if (args != nullptr) {
            const auto requester_it =
                args->find(flutter::EncodableValue("requesterName"));
            if (requester_it != args->end()) {
              if (const auto* value =
                      std::get_if<std::string>(&requester_it->second)) {
                requester = Utf8ToWide(*value);
              }
            }

            const auto label_it = args->find(flutter::EncodableValue("shareLabel"));
            if (label_it != args->end()) {
              if (const auto* value = std::get_if<std::string>(&label_it->second)) {
                share_label = Utf8ToWide(*value);
              }
            }

            const auto count_it =
                args->find(flutter::EncodableValue("requestedFilesCount"));
            if (count_it != args->end()) {
              if (const auto* value = std::get_if<int32_t>(&count_it->second)) {
                requested_files_count = *value;
              } else if (const auto* wide_value =
                             std::get_if<int64_t>(&count_it->second)) {
                requested_files_count = static_cast<int>(*wide_value);
              }
            }
          }

          std::wstringstream stream;
          if (requested_files_count > 0) {
            stream << requester << L" requests " << requested_files_count
                   << L" file(s) from \"" << share_label << L"\".";
          } else {
            stream << requester << L" requests all files from \"" << share_label
                   << L"\".";
          }
          ShowDownloadAttemptBalloon(stream.str());
          result->Success(flutter::EncodableValue());
          return;
        }


        if (call.method_name() == "showFriendRequestNotification") {
          std::wstring requester = L"Device";

          if (args != nullptr) {
            const auto requester_it =
                args->find(flutter::EncodableValue("requesterName"));
            if (requester_it != args->end()) {
              if (const auto* value =
                      std::get_if<std::string>(&requester_it->second)) {
                requester = Utf8ToWide(*value);
              }
            }
          }

          std::wstringstream stream;
          stream << requester << L" sent you a friend request.";
          ShowDownloadAttemptBalloon(stream.str());
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "showSharedRecacheCompletedNotification") {
          int before_files = 0;
          int after_files = 0;

          if (args != nullptr) {
            const auto before_it = args->find(flutter::EncodableValue("beforeFiles"));
            if (before_it != args->end()) {
              if (const auto* value = std::get_if<int32_t>(&before_it->second)) {
                before_files = *value;
              } else if (const auto* wide_value =
                             std::get_if<int64_t>(&before_it->second)) {
                before_files = static_cast<int>(*wide_value);
              }
            }

            const auto after_it = args->find(flutter::EncodableValue("afterFiles"));
            if (after_it != args->end()) {
              if (const auto* value = std::get_if<int32_t>(&after_it->second)) {
                after_files = *value;
              } else if (const auto* wide_value =
                             std::get_if<int64_t>(&after_it->second)) {
                after_files = static_cast<int>(*wide_value);
              }
            }
          }

          std::wstringstream stream;
          stream << L"Before cache: " << before_files << L" files, after re-cache: "
                 << after_files << L" files.";
          ShowDownloadAttemptBalloon(stream.str());
          result->Success(flutter::EncodableValue());
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::EnsureTrayIcon() {
  if (tray_icon_added_ || GetHandle() == nullptr) {
    return;
  }

  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = 1;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayIconMessage;
  tray_icon_data_.hIcon =
      reinterpret_cast<HICON>(GetClassLongPtr(GetHandle(), GCLP_HICON));
  if (tray_icon_data_.hIcon == nullptr) {
    tray_icon_data_.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  }
  wcscpy_s(tray_icon_data_.szTip, L"Landa");

  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_data_) == TRUE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

void FlutterWindow::RestoreFromTray() {
  ShowWindow(GetHandle(), SW_SHOW);
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::ShowTrayContextMenu() {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  AppendMenuW(menu, MF_STRING, kTrayMenuOpen, L"Open Landa");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit, L"Exit");

  POINT cursor;
  GetCursorPos(&cursor);
  SetForegroundWindow(GetHandle());
  const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                      cursor.x, cursor.y, 0, GetHandle(), nullptr);

  if (command == kTrayMenuOpen) {
    RestoreFromTray();
  } else if (command == kTrayMenuExit) {
    force_exit_ = true;
    RemoveTrayIcon();
    Destroy();
  }

  DestroyMenu(menu);
  PostMessage(GetHandle(), WM_NULL, 0, 0);
}

void FlutterWindow::ShowDownloadAttemptBalloon(const std::wstring& text) {
  EnsureTrayIcon();
  if (!tray_icon_added_) {
    return;
  }

  tray_icon_data_.uFlags = NIF_INFO;
  wcscpy_s(tray_icon_data_.szInfoTitle, L"Landa");
  wcsncpy_s(tray_icon_data_.szInfo, text.c_str(), _TRUNCATE);
  tray_icon_data_.dwInfoFlags = NIIF_INFO;
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_);

  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (minimize_to_tray_enabled_ && !force_exit_) {
        EnsureTrayIcon();
        ShowWindow(GetHandle(), SW_HIDE);
        return 0;
      }
      break;
    case kTrayIconMessage:
      if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
        RestoreFromTray();
        return 0;
      }
      if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
        ShowTrayContextMenu();
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
