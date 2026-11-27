#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  flutter_controller_.reset();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  InstallRenderProbe();
  auto* messenger = flutter_controller_->engine()->messenger();
  process_job_channel_ = RegisterProcessJobChannel(messenger);
  render_probe_channel_ = RegisterRenderProbeChannel(messenger);
  fullscreen_ = std::make_unique<WindowFullscreen>(GetHandle());
  fullscreen_channel_ =
      RegisterWindowFullscreenChannel(messenger, fullscreen_.get());
  boss_key_ = std::make_unique<BossKeyHandler>(GetHandle());
  boss_key_channel_ = RegisterBossKeyChannel(messenger, boss_key_.get());

  HWND flutter_hwnd = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_hwnd);
  native_mpv_host_ = RegisterNativeMpvHost(messenger, GetHandle(), flutter_hwnd);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  UninstallRenderProbe();
  if (native_mpv_host_) {
    native_mpv_host_->DetachAndDispose();
    native_mpv_host_.reset();
  }
  render_probe_channel_ = nullptr;
  process_job_channel_ = nullptr;
  fullscreen_channel_ = nullptr;
  if (boss_key_) {
    boss_key_->SetChannel(nullptr);
  }
  boss_key_channel_ = nullptr;
  boss_key_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (fullscreen_) {
    if (auto handled = fullscreen_->HandleMessage(message, wparam, lparam)) {
      return *handled;
    }
  }

  if (boss_key_) {
    if (auto handled = boss_key_->HandleMessage(message, wparam, lparam)) {
      return *handled;
    }
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
