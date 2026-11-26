#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single-instance lock for KimBoxTV
  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, L"Local\\KimBoxTV_Flutter_Mutex");
  if (mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"KimBoxTV");
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      } else {
        ::ShowWindow(existing, SW_SHOW);
      }
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(mutex);
    return EXIT_SUCCESS;
  }

  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(40, 40);
  Win32Window::Size size(1460, 920);
  if (!window.Create(L"KimBoxTV", origin, size)) {
    if (mutex != nullptr) ::CloseHandle(mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  window.Destroy();
  ::CoUninitialize();
  if (mutex != nullptr) ::CloseHandle(mutex);
  return EXIT_SUCCESS;
}
